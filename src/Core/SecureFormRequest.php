<?php
declare(strict_types=1);

namespace ConectaEduca\Core;

use ConectaEduca\Security\CryptoHybrid;

final class SecureFormRequest
{
    private static ?array $cachedJson = null;
    private static ?array $cachedData = null;

    public static function data(): array
    {
        if (self::$cachedData !== null) {
            return self::$cachedData;
        }

        $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

        if ($method !== 'POST') {
            self::$cachedData = [];
            return self::$cachedData;
        }

        $contentType = $_SERVER['CONTENT_TYPE'] ?? '';

        if (str_contains($contentType, 'application/json')) {
            $payload = self::jsonPayload();

            if (self::isEncryptedEnvelope($payload)) {
                self::$cachedData = CryptoHybrid::decryptEnvelope($payload);
                return self::$cachedData;
            }

            self::$cachedData = $payload;
            return self::$cachedData;
        }

        self::$cachedData = $_POST;
        return self::$cachedData;
    }

    public static function csrfToken(?array $data = null): ?string
    {
        $header = $_SERVER['HTTP_X_CSRF_TOKEN'] ?? null;

        if (is_string($header) && $header !== '') {
            return $header;
        }

        $data ??= self::data();
        $token = $data['csrf_token'] ?? null;

        return is_string($token) ? $token : null;
    }

    public static function isEncrypted(): bool
    {
        $contentType = $_SERVER['CONTENT_TYPE'] ?? '';

        if (!str_contains($contentType, 'application/json')) {
            return false;
        }

        return self::isEncryptedEnvelope(self::jsonPayload());
    }

    public static function isEncryptedEnvelope(array $payload): bool
    {
        return isset(
            $payload['encrypted_key'],
            $payload['iv'],
            $payload['tag'],
            $payload['ciphertext']
        );
    }

    private static function jsonPayload(): array
    {
        if (self::$cachedJson !== null) {
            return self::$cachedJson;
        }

        self::$cachedJson = Request::json();

        return self::$cachedJson;
    }
}