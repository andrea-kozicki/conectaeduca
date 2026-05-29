<?php
declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\InputValidator;
use InvalidArgumentException;
use PHPUnit\Framework\TestCase;

final class InputValidatorTest extends TestCase
{
    public function testRequiredStringTrimsValue(): void
    {
        $this->assertSame('Andrea', InputValidator::requiredString('  Andrea  ', 'nome'));
    }

    public function testRequiredStringRejectsEmptyValue(): void
    {
        $this->expectException(InvalidArgumentException::class);

        InputValidator::requiredString('   ', 'nome');
    }

    public function testRequiredStringRejectsTooLongValue(): void
    {
        $this->expectException(InvalidArgumentException::class);

        InputValidator::requiredString(str_repeat('a', 6), 'campo', 5);
    }

    public function testOptionalStringReturnsNullWhenEmpty(): void
    {
        $this->assertNull(InputValidator::optionalString('   '));
        $this->assertNull(InputValidator::optionalString(null));
    }

    public function testEmailAcceptsValidEmail(): void
    {
        $this->assertSame(
            'teste@conectaeduca.local',
            InputValidator::email(' teste@conectaeduca.local ')
        );
    }

    public function testEmailRejectsInvalidEmail(): void
    {
        $this->expectException(InvalidArgumentException::class);

        InputValidator::email('email-invalido');
    }

    public function testIdAcceptsPositiveInteger(): void
    {
        $this->assertSame(15, InputValidator::id('15'));
    }

    public function testIdRejectsSqlInjectionPayload(): void
    {
        $this->expectException(InvalidArgumentException::class);

        InputValidator::id('1 OR 1=1');
    }

    public function testEnumAcceptsAllowedValue(): void
    {
        $this->assertSame(
            'publicada',
            InputValidator::enum('publicada', ['rascunho', 'publicada', 'encerrada'], 'status')
        );
    }

    public function testEnumRejectsInvalidValue(): void
    {
        $this->expectException(InvalidArgumentException::class);

        InputValidator::enum('ativa', ['rascunho', 'publicada', 'encerrada'], 'status');
    }
}
