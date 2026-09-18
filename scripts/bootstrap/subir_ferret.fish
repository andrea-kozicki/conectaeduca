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

set COMPOSE deploy/interna/ferret/compose.yml
if set -q FERRET_WEB_PORT
    set PORT "$FERRET_WEB_PORT"
else
    set PORT 18082
end

fish scripts/bootstrap/preparar_ferret.fish
or exit 1

docker compose -f "$COMPOSE" config >/dev/null
or exit 1

set IMAGE (docker compose -f "$COMPOSE" config --images | head -n 1)

if test -z "$IMAGE"
    echo "ERRO: não foi possível resolver a imagem do Ferret." >&2
    exit 1
end

if docker image inspect "$IMAGE" >/dev/null 2>&1
    echo "OK: imagem Ferret já disponível localmente; pull dispensado."
else
    echo "INFO: imagem Ferret ausente; realizando pull da referência fixada."
    docker compose -f "$COMPOSE" pull ferret
    or exit 1
end

docker compose -f "$COMPOSE" up -d ferret
or exit 1

for tentativa in (seq 1 20)
    if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/" >/dev/null 2>&1
        echo "OK: Ferret Web respondeu em http://127.0.0.1:$PORT/"
        docker compose -f "$COMPOSE" ps
        exit 0
    end

    sleep 1
end

echo "ERRO: Ferret iniciou, mas a interface web não respondeu no prazo." >&2
docker compose -f "$COMPOSE" ps >&2
docker compose -f "$COMPOSE" logs --tail=80 ferret >&2
exit 1