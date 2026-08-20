<?php

declare(strict_types=1);

namespace ConectaEduca\Service;

use Closure;
use ConectaEduca\Config\Database;
use ConectaEduca\Repository\UsuarioRepository;
use ConectaEduca\Security\AuditLogger;
use ConectaEduca\Security\InputValidator;
use ConectaEduca\Security\RateLimiter;

final class PasswordResetRequestService
{
    private const IP_LIMIT = 20;
    private const ACCOUNT_IP_LIMIT = 3;
    private const WINDOW_SECONDS = 900;

    private const PUBLIC_MESSAGE =
        'Se existir uma conta associada ao e-mail informado, enviaremos as instruções de recuperação.';

    private const RATE_LIMIT_MESSAGE =
        'Muitas solicitações de recuperação. Tente novamente mais tarde.';

    private PasswordResetService $tokens;

    /** @var Closure(string):?array */
    private Closure $userFinder;

    /** @var Closure(string,int,int,string):bool */
    private Closure $rateAllow;

    /** @var Closure(string,array):void */
    private Closure $audit;

    public function __construct(
        ?PasswordResetService $tokens = null,
        ?callable $userFinder = null,
        ?callable $rateAllow = null,
        ?callable $audit = null
    ) {
        $this->tokens = $tokens
            ?? new PasswordResetService();

        if ($userFinder !== null) {
            $this->userFinder = Closure::fromCallable(
                $userFinder
            );
        } else {
            $usuarios = new UsuarioRepository(
                Database::connect()
            );

            $this->userFinder = static fn (string $email): ?array =>
                $usuarios->buscarPorEmail($email);
        }

        $this->rateAllow = $rateAllow !== null
            ? Closure::fromCallable($rateAllow)
            : static fn (
                string $action,
                int $limit,
                int $windowSeconds,
                string $identifier
            ): bool => RateLimiter::allow(
                $action,
                $limit,
                $windowSeconds,
                $identifier
            );

        $this->audit = $audit !== null
            ? Closure::fromCallable($audit)
            : static function (string $event, array $context): void {
                AuditLogger::log($event, $context);
            };
    }

    /**
     * Registra uma solicitação de recuperação sem revelar se a conta existe.
     *
     * O campo delivery é exclusivamente interno. Ele será consumido pela
     * camada SMTP no próximo passo e nunca deve ser serializado para o cliente.
     *
     * @return array{
     *     status:'accepted'|'rate_limited',
     *     public_message:string,
     *     delivery:null|array{
     *         user_id:int,
     *         email:string,
     *         name:string,
     *         token:string,
     *         expires_at:\DateTimeImmutable
     *     }
     * }
     */
    public function solicitar(
        string $email,
        ?string $ip = null
    ): array {
        $ipIdentifier = self::ipIdentifier($ip);

        if (!$this->allowed(
            'password_reset_ip',
            self::IP_LIMIT,
            $ipIdentifier
        )) {
            $this->auditRateLimit('password_reset_ip');

            return self::rateLimitedResult();
        }

        $emailNormalizado = strtolower(
            InputValidator::email($email)
        );

        $emailHash = hash(
            'sha256',
            $emailNormalizado
        );

        $accountIdentifier =
            'email_hash:' . $emailHash
            . '|'
            . $ipIdentifier;

        if (!$this->allowed(
            'password_reset_conta_ip',
            self::ACCOUNT_IP_LIMIT,
            $accountIdentifier
        )) {
            $this->auditRateLimit(
                'password_reset_conta_ip'
            );

            return self::rateLimitedResult();
        }

        $usuario = ($this->userFinder)(
            $emailNormalizado
        );

        if (!self::usuarioRecuperavel($usuario)) {
            ($this->audit)(
                'password_reset_requested',
                [
                    'email_hash' => $emailHash,
                ]
            );

            return self::acceptedResult();
        }

        $usuarioId = (int) $usuario['id'];

        $emitido = $this->tokens
            ->emitirParaUsuario($usuarioId);

        ($this->audit)(
            'password_reset_requested',
            [
                'user_id' => $usuarioId,
                'email_hash' => $emailHash,
            ]
        );

        return self::acceptedResult([
            'user_id' => $usuarioId,
            'email' => (string) $usuario['email'],
            'name' => (string) ($usuario['nome'] ?? ''),
            'token' => $emitido['token'],
            'expires_at' => $emitido['expira_em'],
        ]);
    }

    private function allowed(
        string $action,
        int $limit,
        string $identifier
    ): bool {
        return ($this->rateAllow)(
            $action,
            $limit,
            self::WINDOW_SECONDS,
            $identifier
        );
    }

    private function auditRateLimit(
        string $action
    ): void {
        ($this->audit)(
            'rate_limit_blocked',
            [
                'action' => $action,
            ]
        );
    }

    private static function usuarioRecuperavel(
        mixed $usuario
    ): bool {
        return is_array($usuario)
            && (int) ($usuario['id'] ?? 0) > 0
            && (int) ($usuario['conta_ativada'] ?? 0) === 1
            && isset($usuario['email']);
    }

    private static function ipIdentifier(
        ?string $ip
    ): string {
        $ip = trim(
            $ip
                ?? (string) (
                    $_SERVER['REMOTE_ADDR']
                    ?? 'desconhecido'
                )
        );

        if ($ip === '') {
            $ip = 'desconhecido';
        }

        return 'ip:' . $ip;
    }

    /**
     * @param null|array{
     *     user_id:int,
     *     email:string,
     *     name:string,
     *     token:string,
     *     expires_at:\DateTimeImmutable
     * } $delivery
     */
    private static function acceptedResult(
        ?array $delivery = null
    ): array {
        return [
            'status' => 'accepted',
            'public_message' => self::PUBLIC_MESSAGE,
            'delivery' => $delivery,
        ];
    }

    private static function rateLimitedResult(): array
    {
        return [
            'status' => 'rate_limited',
            'public_message' => self::RATE_LIMIT_MESSAGE,
            'delivery' => null,
        ];
    }
}
