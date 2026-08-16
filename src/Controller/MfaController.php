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
use ConectaEduca\Service\MfaRecoveryService;
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

        if (PendingAuthentication::hasRecoveryCodes()) {
            Response::redirect(
                '/mfa-codigos-recuperacao.php'
            );
        }

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
            if (PendingAuthentication::hasRecoveryCodes()) {
                Response::redirect(
                    '/mfa-codigos-recuperacao.php'
                );
            }

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

            $recovery = new MfaRecoveryService();

            $codigos = $recovery->gerarParaUsuario(
                $usuarioId
            );

            PendingAuthentication::storeRecoveryCodes(
                $codigos
            );

            PendingAuthentication::extendForRecoveryCodes();

            AuditLogger::log(
                'mfa_recovery_codes_generated',
                [
                    'user_id' =>
                        $usuarioId,
                    'count' =>
                        count($codigos),
                ]
            );

            Response::redirect(
                '/mfa-codigos-recuperacao.php'
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

    public function mostrarCodigosRecuperacao(): void
    {
        if (Authorization::check()) {
            Response::redirect('/dashboard.php');
        }

        $usuarioId = $this->pendingUserId();

        $mfa = new MfaService();

        if (!$mfa->configurado($usuarioId)) {
            Response::redirect('/mfa-configurar.php');
        }

        $codigos = PendingAuthentication::recoveryCodes();

        if ($codigos === null) {
            Response::redirect('/mfa.php');
        }

        self::noStore();

        View::render(
            'auth/mfa_codigos_recuperacao',
            [
                'error' => null,
                'codigos' => $codigos,
            ]
        );
    }

    public function confirmarCodigosRecuperacao(): void
    {
        if (Authorization::check()) {
            Response::redirect('/dashboard.php');
        }

        $usuarioId = $this->pendingUserId();

        $dados = SecureFormRequest::data();

        Csrf::requireValid(
            SecureFormRequest::csrfToken($dados)
        );

        $codigos = PendingAuthentication::recoveryCodes();

        if ($codigos === null) {
            Response::redirect('/mfa.php');
        }

        $confirmado = (string) (
            $dados['confirmado'] ?? ''
        );

        if ($confirmado !== '1') {
            self::noStore();
            http_response_code(422);

            View::render(
                'auth/mfa_codigos_recuperacao',
                [
                    'error' =>
                        'Confirme que você salvou os códigos de recuperação.',
                    'codigos' => $codigos,
                ]
            );

            return;
        }

        try {
            $recovery = new MfaRecoveryService();

            if ($recovery->quantidadeAtivos($usuarioId) < 1) {
                AuditLogger::log(
                    'mfa_recovery_codes_missing',
                    [
                        'user_id' => $usuarioId,
                    ]
                );

                http_response_code(409);
                self::noStore();

                View::render(
                    'auth/mfa_codigos_recuperacao',
                    [
                        'error' =>
                            'Os códigos de recuperação não estão disponíveis. Refaça a configuração do MFA.',
                        'codigos' => $codigos,
                    ]
                );

                return;
            }

            $auth = new AuthService();

            $auth->concluirMfa($usuarioId);

            AuditLogger::log(
                'mfa_recovery_codes_acknowledged',
                [
                    'user_id' => $usuarioId,
                    'remaining' =>
                        $recovery->quantidadeAtivos($usuarioId),
                ]
            );

            Response::redirect('/dashboard.php');

        } catch (DomainException $e) {
            self::noStore();
            http_response_code(401);

            View::render(
                'auth/mfa_codigos_recuperacao',
                [
                    'error' => $e->getMessage(),
                    'codigos' => $codigos,
                ]
            );

        } catch (Throwable $e) {
            AuditLogger::log(
                'mfa_recovery_codes_internal_error',
                [
                    'user_id' => $usuarioId,
                    'exception' => $e::class,
                ]
            );

            self::noStore();
            http_response_code(500);

            View::render(
                'auth/mfa_codigos_recuperacao',
                [
                    'error' =>
                        'Não foi possível concluir a configuração dos códigos de recuperação.',
                    'codigos' => $codigos,
                ]
            );
        }
    }

    private static function noStore(): void
    {
        header(
            'Cache-Control: no-store, no-cache, must-revalidate, private'
        );
        header('Pragma: no-cache');
        header('Expires: 0');
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
