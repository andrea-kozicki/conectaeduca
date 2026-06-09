<?php

declare(strict_types=1);

namespace ConectaEduca\Tests\Unit\Security;

use ConectaEduca\Service\CognitoUserService;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;
use RuntimeException;

#[TestDox('Grupos Cognito no autocadastro')]
final class CognitoAutocadastroGroupTest extends TestCase
{
    #[TestDox('Aceita grupo usuario no autocadastro')]
    public function testAceitaGrupoUsuario(): void
    {
        $this->assertSame(
            'usuario',
            CognitoUserService::normalizarGrupoAutocadastro('usuario')
        );
    }

    #[TestDox('Aceita grupo empresa no autocadastro')]
    public function testAceitaGrupoEmpresa(): void
    {
        $this->assertSame(
            'empresa',
            CognitoUserService::normalizarGrupoAutocadastro('empresa')
        );
    }

    #[TestDox('Normaliza espaços e letras maiúsculas no grupo')]
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

    #[TestDox('Bloqueia grupo admin no autocadastro público')]
    public function testNaoPermiteGrupoAdminNoAutocadastro(): void
    {
        $this->expectException(RuntimeException::class);

        CognitoUserService::normalizarGrupoAutocadastro('admin');
    }

    #[TestDox('Bloqueia grupo arbitrário no autocadastro público')]
    public function testNaoPermiteGrupoArbitrarioNoAutocadastro(): void
    {
        $this->expectException(RuntimeException::class);

        CognitoUserService::normalizarGrupoAutocadastro('superuser');
    }
}