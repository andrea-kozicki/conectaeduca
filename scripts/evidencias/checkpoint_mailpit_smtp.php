<?php
declare(strict_types=1);

use ConectaEduca\Config\Env;
use ConectaEduca\Service\MailService;

$root = dirname(__DIR__, 2);
require_once $root . '/vendor/autoload.php';

$ok = 0;
$fail = 0;

function aprovado(string $mensagem): void
{
    global $ok;
    ++$ok;
    printf("OK          %s\n", $mensagem);
}

function falha(string $mensagem): void
{
    global $fail;
    ++$fail;
    printf("FALHA       %s\n", $mensagem);
}

/**
 * @return array{status:int,body:string}
 */
function httpGet(string $url, int $timeoutSeconds = 3): array
{
    $context = stream_context_create([
        'http' => [
            'method' => 'GET',
            'timeout' => $timeoutSeconds,
            'ignore_errors' => true,
            'header' => "Connection: close\r\n",
        ],
    ]);

    $body = @file_get_contents($url, false, $context);
    $headers = $http_response_header ?? [];
    $status = 0;

    if (isset($headers[0]) && preg_match('/\s(\d{3})\s/', $headers[0], $matches) === 1) {
        $status = (int) $matches[1];
    }

    return [
        'status' => $status,
        'body' => $body === false ? '' : $body,
    ];
}

function setEnv(string $key, string $value): void
{
    $_ENV[$key] = $value;
    $_SERVER[$key] = $value;
    putenv($key . '=' . $value);
}

printf("======================================================================\n");
printf(" CONECTAEDUCA - CHECKPOINT SMTP REAL / MAILPIT LOCAL\n");
printf(" Captura SMTP sintética; nenhuma credencial ou e-mail real é utilizado\n");
printf("======================================================================\n\n");

$declaredEnv = Env::get('APP_ENV');
$localEnvironments = ['development', 'dev', 'test', 'testing', 'local'];

if ($declaredEnv !== null && trim($declaredEnv) !== '') {
    $normalizedEnv = strtolower(trim($declaredEnv));

    if (!in_array($normalizedEnv, $localEnvironments, true)) {
        falha("checkpoint recusado fora de ambiente local/teste: {$normalizedEnv}");
        printf("\nRESULTADO: REPROVADO.\n");
        exit(1);
    }

    aprovado("ambiente local/teste explicitamente confirmado: {$normalizedEnv}");
} else {
    aprovado('APP_ENV não declarado; checkpoint usará APP_ENV=test somente neste processo sintético');
}

// O transporte sem TLS/autenticação só é liberado dentro deste processo de
// evidência. A configuração persistente da aplicação e o .env não são alterados.
setEnv('APP_ENV', 'test');

$health = httpGet('http://127.0.0.1:18025/readyz');
if ($health['status'] !== 200) {
    falha('Mailpit não respondeu em http://127.0.0.1:18025/readyz');
    printf("\nDICA: suba deploy/lab/mailpit/compose.yml antes do checkpoint.\n");
    printf("\nRESULTADO: REPROVADO.\n");
    exit(1);
}

aprovado('Mailpit respondeu ao healthcheck HTTP local');

$marker = 'CE-RESET-SMTP-' . bin2hex(random_bytes(8));
$subject = 'ConectaEduca checkpoint SMTP ' . $marker;
$recipient = 'checkpoint-reset@exemplo.test';
$htmlMarker = '<strong>' . $marker . '</strong>';
$textMarker = 'Marcador SMTP: ' . $marker;

setEnv('MAIL_HOST', '127.0.0.1');
setEnv('MAIL_PORT', '11025');
setEnv('MAIL_SMTP_AUTH', 'false');
setEnv('MAIL_ENCRYPTION', 'none');
setEnv('MAIL_TIMEOUT', '5');
setEnv('MAIL_FROM_ADDRESS', 'nao-responda@exemplo.test');
setEnv('MAIL_FROM_NAME', 'ConectaEduca Lab');

try {
    $mail = new MailService();
    $mail->sendHtml(
        $recipient,
        'Fixture SMTP',
        $subject,
        '<p>Checkpoint SMTP do ConectaEduca.</p><p>' . $htmlMarker . '</p>',
        "Checkpoint SMTP do ConectaEduca.\n{$textMarker}"
    );
    aprovado('MailService entregou mensagem pelo protocolo SMTP real');
} catch (Throwable $e) {
    falha('MailService não conseguiu entregar a mensagem ao Mailpit');
    printf("INFO        exceção=%s\n", $e::class);
    printf("INFO        detalhe=mensagem interna da exceção omitida por segurança\n");
    printf("\nRESULTADO: REPROVADO.\n");
    exit(1);
}

$query = rawurlencode('subject:"' . $marker . '"');
$searchUrl = 'http://127.0.0.1:18025/api/v1/search?query=' . $query . '&limit=10';
$search = ['status' => 0, 'body' => ''];

for ($attempt = 0; $attempt < 20; ++$attempt) {
    $search = httpGet($searchUrl);

    if ($search['status'] === 200) {
        $decoded = json_decode($search['body'], true);
        $messages = is_array($decoded) ? ($decoded['messages'] ?? []) : [];

        if (is_array($messages) && count($messages) > 0) {
            break;
        }
    }

    usleep(100_000);
}

if ($search['status'] !== 200) {
    falha('API do Mailpit não respondeu à pesquisa da mensagem');
} else {
    aprovado('API do Mailpit respondeu à pesquisa da mensagem');
}

$decoded = json_decode($search['body'], true);
$messages = is_array($decoded) ? ($decoded['messages'] ?? []) : [];

if (!is_array($messages) || count($messages) < 1) {
    falha('mensagem sintética não foi localizada no Mailpit');
} else {
    aprovado('mensagem sintética foi localizada no Mailpit');
}

$message = is_array($messages) && isset($messages[0]) && is_array($messages[0])
    ? $messages[0]
    : [];

if (($message['Subject'] ?? null) === $subject) {
    aprovado('assunto capturado é exatamente o assunto enviado');
} else {
    falha('assunto capturado diverge do assunto enviado');
}

$toAddresses = [];
foreach (($message['To'] ?? []) as $address) {
    if (is_array($address) && isset($address['Address'])) {
        $toAddresses[] = strtolower((string) $address['Address']);
    }
}

if (in_array(strtolower($recipient), $toAddresses, true)) {
    aprovado('destinatário sintético foi preservado no envelope/mensagem');
} else {
    falha('destinatário sintético não foi localizado na mensagem capturada');
}

$text = httpGet(
    'http://127.0.0.1:18025/view/latest.txt?query=' . $query
);

if ($text['status'] === 200 && str_contains($text['body'], $textMarker)) {
    aprovado('parte texto foi capturada com o marcador esperado');
} else {
    falha('parte texto não contém o marcador esperado');
}

$html = httpGet(
    'http://127.0.0.1:18025/view/latest.html?query=' . $query
);

if ($html['status'] === 200 && str_contains($html['body'], $marker)) {
    aprovado('parte HTML foi capturada com o marcador esperado');
} else {
    falha('parte HTML não contém o marcador esperado');
}

$raw = httpGet('http://127.0.0.1:18025/api/v1/message/latest/raw');
if (
    $raw['status'] === 200
    && !str_contains($raw['body'], 'MAIL_PASSWORD')
    && !str_contains($raw['body'], 'smtp-user')
) {
    aprovado('mensagem bruta não contém nomes/valores de credencial SMTP de teste');
} else {
    falha('mensagem bruta apresentou marcador indevido de credencial SMTP');
}

printf("\n======================================================================\n");
printf(" RESULTADO\n");
printf("======================================================================\n");
printf("Aprovacoes: %d\n", $ok);
printf("Falhas:     %d\n", $fail);

if ($fail > 0) {
    printf("\nCHECKPOINT SMTP / MAILPIT: REPROVADO.\n");
    exit(1);
}

printf("\nCHECKPOINT SMTP / MAILPIT: APROVADO.\n");
printf("Mensagem sintética entregue via SMTP real e confirmada pela API local.\n");
printf("Nenhuma credencial SMTP real foi utilizada.\n");
exit(0);
