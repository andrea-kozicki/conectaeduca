<?php

declare(strict_types=1);

namespace ConectaEduca\Tests\Unit\Security;

use ConectaEduca\Security\Authorization;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;

#[TestDox('Controle de acesso por perfil')]
final class AuthorizationRoleEnforcementTest extends TestCase
{
    protected function setUp(): void
    {
        $_SESSION = [];
    }

    protected function tearDown(): void
    {
        $_SESSION = [];
    }

    #[TestDox('Usuário comum não possui permissão de empresa ou administrador')]
    public function testUsuarioComumNaoPossuiPermissaoDeEmpresaOuAdmin(): void
    {
        $_SESSION['user'] = [
            'id' => 1,
            'nome' => 'Usuária Comum',
            'email' => 'usuario@example.com',
            'role' => 'usuario',
        ];

        $this->assertFalse(Authorization::hasRole('empresa'));
        $this->assertFalse(Authorization::hasRole('admin'));
    }

    #[TestDox('Empresa não possui permissão de administrador')]
    public function testEmpresaNaoPossuiPermissaoDeAdmin(): void
    {
        $_SESSION['user'] = [
            'id' => 2,
            'nome' => 'Empresa Teste',
            'email' => 'empresa@example.com',
            'role' => 'empresa',
        ];

        $this->assertTrue(Authorization::hasRole('empresa'));
        $this->assertFalse(Authorization::hasRole('admin'));
    }

    #[TestDox('Administrador não é confundido com usuário ou empresa')]
    public function testAdminNaoEConfundidoComUsuarioOuEmpresa(): void
    {
        $_SESSION['user'] = [
            'id' => 3,
            'nome' => 'Admin Teste',
            'email' => 'admin@example.com',
            'role' => 'admin',
        ];

        $this->assertTrue(Authorization::hasRole('admin'));
        $this->assertFalse(Authorization::hasRole('empresa'));
    }

    #[TestDox('Sem sessão ativa não há nenhuma role autorizada')]
    public function testSemSessaoNaoPossuiNenhumaRole(): void
    {
        $_SESSION = [];

        $this->assertFalse(Authorization::hasRole('usuario'));
        $this->assertFalse(Authorization::hasRole('empresa'));
        $this->assertFalse(Authorization::hasRole('admin'));
    }
}