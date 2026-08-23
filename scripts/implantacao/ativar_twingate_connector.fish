#!/usr/bin/env fish

set -l SCRIPT_FILE (status --current-filename)
set -l SCRIPT_DIR (cd (dirname "$SCRIPT_FILE"); and pwd -P)
or begin
    echo "ERRO: não foi possível resolver o diretório do script." >&2
    exit 1
end

set -l ROOT (realpath "$SCRIPT_DIR/../..")
set -l COMPOSE "$ROOT/deploy/interna/twingate/compose.yml"
set -l RUNTIME /dev/shm/conectaeduca-twingate.env
set -l CONTAINER conectaeduca-twingate-connector

if not test -f "$COMPOSE"
    echo "ERRO: compose Twingate ausente em $COMPOSE." >&2
    exit 1
end

if not test -f "$RUNTIME"
    echo "ERRO: runtime efêmero ausente; execute preparar_twingate_runtime.fish." >&2
    exit 1
end

set -l MODE (stat -c '%a' "$RUNTIME")
if test "$MODE" != "600"
    echo "ERRO: runtime com modo $MODE; esperado 600." >&2
    exit 1
end

for key in TWINGATE_NETWORK TWINGATE_ACCESS_TOKEN TWINGATE_REFRESH_TOKEN
    if not grep -Eq "^$key=.+" "$RUNTIME"
        echo "ERRO: runtime sem $key." >&2
        exit 1
    end
end

cd "$ROOT"
or begin
    echo "ERRO: não foi possível acessar a raiz do projeto: $ROOT" >&2
    exit 1
end

echo "Ativando Twingate Connector com credenciais efêmeras."
echo "raiz_projeto=$ROOT"
echo "Nenhum token será exibido."

docker compose \
    --env-file "$RUNTIME" \
    -f "$COMPOSE" \
    --profile twingate \
    up -d connector
or begin
    echo "ERRO: docker compose não conseguiu iniciar o Connector." >&2
    exit 1
end

for i in (seq 1 30)
    set -l container_status (docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null)
    set -l restarting (docker inspect -f '{{.State.Restarting}}' "$CONTAINER" 2>/dev/null)

    echo "tentativa=$i status="(string escape -- "$container_status")" restarting="(string escape -- "$restarting")

    if test "$container_status" = "running"; and test "$restarting" = "false"
        echo "OK: Connector em execução."
        echo "AVISO: confirme status Online no Admin Console antes de criar Resources."
        exit 0
    end

    sleep 2
end

echo "ERRO: Connector não permaneceu em execução." >&2
exit 1
