<?php
declare(strict_types=1);

namespace ConectaEduca\Security;

use ConectaEduca\Config\Env;

final class AuditLogger
{
    public static function log(string $event, array $context = []): void
    {
        $logDir = Env::rootPath('storage/logs');

        if (!is_dir($logDir)) {
            mkdir($logDir, 0750, true);
        }

        $record = [
            'timestamp' => date('c'),
            'event' => $event,
            'ip' => $_SERVER['REMOTE_ADDR'] ?? 'cli',
            'user_agent' => $_SERVER['HTTP_USER_AGENT'] ?? 'cli',
            'user_id' => $_SESSION['user']['id'] ?? null,
            'context' => self::redact($context),
        ];

        file_put_contents(
            $logDir . '/audit.log',
            json_encode($record, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . PHP_EOL,
            FILE_APPEND | LOCK_EX
        );
    }

    private static function redact(array $context): array
    {
        $sensitiveKeys = [
            'password',
            'senha',
            'token',
            'access_token',
            'id_token',
            'refresh_token',
            'client_secret',
            'private_key',
        ];

        foreach ($context as $key => $value) {
            if (in_array(strtolower((string) $key), $sensitiveKeys, true)) {
                $context[$key] = '[REDACTED]';
            }

            if (is_array($value)) {
                $context[$key] = self::redact($value);
            }
        }

        return $context;
    }
}