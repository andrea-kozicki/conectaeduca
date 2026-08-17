<?php
declare(strict_types=1);

namespace ConectaEduca\Security;

use ConectaEduca\Config\Env;
use RuntimeException;

final class CryptoHybrid
{
    private const CIPHER = 'aes-256-gcm';
    private const AES_KEY_BYTES = 32;
    private const IV_BYTES = 12;

    public static function publicKey(?string $publicKeyPath = null): string
    {
        return self::readKeyFile(
            $publicKeyPath ?? self::defaultPublicKeyPath(),
            'chave pública'
        );
    }

    public static function privateKey(?string $privateKeyPath = null): string
    {
        return self::readKeyFile(
            $privateKeyPath ?? self::defaultPrivateKeyPath(),
            'chave privada'
        );
    }
    public static function encryptString(string $plaintext, ?string $publicKeyPath = null): array
    {
        if ($plaintext === '') {
            throw new RuntimeException('Texto para criptografia não pode ser vazio.');
        }

        $publicKeyPem = self::readKeyFile($publicKeyPath ?? self::defaultPublicKeyPath(), 'chave pública');
        $publicKey = openssl_pkey_get_public($publicKeyPem);

        if ($publicKey === false) {
            throw new RuntimeException('Não foi possível carregar a chave pública.');
        }

        $aesKey = random_bytes(self::AES_KEY_BYTES);
        $iv = random_bytes(self::IV_BYTES);
        $tag = '';

        $ciphertext = openssl_encrypt(
            $plaintext,
            self::CIPHER,
            $aesKey,
            OPENSSL_RAW_DATA,
            $iv,
            $tag
        );

        if ($ciphertext === false || $tag === '') {
            throw new RuntimeException('Falha ao criptografar o conteúdo sensível.');
        }

        $encryptedKey = '';

        $ok = openssl_public_encrypt(
            $aesKey,
            $encryptedKey,
            $publicKey,
            OPENSSL_PKCS1_OAEP_PADDING
        );

        if (!$ok) {
            throw new RuntimeException('Falha ao proteger a chave simétrica.');
        }

        return [
            'algorithm' => 'AES-256-GCM + RSA-OAEP',
            'encrypted_key' => base64_encode($encryptedKey),
            'iv' => base64_encode($iv),
            'tag' => base64_encode($tag),
            'ciphertext' => base64_encode($ciphertext),
        ];
    }

    public static function decryptString(array $payload, ?string $privateKeyPath = null): string
    {
        $encryptedKey = self::base64DecodeRequired($payload['encrypted_key'] ?? null, 'encrypted_key');
        $iv = self::base64DecodeRequired($payload['iv'] ?? null, 'iv');
        $tag = self::base64DecodeRequired($payload['tag'] ?? null, 'tag');
        $ciphertext = self::base64DecodeRequired($payload['ciphertext'] ?? null, 'ciphertext');

        $privateKeyPem = self::readKeyFile($privateKeyPath ?? self::defaultPrivateKeyPath(), 'chave privada');
        $privateKey = openssl_pkey_get_private($privateKeyPem);

        if ($privateKey === false) {
            throw new RuntimeException('Não foi possível carregar a chave privada.');
        }

        $aesKey = '';

        $ok = openssl_private_decrypt(
            $encryptedKey,
            $aesKey,
            $privateKey,
            OPENSSL_PKCS1_OAEP_PADDING
        );

        if (!$ok || $aesKey === '') {
            throw new RuntimeException('Falha ao recuperar a chave simétrica.');
        }

        $plaintext = openssl_decrypt(
            $ciphertext,
            self::CIPHER,
            $aesKey,
            OPENSSL_RAW_DATA,
            $iv,
            $tag
        );

        if ($plaintext === false) {
            throw new RuntimeException('Falha ao descriptografar o conteúdo sensível.');
        }

        return $plaintext;
    }

    public static function encryptEnvelope(array $payload, ?string $publicKeyPath = null): array
    {
        $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);

        return self::encryptString($json, $publicKeyPath);
    }

    public static function decryptEnvelope(array $payload, ?string $privateKeyPath = null): array
    {
        $json = self::decryptString($payload, $privateKeyPath);
        $decoded = json_decode($json, true, 512, JSON_THROW_ON_ERROR);

        if (!is_array($decoded)) {
            throw new RuntimeException('Envelope descriptografado não contém um objeto JSON válido.');
        }

        return $decoded;
    }

    private static function base64DecodeRequired(mixed $value, string $field): string
    {
        if (!is_string($value) || trim($value) === '') {
            throw new RuntimeException("Campo criptográfico obrigatório ausente: {$field}.");
        }

        $decoded = base64_decode($value, true);

        if ($decoded === false) {
            throw new RuntimeException("Campo criptográfico inválido: {$field}.");
        }

        return $decoded;
    }

    private static function readKeyFile(string $path, string $label): string
    {
        if (!is_file($path) || !is_readable($path)) {
            throw new RuntimeException("Arquivo de {$label} não encontrado ou sem permissão de leitura.");
        }

        $content = file_get_contents($path);

        if ($content === false || trim($content) === '') {
            throw new RuntimeException("Arquivo de {$label} está vazio ou não pôde ser lido.");
        }

        return $content;
    }

    private static function defaultPrivateKeyPath(): string
    {
        return self::configuredKeyPath('PRIVATE_KEY_PATH', 'storage/keys/private.pem');
    }

    private static function defaultPublicKeyPath(): string
    {
        return self::configuredKeyPath('PUBLIC_KEY_PATH', 'storage/keys/public.pem');
    }

    private static function configuredKeyPath(string $envKey, string $default): string
    {
        $path = Env::get($envKey, $default) ?? $default;
        $path = trim($path);

        if ($path === '') {
            throw new RuntimeException("Caminho de chave criptográfica vazio em {$envKey}.");
        }

        if (!str_starts_with($path, '/')
            && preg_match('/^[A-Za-z]:[\\\\\/]/', $path) !== 1
        ) {
            $path = Env::rootPath($path);
        }

        return $path;
    }
}