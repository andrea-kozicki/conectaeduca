<?php

declare(strict_types=1);

namespace ConectaEduca\Service;

use ConectaEduca\Config\Database;
use ConectaEduca\Repository\UsuarioRepository;
use ConectaEduca\Security\AuditLogger;
use ConectaEduca\Security\PendingAuthentication;
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

    /**
     * Valida apenas a primeira etapa da autenticação.
     *
     * Senha correta NÃO significa usuário autenticado.
     * O usuário permanece em pré-autenticação até concluir MFA.
     */
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
            && password_verify(
                $senha,
                $senhaHash
            );

        if (!$credenciaisValidas) {
            AuditLogger::log(
                'login_failed',
                [
                    'email_hash' =>
                        hash('sha256', $email),
                    'reason' =>
                        'invalid_credentials',
                ]
            );

            throw new DomainException(
                'E-mail ou senha inválidos.'
            );
        }

        if ((int) $usuario['conta_ativada'] !== 1) {
            AuditLogger::log(
                'login_failed',
                [
                    'user_id' =>
                        (int) $usuario['id'],
                    'reason' =>
                        'inactive_account',
                ]
            );

            throw new DomainException(
                'E-mail ou senha inválidos.'
            );
        }

        /*
         * A senha foi validada, mas o login NÃO está concluído.
         */
        PendingAuthentication::begin(
            (int) $usuario['id'],
            (int) $usuario['mfa_ativo'] === 1
        );

        AuditLogger::log(
            'login_password_verified',
            [
                'user_id' =>
                    (int) $usuario['id'],
                'mfa_configurado' =>
                    (int) $usuario['mfa_ativo'] === 1,
            ]
        );

        return [
            'mfa_configurado' =>
                (int) $usuario['mfa_ativo'] === 1,
        ];
    }

    /**
     * Conclui a autenticação somente depois da validação MFA.
     */
    public function concluirMfa(
        int $usuarioId
    ): array {
        $pendingId =
            PendingAuthentication::userId();

        if (
            $pendingId === null
            || $pendingId !== $usuarioId
        ) {
            throw new DomainException(
                'Sessão de autenticação inválida ou expirada.'
            );
        }

        $usuario = $this->usuarios
            ->buscarPorId($usuarioId);

        if (
            $usuario === null
            || (int) $usuario['conta_ativada'] !== 1
            || (int) $usuario['mfa_ativo'] !== 1
        ) {
            PendingAuthentication::clear();

            throw new DomainException(
                'Não foi possível concluir a autenticação.'
            );
        }

        /*
         * Delimita:
         * pré-autenticado -> autenticado.
         */
        PendingAuthentication::complete();

        $_SESSION['user'] = [
            'id' =>
                (int) $usuario['id'],
            'nome' =>
                (string) $usuario['nome'],
            'email' =>
                (string) $usuario['email'],
            'role' =>
                (string) $usuario['role'],
        ];

        $this->usuarios->registrarUltimoLogin(
            $usuarioId
        );

        AuditLogger::log(
            'login_success',
            [
                'user_id' =>
                    $usuarioId,
                'role' =>
                    (string) $usuario['role'],
                'mfa' =>
                    true,
            ]
        );

        return $_SESSION['user'];
    }

    public function logout(): void
    {
        $usuario = $_SESSION['user'] ?? null;

        AuditLogger::log(
            'logout',
            [
                'user_id' =>
                    is_array($usuario)
                        ? ($usuario['id'] ?? null)
                        : null,
            ]
        );

        SecureSession::destroy();
    }
}
