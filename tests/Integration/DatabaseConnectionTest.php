<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

final class DatabaseConnectionTest extends TestCase
{
    public function testConexaoBancoPendente(): void
    {
        self::markTestSkipped(
            'Teste de integração pendente: depende da criação/importação do banco de dados local.'
        );
    }
}