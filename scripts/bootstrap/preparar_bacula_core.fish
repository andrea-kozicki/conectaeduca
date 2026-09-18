#!/usr/bin/env fish

set -l ROOT /srv/www/htdocs/conectaeduca
set -l RUNTIME "$ROOT/deploy/interna/bacula/.runtime"
set -l ENV_FILE "$RUNTIME/core.env"

function fail
    echo "ERRO       $argv" >&2
    exit 1
end

mkdir -p "$RUNTIME"
or fail "não foi possível criar runtime Bacula"

chmod 700 "$RUNTIME"
or fail "não foi possível proteger runtime Bacula"

if not test -f "$ENV_FILE"
    set -l CONSOLE_PASSWORD \
        (python3 -c 'import secrets; print(secrets.token_hex(32))')
    or fail "não foi possível gerar senha da console"

    set -l SD_PASSWORD \
        (python3 -c 'import secrets; print(secrets.token_hex(32))')
    or fail "não foi possível gerar senha Director/Storage"

    set -l BOOTSTRAP_FD_PASSWORD \
        (python3 -c 'import secrets; print(secrets.token_hex(32))')
    or fail "não foi possível gerar senha do Client placeholder"

    begin
        echo "BACULA_CONSOLE_PASSWORD=$CONSOLE_PASSWORD"
        echo "BACULA_SD_PASSWORD=$SD_PASSWORD"
        echo "BACULA_BOOTSTRAP_FD_PASSWORD=$BOOTSTRAP_FD_PASSWORD"
    end > "$ENV_FILE"
    or fail "não foi possível criar core.env"

    echo "OK         credenciais do núcleo Bacula criadas"
else
    echo "OK         credenciais existentes do núcleo preservadas"

    if not grep -q '^BACULA_BOOTSTRAP_FD_PASSWORD=' "$ENV_FILE"
        set -l BOOTSTRAP_FD_PASSWORD \
            (python3 -c 'import secrets; print(secrets.token_hex(32))')
        or fail "não foi possível gerar senha do Client placeholder"

        echo "BACULA_BOOTSTRAP_FD_PASSWORD=$BOOTSTRAP_FD_PASSWORD" \
            >> "$ENV_FILE"
        or fail "não foi possível acrescentar credencial do placeholder"

        echo "OK         credencial isolada do Client placeholder acrescentada"
    else
        echo "OK         credencial do Client placeholder já existe"
    end
end

chmod 600 "$ENV_FILE"
or fail "não foi possível proteger core.env"

echo "OK         core.env protegido com modo 0600"
