#!/usr/bin/env fish

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositório ConectaEduca." >&2
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
