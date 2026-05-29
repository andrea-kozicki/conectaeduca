<?php
declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\Csrf;
use PHPUnit\Framework\TestCase;

final class CsrfTest extends TestCase
{
    protected function setUp(): void
    {
        $_SESSION = [];
    }

    public function testTokenIsGeneratedWithExpectedFormat(): void
    {
        $token = Csrf::token();

        $this->assertMatchesRegularExpression('/^[a-f0-9]{64}$/', $token);
    }

    public function testTokenIsStableDuringSameSession(): void
    {
        $first = Csrf::token();
        $second = Csrf::token();

        $this->assertSame($first, $second);
    }

    public function testValidateAcceptsValidToken(): void
    {
        $token = Csrf::token();

        $this->assertTrue(Csrf::validate($token));
    }

    public function testValidateRejectsInvalidToken(): void
    {
        Csrf::token();

        $this->assertFalse(Csrf::validate('token-invalido'));
        $this->assertFalse(Csrf::validate(null));
    }

    public function testInputFieldContainsHiddenCsrfToken(): void
    {
        $html = Csrf::inputField();

        $this->assertStringContainsString('type="hidden"', $html);
        $this->assertStringContainsString('name="csrf_token"', $html);
        $this->assertStringContainsString('value="', $html);
    }
}
