#!/usr/bin/env fish

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositório ConectaEduca." >&2
    exit 1
end

cd "$ROOT"

set FERRET_DIR deploy/interna/ferret
set RUNTIME "$FERRET_DIR/.runtime"

if not git check-ignore -q "$RUNTIME/prova-ignore" 2>/dev/null
    echo "ERRO: $RUNTIME ainda não está coberto pelo .gitignore." >&2
    echo "Adicione esta linha ao .gitignore antes de continuar:" >&2
    echo "$RUNTIME/" >&2
    exit 1
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
