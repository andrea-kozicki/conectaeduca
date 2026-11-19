<?php
declare(strict_types=1);

namespace ConectaEduca\Tests\Unit\Security;

use ConectaEduca\Controller\AuthController;
use ConectaEduca\Core\SecureFormRequest;
use PHPUnit\Framework\TestCase;
use ReflectionMethod;

/**
 * Source-only PHP tests: current main login boundary, not PR #205's new v2 route.
 *
 * No DB, browser, HTTP, RSA key, WAF, institutional user, or VM.
 */
final class LoginBaselineBoundaryTest extends TestCase
{
    /** @var array<string, mixed> */
    private array $savedServer = [];

    protected function setUp(): void
    {
        parent::setUp();
        $this->savedServer = $_SERVER;
        $_SERVER = [
            'REMOTE_ADDR' => '203.0.113.9',
        ];
    }

    protected function tearDown(): void
    {
        $_SERVER = $this->savedServer;
        parent::tearDown();
    }

    public function testHeaderCsrfTakesPrecedenceOverBody(): void
    {
        $_SERVER['HTTP_X_CSRF_TOKEN'] = 'synthetic-header';
        self::assertSame('synthetic-header', SecureFormRequest::csrfToken([
            'csrf_token' => 'synthetic-body',
        ]));
    }

    public function testCsrfFallsBackToStringInBody(): void
    {
        self::assertSame('synthetic-body', SecureFormRequest::csrfToken([
            'csrf_token' => 'synthetic-body',
        ]));
    }

    public function testNonStringCsrfHeaderFallsBackToBody(): void
    {
        $_SERVER['HTTP_X_CSRF_TOKEN'] = ['malformed'];
        self::assertSame('synthetic-body', SecureFormRequest::csrfToken([
            'csrf_token' => 'synthetic-body',
        ]));
    }

    public function testNonStringBodyCsrfIsRejectedAsAbsent(): void
    {
        self::assertNull(SecureFormRequest::csrfToken(['csrf_token' => ['invalid']]));
        self::assertNull(SecureFormRequest::csrfToken(['csrf_token' => 123]));
    }

    public function testEncryptedEnvelopeRequiresAllFourKeys(): void
    {
        $envelope = [
            'encrypted_key' => 'synthetic', 'iv' => 'synthetic',
            'tag' => 'synthetic', 'ciphertext' => 'synthetic',
        ];
        self::assertTrue(SecureFormRequest::isEncryptedEnvelope($envelope));
        foreach (array_keys($envelope) as $key) {
            $candidate = $envelope;
            unset($candidate[$key]);
            self::assertFalse(SecureFormRequest::isEncryptedEnvelope($candidate));
        }
    }

    public function testNullEnvelopeComponentIsNotStructurallyComplete(): void
    {
        foreach (['encrypted_key', 'iv', 'tag', 'ciphertext'] as $key) {
            $candidate = [
                'encrypted_key' => 'synthetic', 'iv' => 'synthetic',
                'tag' => 'synthetic', 'ciphertext' => 'synthetic',
            ];
            $candidate[$key] = null;
            self::assertFalse(SecureFormRequest::isEncryptedEnvelope($candidate));
        }
    }

    public function testEnvelopePresenceIsNotADecryptOrV2Validation(): void
    {
        // Deliberate baseline limitation: isEncryptedEnvelope is a shape check.
        // CryptoHybrid validates the cryptographic envelope separately.
        self::assertTrue(SecureFormRequest::isEncryptedEnvelope([
            'encrypted_key' => '', 'iv' => '', 'tag' => '', 'ciphertext' => '',
        ]));
        self::assertFalse(method_exists(SecureFormRequest::class, 'isLoginV2Envelope'));
    }

    public function testCurrentMainUsesPeerIpAndNotForwardedHeaders(): void
    {
        $_SERVER['HTTP_X_FORWARDED_FOR'] = '198.51.100.1';
        $_SERVER['HTTP_X_CONECTAEDUCA_CLIENT_IP'] = '198.51.100.2';
        self::assertSame('ip:203.0.113.9', $this->callPrivateStatic('ipIdentifier'));
    }

    public function testEmptyOrMissingPeerUsesUnknownIdentifier(): void
    {
        $_SERVER['REMOTE_ADDR'] = '';
        self::assertSame('ip:desconhecido', $this->callPrivateStatic('ipIdentifier'));
        unset($_SERVER['REMOTE_ADDR']);
        self::assertSame('ip:desconhecido', $this->callPrivateStatic('ipIdentifier'));
    }

    public function testAccountLimiterUsesCanonicalEmailHashAndPeer(): void
    {
        $expected = 'email_hash:' . hash('sha256', 'demo@example.invalid')
            . '|ip:203.0.113.9';
        self::assertSame($expected, $this->callPrivateStatic(
            'accountIpIdentifier', '  DEMO@EXAMPLE.INVALID  '
        ));
        self::assertStringNotContainsString('demo@example.invalid', $expected);
    }

    public function testDifferentPeersChangeAccountBucket(): void
    {
        $first = $this->callPrivateStatic('accountIpIdentifier', 'demo@example.invalid');
        $_SERVER['REMOTE_ADDR'] = '203.0.113.10';
        $second = $this->callPrivateStatic('accountIpIdentifier', 'demo@example.invalid');
        self::assertNotSame($first, $second);
    }

    public function testChangingUntrustedForwardedHeaderDoesNotChangeBucket(): void
    {
        $_SERVER['HTTP_X_FORWARDED_FOR'] = '198.51.100.1';
        $first = $this->callPrivateStatic('accountIpIdentifier', 'demo@example.invalid');
        $_SERVER['HTTP_X_FORWARDED_FOR'] = '198.51.100.88';
        $second = $this->callPrivateStatic('accountIpIdentifier', 'demo@example.invalid');
        self::assertSame($first, $second);
    }

    private function callPrivateStatic(string $name, mixed ...$args): mixed
    {
        $method = new ReflectionMethod(AuthController::class, $name);
        return $method->invoke(null, ...$args);
    }
}
