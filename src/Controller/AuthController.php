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
use DomainException;
use Throwable;

final class AuthController
{
    private const LOGIN_IP_LIMIT = 60;
    private const LOGIN_ACCOUNT_LIMIT = 5;
    private const LOGIN_WINDOW_SECONDS = 300;

    public function mostrarLogin(): void
    {
        if (Authorization::check()) {
            Response::redirect('/dashboard.php');
        }

        /*
         * Se a senha já foi validada, o usuário deve continuar
         * o fluxo MFA em vez de voltar à primeira etapa.
         */
        if (PendingAuthentication::active()) {
            Response::redirect('/mfa.php');
        }

        View::render('auth/login', [
            'error' => null,
            'email' => '',
            'logoutSuccess' =>
                ($_GET['logout'] ?? '') === '1',
            'passwordResetSuccess' =>
                ($_GET['senha_redefinida'] ?? '') === '1',
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

        $ipIdentifier =
            self::ipIdentifier();

        RateLimiter::requireAllowed(
            'login_ip',
            self::LOGIN_IP_LIMIT,
            self::LOGIN_WINDOW_SECONDS,
            $ipIdentifier
        );

        $accountIdentifier =
            self::accountIpIdentifier($email);

        RateLimiter::requireAllowed(
            'login_conta_ip',
            self::LOGIN_ACCOUNT_LIMIT,
            self::LOGIN_WINDOW_SECONDS,
            $accountIdentifier
        );

        try {
            $service = new AuthService();

            $resultado =
                $service->autenticar(
                    $email,
                    $senha
                );

            /*
             * A senha está correta.
             * As futuras falhas agora pertencem ao bucket MFA.
             */
            RateLimiter::reset(
                'login_conta_ip',
                $accountIdentifier
            );

            if (
                ($resultado['mfa_configurado'] ?? false)
                === true
            ) {
                Response::redirect('/mfa.php');
            }

            Response::redirect(
                '/mfa-configurar.php'
            );

        } catch (DomainException $e) {
            http_response_code(401);

            View::render('auth/login', [
                'error' => $e->getMessage(),
                'email' => $email,
                'logoutSuccess' => false,
                'passwordResetSuccess' => false,
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
                'passwordResetSuccess' => false,
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

    private static function ipIdentifier(): string
    {
        $ip = trim(
            (string) (
                $_SERVER['REMOTE_ADDR']
                ?? 'desconhecido'
            )
        );

        if ($ip === '') {
            $ip = 'desconhecido';
        }

        return 'ip:' . $ip;
    }

    private static function accountIpIdentifier(
        string $email
    ): string {
        $emailNormalizado = strtolower(
            trim($email)
        );

        $emailHash = hash(
            'sha256',
            $emailNormalizado
        );

        return
            'email_hash:' . $emailHash
            . '|'
            . self::ipIdentifier();
    }
}
