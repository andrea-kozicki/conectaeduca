<?php

declare(strict_types=1);

namespace ConectaEduca\Security;

/**
 * Identifica o cliente no login sem aceitar cabeçalhos forjados.
 *
 * O WAF sobrescreve X-ConectaEduca-Client-IP com o peer observado.
 * O endereço só é utilizado se REMOTE_ADDR corresponder ao serviço
 * Docker "waf" na mesma rede interna da aplicação. Na dúvida,
 * prevalece o endereço do peer informado pelo servidor web.
 */
final class TrustedClientIp
{
    public static function current(): string
    {
        $header = $_SERVER['HTTP_X_CONECTAEDUCA_CLIENT_IP'] ?? null;
        if (!is_string($header) || trim($header) === '') {
            // Caminho direto (sem WAF): não faz consulta DNS desnecessária.
            return self::resolve($_SERVER, []);
        }

        // Serviço Docker presente apenas quando o overlay WAF está ativo.
        // Ausência/falha de DNS não amplia a confiança nos cabeçalhos.
        $addresses = @gethostbynamel('waf');

        return self::resolve(
            $_SERVER,
            is_array($addresses) ? $addresses : []
        );
    }

    /**
     * @param array<string, mixed> $server
     * @param list<string> $trustedWafAddresses
     */
    public static function resolve(
        array $server,
        array $trustedWafAddresses
    ): string {
        $peer = self::normalizeIp($server['REMOTE_ADDR'] ?? null);

        if ($peer === null) {
            return 'desconhecido';
        }

        $trusted = [];
        foreach ($trustedWafAddresses as $address) {
            $normalized = self::normalizeIp($address);
            if ($normalized !== null) {
                $trusted[] = $normalized;
            }
        }

        if (!in_array($peer, $trusted, true)) {
            return $peer;
        }

        $client = self::normalizeIp(
            $server['HTTP_X_CONECTAEDUCA_CLIENT_IP'] ?? null
        );

        return $client ?? $peer;
    }

    private static function normalizeIp(mixed $value): ?string
    {
        if (!is_string($value)) {
            return null;
        }

        $value = trim($value);
        if ($value === '' || str_contains($value, ',')) {
            return null;
        }

        $packed = @inet_pton($value);
        if ($packed === false) {
            return null;
        }

        $normalized = inet_ntop($packed);

        return $normalized === false ? null : $normalized;
    }
}
