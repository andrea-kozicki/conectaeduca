#!/usr/bin/env fish

set -l ROOT (realpath (dirname (status filename))/../..)
set -l SCRIPT "$ROOT/scripts/bootstrap/materializar_bacula_catalog_secret.py"

if not test -f "$SCRIPT"
    echo "ERRO       materializador Python do Catalog ausente" >&2
    exit 1
end

exec python3 "$SCRIPT"
