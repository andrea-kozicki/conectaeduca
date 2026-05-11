<?php
declare(strict_types=1);

namespace ConectaEduca\Middleware;

use ConectaEduca\Security\SecurityHeaders;

final class SecurityHeadersMiddleware
{
    public static function handle(): void
    {
        SecurityHeaders::apply();
    }
}