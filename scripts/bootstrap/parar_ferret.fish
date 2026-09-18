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

cd "$ROOT"

docker compose -f deploy/interna/ferret/compose.yml down