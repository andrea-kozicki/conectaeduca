#!/usr/bin/env fish

set -l ROOT /srv/www/htdocs/conectaeduca
set -l RUNTIME "$ROOT/deploy/interna/bacula/.runtime"
set -l ENV_FILE "$RUNTIME/catalog.env"

function fail
    echo "ERRO       $argv" >&2
    exit 1
end

mkdir -p "$RUNTIME"
or fail "não foi possível criar runtime Bacula"

chmod 700 "$RUNTIME"
or fail "não foi possível proteger runtime Bacula"

if test -f "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    or fail "não foi possível proteger catalog.env"

    echo "OK         credencial existente do Catalog preservada"
    exit 0
end

set -l PASSWORD (python3 -c 'import secrets; print(secrets.token_hex(32))')
or fail "não foi possível gerar credencial aleatória"

begin
    echo 'POSTGRES_DB=bacula'
    echo 'POSTGRES_USER=bacula'
    echo "POSTGRES_PASSWORD=$PASSWORD"
end > "$ENV_FILE"
or fail "não foi possível criar catalog.env"

chmod 600 "$ENV_FILE"
or fail "não foi possível proteger catalog.env"

set PASSWORD ""

echo "OK         credencial do Catalog criada fora do Git"
echo "OK         catalog.env protegido com modo 0600"
