<?php

declare(strict_types=1);

use ConectaEduca\Config\Env;
use ConectaEduca\Security\Secrets;
use ConectaEduca\Service\MailService;
use PHPMailer\PHPMailer\PHPMailer;

require_once dirname(__DIR__, 2) . '/vendor/autoload.php';

function out(string $level, string $message): void
{
    printf("%-11s %s\n", $level, $message);
}

function reservedEmail(string $email): bool
{
    $domain = strtolower((string) substr(strrchr($email, '@') ?: '', 1));

    return $domain === ''
        || $domain === 'localhost'
        || str_ends_with($domain, '.test')
        || str_ends_with($domain, '.invalid')
        || str_ends_with($domain, '.example');
}

try {
    Env::load();

    $host = strtolower(trim(Env::required('MAIL_HOST')));
    $encryption = strtolower(trim(Env::required('MAIL_ENCRYPTION')));
    $smtpAuth = Env::bool('MAIL_SMTP_AUTH', true);
    $to = trim(Env::required('SMTP_REAL_CHECKPOINT_TO'));
    $from = trim(Env::required('MAIL_FROM_ADDRESS'));

    if (in_array($host, ['127.0.0.1', '::1', 'localhost', 'mailpit'], true)) {
        throw new RuntimeException('MAIL_HOST aponta para laboratório/local, não SMTP real.');
    }

    if (!in_array($encryption, ['tls', 'starttls', 'ssl', 'smtps'], true)) {
        throw new RuntimeException('SMTP real exige TLS/STARTTLS ou SMTPS.');
    }

    if (!$smtpAuth) {
        throw new RuntimeException('Checkpoint SMTP real exige autenticação habilitada.');
    }

    if (!PHPMailer::validateAddress($to) || reservedEmail($to)) {
        throw new RuntimeException('SMTP_REAL_CHECKPOINT_TO deve ser uma caixa real válida.');
    }

    if (!PHPMailer::validateAddress($from) || reservedEmail($from)) {
        throw new RuntimeException('MAIL_FROM_ADDRESS deve usar domínio real válido.');
    }

    if (Env::get('MAIL_PASSWORD') !== null) {
        throw new RuntimeException('Para este checkpoint, use MAIL_PASSWORD_FILE em vez de MAIL_PASSWORD.');
    }

    $passwordFile = Env::required('MAIL_PASSWORD_FILE');
    if (!is_file($passwordFile) || !is_readable($passwordFile)) {
        throw new RuntimeException('MAIL_PASSWORD_FILE não aponta para arquivo legível.');
    }

    // Força leitura antecipada sem exibir o conteúdo.
    Secrets::get('MAIL_PASSWORD');
    out('OK', 'segredo SMTP obtido por arquivo sem exposição no relatório');
    out('OK', 'SMTP real usa autenticação e transporte TLS');

    $id = strtoupper(bin2hex(random_bytes(5)));
    $subject = "ConectaEduca - checkpoint SMTP real {$id}";

    $html = '<p>Checkpoint técnico de entrega SMTP do ConectaEduca.</p>'
        . '<p>Identificador: <strong>' . htmlspecialchars($id, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') . '</strong></p>'
        . '<p>Esta mensagem não contém token, senha ou dado pessoal da aplicação.</p>';

    $text = "Checkpoint técnico de entrega SMTP do ConectaEduca.\n"
        . "Identificador: {$id}\n"
        . "Esta mensagem não contém token, senha ou dado pessoal da aplicação.";

    (new MailService())->sendHtml(
        $to,
        'Checkpoint ConectaEduca',
        $subject,
        $html,
        $text
    );

    out('OK', 'servidor SMTP real aceitou a mensagem para entrega');
    out('INFO', "identificador={$id}");
    out('INFO', 'a confirmação final de entregabilidade exige verificar a caixa de destino e spam');
    exit(0);
} catch (Throwable $e) {
    out('FALHA', 'checkpoint SMTP real não foi concluído');
    out('INFO', 'classe=' . $e::class);
    out('INFO', 'mensagem=' . $e->getMessage());
    exit(1);
}
