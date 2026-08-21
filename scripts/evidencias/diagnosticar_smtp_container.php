<?php

declare(strict_types=1);

use PHPMailer\PHPMailer\PHPMailer;

require '/var/www/conectaeduca/vendor/autoload.php';

function out(string $level, string $message): void
{
    printf("%-11s %s\n", $level, $message);
}

function fail(string $stage, string $message): never
{
    out('FALHA', "{$stage}: {$message}");
    exit(1);
}

function envRequired(string $key): string
{
    $value = getenv($key);
    if ($value === false || trim($value) === '') {
        fail('ambiente', "variável ausente: {$key}");
    }
    return trim($value);
}

function smtpReadResponse($stream): array
{
    $lines = [];
    while (!feof($stream)) {
        $line = fgets($stream, 4096);
        if ($line === false) {
            break;
        }
        $lines[] = rtrim($line, "\r\n");
        if (preg_match('/^\d{3} /', $line) === 1) {
            break;
        }
        if (count($lines) > 100) {
            break;
        }
    }
    return $lines;
}

function smtpCode(array $lines): int
{
    if ($lines === []) {
        return 0;
    }
    if (preg_match('/^(\d{3})/', $lines[count($lines) - 1], $m) !== 1) {
        return 0;
    }
    return (int) $m[1];
}

function sendCommand($stream, string $command): array
{
    if (fwrite($stream, $command . "\r\n") === false) {
        fail('smtp-protocolo', 'não foi possível escrever no socket');
    }
    return smtpReadResponse($stream);
}

function safeOpenSslError(): string
{
    $last = error_get_last();
    if (!is_array($last)) {
        return 'detalhe indisponível';
    }
    $message = (string)($last['message'] ?? '');
    $message = preg_replace('/[\r\n]+/', ' ', $message) ?? $message;
    return mb_substr($message, 0, 280);
}

$host = envRequired('MAIL_HOST');
$port = (int) envRequired('MAIL_PORT');
$username = envRequired('MAIL_USERNAME');
$passwordFile = envRequired('MAIL_PASSWORD_FILE');
$encryption = strtolower(envRequired('MAIL_ENCRYPTION'));

if (!in_array($encryption, ['tls', 'starttls'], true)) {
    fail('ambiente', 'este diagnóstico espera STARTTLS');
}

if (!is_file($passwordFile) || !is_readable($passwordFile)) {
    fail('docker-secret', 'MAIL_PASSWORD_FILE não é legível dentro do container');
}

$password = trim((string) file_get_contents($passwordFile));
if ($password === '') {
    fail('docker-secret', 'arquivo de segredo está vazio');
}

$mode = substr(sprintf('%o', fileperms($passwordFile) & 0777), -3);
out('OK', "Docker secret legível dentro do container (mode={$mode}, conteúdo não exibido)");

if (!extension_loaded('openssl')) {
    fail('php', 'ext-openssl ausente');
}
out('OK', 'ext-openssl disponível');

$ips = gethostbynamel($host);
if ($ips === false || $ips === []) {
    fail('dns', "não foi possível resolver {$host}");
}
out('OK', 'DNS do container resolveu o servidor SMTP: ' . count($ips) . ' IPv4');

$errno = 0;
$errstr = '';
$stream = @stream_socket_client(
    "tcp://{$host}:{$port}",
    $errno,
    $errstr,
    10,
    STREAM_CLIENT_CONNECT
);

if (!is_resource($stream)) {
    fail('tcp', "conexão {$host}:{$port} falhou (errno={$errno})");
}

stream_set_timeout($stream, 10);
out('OK', "TCP do container alcança {$host}:{$port}");

$banner = smtpReadResponse($stream);
if (smtpCode($banner) !== 220) {
    fclose($stream);
    fail('smtp-banner', 'servidor não respondeu com 220');
}
out('OK', 'banner SMTP 220 recebido');

$ehlo = sendCommand($stream, 'EHLO conectaeduca.local');
if (smtpCode($ehlo) !== 250) {
    fclose($stream);
    fail('smtp-ehlo', 'EHLO não recebeu resposta 250');
}

$ehloText = strtoupper(implode("\n", $ehlo));
if (!str_contains($ehloText, 'STARTTLS')) {
    fclose($stream);
    fail('smtp-starttls', 'servidor não anunciou STARTTLS');
}
out('OK', 'servidor SMTP anuncia STARTTLS');

$startTls = sendCommand($stream, 'STARTTLS');
if (smtpCode($startTls) !== 220) {
    fclose($stream);
    fail('smtp-starttls', 'STARTTLS não recebeu resposta 220');
}

$context = stream_context_get_options($stream);
stream_context_set_option($stream, 'ssl', 'verify_peer', true);
stream_context_set_option($stream, 'ssl', 'verify_peer_name', true);
stream_context_set_option($stream, 'ssl', 'allow_self_signed', false);
stream_context_set_option($stream, 'ssl', 'peer_name', $host);
stream_context_set_option($stream, 'ssl', 'SNI_enabled', true);

$cryptoOk = @stream_socket_enable_crypto(
    $stream,
    true,
    STREAM_CRYPTO_METHOD_TLS_CLIENT
);

if ($cryptoOk !== true) {
    $detail = safeOpenSslError();
    fclose($stream);
    fail('tls', "handshake/validação de certificado falhou: {$detail}");
}
out('OK', 'TLS negociado com validação de peer/hostname');

fclose($stream);

/*
 * Agora testa autenticação SMTP, sem enviar mensagem.
 * O password nunca é impresso e mensagens são sanitizadas.
 */
$mail = new PHPMailer(true);
$mail->isSMTP();
$mail->Host = $host;
$mail->Port = $port;
$mail->SMTPAuth = true;
$mail->Username = $username;
$mail->Password = $password;
$mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
$mail->SMTPAutoTLS = true;
$mail->Timeout = 10;
$mail->SMTPDebug = 0;
$mail->SMTPKeepAlive = false;
$mail->SMTPOptions = [
    'ssl' => [
        'verify_peer' => true,
        'verify_peer_name' => true,
        'allow_self_signed' => false,
    ],
];

try {
    if (!$mail->smtpConnect()) {
        fail('smtp-auth', 'PHPMailer não conseguiu abrir/autenticar a sessão SMTP');
    }
    out('OK', 'PHPMailer autenticou no relay sem enviar mensagem');
    $mail->smtpClose();
} catch (Throwable $e) {
    $msg = $e->getMessage();
    $msg = str_replace([$password, $username], ['[REDACTED]', '[EMAIL]'], $msg);
    $msg = preg_replace('/[\r\n]+/', ' ', $msg) ?? $msg;
    $msg = mb_substr($msg, 0, 280);
    fail('smtp-auth', $msg !== '' ? $msg : 'falha de autenticação sem detalhe seguro');
} finally {
    $password = '';
}

out('OK', 'diagnóstico SMTP do container concluído sem transmitir conteúdo sensível');
