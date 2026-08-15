<?php

declare(strict_types=1);

namespace ConectaEduca\Security;

use ConectaEduca\Config\Database;
use ConectaEduca\Repository\RateLimitRepository;
use ConectaEduca\Repository\RateLimitStore;
use InvalidArgumentException;

final class RateLimiter
{
    private static ?RateLimitStore $store = null;

    public static function allow(
        string $action,
        int $limit = 10,
        int $windowSeconds = 60,
        ?string $identifier = null
    ): bool {
        self::validateParameters(
            $action,
            $limit,
            $windowSeconds
        );

        $identifier ??= self::defaultIdentifier();

        $identifierHash = hash(
            'sha256',
            $identifier
        );

        return self::store()->consume(
            $action,
            $identifierHash,
            $limit,
            $windowSeconds
        );
    }

    public static function requireAllowed(
        string $action,
        int $limit = 10,
        int $windowSeconds = 60,
        ?string $identifier = null
    ): void {
        if (
            self::allow(
                $action,
                $limit,
                $windowSeconds,
                $identifier
            )
        ) {
            return;
        }

        http_response_code(429);

        AuditLogger::log(
            'rate_limit_blocked',
            [
                'action' => $action,
            ]
        );

        exit(
            'Muitas requisições. '
            . 'Tente novamente mais tarde.'
        );
    }

    public static function reset(
        string $action,
        ?string $identifier = null
    ): void {
        $identifier ??= self::defaultIdentifier();

        $identifierHash = hash(
            'sha256',
            $identifier
        );

        self::store()->reset(
            $action,
            $identifierHash
        );
    }

    /*
     * Permite substituir o backend de armazenamento.
     *
     * Em produção, null faz o componente voltar ao MariaDB.
     * Nos testes unitários podemos usar uma implementação
     * exclusivamente em memória.
     */
    public static function setStore(
        ?RateLimitStore $store
    ): void {
        self::$store = $store;
    }

    private static function store(): RateLimitStore
    {
        if (self::$store === null) {
            self::$store = new RateLimitRepository(
                Database::connect()
            );
        }

        return self::$store;
    }

    private static function defaultIdentifier(): string
    {
        $ip = trim(
            (string) (
                $_SERVER['REMOTE_ADDR']
                ?? 'cli'
            )
        );

        if ($ip === '') {
            $ip = 'desconhecido';
        }

        return 'ip:' . $ip;
    }

    private static function validateParameters(
        string $action,
        int $limit,
        int $windowSeconds
    ): void {
        if (
            $action === ''
            || strlen($action) > 80
        ) {
            throw new InvalidArgumentException(
                'Ação de rate limit inválida.'
            );
        }

        if ($limit < 1) {
            throw new InvalidArgumentException(
                'Limite deve ser maior que zero.'
            );
        }

        if ($windowSeconds < 1) {
            throw new InvalidArgumentException(
                'Janela deve ser maior que zero.'
            );
        }
    }
}
