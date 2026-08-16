<?php

declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\PendingAuthentication;
use ConectaEduca\Security\SecureSession;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;

#[TestDox('Pré-autenticação MFA')]
final class PendingAuthenticationTest extends TestCase
{
    protected function setUp(): void
    {
        SecureSession::start();

        $_SESSION = [];
    }

    protected function tearDown(): void
    {
        $_SESSION = [];
    }

    #[TestDox('Cria uma pré-autenticação para o usuário')]
    public function testBeginCreatesPendingAuthentication(): void
    {
        PendingAuthentication::begin(42);

        $this->assertTrue(
            PendingAuthentication::active()
        );

        $this->assertSame(
            42,
            PendingAuthentication::userId()
        );
    }

    #[TestDox('Pré-autenticação não cria usuário autenticado')]
    public function testPendingAuthenticationDoesNotAuthenticateUser(): void
    {
        PendingAuthentication::begin(42);

        $this->assertArrayNotHasKey(
            'user',
            $_SESSION
        );
    }

    #[TestDox('Remove autenticação pendente')]
    public function testClearRemovesPendingAuthentication(): void
    {
        PendingAuthentication::begin(42);

        PendingAuthentication::clear();

        $this->assertFalse(
            PendingAuthentication::active()
        );

        $this->assertNull(
            PendingAuthentication::userId()
        );
    }

    #[TestDox('Descarta autenticação pendente expirada')]
    public function testExpiredPendingAuthenticationIsRejected(): void
    {
        PendingAuthentication::begin(42);

        $_SESSION['mfa_pending']['expires_at'] =
            time() - 1;

        $this->assertFalse(
            PendingAuthentication::active()
        );

        $this->assertNull(
            PendingAuthentication::userId()
        );
    }

    #[TestDox('Nova pré-autenticação remove sessão autenticada anterior')]
    public function testBeginRemovesExistingAuthenticatedUser(): void
    {
        $_SESSION['user'] = [
            'id' => 99,
            'role' => 'admin',
        ];

        PendingAuthentication::begin(42);

        $this->assertArrayNotHasKey(
            'user',
            $_SESSION
        );

        $this->assertSame(
            42,
            PendingAuthentication::userId()
        );
    }
    #[TestDox('Registra se a conta já possuía MFA no início do login')]
    public function testTracksPreviousMfaState(): void
    {
        PendingAuthentication::begin(42, true);

        $this->assertTrue(
            PendingAuthentication::mfaWasConfiguredAtLogin()
        );

        $this->assertFalse(
            PendingAuthentication::mfaRecoveryAuthorized()
        );
    }

    #[TestDox('Autoriza reconfiguração somente após recuperação explícita')]
    public function testAuthorizesMfaRecovery(): void
    {
        PendingAuthentication::begin(42, true);

        PendingAuthentication::authorizeMfaRecovery();

        $this->assertTrue(
            PendingAuthentication::mfaRecoveryAuthorized()
        );
    }

    #[TestDox('Nova pré-autenticação remove autorização de recuperação anterior')]
    public function testNewPendingClearsRecoveryAuthorization(): void
    {
        PendingAuthentication::begin(42, true);
        PendingAuthentication::authorizeMfaRecovery();

        PendingAuthentication::begin(43, true);

        $this->assertFalse(
            PendingAuthentication::mfaRecoveryAuthorized()
        );
        $this->assertSame(
            43,
            PendingAuthentication::userId()
        );
    }

}
