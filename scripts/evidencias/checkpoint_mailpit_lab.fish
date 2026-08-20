#!/usr/bin/env fish

set -g OK_COUNT 0
set -g FAIL_COUNT 0
set -g INFO_COUNT 0

function ok
    set -g OK_COUNT (math $OK_COUNT + 1)
    printf 'OK          %s\n' "$argv"
end

function fail
    set -g FAIL_COUNT (math $FAIL_COUNT + 1)
    printf 'FALHA       %s\n' "$argv"
end

function info
    set -g INFO_COUNT (math $INFO_COUNT + 1)
    printf 'INFO        %s\n' "$argv"
end

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo 'ERRO: execute este checkpoint dentro do repositório ConectaEduca.'
    exit 2
end

cd "$ROOT"

set COMPOSE deploy/lab/mailpit/compose.yml
set CONTAINER conectaeduca-mailpit-lab
set IMAGE 'axllent/mailpit:v1.30.6@sha256:7f33095f80e901f6ad08028f06ca284aa58fe84942be5496008d041d3b9f4d4d'

printf '%s\n' '======================================================================'
printf '%s\n' ' CONECTAEDUCA - CHECKPOINT MAILPIT / SMTP DE LABORATORIO'
printf '%s\n' ' Uso exclusivo de desenvolvimento/teste; não pertence ao deploy final'
printf '%s\n' '======================================================================'

echo
echo '=== 1. ARQUIVOS / COMPOSE ==='

for arquivo in \
    deploy/lab/mailpit/compose.yml \
    deploy/lab/mailpit/IMAGENS-VALIDADAS.md \
    scripts/evidencias/checkpoint_mailpit_smtp.php \
    scripts/evidencias/checkpoint_mailpit_lab.fish

    if test -f "$arquivo"
        ok "arquivo presente: $arquivo"
    else
        fail "arquivo ausente: $arquivo"
    end
end

if docker compose -f "$COMPOSE" config >/dev/null 2>&1
    ok 'Docker Compose sintaticamente válido'
else
    fail 'Docker Compose inválido'
end

if grep -Fq "$IMAGE" "$COMPOSE"
    ok 'imagem Mailpit fixada por versão e digest'
else
    fail 'imagem Mailpit não está fixada pelo digest esperado'
end

if grep -Fq '127.0.0.1:11025:1025' "$COMPOSE"; and grep -Fq '127.0.0.1:18025:8025' "$COMPOSE"
    ok 'SMTP e UI/API declarados somente em loopback'
else
    fail 'bindings de laboratório não estão restritos a loopback'
end

echo
echo '=== 2. CONTAINER / HARDENING ==='

if not docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER"
    fail 'container Mailpit não está em execução'
else
    ok 'container Mailpit está em execução'

    set RUN_IMAGE (docker inspect -f '{{.Config.Image}}' "$CONTAINER" 2>/dev/null)
    if test "$RUN_IMAGE" = "$IMAGE"
        ok 'container usa exatamente a imagem fixada'
    else
        fail "imagem efetiva inesperada: $RUN_IMAGE"
    end

    set RUN_USER (docker inspect -f '{{.Config.User}}' "$CONTAINER" 2>/dev/null)
    if test "$RUN_USER" = '10001:10001'
        ok 'container executa como usuário não-root 10001:10001'
    else
        fail "usuário efetivo inesperado: $RUN_USER"
    end

    set READONLY (docker inspect -f '{{.HostConfig.ReadonlyRootfs}}' "$CONTAINER" 2>/dev/null)
    if test "$READONLY" = 'true'
        ok 'root filesystem somente leitura'
    else
        fail 'root filesystem não está somente leitura'
    end

    set SECURITY (docker inspect -f '{{json .HostConfig.SecurityOpt}}' "$CONTAINER" 2>/dev/null)
    if string match -q '*no-new-privileges:true*' -- "$SECURITY"
        ok 'no-new-privileges aplicado'
    else
        fail 'no-new-privileges não confirmado'
    end

    set CAPS (docker inspect -f '{{json .HostConfig.CapDrop}}' "$CONTAINER" 2>/dev/null)
    if string match -q '*ALL*' -- "$CAPS"
        ok 'Linux capabilities removidas'
    else
        fail 'cap_drop ALL não confirmado'
    end

    set MEMORY (docker inspect -f '{{.HostConfig.Memory}}' "$CONTAINER" 2>/dev/null)
    set SWAP (docker inspect -f '{{.HostConfig.MemorySwap}}' "$CONTAINER" 2>/dev/null)
    if test "$MEMORY" = '268435456'; and test "$SWAP" = '268435456'
        ok 'memória e swap limitados a 256 MiB'
    else
        fail "limites inesperados: Memory=$MEMORY MemorySwap=$SWAP"
    end

    set PIDS (docker inspect -f '{{.HostConfig.PidsLimit}}' "$CONTAINER" 2>/dev/null)
    if test "$PIDS" = '128'
        ok 'limite de PIDs = 128'
    else
        fail "PidsLimit inesperado: $PIDS"
    end

    set TMPFS (docker inspect -f '{{json .HostConfig.Tmpfs}}' "$CONTAINER" 2>/dev/null)
    if string match -q '*/data*' -- "$TMPFS"; and string match -q '*/tmp*' -- "$TMPFS"
        ok '/data e /tmp usam tmpfs efêmero'
    else
        fail 'tmpfs esperado não foi confirmado'
    end

    set SMTP_BIND (docker port "$CONTAINER" 1025/tcp 2>/dev/null)
    set HTTP_BIND (docker port "$CONTAINER" 8025/tcp 2>/dev/null)

    if test "$SMTP_BIND" = '127.0.0.1:11025'
        ok 'SMTP efetivamente publicado somente em 127.0.0.1:11025'
    else
        fail "binding SMTP inesperado: $SMTP_BIND"
    end

    if test "$HTTP_BIND" = '127.0.0.1:18025'
        ok 'UI/API efetivamente publicada somente em 127.0.0.1:18025'
    else
        fail "binding UI/API inesperado: $HTTP_BIND"
    end

    set IMAGE_PLATFORM (docker image inspect -f '{{.Os}}/{{.Architecture}}' "$IMAGE" 2>/dev/null)
    if test "$IMAGE_PLATFORM" = 'linux/amd64'
        ok 'imagem local confirmada para linux/amd64'
    else
        fail "plataforma inesperada: $IMAGE_PLATFORM"
    end
end

echo
echo '=== 3. SMTP REAL / MAILSERVICE ==='

php scripts/evidencias/checkpoint_mailpit_smtp.php
set SMTP_RC $status

if test $SMTP_RC -eq 0
    ok 'checkpoint PHP confirmou entrega SMTP real e captura no Mailpit'
else
    fail 'checkpoint PHP de SMTP/Mailpit reprovou'
end

echo
echo '======================================================================'
echo ' RESULTADO'
echo '======================================================================'
printf 'Aprovacoes:   %d\n' $OK_COUNT
printf 'Falhas:       %d\n' $FAIL_COUNT
printf 'Informacoes:  %d\n' $INFO_COUNT

if test $FAIL_COUNT -gt 0
    echo
    echo 'CHECKPOINT MAILPIT / SMTP LAB: REPROVADO.'
    exit 1
end

echo
echo 'CHECKPOINT MAILPIT / SMTP LAB: APROVADO.'
echo 'MailService validado contra SMTP real de laboratório.'
exit 0
