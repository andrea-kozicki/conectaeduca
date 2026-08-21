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

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositório ConectaEduca." >&2
    exit 1
end
cd "$ROOT"

set ENV_FILE deploy/dmz/.runtime/smtp-google.env
if set -q CONECTAEDUCA_SMTP_ENV_FILE
    set ENV_FILE "$CONECTAEDUCA_SMTP_ENV_FILE"
end

printf '%s\n' '======================================================================'
printf '%s\n' ' CONECTAEDUCA - CHECKPOINT SMTP REAL / CONTAINER DMZ'
printf '%s\n' ' Secret group bridge + DNS + TCP + STARTTLS + CA + auth + envio'
printf '%s\n' '======================================================================'

if not test -f "$ENV_FILE"
    echo "FALHA       runtime SMTP ausente: $ENV_FILE"
    exit 1
end

for line in (string split '\n' -- (cat "$ENV_FILE"))
    set line (string trim -- "$line")
    if test -z "$line"; or string match -q '#*' -- "$line"
        continue
    end
    set pair (string split -m 1 '=' -- "$line")
    if test (count $pair) -ne 2
        echo 'FALHA       linha inválida no runtime SMTP'
        exit 1
    end
    set -gx $pair[1] $pair[2]
end

for key in \
    CONECTAEDUCA_SMTP_HOST \
    CONECTAEDUCA_SMTP_USERNAME \
    CONECTAEDUCA_SMTP_PASSWORD_FILE \
    CONECTAEDUCA_SMTP_FROM_ADDRESS \
    CONECTAEDUCA_SMTP_SECRET_GID \
    SMTP_REAL_CHECKPOINT_TO
    require_env $key; or exit 1
end

if not test -f "$CONECTAEDUCA_SMTP_PASSWORD_FILE"
    echo 'FALHA       arquivo de segredo SMTP não existe no host'
    exit 1
end

set mode (stat -c '%a' "$CONECTAEDUCA_SMTP_PASSWORD_FILE" 2>/dev/null)
set gid (stat -c '%g' "$CONECTAEDUCA_SMTP_PASSWORD_FILE" 2>/dev/null)

if test "$mode" != "640"
    echo "FALHA       segredo SMTP deveria possuir modo 640 para a ponte dedicada; mode=$mode"
    exit 1
end

if test "$gid" != "$CONECTAEDUCA_SMTP_SECRET_GID"
    echo "FALHA       GID do secret diverge do GID runtime; file=$gid runtime=$CONECTAEDUCA_SMTP_SECRET_GID"
    exit 1
end

set group_line (getent group "$CONECTAEDUCA_SMTP_SECRET_GID" 2>/dev/null)
if test -z "$group_line"
    echo 'FALHA       grupo dedicado do secret não existe no host'
    exit 1
end

set members (string split ':' -- "$group_line")[4]
if test -n "$members"
    echo 'FALHA       grupo dedicado do secret possui membros explícitos'
    exit 1
end

echo "OK          secret host: modo 640, grupo dedicado sem membros, other=deny"

set compose_files \
    -f deploy/dmz/compose.yml \
    -f deploy/dmz/compose.smtp.yml

docker compose \
    --env-file "$ENV_FILE" \
    $compose_files \
    config >/tmp/conectaeduca-smtp-real-compose.yml
or begin
    echo 'FALHA       docker compose config reprovou para overlay SMTP'
    exit 1
end

if not grep -q "group_add:" /tmp/conectaeduca-smtp-real-compose.yml
    echo 'FALHA       Compose renderizado não contém group_add para o secret'
    exit 1
end

echo 'OK          overlay compose injeta somente o GID dedicado no PHP'

echo
echo '=== 1. DIAGNÓSTICO DENTRO DO CONTAINER ==='

docker compose \
    --env-file "$ENV_FILE" \
    $compose_files \
    run --rm --no-deps \
    -v "$ROOT/scripts/evidencias/diagnosticar_smtp_container.php:/tmp/diagnosticar_smtp_container.php:ro" \
    php \
    php /tmp/diagnosticar_smtp_container.php

set diag_rc $status
if test $diag_rc -ne 0
    echo 'FALHA       diagnóstico SMTP do container reprovou'
    exit $diag_rc
end

echo
echo '=== 2. ENVIO REAL PELO CONTAINER ==='

set php_code '
require "/var/www/conectaeduca/vendor/autoload.php";
$to = getenv("SMTP_REAL_CHECKPOINT_TO") ?: "";
if (!PHPMailer\\PHPMailer\\PHPMailer::validateAddress($to)) { fwrite(STDERR, "destino inválido\n"); exit(2); }
$id = strtoupper(bin2hex(random_bytes(5)));
$service = new ConectaEduca\\Service\\MailService();
$service->sendHtml(
    $to,
    "Checkpoint ConectaEduca",
    "ConectaEduca - checkpoint SMTP container " . $id,
    "<p>Checkpoint técnico SMTP do container DMZ do ConectaEduca.</p><p>Identificador: <strong>" . htmlspecialchars($id, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8") . "</strong></p>",
    "Checkpoint técnico SMTP do container DMZ do ConectaEduca. Identificador: " . $id
);
echo "OK          servidor SMTP real aceitou a mensagem do container\n";
echo "INFO        identificador=" . $id . "\n";
echo "INFO        confirme a chegada na caixa de destino/spam\n";
'

docker compose \
    --env-file "$ENV_FILE" \
    $compose_files \
    run --rm --no-deps \
    -e SMTP_REAL_CHECKPOINT_TO="$SMTP_REAL_CHECKPOINT_TO" \
    php php -r "$php_code"

set rc $status
if test $rc -ne 0
    echo 'FALHA       transporte SMTP real pelo container reprovou'
    exit $rc
end

echo 'OK          transporte SMTP real pelo container aprovado'
