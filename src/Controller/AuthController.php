<?php

declare(strict_types=1);

namespace ConectaEduca\Controller;

use ConectaEduca\Core\Response;
use ConectaEduca\Core\SecureFormRequest;
use ConectaEduca\Core\View;
use ConectaEduca\Security\AuditLogger;
use ConectaEduca\Security\Authorization;
use ConectaEduca\Security\Csrf;
use ConectaEduca\Service\AuthService;
use DomainException;
use Throwable;

final class AuthController
{
    public function mostrarLogin(): void
    {
        if (Authorization::check()) {
            Response::redirect('/dashboard.php');
        }

        View::render('auth/login', [
            'error' => null,
            'email' => '',
            'logoutSuccess' =>
                ($_GET['logout'] ?? '') === '1',
        ]);
    }

    public function autenticar(): void
    {
        $dados = SecureFormRequest::data();

        Csrf::requireValid(
            SecureFormRequest::csrfToken($dados)
        );

        $email = trim(
            (string) ($dados['email'] ?? '')
        );

        $senha = (string) ($dados['senha'] ?? '');

        try {
            $service = new AuthService();

            $service->autenticar(
                $email,
                $senha
            );

            Response::redirect('/dashboard.php');

        } catch (DomainException $e) {
            http_response_code(401);

            View::render('auth/login', [
                'error' => $e->getMessage(),
                'email' => $email,
                'logoutSuccess' => false,
            ]);

        } catch (Throwable $e) {
            AuditLogger::log(
                'login_internal_error',
                [
                    'exception' => $e::class,
                ]
            );

            http_response_code(500);

            View::render('auth/login', [
                'error' =>
                    'Não foi possível realizar o login.',
                'email' => $email,
                'logoutSuccess' => false,
            ]);
        }
    }

    
    public function logout(): void
    {
        $service = new AuthService();

        $service->logout();

        Response::redirect(
            '/login.php?logout=1'
        );
    }
}