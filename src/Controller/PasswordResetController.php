<?php

declare(strict_types=1);

namespace ConectaEduca\Controller;

use ConectaEduca\Core\Response;
use ConectaEduca\Core\SecureFormRequest;
use ConectaEduca\Core\View;
use ConectaEduca\Security\AuditLogger;
use ConectaEduca\Security\Csrf;
use ConectaEduca\Service\PasswordResetNotificationService;
use ConectaEduca\Service\PasswordResetService;
use InvalidArgumentException;
use Throwable;

final class PasswordResetController
{
    private const ACCEPTED_MESSAGE =
        'Se existir uma conta associada ao e-mail informado, enviaremos as instruções de recuperação.';

    private const RATE_LIMIT_MESSAGE =
        'Muitas solicitações de recuperação. Tente novamente mais tarde.';

    public function mostrarSolicitacao(): void
    {
        $status = trim((string) ($_GET['status'] ?? ''));

        $message = match ($status) {
            'enviado' => self::ACCEPTED_MESSAGE,
            'limitado' => self::RATE_LIMIT_MESSAGE,
            default => null,
        };

        View::render('auth/esqueci_senha', [
            'error' => null,
            'message' => $message,
            'email' => '',
        ]);
    }

    public function solicitar(): void
    {
        $dados = SecureFormRequest::data();

        Csrf::requireValid(
            SecureFormRequest::csrfToken($dados)
        );

        $email = trim((string) ($dados['email'] ?? ''));

        try {
            $service = new PasswordResetNotificationService();

            $resultado = $service->solicitarEEnviar($email);

            if (($resultado['status'] ?? '') === 'rate_limited') {
                Response::redirect('/esqueci-senha.php?status=limitado');
            }

            Response::redirect('/esqueci-senha.php?status=enviado');
        } catch (InvalidArgumentException $e) {
            http_response_code(422);

            View::render('auth/esqueci_senha', [
                'error' => 'Informe um endereço de e-mail válido.',
                'message' => null,
                'email' => $email,
            ]);
        } catch (Throwable $e) {
            AuditLogger::log(
                'password_reset_request_internal_error',
                [
                    'exception' => $e::class,
                ]
            );

            http_response_code(500);

            View::render('auth/esqueci_senha', [
                'error' => 'Não foi possível processar a solicitação de recuperação.',
                'message' => null,
                'email' => '',
            ]);
        }
    }

    public function mostrarRedefinicao(): void
    {
        self::noStoreHeaders();

        View::render('auth/redefinir_senha', [
            'error' => null,
            'invalid' => false,
            'token' => '',
        ]);
    }

    public function redefinir(): void
    {
        self::noStoreHeaders();

        $dados = SecureFormRequest::data();

        Csrf::requireValid(
            SecureFormRequest::csrfToken($dados)
        );

        $token = trim((string) ($dados['token'] ?? ''));
        $senha = (string) ($dados['senha'] ?? '');
        $confirmarSenha = (string) ($dados['confirmar_senha'] ?? '');

        try {
            $service = new PasswordResetService();

            $usuarioId = $service->redefinirSenha(
                $token,
                $senha,
                $confirmarSenha
            );

            if ($usuarioId === null) {
                AuditLogger::log('password_reset_invalid_token');

                http_response_code(400);

                View::render('auth/redefinir_senha', [
                    'error' => 'Este link de recuperação é inválido, expirou ou já foi utilizado.',
                    'invalid' => true,
                    'token' => '',
                ]);

                return;
            }

            AuditLogger::log(
                'password_reset_success',
                [
                    'user_id' => $usuarioId,
                ]
            );

            Response::redirect('/login.php?senha_redefinida=1');
        } catch (InvalidArgumentException $e) {
            http_response_code(422);

            View::render('auth/redefinir_senha', [
                'error' => $e->getMessage(),
                'invalid' => false,
                'token' => $token,
            ]);
        } catch (Throwable $e) {
            AuditLogger::log(
                'password_reset_internal_error',
                [
                    'exception' => $e::class,
                ]
            );

            http_response_code(500);

            View::render('auth/redefinir_senha', [
                'error' => 'Não foi possível redefinir a senha.',
                'invalid' => false,
                'token' => '',
            ]);
        }
    }

    private static function noStoreHeaders(): void
    {
        header('Cache-Control: no-store, max-age=0');
        header('Pragma: no-cache');
        header('Referrer-Policy: no-referrer');
    }
}
