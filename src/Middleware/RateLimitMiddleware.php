<?php
declare(strict_types=1);

namespace ConectaEduca\Middleware;

use ConectaEduca\Security\RateLimiter;

final class RateLimitMiddleware
{
    public static function login(): void
    {
        RateLimiter::requireAllowed('login', 5, 300);
    }

    public static function cadastro(): void
    {
        RateLimiter::requireAllowed('cadastro', 10, 300);
    }

    public static function geral(): void
    {
        RateLimiter::requireAllowed('geral', 60, 60);
    }
}