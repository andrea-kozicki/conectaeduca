<?php
declare(strict_types=1);

namespace ConectaEduca\Security;

final class RateLimiter
{
    public static function allow(string $action, int $limit = 10, int $windowSeconds = 60): bool
    {
        SecureSession::start();

        $key = '_rate_limit_' . hash('sha256', $action . '|' . ($_SERVER['REMOTE_ADDR'] ?? 'cli'));
        $now = time();

        if (empty($_SESSION[$key])) {
            $_SESSION[$key] = [
                'start' => $now,
                'count' => 1,
            ];

            return true;
        }

        $bucket = $_SESSION[$key];

        if (($now - $bucket['start']) > $windowSeconds) {
            $_SESSION[$key] = [
                'start' => $now,
                'count' => 1,
            ];

            return true;
        }

        if ($bucket['count'] >= $limit) {
            return false;
        }

        $_SESSION[$key]['count']++;

        return true;
    }

    public static function requireAllowed(string $action, int $limit = 10, int $windowSeconds = 60): void
    {
        if (!self::allow($action, $limit, $windowSeconds)) {
            http_response_code(429);
            AuditLogger::log('rate_limit_blocked', ['action' => $action]);
            exit('Muitas requisições. Tente novamente mais tarde.');
        }
    }
}