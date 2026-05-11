<?php
declare(strict_types=1);

namespace ConectaEduca\Service;

use ConectaEduca\Config\Database;
use ConectaEduca\Repository\UsuarioRepository;
use ConectaEduca\Security\AuditLogger;
use ConectaEduca\Security\CognitoJwtVerifier;
use ConectaEduca\Security\CognitoOAuthClient;
use ConectaEduca\Security\SecureSession;

final class AuthService
{
    public function loginUrl(): string
    {
        return CognitoOAuthClient::authorizationUrl();
    }

    public function processCallback(string $code, string $state): array
    {
        $tokens = CognitoOAuthClient::exchangeCodeForTokens($code, $state);
        $claims = CognitoJwtVerifier::verify($tokens['id_token']);

        $sub = (string) ($claims['sub'] ?? '');
        $email = (string) ($claims['email'] ?? '');
        $nome = (string) ($claims['name'] ?? $claims['given_name'] ?? $email);

        $pdo = Database::connect();
        $repo = new UsuarioRepository($pdo);

        $usuario = $repo->criarOuAtualizarPorCognito($sub, $nome, $email, 'usuario');

        SecureSession::regenerate();

        $_SESSION['user'] = [
            'id' => (int) $usuario['id'],
            'cognito_sub' => $sub,
            'nome' => $usuario['nome'],
            'email' => $usuario['email'],
            'role' => $usuario['role'],
        ];

        $_SESSION['tokens'] = [
            'access_token' => $tokens['access_token'] ?? null,
            'id_token' => $tokens['id_token'] ?? null,
        ];

        AuditLogger::log('login_success', [
            'user_id' => $usuario['id'],
            'email' => $usuario['email'],
        ]);

        return $usuario;
    }

    public function logout(): string
    {
        AuditLogger::log('logout');

        SecureSession::destroy();

        return CognitoOAuthClient::logoutUrl();
    }
}