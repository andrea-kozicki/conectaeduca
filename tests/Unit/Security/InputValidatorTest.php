<?php
declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\InputValidator;
use InvalidArgumentException;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;

#[TestDox('Validação de entrada')]
final class InputValidatorTest extends TestCase
{
    #[TestDox('Remove espaços em string obrigatória')]
    public function testRequiredStringTrimsValue(): void
    {
        $this->assertSame('Andrea', InputValidator::requiredString('  Andrea  ', 'nome'));
    }

    #[TestDox('Rejeita string obrigatória vazia')]
    public function testRequiredStringRejectsEmptyValue(): void
    {
        $this->expectException(InvalidArgumentException::class);

        InputValidator::requiredString('   ', 'nome');
    }

    #[TestDox('Rejeita string obrigatória acima do tamanho permitido')]
    public function testRequiredStringRejectsTooLongValue(): void
    {
        $this->expectException(InvalidArgumentException::class);

        InputValidator::requiredString(str_repeat('a', 6), 'campo', 5);
    }

    #[TestDox('Retorna null para string opcional vazia')]
    public function testOptionalStringReturnsNullWhenEmpty(): void
    {
        $this->assertNull(InputValidator::optionalString('   '));
        $this->assertNull(InputValidator::optionalString(null));
    }

    #[TestDox('Aceita e-mail válido')]
    public function testEmailAcceptsValidEmail(): void
    {
        $this->assertSame(
            'teste@conectaeduca.local',
            InputValidator::email(' teste@conectaeduca.local ')
        );
    }

    #[TestDox('Rejeita e-mail inválido')]
    public function testEmailRejectsInvalidEmail(): void
    {
        $this->expectException(InvalidArgumentException::class);

        InputValidator::email('email-invalido');
    }

    #[TestDox('Aceita ID inteiro positivo')]
    public function testIdAcceptsPositiveInteger(): void
    {
        $this->assertSame(15, InputValidator::id('15'));
    }

    #[TestDox('Rejeita payload de SQL injection no ID')]
    public function testIdRejectsSqlInjectionPayload(): void
    {
        $this->expectException(InvalidArgumentException::class);

        InputValidator::id('1 OR 1=1');
    }

    #[TestDox('Aceita valor permitido em enum')]
    public function testEnumAcceptsAllowedValue(): void
    {
        $this->assertSame(
            'publicada',
            InputValidator::enum('publicada', ['rascunho', 'publicada', 'encerrada'], 'status')
        );
    }

    #[TestDox('Rejeita valor inválido em enum')]
    public function testEnumRejectsInvalidValue(): void
    {
        $this->expectException(InvalidArgumentException::class);

        InputValidator::enum('ativa', ['rascunho', 'publicada', 'encerrada'], 'status');
    }
}
