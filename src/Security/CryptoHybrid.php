<?php
declare(strict_types=1);

namespace ConectaEduca\Security;

use ConectaEduca\Config\Env;
use phpseclib4\Crypt\PublicKeyLoader;
use phpseclib4\Crypt\RSA;
use phpseclib4\Crypt\RSA\PrivateKey;
use phpseclib4\Crypt\RSA\PublicKey;
use RuntimeException;
use Throwable;

final class CryptoHybrid
{
    private const CIPHER = 'aes-256-gcm';
    private const AES_KEY_BYTES = 32;
    private const IV_BYTES = 12;
    private const TAG_BYTES = 16;

    public const LEGACY_VERSION = 1;
    public const CURRENT_VERSION = 2;

    /**
     * Identificador histórico já persistido em mensagens_contato.
     * A ausência de version no envelope também é interpretada como v1.
     */
    public const LEGACY_ALGORITHM = 'AES-256-GCM + RSA-OAEP';

    /**
     * Novas escritas usam OAEP SHA-256 / MGF1-SHA256.
     */
    public const CURRENT_ALGORITHM = 'AES-256-GCM + RSA-OAEP-SHA256';

    private const LEGACY_OAEP_HASH = 'sha1';
    private const CURRENT_OAEP_HASH = 'sha256';

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

    public static function encryptString(
        string $plaintext,
        ?string $publicKeyPath = null
    ): array {
        if ($plaintext === '') {
            throw new RuntimeException(
                'Texto para criptografia não pode ser vazio.'
            );
        }

        $publicKeyPem = self::readKeyFile(
            $publicKeyPath ?? self::defaultPublicKeyPath(),
            'chave pública'
        );

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

        if (
            $ciphertext === false
            || strlen($tag) !== self::TAG_BYTES
        ) {
            throw new RuntimeException(
                'Falha ao criptografar o conteúdo sensível.'
            );
        }

        $encryptedKey = self::rsaEncrypt(
            $aesKey,
            $publicKeyPem,
            self::CURRENT_OAEP_HASH
        );

        return [
            'version' => self::CURRENT_VERSION,
            'algorithm' => self::CURRENT_ALGORITHM,
            'encrypted_key' => base64_encode($encryptedKey),
            'iv' => base64_encode($iv),
            'tag' => base64_encode($tag),
            'ciphertext' => base64_encode($ciphertext),
        ];
    }

    public static function decryptString(
        array $payload,
        ?string $privateKeyPath = null
    ): string {
        $profile = self::resolveProfile($payload);

        $encryptedKey = self::base64DecodeRequired(
            $payload['encrypted_key'] ?? null,
            'encrypted_key'
        );
        $iv = self::base64DecodeRequired(
            $payload['iv'] ?? null,
            'iv'
        );
        $tag = self::base64DecodeRequired(
            $payload['tag'] ?? null,
            'tag'
        );
        $ciphertext = self::base64DecodeRequired(
            $payload['ciphertext'] ?? null,
            'ciphertext'
        );

        if (strlen($iv) !== self::IV_BYTES) {
            throw new RuntimeException(
                'IV criptográfico possui tamanho inválido.'
            );
        }

        /*
         * openssl_decrypt() não valida o tamanho do tag GCM por nós.
         * Exigimos explicitamente os 128 bits gerados pelo protocolo.
         */
        if (strlen($tag) !== self::TAG_BYTES) {
            throw new RuntimeException(
                'Tag de autenticação possui tamanho inválido.'
            );
        }

        $privateKeyPem = self::readKeyFile(
            $privateKeyPath ?? self::defaultPrivateKeyPath(),
            'chave privada'
        );

        $aesKey = self::rsaDecrypt(
            $encryptedKey,
            $privateKeyPem,
            $profile['hash']
        );

        if (strlen($aesKey) !== self::AES_KEY_BYTES) {
            throw new RuntimeException(
                'Chave simétrica recuperada possui tamanho inválido.'
            );
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
            throw new RuntimeException(
                'Falha ao descriptografar o conteúdo sensível.'
            );
        }

        return $plaintext;
    }

    public static function encryptEnvelope(
        array $payload,
        ?string $publicKeyPath = null
    ): array {
        $json = json_encode(
            $payload,
            JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR
        );

        return self::encryptString(
            $json,
            $publicKeyPath
        );
    }

    public static function decryptEnvelope(
        array $payload,
        ?string $privateKeyPath = null
    ): array {
        $json = self::decryptString(
            $payload,
            $privateKeyPath
        );

        $decoded = json_decode(
            $json,
            true,
            512,
            JSON_THROW_ON_ERROR
        );

        if (!is_array($decoded)) {
            throw new RuntimeException(
                'Envelope descriptografado não contém um objeto JSON válido.'
            );
        }

        return $decoded;
    }

    /**
     * Retorna apenas metadados não sensíveis sobre o perfil do envelope.
     *
     * @return array{version:int,algorithm:string,hash:string}
     */
    public static function profile(array $payload): array
    {
        return self::resolveProfile($payload);
    }

    /**
     * @return array{version:int,algorithm:string,hash:string}
     */
    private static function resolveProfile(array $payload): array
    {
        $versionRaw = $payload['version'] ?? null;
        $algorithmRaw = $payload['algorithm'] ?? null;

        $algorithm = is_string($algorithmRaw)
            ? trim($algorithmRaw)
            : '';

        /*
         * Retrocompatibilidade:
         * envelopes históricos não possuíam version. Alguns também não
         * carregavam algorithm porque o banco o guardava em coluna separada.
         */
        if ($versionRaw === null || $versionRaw === '') {
            if (
                $algorithm === ''
                || $algorithm === self::LEGACY_ALGORITHM
            ) {
                return [
                    'version' => self::LEGACY_VERSION,
                    'algorithm' => self::LEGACY_ALGORITHM,
                    'hash' => self::LEGACY_OAEP_HASH,
                ];
            }

            if ($algorithm === self::CURRENT_ALGORITHM) {
                return [
                    'version' => self::CURRENT_VERSION,
                    'algorithm' => self::CURRENT_ALGORITHM,
                    'hash' => self::CURRENT_OAEP_HASH,
                ];
            }

            throw new RuntimeException(
                'Algoritmo de envelope criptográfico desconhecido.'
            );
        }

        if (
            !is_int($versionRaw)
            && !(
                is_string($versionRaw)
                && preg_match('/^[12]$/', $versionRaw) === 1
            )
        ) {
            throw new RuntimeException(
                'Versão de envelope criptográfico inválida.'
            );
        }

        $version = (int) $versionRaw;

        if ($version === self::LEGACY_VERSION) {
            if (
                $algorithm !== ''
                && $algorithm !== self::LEGACY_ALGORITHM
            ) {
                throw new RuntimeException(
                    'Metadados incompatíveis no envelope criptográfico legado.'
                );
            }

            return [
                'version' => self::LEGACY_VERSION,
                'algorithm' => self::LEGACY_ALGORITHM,
                'hash' => self::LEGACY_OAEP_HASH,
            ];
        }

        if ($version === self::CURRENT_VERSION) {
            if ($algorithm !== self::CURRENT_ALGORITHM) {
                throw new RuntimeException(
                    'Metadados incompatíveis no envelope criptográfico v2.'
                );
            }

            return [
                'version' => self::CURRENT_VERSION,
                'algorithm' => self::CURRENT_ALGORITHM,
                'hash' => self::CURRENT_OAEP_HASH,
            ];
        }

        throw new RuntimeException(
            'Versão de envelope criptográfico não suportada.'
        );
    }

    private static function rsaEncrypt(
        string $plaintext,
        string $publicKeyPem,
        string $hash
    ): string {
        try {
            $key = PublicKeyLoader::load($publicKeyPem);

            if (!$key instanceof PublicKey) {
                throw new RuntimeException(
                    'Material informado não contém uma chave pública RSA.'
                );
            }

            $key = $key
                ->withPadding(RSA::ENCRYPTION_OAEP)
                ->withHash($hash)
                ->withMGFHash($hash);

            return $key->encrypt($plaintext);
        } catch (Throwable $e) {
            throw new RuntimeException(
                'Falha ao proteger a chave simétrica.',
                0,
                $e
            );
        }
    }

    private static function rsaDecrypt(
        string $ciphertext,
        string $privateKeyPem,
        string $hash
    ): string {
        try {
            $key = PublicKeyLoader::load($privateKeyPem);

            if (!$key instanceof PrivateKey) {
                throw new RuntimeException(
                    'Material informado não contém uma chave privada RSA.'
                );
            }

            $key = $key
                ->withPadding(RSA::ENCRYPTION_OAEP)
                ->withHash($hash)
                ->withMGFHash($hash);

            return $key->decrypt($ciphertext);
        } catch (Throwable $e) {
            throw new RuntimeException(
                'Falha ao recuperar a chave simétrica.',
                0,
                $e
            );
        }
    }

    private static function base64DecodeRequired(
        mixed $value,
        string $field
    ): string {
        if (!is_string($value) || trim($value) === '') {
            throw new RuntimeException(
                "Campo criptográfico obrigatório ausente: {$field}."
            );
        }

        $decoded = base64_decode($value, true);

        if ($decoded === false || $decoded === '') {
            throw new RuntimeException(
                "Campo criptográfico inválido: {$field}."
            );
        }

        return $decoded;
    }

    private static function readKeyFile(
        string $path,
        string $label
    ): string {
        if (!is_file($path) || !is_readable($path)) {
            throw new RuntimeException(
                "Arquivo de {$label} não encontrado ou sem permissão de leitura."
            );
        }

        $content = file_get_contents($path);

        if ($content === false || trim($content) === '') {
            throw new RuntimeException(
                "Arquivo de {$label} está vazio ou não pôde ser lido."
            );
        }

        return $content;
    }

    private static function defaultPrivateKeyPath(): string
    {
        return self::configuredKeyPath(
            'PRIVATE_KEY_PATH',
            'storage/keys/private.pem'
        );
    }

    private static function defaultPublicKeyPath(): string
    {
        return self::configuredKeyPath(
            'PUBLIC_KEY_PATH',
            'storage/keys/public.pem'
        );
    }

    private static function configuredKeyPath(
        string $envKey,
        string $default
    ): string {
        $path = Env::get(
            $envKey,
            $default
        ) ?? $default;

        $path = trim($path);

        if ($path === '') {
            throw new RuntimeException(
                "Caminho de chave criptográfica vazio em {$envKey}."
            );
        }

        if (
            !str_starts_with($path, '/')
            && preg_match(
                '/^[A-Za-z]:[\\\\\/]/',
                $path
            ) !== 1
        ) {
            $path = Env::rootPath($path);
        }

        return $path;
    }
}
