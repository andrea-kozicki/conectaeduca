#!/usr/bin/env fish

function require_env
    set key $argv[1]
    if not set -q $key
        echo "FALHA       variável obrigatória ausente: $key"
        return 1
    end
    if test -z "$$key"
        echo "FALHA       variável obrigatória vazia: $key"
        return 1
    end
    return 0
end

printf '%s\n' '======================================================================'
printf '%s\n' ' CONECTAEDUCA - CHECKPOINT SMTP REAL / CONTAINER DMZ'
printf '%s\n' ' PHPMailer + TLS + secret file + relay autenticado'
printf '%s\n' '======================================================================'

for key in \
    CONECTAEDUCA_SMTP_HOST \
    CONECTAEDUCA_SMTP_USERNAME \
    CONECTAEDUCA_SMTP_PASSWORD_FILE \
    CONECTAEDUCA_SMTP_FROM_ADDRESS \
    SMTP_REAL_CHECKPOINT_TO
    require_env $key; or exit 1
end

if not test -f "$CONECTAEDUCA_SMTP_PASSWORD_FILE"
    echo 'FALHA       arquivo de segredo SMTP não existe'
    exit 1
end

set mode (stat -c '%a' "$CONECTAEDUCA_SMTP_PASSWORD_FILE" 2>/dev/null)
if test -z "$mode"
    echo 'FALHA       não foi possível ler permissões do arquivo de segredo'
    exit 1
end

set group_digit (string sub -s -2 -l 1 "$mode")
set other_digit (string sub -s -1 -l 1 "$mode")
if test "$group_digit" -gt 0; or test "$other_digit" -gt 0
    echo "FALHA       segredo SMTP permissivo demais: mode=$mode"
    echo 'INFO        esperado 600, 400 ou equivalente sem leitura para grupo/outros'
    exit 1
end

echo "OK          arquivo de segredo SMTP possui modo restritivo: $mode"

set encryption tls
if set -q CONECTAEDUCA_SMTP_ENCRYPTION
    set encryption (string lower "$CONECTAEDUCA_SMTP_ENCRYPTION")
end

if not contains -- $encryption tls starttls ssl smtps
    echo 'FALHA       SMTP real exige tls/starttls/ssl/smtps'
    exit 1
end

echo "OK          criptografia SMTP configurada: $encryption"

set compose_files \
    -f deploy/dmz/compose.yml \
    -f deploy/dmz/compose.smtp.yml

docker compose $compose_files config >/tmp/conectaeduca-smtp-real-compose.yml
if test $status -ne 0
    echo 'FALHA       docker compose config reprovou para overlay SMTP'
    exit 1
end

echo 'OK          overlay compose SMTP é válido'

set php_code '
require "/var/www/conectaeduca/vendor/autoload.php";
$to = getenv("SMTP_REAL_CHECKPOINT_TO") ?: "";
if (!PHPMailer\\PHPMailer\\PHPMailer::validateAddress($to)) { fwrite(STDERR, "destino inválido\n"); exit(2); }
$id = strtoupper(bin2hex(random_bytes(5)));
$service = new ConectaEduca\\Service\\MailService();
$service->sendHtml(
    $to,
    "Checkpoint ConectaEduca",
    "ConectaEduca - checkpoint SMTP real " . $id,
    "<p>Checkpoint técnico SMTP do ConectaEduca.</p><p>Identificador: <strong>" . htmlspecialchars($id, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8") . "</strong></p>",
    "Checkpoint técnico SMTP do ConectaEduca. Identificador: " . $id
);
echo "OK          servidor SMTP real aceitou a mensagem\n";
echo "INFO        identificador=" . $id . "\n";
echo "INFO        confirme a chegada na caixa de destino/spam\n";
'

docker compose $compose_files run --rm --no-deps \
    -e SMTP_REAL_CHECKPOINT_TO="$SMTP_REAL_CHECKPOINT_TO" \
    php php -r "$php_code"
set rc $status

if test $rc -ne 0
    echo 'FALHA       transporte SMTP real pelo container reprovou'
    exit $rc
end

echo 'OK          transporte SMTP real pelo container aprovado'
