<?php
declare(strict_types=1);

namespace ConectaEduca\Middleware;

use ConectaEduca\Security\Csrf;

final class CsrfMiddleware
{
    public static function validatePost(): void
    {
        $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

        if (!in_array($method, ['POST', 'PUT', 'PATCH', 'DELETE'], true)) {
            return;
        }

        $token = $_POST['csrf_token'] ?? $_SERVER['HTTP_X_CSRF_TOKEN'] ?? null;

        Csrf::requireValid(is_string($token) ? $token : null);
    }
}