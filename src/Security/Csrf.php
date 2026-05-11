<?php
declare(strict_types=1);

namespace ConectaEduca\Security;

final class Csrf
{
    private const SESSION_KEY = '_csrf_token';

    public static function token(): string
    {
        SecureSession::start();

        if (empty($_SESSION[self::SESSION_KEY])) {
            $_SESSION[self::SESSION_KEY] = bin2hex(random_bytes(32));
        }

        return $_SESSION[self::SESSION_KEY];
    }

    public static function validate(?string $token): bool
    {
        SecureSession::start();

        if (empty($_SESSION[self::SESSION_KEY]) || empty($token)) {
            return false;
        }

        return hash_equals($_SESSION[self::SESSION_KEY], $token);
    }

    public static function requireValid(?string $token): void
    {
        if (!self::validate($token)) {
            http_response_code(419);
            exit('Requisição bloqueada: token CSRF inválido.');
        }
    }

    public static function inputField(): string
    {
        $token = htmlspecialchars(self::token(), ENT_QUOTES | ENT_HTML5, 'UTF-8');

        return '<input type="hidden" name="csrf_token" value="' . $token . '">';
    }
}