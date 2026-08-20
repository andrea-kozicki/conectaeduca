<?php

declare(strict_types=1);

namespace ConectaEduca\Service;

use Closure;
use ConectaEduca\Config\Env;
use ConectaEduca\Security\AuditLogger;
use InvalidArgumentException;
use RuntimeException;

final class PasswordResetNotificationService
{
    private const SUBJECT = 'Recuperação de senha - ConectaEduca';

    private PasswordResetRequestService $requests;

    /** @var Closure(string,string,string,string,string):void */
    private Closure $sendMail;

    /** @var Closure(string,array):void */
    private Closure $audit;

    /** @var Closure(string):string */
    private Closure $resetUrlBuilder;

    public function __construct(
        ?PasswordResetRequestService $requests = null,
        ?callable $sendMail = null,
        ?callable $audit = null,
        ?callable $resetUrlBuilder = null
    ) {
        $this->requests = $requests
            ?? new PasswordResetRequestService();

        if ($sendMail !== null) {
            $this->sendMail = Closure::fromCallable($sendMail);
        } else {
            $mailer = new MailService();

            $this->sendMail = static function (
                string $toEmail,
                string $toName,
                string $subject,
                string $htmlBody,
                string $textBody
            ) use ($mailer): void {
                $mailer->sendHtml(
                    $toEmail,
                    $toName,
                    $subject,
                    $htmlBody,
                    $textBody
                );
            };
        }

        $this->audit = $audit !== null
            ? Closure::fromCallable($audit)
            : static function (string $event, array $context): void {
                AuditLogger::log($event, $context);
            };

        $this->resetUrlBuilder = $resetUrlBuilder !== null
            ? Closure::fromCallable($resetUrlBuilder)
            : static fn (string $token): string => self::buildResetUrl($token);
    }

    /**
     * Solicita recuperação e, quando houver uma conta recuperável, envia o
     * token por e-mail sem expor o campo interno "delivery" ao chamador.
     *
     * Falhas de configuração/transporte SMTP não alteram a resposta pública,
     * evitando transformar o e-mail em um canal de enumeração de usuários.
     * A falha é registrada somente por evento operacional, sem destinatário,
     * token, link ou corpo da mensagem.
     *
     * @return array{
     *     status:'accepted'|'rate_limited',
     *     public_message:string
     * }
     */
    public function solicitarEEnviar(
        string $email,
        ?string $ip = null
    ): array {
        $resultado = $this->requests->solicitar(
            $email,
            $ip
        );

        $publico = [
            'status' => $resultado['status'],
            'public_message' => $resultado['public_message'],
        ];

        $delivery = $resultado['delivery'] ?? null;

        if (!is_array($delivery)) {
            return $publico;
        }

        $usuarioId = (int) ($delivery['user_id'] ?? 0);

        try {
            $resetUrl = ($this->resetUrlBuilder)(
                (string) $delivery['token']
            );

            [$htmlBody, $textBody] = self::buildBodies(
                (string) ($delivery['name'] ?? ''),
                $resetUrl,
                $delivery['expires_at'] ?? null
            );

            ($this->sendMail)(
                (string) $delivery['email'],
                (string) ($delivery['name'] ?? ''),
                self::SUBJECT,
                $htmlBody,
                $textBody
            );

            ($this->audit)(
                'password_reset_mail_sent',
                [
                    'user_id' => $usuarioId,
                ]
            );
        } catch (RuntimeException|InvalidArgumentException $e) {
            ($this->audit)(
                'password_reset_mail_failed',
                [
                    'user_id' => $usuarioId,
                ]
            );
        }

        return $publico;
    }

    private static function buildResetUrl(string $token): string
    {
        $appUrl = trim(Env::required('APP_URL'));

        if (
            filter_var($appUrl, FILTER_VALIDATE_URL) === false
            || !in_array(
                strtolower((string) parse_url($appUrl, PHP_URL_SCHEME)),
                ['http', 'https'],
                true
            )
        ) {
            throw new RuntimeException('APP_URL inválida para recuperação de senha.');
        }

        return rtrim($appUrl, '/')
            . '/redefinir-senha.php?token='
            . rawurlencode($token);
    }

    /**
     * @return array{0:string,1:string}
     */
    private static function buildBodies(
        string $name,
        string $resetUrl,
        mixed $expiresAt
    ): array {
        $safeName = htmlspecialchars(
            trim($name) !== '' ? trim($name) : 'Olá',
            ENT_QUOTES | ENT_SUBSTITUTE,
            'UTF-8'
        );

        $safeUrl = htmlspecialchars(
            $resetUrl,
            ENT_QUOTES | ENT_SUBSTITUTE,
            'UTF-8'
        );

        $expiresText = '';

        if ($expiresAt instanceof \DateTimeInterface) {
            $expiresText = $expiresAt->format('d/m/Y H:i');
        }

        $htmlExpiry = $expiresText !== ''
            ? '<p>Este link expira em <strong>'
                . htmlspecialchars($expiresText, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8')
                . '</strong>.</p>'
            : '';

        $textExpiry = $expiresText !== ''
            ? "\nEste link expira em {$expiresText}.\n"
            : "\n";

        $htmlBody = <<<HTML
<p>{$safeName},</p>
<p>Recebemos uma solicitação para redefinir a senha da sua conta no ConectaEduca.</p>
<p><a href="{$safeUrl}">Redefinir minha senha</a></p>
{$htmlExpiry}<p>Se você não solicitou esta alteração, ignore esta mensagem.</p>
<p>Por segurança, não encaminhe este e-mail nem compartilhe o link de recuperação.</p>
HTML;

        $textBody = "{$name},\n\n"
            . "Recebemos uma solicitação para redefinir a senha da sua conta no ConectaEduca.\n\n"
            . "Redefina sua senha usando este link:\n{$resetUrl}\n"
            . $textExpiry
            . "Se você não solicitou esta alteração, ignore esta mensagem.\n"
            . "Por segurança, não encaminhe este e-mail nem compartilhe o link de recuperação.";

        return [
            trim($htmlBody),
            trim($textBody),
        ];
    }
}
