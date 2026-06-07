<?php

declare(strict_types=1);

namespace ConectaEduca\Tests\Unit\Security;

use ConectaEduca\Security\Authorization;
use PHPUnit\Framework\TestCase;

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

    public function testSemSessaoNaoPossuiNenhumaRole(): void
    {
        $_SESSION = [];

        $this->assertFalse(Authorization::hasRole('usuario'));
        $this->assertFalse(Authorization::hasRole('empresa'));
        $this->assertFalse(Authorization::hasRole('admin'));
    }
}