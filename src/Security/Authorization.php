<?php
declare(strict_types=1);

namespace ConectaEduca\Security;

final class Authorization
{
    public static function user(): ?array
    {
        SecureSession::start();

        return $_SESSION['user'] ?? null;
    }

    public static function check(): bool
    {
        return self::user() !== null;
    }

    public static function requireAuth(): array
    {
        $user = self::user();

        if ($user === null) {
            http_response_code(401);
            AuditLogger::log('unauthorized_access_attempt');
            exit('Acesso não autenticado.');
        }

        return $user;
    }

    public static function hasRole(string $role): bool
    {
        $user = self::user();

        if ($user === null) {
            return false;
        }

        return ($user['role'] ?? '') === $role;
    }

    public static function requireRole(string $role): array
    {
        $user = self::requireAuth();

        if (($user['role'] ?? '') !== $role) {
            http_response_code(403);
            AuditLogger::log('forbidden_access_attempt', [
                'required_role' => $role,
                'actual_role' => $user['role'] ?? null,
            ]);
            exit('Acesso negado.');
        }

        return $user;
    }

    public static function requireAnyRole(array $roles): array
    {
        $user = self::requireAuth();

        if (!in_array($user['role'] ?? '', $roles, true)) {
            http_response_code(403);
            AuditLogger::log('forbidden_access_attempt', [
                'required_roles' => $roles,
                'actual_role' => $user['role'] ?? null,
            ]);
            exit('Acesso negado.');
        }

        return $user;
    }
}