<?php
declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\InputValidator;
use InvalidArgumentException;
use PHPUnit\Framework\TestCase;

final class SqlInjectionTest extends TestCase
{
    public function testNumericIdRejectsClassicSqlInjectionPayload(): void
    {
        $this->expectException(InvalidArgumentException::class);

        InputValidator::id('1 OR 1=1');
    }

    public function testNumericIdRejectsUnionSelectPayload(): void
    {
        $this->expectException(InvalidArgumentException::class);

        InputValidator::id('1 UNION SELECT senha_hash FROM usuarios');
    }

    public function testEnumRejectsUnexpectedStatusValue(): void
    {
        $this->expectException(InvalidArgumentException::class);

        InputValidator::enum(
            "publicada' OR '1'='1",
            ['rascunho', 'publicada', 'encerrada', 'suspensa'],
            'status'
        );
    }

    public function testSearchTermDoesNotExecuteOrTransformPayload(): void
    {
        $payload = "' OR '1'='1";

        $this->assertSame($payload, InputValidator::searchTerm($payload));
    }
}