#!/usr/bin/env fish

set -l ROOT /srv/www/htdocs/conectaeduca
set -l RUNTIME "$ROOT/deploy/interna/bacula/.runtime"
set -l ENV_FILE "$RUNTIME/director-db.env"

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
    or fail "não foi possível proteger director-db.env"

    echo "OK         credencial existente do Director preservada"
    exit 0
end

set -l PASSWORD (python3 -c 'import secrets; print(secrets.token_hex(32))')
or fail "não foi possível gerar credencial aleatória"

begin
    echo 'BACULA_DB_HOST=catalog'
    echo 'BACULA_DB_PORT=5432'
    echo 'BACULA_DB_NAME=bacula'
    echo 'BACULA_DB_USER=bacula_director'
    echo "BACULA_DB_PASSWORD=$PASSWORD"
end > "$ENV_FILE"
or fail "não foi possível criar director-db.env"

chmod 600 "$ENV_FILE"
or fail "não foi possível proteger director-db.env"

set PASSWORD ""

echo "OK         identidade operacional do Director criada fora do Git"
echo "OK         director-db.env protegido com modo 0600"
