<?php
declare(strict_types=1);

namespace ConectaEduca\Controller;

use ConectaEduca\Core\Response;
use ConectaEduca\Service\AuthService;
use ConectaEduca\Security\AuditLogger;

final class AuthController
{
    public function login(): void
    {
        $service = new AuthService();

        Response::redirect($service->loginUrl());
    }

    public function callback(): void
    {
        $code = $_GET['code'] ?? null;
        $state = $_GET['state'] ?? null;

        if (!is_string($code) || !is_string($state)) {
            http_response_code(400);
            echo 'Callback inválido.';
            return;
        }

        try {
            $service = new AuthService();
            $service->processCallback($code, $state);

            Response::redirect('/dashboard.php');
        } catch (\Throwable $e) {
            AuditLogger::log('login_callback_error', [
                'message' => $e->getMessage(),
            ]);

            http_response_code(401);
            echo 'Falha na autenticação.';
        }
    }

    public function logout(): void
    {
        $service = new AuthService();

        Response::redirect($service->logout());
    }
}