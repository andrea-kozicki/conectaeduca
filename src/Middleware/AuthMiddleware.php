<?php
declare(strict_types=1);

namespace ConectaEduca\Middleware;

use ConectaEduca\Security\Authorization;

final class AuthMiddleware
{
    public static function requireAuth(): array
    {
        return Authorization::requireAuth();
    }

    public static function requireRole(string $role): array
    {
        return Authorization::requireRole($role);
    }

    public static function requireAnyRole(array $roles): array
    {
        return Authorization::requireAnyRole($roles);
    }
}