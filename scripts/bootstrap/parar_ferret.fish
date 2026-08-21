#!/usr/bin/env fish

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositório ConectaEduca." >&2
    exit 1
end

cd "$ROOT"

docker compose -f deploy/interna/ferret/compose.yml down
