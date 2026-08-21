#!/usr/bin/env fish

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositório ConectaEduca." >&2
    exit 1
end
cd "$ROOT"

set ENV_FILE deploy/dmz/.runtime/smtp-google.env

echo
echo "======================================================================"
echo " CONECTAEDUCA - CHECKPOINT SMTP GOOGLE + OPENBAO"
echo " Host + container PHP + TLS + secret materializado em RAM"
echo "======================================================================"

if not test -f "$ENV_FILE"
    echo "FALHA       runtime SMTP ausente: $ENV_FILE"
    echo "INFO        execute primeiro scripts/bootstrap/operacionalizar_openbao_smtp.fish"
    exit 1
end

set ENV_MODE (stat -c '%a' "$ENV_FILE" 2>/dev/null)
if test "$ENV_MODE" != "600"
    echo "FALHA       runtime SMTP deveria possuir modo 600; encontrado=$ENV_MODE"
    exit 1
end
echo "OK          runtime SMTP possui modo 600"

while read -l line
    set line (string trim -- "$line")
    if test -z "$line"
        continue
    end
    if string match -q '#*' -- "$line"
        continue
    end

    set pair (string split -m 1 '=' -- "$line")
    if test (count $pair) -ne 2
        echo "FALHA       linha inválida no runtime SMTP"
        exit 1
    end

    set -gx $pair[1] $pair[2]
end < "$ENV_FILE"

for key in \
    CONECTAEDUCA_SMTP_HOST \
    CONECTAEDUCA_SMTP_PORT \
    CONECTAEDUCA_SMTP_USERNAME \
    CONECTAEDUCA_SMTP_PASSWORD_FILE \
    CONECTAEDUCA_SMTP_ENCRYPTION \
    CONECTAEDUCA_SMTP_FROM_ADDRESS \
    SMTP_REAL_CHECKPOINT_TO

    if not set -q $key
        echo "FALHA       variável runtime ausente: $key"
        exit 1
    end
end

if test "$CONECTAEDUCA_SMTP_HOST" != "smtp.gmail.com"
    echo "FALHA       host esperado para este checkpoint é smtp.gmail.com"
    exit 1
end

if test "$CONECTAEDUCA_SMTP_PORT" != "587"
    echo "FALHA       porta esperada para STARTTLS é 587"
    exit 1
end

if not contains -- (string lower "$CONECTAEDUCA_SMTP_ENCRYPTION") tls starttls
    echo "FALHA       Gmail deve usar STARTTLS neste checkpoint"
    exit 1
end

if not test -f "$CONECTAEDUCA_SMTP_PASSWORD_FILE"
    echo "FALHA       segredo SMTP materializado não existe"
    exit 1
end

set SECRET_MODE (stat -c '%a' "$CONECTAEDUCA_SMTP_PASSWORD_FILE" 2>/dev/null)
if test "$SECRET_MODE" != "600"
    echo "FALHA       segredo SMTP materializado deveria possuir modo 600; encontrado=$SECRET_MODE"
    exit 1
end

if not string match -q '/dev/shm/*' -- "$CONECTAEDUCA_SMTP_PASSWORD_FILE"
    echo "FALHA       segredo SMTP não está materializado em memória (/dev/shm)"
    exit 1
end

echo "OK          configuração Gmail usa smtp.gmail.com:587 + STARTTLS"
echo "OK          segredo materializado em /dev/shm com modo 600"

# Defesa contra configuração legada: produção usa exclusivamente arquivo de segredo.
# Remove eventual variável herdada do shell; .env é verificado sem exibir o valor.
set -e MAIL_PASSWORD
if test -f .env
    if grep -Eq '^[[:space:]]*MAIL_PASSWORD[[:space:]]*=' .env
        echo "FALHA       .env ainda contém MAIL_PASSWORD direto"
        echo "INFO        remova a chave legada; SMTP real usa somente MAIL_PASSWORD_FILE"
        exit 1
    end
end
echo "OK          nenhuma credencial SMTP direta/legada será usada"

# Mapeia o contrato do overlay para o contrato direto do MailService.
set -gx MAIL_HOST "$CONECTAEDUCA_SMTP_HOST"
set -gx MAIL_PORT "$CONECTAEDUCA_SMTP_PORT"
set -gx MAIL_SMTP_AUTH true
set -gx MAIL_USERNAME "$CONECTAEDUCA_SMTP_USERNAME"
set -gx MAIL_PASSWORD_FILE "$CONECTAEDUCA_SMTP_PASSWORD_FILE"
set -gx MAIL_ENCRYPTION "$CONECTAEDUCA_SMTP_ENCRYPTION"
set -gx MAIL_TIMEOUT 15
set -gx MAIL_FROM_ADDRESS "$CONECTAEDUCA_SMTP_FROM_ADDRESS"
set -gx MAIL_FROM_NAME ConectaEduca
set -gx APP_ENV production

echo
echo "=== 1. SMTP REAL PELO HOST ==="
php scripts/evidencias/checkpoint_smtp_real.php
or begin
    echo "FALHA       SMTP real pelo host reprovou"
    exit 1
end

echo
echo "=== 2. REBUILD DO PHP DMZ ==="
docker compose \
    -f deploy/dmz/compose.yml \
    -f deploy/dmz/compose.smtp.yml \
    build php
or begin
    echo "FALHA       imagem PHP DMZ não reconstruiu"
    exit 1
end

echo
echo "=== 3. SMTP REAL PELO CONTAINER PHP ==="
fish scripts/evidencias/checkpoint_smtp_real_container.fish
or begin
    echo "FALHA       SMTP real pelo container reprovou"
    exit 1
end

echo
echo "======================================================================"
echo " RESULTADO"
echo "======================================================================"
echo "OK          SMTP Google aceitou mensagem pelo host"
echo "OK          SMTP Google aceitou mensagem pelo container PHP DMZ"
echo "INFO        confirme visualmente a chegada do(s) identificador(es) na caixa real/spam"
echo "CHECKPOINT SMTP GOOGLE + OPENBAO: APROVADO NO TRANSPORTE."
