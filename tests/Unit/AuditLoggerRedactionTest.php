<?php
declare(strict_types=1);

namespace ConectaEduca\Tests\Unit;

use ConectaEduca\Security\AuditLogger;
use PHPUnit\Framework\TestCase;
use ReflectionMethod;

/**
 * GA-07 / PA-06: privacidade do JSONL de auditoria.
 *
 * Este teste chama somente o mascaramento em memoria e nao escreve
 * storage/logs/audit.log nem usa eventos reais de usuarios.
 */
final class AuditLoggerRedactionTest extends TestCase
{
    /** @param array<string, mixed> $context
     *  @return array<string, mixed>
     */
    private function redact(array $context): array
    {
        $method = new ReflectionMethod(AuditLogger::class, 'redact');
        $result = $method->invoke(null, $context);
        self::assertIsArray($result);
        return $result;
    }

    public function testSensitiveScalarValuesAreMasked(): void
    {
        foreach (['password', 'senha', 'token', 'access_token', 'id_token',
            'refresh_token', 'client_secret', 'private_key', 'otp', 'totp',
            'codigo_mfa', 'segredo_mfa', 'segredo_totp', 'recovery_code',
            'codigo_recuperacao', 'recovery_codes', 'codigos_recuperacao'] as $key) {
            self::assertSame('[REDACTED]',
                $this->redact([$key => 'GA07-FICTICIO-NAO-SECRETO'])[$key],
                "Campo sensivel nao mascarado: {$key}");
        }
    }

    public function testSensitiveArrayValueIsFullyMasked(): void
    {
        $fake = 'GA07-FICTICIO-ARRAY-NAO-SECRETO';
        $result = $this->redact([
            'token' => ['value' => $fake, 'nested' => ['raw' => $fake]],
            'password' => ['part1' => $fake, 'part2' => $fake],
            'recovery_codes' => [$fake, $fake],
            'event_source' => 'synthetic',
        ]);

        foreach (['token', 'password', 'recovery_codes'] as $key) {
            self::assertSame('[REDACTED]', $result[$key]);
        }
        self::assertSame('synthetic', $result['event_source']);
        self::assertStringNotContainsString($fake, json_encode($result, JSON_THROW_ON_ERROR));
    }

    public function testNestedContextMasksSensitiveKeysWithoutFlatteningSafeKeys(): void
    {
        $result = $this->redact([
            'metadata' => [
                'request' => [
                    'token' => ['unsafe' => 'GA07-FAKE-NESTED'],
                    'otp' => 'GA07-FAKE-OTP',
                    'allowed' => ['count' => 3],
                ],
            ],
        ]);

        self::assertSame('[REDACTED]', $result['metadata']['request']['token']);
        self::assertSame('[REDACTED]', $result['metadata']['request']['otp']);
        self::assertSame(3, $result['metadata']['request']['allowed']['count']);
        self::assertStringNotContainsString('GA07-FAKE-NESTED',
            json_encode($result, JSON_THROW_ON_ERROR));
    }

    public function testKeyMatchingIsCaseInsensitiveForArraysAndScalars(): void
    {
        $result = $this->redact([
            'ToKeN' => ['value' => 'GA07-FAKE-TOKEN'],
            'PASSWORD' => 'GA07-FAKE-PASSWORD',
            'nested' => ['PRIVATE_KEY' => ['material' => 'GA07-FAKE-KEY']],
        ]);

        self::assertSame('[REDACTED]', $result['ToKeN']);
        self::assertSame('[REDACTED]', $result['PASSWORD']);
        self::assertSame('[REDACTED]', $result['nested']['PRIVATE_KEY']);
    }

    public function testOriginalInputIsNotMutated(): void
    {
        $input = ['token' => ['value' => 'GA07-FAKE-ORIGINAL']];
        $result = $this->redact($input);

        self::assertSame(['value' => 'GA07-FAKE-ORIGINAL'], $input['token']);
        self::assertSame('[REDACTED]', $result['token']);
    }

    public function testNonSensitiveArraysRemainAvailableForAudit(): void
    {
        $input = ['scope' => ['role' => 'usuario', 'attempt' => 2, 'allowed' => false]];
        self::assertSame($input, $this->redact($input));
    }
}
