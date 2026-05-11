<?php
declare(strict_types=1);

namespace ConectaEduca\Security;

use RuntimeException;

final class CryptoHybrid
{
    public static function decryptEnvelope(array $payload): array
    {
        $encryptedKey = self::base64DecodeRequired($payload['encrypted_key'] ?? null, 'encrypted_key');
        $iv = self::base64DecodeRequired($payload['iv'] ?? null, 'iv');
        $ciphertext = self::base64DecodeRequired($payload['ciphertext'] ?? null, 'ciphertext');
        $tag = self::base64DecodeRequired($payload['tag'] ?? null, 'tag');

        $privateKeyPem = Secrets::fileContents('PRIVATE_KEY_PATH');

        $privateKey = openssl_pkey_get_private($privateKeyPem);

        if ($privateKey === false) {
            throw new RuntimeException('Chave privada inválida.');
        }

        $aesKey = '';

        $ok = openssl_private_decrypt(
            $encryptedKey,
            $aesKey,
            $privateKey,
            OPENSSL_PKCS1_OAEP_PADDING
        );

        if (!$ok || $aesKey === '') {
            throw new RuntimeException('Falha ao descriptografar chave simétrica.');
        }

        $plaintext = openssl_decrypt(
            $ciphertext,
            'aes-256-gcm',
            $aesKey,
            OPENSSL_RAW_DATA,
            $iv,
            $tag
        );

        if ($plaintext === false) {
            throw new RuntimeException('Falha ao descriptografar dados.');
        }

        $decoded = json_decode($plaintext, true);

        if (!is_array($decoded)) {
            throw new RuntimeException('Payload descriptografado não é um JSON válido.');
        }

        return $decoded;
    }

    public static function publicKey(): string
    {
        return Secrets::fileContents('PUBLIC_KEY_PATH');
    }

    private static function base64DecodeRequired(mixed $value, string $field): string
    {
        if (!is_string($value) || trim($value) === '') {
            throw new RuntimeException("Campo criptográfico ausente: {$field}");
        }

        $decoded = base64_decode($value, true);

        if ($decoded === false) {
            throw new RuntimeException("Campo criptográfico inválido: {$field}");
        }

        return $decoded;
    }
}