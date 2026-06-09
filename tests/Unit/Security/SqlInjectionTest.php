<?php
declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\InputValidator;
use InvalidArgumentException;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;

#[TestDox('Proteção contra SQL Injection')]
final class SqlInjectionTest extends TestCase
{
    #[TestDox('Rejeita SQL injection clássico em ID numérico')]
    public function testNumericIdRejectsClassicSqlInjectionPayload(): void
    {
        $this->expectException(InvalidArgumentException::class);

        InputValidator::id('1 OR 1=1');
    }

    #[TestDox('Rejeita payload UNION SELECT em ID numérico')]
    public function testNumericIdRejectsUnionSelectPayload(): void
    {
        $this->expectException(InvalidArgumentException::class);

        InputValidator::id('1 UNION SELECT senha_hash FROM usuarios');
    }

    #[TestDox('Rejeita status inesperado em enum')]
    public function testEnumRejectsUnexpectedStatusValue(): void
    {
        $this->expectException(InvalidArgumentException::class);

        InputValidator::enum(
            "publicada' OR '1'='1",
            ['rascunho', 'publicada', 'encerrada', 'suspensa'],
            'status'
        );
    }

    #[TestDox('Mantém termo de busca sem executar ou transformar payload')]
    public function testSearchTermDoesNotExecuteOrTransformPayload(): void
    {
        $payload = "' OR '1'='1";

        $this->assertSame($payload, InputValidator::searchTerm($payload));
    }
}