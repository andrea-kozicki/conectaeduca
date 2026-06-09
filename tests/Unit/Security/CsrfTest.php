<?php
declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\Csrf;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;

#[TestDox('Proteção CSRF')]
final class CsrfTest extends TestCase
{
    protected function setUp(): void
    {
        $_SESSION = [];
    }

    #[TestDox('Gera token CSRF com o formato esperado')]
    public function testTokenIsGeneratedWithExpectedFormat(): void
    {
        $token = Csrf::token();

        $this->assertMatchesRegularExpression('/^[a-f0-9]{64}$/', $token);
    }

    #[TestDox('Mantém o mesmo token CSRF durante a sessão')]
    public function testTokenIsStableDuringSameSession(): void
    {
        $first = Csrf::token();
        $second = Csrf::token();

        $this->assertSame($first, $second);
    }

    #[TestDox('Aceita token CSRF válido')]
    public function testValidateAcceptsValidToken(): void
    {
        $token = Csrf::token();

        $this->assertTrue(Csrf::validate($token));
    }

    #[TestDox('Rejeita token CSRF inválido')]
    public function testValidateRejectsInvalidToken(): void
    {
        Csrf::token();

        $this->assertFalse(Csrf::validate('token-invalido'));
        $this->assertFalse(Csrf::validate(null));
    }

    #[TestDox('Gera campo hidden com o token CSRF')]
    public function testInputFieldContainsHiddenCsrfToken(): void
    {
        $html = Csrf::inputField();

        $this->assertStringContainsString('type="hidden"', $html);
        $this->assertStringContainsString('name="csrf_token"', $html);
        $this->assertStringContainsString('value="', $html);
    }
}
