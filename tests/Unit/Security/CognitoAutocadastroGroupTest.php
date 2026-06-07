<?php

declare(strict_types=1);

namespace ConectaEduca\Tests\Unit\Security;

use ConectaEduca\Service\CognitoUserService;
use PHPUnit\Framework\TestCase;
use RuntimeException;

final class CognitoAutocadastroGroupTest extends TestCase
{
    public function testAceitaGrupoUsuario(): void
    {
        $this->assertSame(
            'usuario',
            CognitoUserService::normalizarGrupoAutocadastro('usuario')
        );
    }

    public function testAceitaGrupoEmpresa(): void
    {
        $this->assertSame(
            'empresa',
            CognitoUserService::normalizarGrupoAutocadastro('empresa')
        );
    }

    public function testNormalizaEspacosEMaiusculas(): void
    {
        $this->assertSame(
            'usuario',
            CognitoUserService::normalizarGrupoAutocadastro(' USUARIO ')
        );

        $this->assertSame(
            'empresa',
            CognitoUserService::normalizarGrupoAutocadastro(' Empresa ')
        );
    }

    public function testNaoPermiteGrupoAdminNoAutocadastro(): void
    {
        $this->expectException(RuntimeException::class);

        CognitoUserService::normalizarGrupoAutocadastro('admin');
    }

    public function testNaoPermiteGrupoArbitrarioNoAutocadastro(): void
    {
        $this->expectException(RuntimeException::class);

        CognitoUserService::normalizarGrupoAutocadastro('superuser');
    }
}