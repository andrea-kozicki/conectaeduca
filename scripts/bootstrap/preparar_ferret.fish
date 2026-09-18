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

set FERRET_DIR deploy/interna/ferret
set RUNTIME "$FERRET_DIR/.runtime"

if test -d "$ROOT/.git"
    if not git -C "$ROOT" check-ignore -q "$RUNTIME/prova-ignore" 2>/dev/null
        echo "ERRO: $RUNTIME ainda não está coberto pelo .gitignore." >&2
        exit 1
    end
else
    set -l metadata "$ROOT/RELEASE-METADATA.txt"
    if not test -f "$metadata"
        echo "ERRO: execução fora de Git exige RELEASE-METADATA.txt do handoff." >&2
        exit 1
    end
    if not grep -Fxq 'runtime_secrets_included=no' "$metadata"
        echo "ERRO: metadata do handoff não comprova exclusão de runtime secrets." >&2
        exit 1
    end
end

mkdir -p \
    "$RUNTIME/state" \
    "$RUNTIME/inbox" \
    "$RUNTIME/reports" \
    "$RUNTIME/reports/raw" \
    "$RUNTIME/events"
or exit 1

chmod 0700 \
    "$RUNTIME" \
    "$RUNTIME/state" \
    "$RUNTIME/inbox" \
    "$RUNTIME/reports" \
    "$RUNTIME/reports/raw" \
    "$RUNTIME/events"
or exit 1

for dir in \
    "$RUNTIME" \
    "$RUNTIME/state" \
    "$RUNTIME/inbox" \
    "$RUNTIME/reports" \
    "$RUNTIME/reports/raw" \
    "$RUNTIME/events"

    set OWNER (stat -c '%u:%g' "$dir" 2>/dev/null)
    if test "$OWNER" != "1000:1000"
        echo "ERRO: $dir pertence a $OWNER; a imagem Ferret usa UID/GID 1000:1000." >&2
        echo "Ajuste a propriedade do runtime antes da subida (ex.: sudo chown -R 1000:1000 '$RUNTIME')." >&2
        exit 1
    end
end

echo "OK: runtime Ferret preparado com modo 0700 e propriedade 1000:1000."