<?php

declare(strict_types=1);

namespace ConectaEduca\Security;

use RuntimeException;
use Throwable;

final class PendingAuthentication
{
    private const SESSION_KEY = 'mfa_pending';
    private const RECOVERY_CODES_KEY = 'recovery_codes_envelope';
    private const TTL_SECONDS = 300;
    private const RECOVERY_CODES_TTL_SECONDS = 600;

    public static function begin(int $usuarioId): void
    {
        if ($usuarioId < 1) {
            return;
        }

        /*
         * Delimita a transição:
         * anônimo -> senha validada.
         */
        SecureSession::regenerate();

        /*
         * Uma autenticação pendente jamais pode coexistir
         * com uma sessão autenticada.
         */
        unset($_SESSION['user']);

        $_SESSION[self::SESSION_KEY] = [
            'user_id' => $usuarioId,
            'created_at' => time(),
            'expires_at' => time() + self::TTL_SECONDS,
        ];
    }

    public static function get(): ?array
    {
        SecureSession::start();

        $pending = $_SESSION[self::SESSION_KEY] ?? null;

        if (!is_array($pending)) {
            return null;
        }

        $usuarioId = $pending['user_id'] ?? null;
        $expiraEm = $pending['expires_at'] ?? null;

        if (
            !is_int($usuarioId)
            || $usuarioId < 1
            || !is_int($expiraEm)
        ) {
            self::clear();

            return null;
        }

        if ($expiraEm < time()) {
            self::clear();

            return null;
        }

        return $pending;
    }

    public static function userId(): ?int
    {
        $pending = self::get();

        if ($pending === null) {
            return null;
        }

        return (int) $pending['user_id'];
    }

    public static function active(): bool
    {
        return self::get() !== null;
    }

    /**
     * Mantém os códigos puros somente na memória da requisição.
     * Na sessão é persistido apenas um envelope criptografado,
     * vinculado ao mesmo TTL da pré-autenticação.
     *
     * @param list<string> $codigos
     */
    public static function storeRecoveryCodes(
        array $codigos
    ): void {
        $pending = self::get();

        if ($pending === null) {
            throw new RuntimeException(
                'Não há autenticação pendente para armazenar códigos.'
            );
        }

        if ($codigos === []) {
            throw new RuntimeException(
                'Nenhum código de recuperação foi fornecido.'
            );
        }

        foreach ($codigos as $codigo) {
            if (
                !is_string($codigo)
                || !preg_match(
                    '/^[A-F0-9]{4}(?:-[A-F0-9]{4}){4}$/',
                    $codigo
                )
            ) {
                throw new RuntimeException(
                    'Código de recuperação inválido.'
                );
            }
        }

        $json = json_encode(
            array_values($codigos),
            JSON_UNESCAPED_SLASHES
            | JSON_THROW_ON_ERROR
        );

        $envelope = CryptoHybrid::encryptString($json);

        $_SESSION[self::SESSION_KEY][self::RECOVERY_CODES_KEY] =
            json_encode(
                $envelope,
                JSON_UNESCAPED_SLASHES
                | JSON_THROW_ON_ERROR
            );
    }

    /**
     * @return list<string>|null
     */
    public static function recoveryCodes(): ?array
    {
        $pending = self::get();

        if ($pending === null) {
            return null;
        }

        $envelopeJson =
            $pending[self::RECOVERY_CODES_KEY] ?? null;

        if (
            !is_string($envelopeJson)
            || $envelopeJson === ''
        ) {
            return null;
        }

        try {
            $envelope = json_decode(
                $envelopeJson,
                true,
                512,
                JSON_THROW_ON_ERROR
            );

            if (!is_array($envelope)) {
                throw new RuntimeException(
                    'Envelope de apresentação inválido.'
                );
            }

            $json = CryptoHybrid::decryptString(
                $envelope
            );

            $codigos = json_decode(
                $json,
                true,
                512,
                JSON_THROW_ON_ERROR
            );

            if (!is_array($codigos) || $codigos === []) {
                throw new RuntimeException(
                    'Códigos de apresentação inválidos.'
                );
            }

            $resultado = [];

            foreach ($codigos as $codigo) {
                if (
                    !is_string($codigo)
                    || !preg_match(
                        '/^[A-F0-9]{4}(?:-[A-F0-9]{4}){4}$/',
                        $codigo
                    )
                ) {
                    throw new RuntimeException(
                        'Código de apresentação inválido.'
                    );
                }

                $resultado[] = $codigo;
            }

            return $resultado;

        } catch (Throwable) {
            self::clearRecoveryCodes();

            return null;
        }
    }

    public static function hasRecoveryCodes(): bool
    {
        return self::recoveryCodes() !== null;
    }

    /**
     * Após a confirmação bem-sucedida do TOTP, concede uma janela
     * curta e específica para o usuário salvar os códigos de recuperação.
     */
    public static function extendForRecoveryCodes(): void
    {
        $pending = self::get();

        if ($pending === null) {
            throw new RuntimeException(
                'Não há autenticação pendente para apresentar códigos.'
            );
        }

        $_SESSION[self::SESSION_KEY]['expires_at'] =
            time() + self::RECOVERY_CODES_TTL_SECONDS;
    }

    public static function clearRecoveryCodes(): void
    {
        SecureSession::start();

        if (!isset($_SESSION[self::SESSION_KEY])) {
            return;
        }

        unset(
            $_SESSION[self::SESSION_KEY][self::RECOVERY_CODES_KEY]
        );
    }

    public static function clear(): void
    {
        SecureSession::start();

        unset($_SESSION[self::SESSION_KEY]);
    }

    public static function complete(): void
    {
        /*
         * Delimita a transição:
         * pré-autenticado -> autenticado.
         */
        SecureSession::regenerate();

        self::clear();
    }
}
