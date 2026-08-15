<?php

declare(strict_types=1);

namespace ConectaEduca\Controller;

use ConectaEduca\Core\Response;
use ConectaEduca\Core\SecureFormRequest;
use ConectaEduca\Core\View;
use ConectaEduca\Security\AuditLogger;
use ConectaEduca\Security\Authorization;
use ConectaEduca\Security\Csrf;
use ConectaEduca\Security\PendingAuthentication;
use ConectaEduca\Security\RateLimiter;
use ConectaEduca\Service\AuthService;
use ConectaEduca\Service\MfaService;
use ConectaEduca\Service\UsuarioService;
use DomainException;
use Throwable;

final class MfaController
{
    private const MFA_LIMIT = 5;
    private const MFA_WINDOW_SECONDS = 300;

    public function mostrarDesafio(): void
    {
        if (Authorization::check()) {
            Response::redirect('/dashboard.php');
        }

        $usuarioId = $this->pendingUserId();

        $mfa = new MfaService();

        if (!$mfa->configurado($usuarioId)) {
            Response::redirect(
                '/mfa-configurar.php'
            );
        }

        View::render(
            'auth/mfa',
            [
                'error' => null,
            ]
        );
    }

    public function validarDesafio(): void
    {
        $usuarioId = $this->pendingUserId();

        $dados = SecureFormRequest::data();

        Csrf::requireValid(
            SecureFormRequest::csrfToken($dados)
        );

        $codigo = (string) (
            $dados['codigo'] ?? ''
        );

        $identifier =
            self::rateIdentifier($usuarioId);

        RateLimiter::requireAllowed(
            'mfa_totp',
            self::MFA_LIMIT,
            self::MFA_WINDOW_SECONDS,
            $identifier
        );

        try {
            $mfa = new MfaService();

            if (
                !$mfa->validarCodigo(
                    $usuarioId,
                    $codigo
                )
            ) {
                AuditLogger::log(
                    'mfa_challenge_failed',
                    [
                        'user_id' =>
                            $usuarioId,
                    ]
                );

                http_response_code(401);

                View::render(
                    'auth/mfa',
                    [
                        'error' =>
                            'Código de autenticação inválido.',
                    ]
                );

                return;
            }

            RateLimiter::reset(
                'mfa_totp',
                $identifier
            );

            $auth = new AuthService();

            $auth->concluirMfa(
                $usuarioId
            );

            AuditLogger::log(
                'mfa_challenge_success',
                [
                    'user_id' =>
                        $usuarioId,
                ]
            );

            Response::redirect(
                '/dashboard.php'
            );

        } catch (DomainException $e) {
            http_response_code(401);

            View::render(
                'auth/mfa',
                [
                    'error' =>
                        $e->getMessage(),
                ]
            );

        } catch (Throwable $e) {
            AuditLogger::log(
                'mfa_internal_error',
                [
                    'user_id' =>
                        $usuarioId,
                    'exception' =>
                        $e::class,
                ]
            );

            http_response_code(500);

            View::render(
                'auth/mfa',
                [
                    'error' =>
                        'Não foi possível validar o segundo fator.',
                ]
            );
        }
    }

    public function mostrarConfiguracao(): void
    {
        if (Authorization::check()) {
            Response::redirect(
                '/dashboard.php'
            );
        }

        $usuarioId = $this->pendingUserId();

        $mfa = new MfaService();

        if ($mfa->configurado($usuarioId)) {
            Response::redirect('/mfa.php');
        }

        $usuario = $this->buscarUsuario(
            $usuarioId
        );

        $configuracao =
            $mfa->prepararConfiguracao(
                $usuarioId,
                (string) $usuario['email']
            );

        View::render(
            'auth/mfa_configurar',
            [
                'error' => null,
                'qrDataUri' =>
                    $configuracao['qr_data_uri'],
                'segredo' =>
                    $configuracao['segredo'],
            ]
        );
    }

    public function confirmarConfiguracao(): void
    {
        $usuarioId =
            $this->pendingUserId();

        $dados = SecureFormRequest::data();

        Csrf::requireValid(
            SecureFormRequest::csrfToken($dados)
        );

        $codigo = (string) (
            $dados['codigo'] ?? ''
        );

        $identifier =
            self::rateIdentifier($usuarioId);

        RateLimiter::requireAllowed(
            'mfa_configuracao',
            self::MFA_LIMIT,
            self::MFA_WINDOW_SECONDS,
            $identifier
        );

        try {
            $mfa = new MfaService();

            if (
                !$mfa->confirmarConfiguracao(
                    $usuarioId,
                    $codigo
                )
            ) {
                AuditLogger::log(
                    'mfa_setup_failed',
                    [
                        'user_id' =>
                            $usuarioId,
                    ]
                );

                $usuario =
                    $this->buscarUsuario(
                        $usuarioId
                    );

                $configuracao =
                    $mfa->prepararConfiguracao(
                        $usuarioId,
                        (string) $usuario['email']
                    );

                http_response_code(401);

                View::render(
                    'auth/mfa_configurar',
                    [
                        'error' =>
                            'Código inválido. Confira o aplicativo autenticador.',
                        'qrDataUri' =>
                            $configuracao['qr_data_uri'],
                        'segredo' =>
                            $configuracao['segredo'],
                    ]
                );

                return;
            }

            RateLimiter::reset(
                'mfa_configuracao',
                $identifier
            );

            AuditLogger::log(
                'mfa_setup_completed',
                [
                    'user_id' =>
                        $usuarioId,
                ]
            );

            $auth = new AuthService();

            $auth->concluirMfa(
                $usuarioId
            );

            Response::redirect(
                '/dashboard.php'
            );

        } catch (Throwable $e) {
            AuditLogger::log(
                'mfa_setup_internal_error',
                [
                    'user_id' =>
                        $usuarioId,
                    'exception' =>
                        $e::class,
                ]
            );

            http_response_code(500);

            exit(
                'Não foi possível concluir a configuração do MFA.'
            );
        }
    }

    private function pendingUserId(): int
    {
        $usuarioId =
            PendingAuthentication::userId();

        if ($usuarioId === null) {
            Response::redirect('/login.php');
            exit;
        }

        return $usuarioId;
    }

    private function buscarUsuario(
        int $usuarioId
    ): array {
        $service = new UsuarioService();

        $usuario =
            $service->buscarPorId(
                $usuarioId
            );

        if ($usuario === null) {
            PendingAuthentication::clear();

            Response::redirect('/login.php');
            exit;
        }

        return $usuario;
    }

    private static function rateIdentifier(
        int $usuarioId
    ): string {
        $ip = trim(
            (string) (
                $_SERVER['REMOTE_ADDR']
                ?? 'desconhecido'
            )
        );

        return
            'usuario:' . $usuarioId
            . '|ip:' . $ip;
    }
}
