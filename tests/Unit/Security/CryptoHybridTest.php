<?php
declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\CryptoHybrid;
use phpseclib4\Crypt\PublicKeyLoader;
use phpseclib4\Crypt\RSA;
use phpseclib4\Crypt\RSA\PublicKey;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;
use RuntimeException;

#[TestDox('Criptografia híbrida versionada')]
final class CryptoHybridTest extends TestCase
{
    private static string $privateKeyFile;
    private static string $publicKeyFile;

    public static function setUpBeforeClass(): void
    {
        $key = openssl_pkey_new([
            'private_key_bits' => 2048,
            'private_key_type' => OPENSSL_KEYTYPE_RSA,
        ]);

        self::assertNotFalse($key);

        $privatePem = '';
        self::assertTrue(
            openssl_pkey_export(
                $key,
                $privatePem
            )
        );

        $details = openssl_pkey_get_details($key);
        self::assertIsArray($details);
        self::assertArrayHasKey('key', $details);

        self::$privateKeyFile = tempnam(
            sys_get_temp_dir(),
            'ce-crypto-private-'
        );
        self::$publicKeyFile = tempnam(
            sys_get_temp_dir(),
            'ce-crypto-public-'
        );

        self::assertNotFalse(self::$privateKeyFile);
        self::assertNotFalse(self::$publicKeyFile);

        file_put_contents(
            self::$privateKeyFile,
            $privatePem
        );
        file_put_contents(
            self::$publicKeyFile,
            (string) $details['key']
        );
    }

    public static function tearDownAfterClass(): void
    {
        @unlink(self::$privateKeyFile);
        @unlink(self::$publicKeyFile);
    }

    #[TestDox('Rejeita envelope criptográfico sem campos obrigatórios')]
    public function testDecryptEnvelopeRejectsMissingFields(): void
    {
        $this->expectException(RuntimeException::class);

        CryptoHybrid::decryptEnvelope(
            [],
            self::$privateKeyFile
        );
    }

    #[TestDox('Rejeita envelope criptográfico com base64 inválido')]
    public function testDecryptEnvelopeRejectsInvalidBase64(): void
    {
        $this->expectException(RuntimeException::class);

        CryptoHybrid::decryptEnvelope([
            'encrypted_key' => 'isso-nao-e-base64-valido###',
            'iv' => base64_encode(random_bytes(12)),
            'ciphertext' => base64_encode('texto'),
            'tag' => base64_encode(random_bytes(16)),
        ], self::$privateKeyFile);
    }

    #[TestDox('Novas escritas usam envelope v2 com RSA-OAEP SHA-256')]
    public function testEncryptStringEmitsVersion2Sha256Envelope(): void
    {
        $envelope = CryptoHybrid::encryptString(
            'segredo-v2',
            self::$publicKeyFile
        );

        self::assertSame(
            CryptoHybrid::CURRENT_VERSION,
            $envelope['version']
        );
        self::assertSame(
            CryptoHybrid::CURRENT_ALGORITHM,
            $envelope['algorithm']
        );
        self::assertSame(
            'segredo-v2',
            CryptoHybrid::decryptString(
                $envelope,
                self::$privateKeyFile
            )
        );
    }

    #[TestDox('Envelope JSON v2 preserva o payload original')]
    public function testEncryptEnvelopeV2RestoresOriginalPayload(): void
    {
        $payload = [
            'nome' => 'Usuária Teste',
            'email' => 'teste.crypto@conectaeduca.local',
            'csrf_token' => 'token-de-teste',
        ];

        $envelope = CryptoHybrid::encryptEnvelope(
            $payload,
            self::$publicKeyFile
        );

        self::assertSame(
            $payload,
            CryptoHybrid::decryptEnvelope(
                $envelope,
                self::$privateKeyFile
            )
        );
    }

    #[TestDox('Continua lendo envelope legado OAEP SHA-1 sem metadados de versão')]
    public function testDecryptStringReadsLegacySha1Envelope(): void
    {
        $plaintext = 'segredo-legado';
        $legacy = $this->legacyEnvelope($plaintext);

        self::assertArrayNotHasKey(
            'version',
            $legacy
        );

        self::assertSame(
            $plaintext,
            CryptoHybrid::decryptString(
                $legacy,
                self::$privateKeyFile
            )
        );

        self::assertSame(
            CryptoHybrid::LEGACY_VERSION,
            CryptoHybrid::profile($legacy)['version']
        );
    }

    #[TestDox('Continua lendo algoritmo legado persistido em coluna separada')]
    public function testDecryptStringReadsLegacyAlgorithmMetadata(): void
    {
        $legacy = $this->legacyEnvelope(
            'mensagem-antiga'
        );

        $legacy['algorithm'] =
            CryptoHybrid::LEGACY_ALGORITHM;

        self::assertSame(
            'mensagem-antiga',
            CryptoHybrid::decryptString(
                $legacy,
                self::$privateKeyFile
            )
        );
    }

    #[TestDox('Rejeita metadados v2 incompatíveis para impedir downgrade silencioso')]
    public function testRejectsMismatchedVersion2Metadata(): void
    {
        $envelope = CryptoHybrid::encryptString(
            'segredo',
            self::$publicKeyFile
        );

        $envelope['algorithm'] =
            CryptoHybrid::LEGACY_ALGORITHM;

        $this->expectException(
            RuntimeException::class
        );

        CryptoHybrid::decryptString(
            $envelope,
            self::$privateKeyFile
        );
    }

    #[TestDox('Rejeita tag GCM truncado antes da descriptografia')]
    public function testRejectsTruncatedGcmTag(): void
    {
        $envelope = CryptoHybrid::encryptString(
            'segredo',
            self::$publicKeyFile
        );

        $envelope['tag'] =
            base64_encode(random_bytes(8));

        $this->expectException(
            RuntimeException::class
        );

        CryptoHybrid::decryptString(
            $envelope,
            self::$privateKeyFile
        );
    }

    #[TestDox('Rejeita IV GCM com tamanho diferente do protocolo')]
    public function testRejectsInvalidIvLength(): void
    {
        $envelope = CryptoHybrid::encryptString(
            'segredo',
            self::$publicKeyFile
        );

        $envelope['iv'] =
            base64_encode(random_bytes(8));

        $this->expectException(
            RuntimeException::class
        );

        CryptoHybrid::decryptString(
            $envelope,
            self::$privateKeyFile
        );
    }

    #[TestDox('Respeita PRIVATE_KEY_PATH configurado no ambiente')]
    public function testPrivateKeyUsesConfiguredEnvironmentPath(): void
    {
        $file = tempnam(
            sys_get_temp_dir(),
            'ce-private-key-'
        );

        self::assertNotFalse($file);

        file_put_contents(
            $file,
            "-----BEGIN TEST PRIVATE KEY-----\n"
            . "privada-configurada\n"
            . "-----END TEST PRIVATE KEY-----\n"
        );

        $_ENV['PRIVATE_KEY_PATH'] = $file;

        try {
            self::assertStringContainsString(
                'privada-configurada',
                CryptoHybrid::privateKey()
            );
        } finally {
            unset(
                $_ENV['PRIVATE_KEY_PATH'],
                $_SERVER['PRIVATE_KEY_PATH']
            );
            putenv('PRIVATE_KEY_PATH');
            @unlink($file);
        }
    }

    #[TestDox('Respeita PUBLIC_KEY_PATH configurado no ambiente')]
    public function testPublicKeyUsesConfiguredEnvironmentPath(): void
    {
        $file = tempnam(
            sys_get_temp_dir(),
            'ce-public-key-'
        );

        self::assertNotFalse($file);

        file_put_contents(
            $file,
            "-----BEGIN TEST PUBLIC KEY-----\n"
            . "publica-configurada\n"
            . "-----END TEST PUBLIC KEY-----\n"
        );

        $_ENV['PUBLIC_KEY_PATH'] = $file;

        try {
            self::assertStringContainsString(
                'publica-configurada',
                CryptoHybrid::publicKey()
            );
        } finally {
            unset(
                $_ENV['PUBLIC_KEY_PATH'],
                $_SERVER['PUBLIC_KEY_PATH']
            );
            putenv('PUBLIC_KEY_PATH');
            @unlink($file);
        }
    }

    private function legacyEnvelope(
        string $plaintext
    ): array {
        $aesKey = random_bytes(32);
        $iv = random_bytes(12);
        $tag = '';

        $ciphertext = openssl_encrypt(
            $plaintext,
            'aes-256-gcm',
            $aesKey,
            OPENSSL_RAW_DATA,
            $iv,
            $tag
        );

        self::assertIsString($ciphertext);
        self::assertSame(16, strlen($tag));

        $publicPem = file_get_contents(
            self::$publicKeyFile
        );
        self::assertIsString($publicPem);

        $publicKey =
            PublicKeyLoader::load($publicPem);

        self::assertInstanceOf(
            PublicKey::class,
            $publicKey
        );

        $publicKey = $publicKey
            ->withPadding(RSA::ENCRYPTION_OAEP)
            ->withHash('sha1')
            ->withMGFHash('sha1');

        $encryptedKey =
            $publicKey->encrypt($aesKey);

        return [
            'encrypted_key' =>
                base64_encode($encryptedKey),
            'iv' => base64_encode($iv),
            'tag' => base64_encode($tag),
            'ciphertext' =>
                base64_encode($ciphertext),
        ];
    }
}
