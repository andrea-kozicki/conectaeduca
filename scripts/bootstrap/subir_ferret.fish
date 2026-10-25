#!/usr/bin/env fish

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositório ConectaEduca." >&2
    exit 1
end

cd "$ROOT"

set COMPOSE deploy/interna/ferret/compose.yml
# Explicitly opt in to the tested PA-07 image, otherwise preserve upstream.
set COMPOSE_ARGS -f "$COMPOSE"
if set -q FERRET_COMPOSE_OVERRIDE; and test -n "$FERRET_COMPOSE_OVERRIDE"
    if not test -f "$FERRET_COMPOSE_OVERRIDE"
        echo "ERRO: override Ferret inexistente: $FERRET_COMPOSE_OVERRIDE" >&2
        exit 1
    end
    set -a COMPOSE_ARGS -f "$FERRET_COMPOSE_OVERRIDE"
end
if set -q FERRET_WEB_PORT
    set PORT "$FERRET_WEB_PORT"
else
    set PORT 18082
end

fish scripts/bootstrap/preparar_ferret.fish
or exit 1

docker compose $COMPOSE_ARGS config >/dev/null
or exit 1

set IMAGE (docker compose $COMPOSE_ARGS config --images | head -n 1)

if test -z "$IMAGE"
    echo "ERRO: não foi possível resolver a imagem do Ferret." >&2
    exit 1
end

if docker image inspect "$IMAGE" >/dev/null 2>&1
    echo "OK: imagem Ferret já disponível localmente; pull dispensado."
else
    echo "INFO: imagem Ferret ausente; realizando pull da referência fixada."
    docker compose $COMPOSE_ARGS pull ferret
    or exit 1
end

docker compose $COMPOSE_ARGS up -d ferret
or exit 1

for tentativa in (seq 1 20)
    if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/" >/dev/null 2>&1
        echo "OK: Ferret Web respondeu em http://127.0.0.1:$PORT/"
        docker compose $COMPOSE_ARGS ps
        exit 0
    end

    sleep 1
end

echo "ERRO: Ferret iniciou, mas a interface web não respondeu no prazo." >&2
docker compose $COMPOSE_ARGS ps >&2
docker compose $COMPOSE_ARGS logs --tail=80 ferret >&2
exit 1
