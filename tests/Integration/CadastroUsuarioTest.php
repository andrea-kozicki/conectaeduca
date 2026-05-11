<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

final class CadastroUsuarioTest extends TestCase
{
    public function testCadastroUsuarioIntegracaoPendente(): void
    {
        self::markTestSkipped(
            'Teste de integração pendente: depende de banco, CSRF e fluxo de cadastro configurados.'
        );
    }
}