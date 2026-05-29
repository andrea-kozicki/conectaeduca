<?php
declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\CryptoHybrid;
use PHPUnit\Framework\TestCase;
use RuntimeException;

final class CryptoHybridTest extends TestCase
{
    public function testDecryptEnvelopeRejectsMissingFields(): void
    {
        $this->expectException(RuntimeException::class);

        CryptoHybrid::decryptEnvelope([]);
    }

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

    public function testPublicKeyCanBeReadWhenConfigured(): void
    {
        try {
            $publicKey = CryptoHybrid::publicKey();
        } catch (RuntimeException $exception) {
            $this->markTestSkipped('Chave pública não configurada neste ambiente de teste.');
        }

        $this->assertStringContainsString('BEGIN PUBLIC KEY', $publicKey);
    }

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
}
