<?php
declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\CryptoHybrid;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;
use RuntimeException;

#[TestDox('Criptografia híbrida')]
final class CryptoHybridTest extends TestCase
{
    #[TestDox('Rejeita envelope criptográfico sem campos obrigatórios')]
    public function testDecryptEnvelopeRejectsMissingFields(): void
    {
        $this->expectException(RuntimeException::class);

        CryptoHybrid::decryptEnvelope([]);
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
        ]);
    }

    #[TestDox('Lê a chave pública quando configurada')]
    public function testPublicKeyCanBeReadWhenConfigured(): void
    {
        try {
            $publicKey = CryptoHybrid::publicKey();
        } catch (RuntimeException $exception) {
            $this->markTestSkipped('Chave pública não configurada neste ambiente de teste.');
        }

        $this->assertStringContainsString('BEGIN PUBLIC KEY', $publicKey);
    }

    #[TestDox('Descriptografa o payload original quando as chaves estão configuradas')]
    public function testDecryptEnvelopeRestoresOriginalPayloadWhenKeysAreConfigured(): void
    {
        try {
            $publicKeyPem = CryptoHybrid::publicKey();
        } catch (RuntimeException $exception) {
            $this->markTestSkipped('Chaves RSA não configuradas neste ambiente de teste.');
        }

        $publicKey = openssl_pkey_get_public($publicKeyPem);

        if ($publicKey === false) {
            $this->markTestSkipped('Chave pública inválida neste ambiente de teste.');
        }

        $payload = [
            'nome' => 'Usuária Teste',
            'email' => 'teste.crypto@conectaeduca.local',
            'csrf_token' => 'token-de-teste',
        ];

        $plaintext = json_encode($payload, JSON_THROW_ON_ERROR);

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

        $this->assertIsString($ciphertext);

        $encryptedKey = '';

        $encrypted = openssl_public_encrypt(
            $aesKey,
            $encryptedKey,
            $publicKey,
            OPENSSL_PKCS1_OAEP_PADDING
        );

        $this->assertTrue($encrypted);

        $envelope = [
            'encrypted_key' => base64_encode($encryptedKey),
            'iv' => base64_encode($iv),
            'ciphertext' => base64_encode($ciphertext),
            'tag' => base64_encode($tag),
        ];

        $decrypted = CryptoHybrid::decryptEnvelope($envelope);

        $this->assertSame($payload, $decrypted);
    }

    #[TestDox('Respeita PRIVATE_KEY_PATH configurado no ambiente')]
    public function testPrivateKeyUsesConfiguredEnvironmentPath(): void
    {
        $file = tempnam(sys_get_temp_dir(), 'ce-private-key-');
        self::assertNotFalse($file);
        file_put_contents($file, "-----BEGIN TEST PRIVATE KEY-----\nprivada-configurada\n-----END TEST PRIVATE KEY-----\n");

        $_ENV['PRIVATE_KEY_PATH'] = $file;

        try {
            self::assertStringContainsString('privada-configurada', CryptoHybrid::privateKey());
        } finally {
            unset($_ENV['PRIVATE_KEY_PATH'], $_SERVER['PRIVATE_KEY_PATH']);
            putenv('PRIVATE_KEY_PATH');
            @unlink($file);
        }
    }

    #[TestDox('Respeita PUBLIC_KEY_PATH configurado no ambiente')]
    public function testPublicKeyUsesConfiguredEnvironmentPath(): void
    {
        $file = tempnam(sys_get_temp_dir(), 'ce-public-key-');
        self::assertNotFalse($file);
        file_put_contents($file, "-----BEGIN TEST PUBLIC KEY-----\npublica-configurada\n-----END TEST PUBLIC KEY-----\n");

        $_ENV['PUBLIC_KEY_PATH'] = $file;

        try {
            self::assertStringContainsString('publica-configurada', CryptoHybrid::publicKey());
        } finally {
            unset($_ENV['PUBLIC_KEY_PATH'], $_SERVER['PUBLIC_KEY_PATH']);
            putenv('PUBLIC_KEY_PATH');
            @unlink($file);
        }
    }

}
