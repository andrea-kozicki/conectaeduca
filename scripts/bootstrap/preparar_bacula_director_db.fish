#!/usr/bin/env fish

function resolve_root
    if set -q PROJECT_ROOT
        set -l candidate (realpath "$PROJECT_ROOT" 2>/dev/null)
        if test -n "$candidate"; and test -d "$candidate/deploy"
            echo "$candidate"
            return 0
        end
        return 1
    end

    set -l script_file (status --current-filename)
    set -l candidate (realpath (dirname "$script_file")/../.. 2>/dev/null)
    if test -n "$candidate"; and test -d "$candidate/deploy"
        echo "$candidate"
        return 0
    end
    return 1
end

set ROOT (resolve_root)
or begin
    echo "ERRO: raiz ConectaEduca não localizada; defina PROJECT_ROOT." >&2
    exit 1
end

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

set -l PASSWORD ""

if test -f "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    or fail "não foi possível proteger director-db.env"

    set PASSWORD (string replace -r '^BACULA_DB_PASSWORD=' '' -- (grep -E '^BACULA_DB_PASSWORD=' "$ENV_FILE" | tail -n 1))
    if test -z "$PASSWORD"
        fail "director-db.env existente não contém BACULA_DB_PASSWORD"
    end
    echo "OK         credencial existente do Director preservada"
else
    set PASSWORD (python3 -c 'import secrets; print(secrets.token_hex(32))')
    or fail "não foi possível gerar credencial aleatória"
end

set -l TMP "$ENV_FILE.tmp."(random)
begin
    echo 'BACULA_DB_HOST=/run/pgbouncer'
    echo 'BACULA_DB_PORT=6432'
    echo 'BACULA_DB_NAME=bacula'
    echo 'BACULA_DB_USER=bacula_director'
    echo "BACULA_DB_PASSWORD=$PASSWORD"
end > "$TMP"
or fail "não foi possível materializar director-db.env"

chmod 600 "$TMP"
or fail "não foi possível proteger temporário director-db.env"
mv -f "$TMP" "$ENV_FILE"
or fail "não foi possível promover director-db.env"

chmod 600 "$ENV_FILE"
or fail "não foi possível proteger director-db.env"

set PASSWORD ""

echo "OK         identidade operacional do Director criada fora do Git"
echo "OK         director-db.env protegido com modo 0600"