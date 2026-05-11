<?php
declare(strict_types=1);

namespace ConectaEduca\Core;

use ConectaEduca\Security\SecurityHeaders;

final class Response
{
    public static function redirect(string $url): void
    {
        header('Location: ' . $url);
        exit;
    }

    public static function json(array $data, int $status = 200): void
    {
        http_response_code($status);
        SecurityHeaders::json();

        echo json_encode(
            $data,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR
        );

        exit;
    }

    public static function notFound(): void
    {
        http_response_code(404);
        echo 'Página não encontrada.';
        exit;
    }
}