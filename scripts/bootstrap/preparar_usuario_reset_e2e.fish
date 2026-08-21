#!/usr/bin/env fish

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositório ConectaEduca." >&2
    exit 1
end
cd "$ROOT"

set ENV_FILE "$ROOT/deploy/lab/stack-local/.runtime/stack-local.env"
set DMZ_PROJECT conectaeduca-dmz-local

if not test -f "$ENV_FILE"
    echo "FALHA: stack ainda não possui runtime."
    echo "Execute primeiro: fish scripts/bootstrap/subir_stack_local.fish"
    exit 1
end

set DMZ_FILES \
    -f deploy/dmz/compose.yml \
    -f deploy/dmz/compose.database.yml \
    -f deploy/dmz/compose.app-secrets.yml \
    -f deploy/dmz/compose.waf.yml \
    -f deploy/dmz/compose.waf-tls.yml \
    -f deploy/dmz/compose.waf-policy.yml \
    -f deploy/dmz/compose.host.yml \
    -f deploy/dmz/compose.smtp.yml \
    -f deploy/lab/stack-local/compose.dmz-local.yml

read -P "E-mail da conta de teste para recuperação: " RESET_EMAIL

if test -z "$RESET_EMAIL"
    echo "FALHA: e-mail vazio."
    exit 1
end

echo
echo "Preparando conta ativa no MariaDB conteinerizado..."
echo "A senha inicial será aleatória e não será exibida."

docker compose \
    -p "$DMZ_PROJECT" \
    --env-file "$ENV_FILE" \
    $DMZ_FILES \
    run --rm --no-deps \
    -e RESET_E2E_EMAIL="$RESET_EMAIL" \
    -v "$ROOT/scripts/bootstrap/preparar_usuario_reset_e2e.php:/tmp/preparar_usuario_reset_e2e.php:ro" \
    php \
    php /tmp/preparar_usuario_reset_e2e.php

set RC $status
if test $RC -ne 0
    exit $RC
end

echo
echo "Conta pronta."
echo "Abra:"
echo "  https://conectaeduca.local:18444/login.php"
echo
echo "Clique em 'Esqueceu sua senha?' e use:"
echo "  $RESET_EMAIL"
