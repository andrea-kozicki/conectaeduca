<?php
declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\Authorization;
use ConectaEduca\Security\SecureSession;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;

#[TestDox('Autorização')]
final class AuthorizationTest extends TestCase
{
    protected function setUp(): void
    {
        SecureSession::start();
        $_SESSION = [];
    }

    #[TestDox('Retorna falso quando não há usuário autenticado')]
    public function testCheckReturnsFalseWhenUserIsNotLoggedIn(): void
    {
        $this->assertFalse(Authorization::check());
        $this->assertNull(Authorization::user());
    }

    #[TestDox('Retorna verdadeiro quando há usuário autenticado')]
    public function testCheckReturnsTrueWhenUserIsLoggedIn(): void
    {
        $_SESSION['user'] = [
            'id' => 10,
            'nome' => 'Usuária Teste',
            'email' => 'teste@conectaeduca.local',
            'role' => 'usuario',
        ];

        $this->assertTrue(Authorization::check());
        $this->assertSame('Usuária Teste', Authorization::user()['nome']);
    }

    #[TestDox('Reconhece corretamente a role do usuário autenticado')]
    public function testHasRoleReturnsTrueForCorrectRole(): void
    {
        $_SESSION['user'] = [
            'id' => 10,
            'role' => 'admin',
        ];

        $this->assertTrue(Authorization::hasRole('admin'));
        $this->assertFalse(Authorization::hasRole('usuario'));
    }

    #[TestDox('Retorna falso para role quando não há usuário autenticado')]
    public function testHasRoleReturnsFalseWithoutUser(): void
    {
        $this->assertFalse(Authorization::hasRole('admin'));
    }
}
