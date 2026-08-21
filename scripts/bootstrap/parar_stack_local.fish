#!/usr/bin/env fish

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositório ConectaEduca." >&2
    exit 1
end
cd "$ROOT"

set ENV_FILE "$ROOT/deploy/lab/stack-local/.runtime/stack-local.env"
set DB_PROJECT conectaeduca-mariadb-local
set DMZ_PROJECT conectaeduca-dmz-local

if not test -f "$ENV_FILE"
    echo "INFO: runtime do stack não existe; nada a parar."
    exit 0
end

set DB_FILES \
    -f deploy/interna/mariadb/compose.yml \
    -f deploy/interna/mariadb/compose.host.yml \
    -f deploy/lab/stack-local/compose.db-local.yml

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

echo "Parando DMZ sem apagar secrets/runtime..."
docker compose -p "$DMZ_PROJECT" --env-file "$ENV_FILE" $DMZ_FILES down --remove-orphans
or exit 1

echo "Parando MariaDB sem remover volume..."
docker compose -p "$DB_PROJECT" --env-file "$ENV_FILE" $DB_FILES down --remove-orphans
or exit 1

echo
echo "OK: stack parado."
echo "O volume MariaDB foi PRESERVADO."
echo "O OpenBao NÃO foi parado."
echo "Nenhum secret foi apagado."
