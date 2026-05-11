<?php
declare(strict_types=1);

namespace ConectaEduca\Security;

use Throwable;

final class ErrorHandler
{
    public static function register(bool $debug = false): void
    {
        set_exception_handler(function (Throwable $e) use ($debug): void {
            error_log('[UNCAUGHT_EXCEPTION] ' . $e->getMessage());

            http_response_code(500);

            if ($debug) {
                echo '<pre>';
                echo OutputEncoder::html($e->getMessage());
                echo "\n\n";
                echo OutputEncoder::html($e->getTraceAsString());
                echo '</pre>';
                return;
            }

            echo 'Erro interno. Tente novamente mais tarde.';
        });

        set_error_handler(function (int $severity, string $message, string $file, int $line): bool {
            error_log("[PHP_ERROR] {$message} em {$file}:{$line}");
            return false;
        });
    }
}