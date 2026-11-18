<?php
declare(strict_types=1);

namespace ConectaEduca\Core;

use InvalidArgumentException;
use LengthException;

final class Request
{
    public static function method(): string
    {
        return strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
    }

    public static function path(): string
    {
        $uri = $_SERVER['REQUEST_URI'] ?? '/';
        $path = parse_url($uri, PHP_URL_PATH);

        return '/' . trim((string) $path, '/');
    }

    public static function input(string $key, mixed $default = null): mixed
    {
        return $_POST[$key] ?? $_GET[$key] ?? $default;
    }

    public static function post(string $key, mixed $default = null): mixed
    {
        return $_POST[$key] ?? $default;
    }

    public static function get(string $key, mixed $default = null): mixed
    {
        return $_GET[$key] ?? $default;
    }

    public static function json(?int $maxBytes = null): array
    {
        if ($maxBytes !== null && $maxBytes < 1) {
            throw new InvalidArgumentException('Limite de JSON inválido.');
        }

        // O Content-Length é apenas um atalho: a leitura limitada abaixo
        // continua protegendo requisições sem tamanho declarado.
        $declaredLength = $_SERVER['CONTENT_LENGTH'] ?? null;
        if (
            $maxBytes !== null
            && is_scalar($declaredLength)
            && ctype_digit((string) $declaredLength)
            && (int) $declaredLength > $maxBytes
        ) {
            throw new LengthException('Corpo JSON acima do limite permitido.');
        }

        $raw = $maxBytes === null
            ? file_get_contents('php://input')
            : file_get_contents('php://input', false, null, 0, $maxBytes + 1);

        if ($maxBytes !== null && $raw !== false && strlen($raw) > $maxBytes) {
            throw new LengthException('Corpo JSON acima do limite permitido.');
        }

        if ($raw === false || trim($raw) === '') {
            return [];
        }

        $decoded = json_decode($raw, true);

        return is_array($decoded) ? $decoded : [];
    }
}
