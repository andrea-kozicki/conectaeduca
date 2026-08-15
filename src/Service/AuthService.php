<?php

declare(strict_types=1);

namespace ConectaEduca\Service;

use ConectaEduca\Config\Database;
use ConectaEduca\Repository\UsuarioRepository;
use ConectaEduca\Security\AuditLogger;
use ConectaEduca\Security\SecureSession;
use DomainException;

final class AuthService
{
    private UsuarioRepository $usuarios;

    public function __construct()
    {
        $this->usuarios = new UsuarioRepository(
            Database::connect()
        );
    }

    public function autenticar(
        string $email,
        string $senha
    ): array {
        $email = trim($email);

        if (
            !filter_var($email, FILTER_VALIDATE_EMAIL)
            || $senha === ''
        ) {
            throw new DomainException(
                'E-mail ou senha inválidos.'
            );
        }

        $usuario = $this->usuarios
            ->buscarCredenciaisPorEmail($email);

        $senhaHash = $usuario !== null
            ? (string) ($usuario['senha_hash'] ?? '')
            : '';

        $credenciaisValidas =
            $usuario !== null
            && $senhaHash !== ''
            && password_verify($senha, $senhaHash);

        if (!$credenciaisValidas) {
            AuditLogger::log('login_failed', [
                'email_hash' => hash('sha256', $email),
                'reason' => 'invalid_credentials',
            ]);

            throw new DomainException(
                'E-mail ou senha inválidos.'
            );
        }

        if ((int) $usuario['conta_ativada'] !== 1) {
            AuditLogger::log('login_failed', [
                'user_id' => (int) $usuario['id'],
                'reason' => 'inactive_account',
            ]);

            throw new DomainException(
                'E-mail ou senha inválidos.'
            );
        }

        /*
         * O MFA local será implementado posteriormente.
         * Uma conta que já esteja marcada com MFA ativo
         * não deve ignorar a segunda etapa.
         */
        if ((int) $usuario['mfa_ativo'] === 1) {
            AuditLogger::log('login_mfa_required', [
                'user_id' => (int) $usuario['id'],
            ]);

            throw new DomainException(
                'Esta conta exige uma segunda etapa de autenticação.'
            );
        }

        SecureSession::regenerate();

        $_SESSION['user'] = [
            'id' => (int) $usuario['id'],
            'nome' => (string) $usuario['nome'],
            'email' => (string) $usuario['email'],
            'role' => (string) $usuario['role'],
        ];

        $this->usuarios->registrarUltimoLogin(
            (int) $usuario['id']
        );

        AuditLogger::log('login_success', [
            'user_id' => (int) $usuario['id'],
            'role' => (string) $usuario['role'],
        ]);

        return $_SESSION['user'];
    }

    public function logout(): void
    {
        $usuario = $_SESSION['user'] ?? null;

        AuditLogger::log('logout', [
            'user_id' => is_array($usuario)
                ? ($usuario['id'] ?? null)
                : null,
        ]);

        SecureSession::destroy();
    }
}