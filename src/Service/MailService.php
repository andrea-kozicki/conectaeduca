<?php
declare(strict_types=1);

namespace ConectaEduca\Service;

use Closure;
use ConectaEduca\Config\Env;
use ConectaEduca\Security\Secrets;
use InvalidArgumentException;
use PHPMailer\PHPMailer\Exception as PHPMailerException;
use PHPMailer\PHPMailer\PHPMailer;
use RuntimeException;

final class MailService
{
    /** @var Closure(): PHPMailer */
    private Closure $mailerFactory;

    public function __construct(?callable $mailerFactory = null)
    {
        $this->mailerFactory = $mailerFactory !== null
            ? Closure::fromCallable($mailerFactory)
            : static fn (): PHPMailer => new PHPMailer(true);
    }

    public function sendHtml(
        string $toEmail,
        string $toName,
        string $subject,
        string $htmlBody,
        ?string $textBody = null
    ): void {
        $toEmail = trim($toEmail);
        $toName = trim($toName);
        $subject = trim($subject);

        if (!PHPMailer::validateAddress($toEmail)) {
            throw new InvalidArgumentException('Endereço de e-mail de destino inválido.');
        }

        if ($subject === '' || preg_match('/[\r\n]/', $subject) === 1) {
            throw new InvalidArgumentException('Assunto de e-mail inválido.');
        }

        if (trim($htmlBody) === '') {
            throw new InvalidArgumentException('O corpo HTML do e-mail não pode estar vazio.');
        }

        $mailer = ($this->mailerFactory)();

        if (!$mailer instanceof PHPMailer) {
            throw new RuntimeException('Factory de e-mail inválida.');
        }

        $this->configureSmtp($mailer);

        try {
            $fromAddress = Env::required('MAIL_FROM_ADDRESS');
            $fromName = Env::get('MAIL_FROM_NAME', 'ConectaEduca') ?? 'ConectaEduca';

            if (!PHPMailer::validateAddress($fromAddress)) {
                throw new RuntimeException('MAIL_FROM_ADDRESS contém um endereço inválido.');
            }

            $mailer->clearAllRecipients();
            $mailer->clearReplyTos();
            $mailer->clearAttachments();
            $mailer->clearCustomHeaders();

            $mailer->setFrom($fromAddress, $fromName);
            $mailer->addAddress($toEmail, $toName);
            $mailer->isHTML(true);
            $mailer->Subject = $subject;
            $mailer->Body = $htmlBody;
            $mailer->AltBody = $textBody !== null && trim($textBody) !== ''
                ? trim($textBody)
                : self::plainTextFromHtml($htmlBody);

            if (!$mailer->send()) {
                throw new RuntimeException('Falha no transporte SMTP.');
            }
        } catch (PHPMailerException $e) {
            // Não registrar ErrorInfo, credenciais SMTP, corpo ou destinatário.
            error_log('[MAIL_ERROR] Falha no envio SMTP pelo PHPMailer.');

            throw new RuntimeException('Não foi possível enviar o e-mail.', 0, $e);
        } catch (RuntimeException $e) {
            error_log('[MAIL_ERROR] Falha no envio SMTP.');

            throw new RuntimeException('Não foi possível enviar o e-mail.', 0, $e);
        }
    }

    private function configureSmtp(PHPMailer $mailer): void
    {
        $host = trim(Env::required('MAIL_HOST'));
        $port = self::positiveInt('MAIL_PORT', Env::get('MAIL_PORT', '587') ?? '587', 65535);
        $timeout = self::positiveInt('MAIL_TIMEOUT', Env::get('MAIL_TIMEOUT', '10') ?? '10', 120);
        $encryption = strtolower(trim(Env::get('MAIL_ENCRYPTION', 'tls') ?? 'tls'));
        $smtpAuth = Env::bool('MAIL_SMTP_AUTH', true);

        if ($host === '') {
            throw new RuntimeException('MAIL_HOST não pode estar vazio.');
        }

        $mailer->isSMTP();
        $mailer->Host = $host;
        $mailer->Port = $port;
        $mailer->Timeout = $timeout;
        $mailer->SMTPDebug = 0;
        $mailer->SMTPKeepAlive = false;
        $mailer->SMTPAuth = $smtpAuth;
        $mailer->CharSet = PHPMailer::CHARSET_UTF8;

        switch ($encryption) {
            case 'tls':
            case 'starttls':
                $mailer->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
                $mailer->SMTPAutoTLS = true;
                break;

            case 'ssl':
            case 'smtps':
                $mailer->SMTPSecure = PHPMailer::ENCRYPTION_SMTPS;
                $mailer->SMTPAutoTLS = true;
                break;

            case 'none':
                // Permitido para capturadores SMTP locais de desenvolvimento/teste.
                $mailer->SMTPSecure = '';
                $mailer->SMTPAutoTLS = false;
                break;

            default:
                throw new RuntimeException(
                    'MAIL_ENCRYPTION deve ser tls, starttls, smtps, ssl ou none.'
                );
        }

        if ($smtpAuth) {
            $mailer->Username = Env::required('MAIL_USERNAME');
            $mailer->Password = Secrets::get('MAIL_PASSWORD');
        } else {
            $mailer->Username = '';
            $mailer->Password = '';
        }
    }

    private static function positiveInt(string $key, string $value, int $max): int
    {
        if (!preg_match('/^[0-9]+$/', $value)) {
            throw new RuntimeException("{$key} deve ser um número inteiro positivo.");
        }

        $number = (int) $value;

        if ($number < 1 || $number > $max) {
            throw new RuntimeException("{$key} está fora do intervalo permitido.");
        }

        return $number;
    }

    private static function plainTextFromHtml(string $html): string
    {
        $text = html_entity_decode(
            strip_tags(str_replace(['<br>', '<br/>', '<br />'], "\n", $html)),
            ENT_QUOTES | ENT_HTML5,
            'UTF-8'
        );

        $text = preg_replace('/[ \t]+/', ' ', $text) ?? $text;
        $text = preg_replace('/\n{3,}/', "\n\n", $text) ?? $text;

        return trim($text);
    }
}
