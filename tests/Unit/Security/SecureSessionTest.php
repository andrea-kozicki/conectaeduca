<?php
declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\SecureSession;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;

#[TestDox('Sessão segura')]
final class SecureSessionTest extends TestCase
{
    protected function setUp(): void
    {
        if (session_status() === PHP_SESSION_ACTIVE) {
            $_SESSION = [];
            session_write_close();
        }

        $_SESSION = [];

        unset(
            $_SERVER['HTTPS'],
            $_SERVER['SERVER_PORT']
        );
    }

    protected function tearDown(): void
    {
        if (session_status() === PHP_SESSION_ACTIVE) {
            $_SESSION = [];
            session_write_close();
        }

        $_SESSION = [];
    }

    #[TestDox('Inicializa sessão com sucesso')]
    public function testStartInitializesSession(): void
    {
        SecureSession::start();

        $this->assertSame(PHP_SESSION_ACTIVE, session_status());
        $this->assertIsArray($_SESSION);
    }

    #[TestDox('Não reinicializa sessão já ativa')]
    public function testStartIsIdempotent(): void
    {
        SecureSession::start();

        $firstSessionId = session_id();

        SecureSession::start();

        $this->assertSame(PHP_SESSION_ACTIVE, session_status());
        $this->assertSame($firstSessionId, session_id());
    }

    #[TestDox('Configura cookies seguros em HTTPS')]
    public function testStartConfiguresSecureCookieParamsForHttps(): void
    {
        if (session_status() === PHP_SESSION_ACTIVE) {
            session_write_close();
        }

        $_SERVER['HTTPS'] = 'on';
        $_SERVER['SERVER_PORT'] = '443';

        SecureSession::start();

        $params = session_get_cookie_params();

        $this->assertSame('/', $params['path']);
        $this->assertTrue((bool) $params['secure']);
        $this->assertTrue((bool) $params['httponly']);
        $this->assertSame('Lax', $params['samesite']);
    }

    #[TestDox('Configura cookies apropriados para ambiente local HTTP')]
    public function testStartConfiguresCookieParamsForHttpLocalEnvironment(): void
    {
        if (session_status() === PHP_SESSION_ACTIVE) {
            session_write_close();
        }

        $_SERVER['HTTPS'] = 'off';
        $_SERVER['SERVER_PORT'] = '80';

        SecureSession::start();

        $params = session_get_cookie_params();

        $this->assertSame('/', $params['path']);
        $this->assertFalse((bool) $params['secure']);
        $this->assertTrue((bool) $params['httponly']);
        $this->assertSame('Lax', $params['samesite']);
    }

    #[TestDox('Regenera sessão mantendo dados ativos')]
    public function testRegenerateKeepsSessionActive(): void
    {
        SecureSession::start();

        $_SESSION['usuario_id'] = 123;

        SecureSession::regenerate();

        $this->assertSame(PHP_SESSION_ACTIVE, session_status());
        $this->assertSame(123, $_SESSION['usuario_id']);
    }

    #[TestDox('Destrói sessão e limpa dados')]
    public function testDestroyClearsSessionData(): void
    {
        SecureSession::start();

        $_SESSION['usuario_id'] = 123;
        $_SESSION['role'] = 'usuario';

        SecureSession::destroy();

        $this->assertSame(PHP_SESSION_NONE, session_status());
        $this->assertSame([], $_SESSION);
    }
}
