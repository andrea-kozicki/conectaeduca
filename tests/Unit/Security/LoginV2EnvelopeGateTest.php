<?php
declare(strict_types=1);

namespace ConectaEduca\Tests\Unit\Security;

use ConectaEduca\Core\SecureFormRequest;
use ConectaEduca\Security\CryptoHybrid;
use PHPUnit\Framework\TestCase;

final class LoginV2EnvelopeGateTest extends TestCase
{
    /** @return array<string, mixed> */
    private static function valido(): array
    {
        return [
            'version' => CryptoHybrid::CURRENT_VERSION,
            'algorithm' => CryptoHybrid::CURRENT_ALGORITHM,
            'encrypted_key' => 'test-rsa',
            'iv' => 'test-iv',
            'tag' => 'test-tag',
            'ciphertext' => 'test-aes',
        ];
    }

    public function testAceitaEstruturaDeEnvelopeV2(): void
    {
        self::assertTrue(SecureFormRequest::isLoginV2Envelope(self::valido()));
    }

    public function testRejeitaPayloadSemEnvelope(): void
    {
        self::assertFalse(SecureFormRequest::isLoginV2Envelope([
            'email' => 'usuario@example.test',
            'senha' => 'SENHA_APENAS_TESTE',
        ]));
    }

    public function testRejeitaEnvelopeV1OuVersionString(): void
    {
        foreach ([1, '1', '2', null] as $versao) {
            $payload = self::valido();
            $payload['version'] = $versao;
            self::assertFalse(SecureFormRequest::isLoginV2Envelope($payload));
        }
    }

    public function testRejeitaAlgoritmoLegadoOuIncorreto(): void
    {
        foreach ([CryptoHybrid::LEGACY_ALGORITHM, '', 'RSA-OAEP-SHA1', null] as $algoritmo) {
            $payload = self::valido();
            $payload['algorithm'] = $algoritmo;
            self::assertFalse(SecureFormRequest::isLoginV2Envelope($payload));
        }
    }

    public function testRejeitaCamposCriptograficosAusentesOuNulos(): void
    {
        foreach (['encrypted_key', 'iv', 'tag', 'ciphertext'] as $campo) {
            $payload = self::valido();
            unset($payload[$campo]);
            self::assertFalse(SecureFormRequest::isLoginV2Envelope($payload));
            $payload[$campo] = null;
            self::assertFalse(SecureFormRequest::isLoginV2Envelope($payload));
        }
    }
}
