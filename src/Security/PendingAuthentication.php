<?php

declare(strict_types=1);

namespace ConectaEduca\Security;

final class PendingAuthentication
{
    private const SESSION_KEY = 'mfa_pending';
    private const TTL_SECONDS = 300;

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
