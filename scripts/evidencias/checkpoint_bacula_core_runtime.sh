#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/srv/www/htdocs/conectaeduca"
COMPOSE="$ROOT/deploy/interna/bacula/compose.yml"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HOME/Downloads/conectaeduca-checkpoint-bacula-core-$STAMP.txt"

mkdir -p "$HOME/Downloads"

exec > >(tee "$OUT") 2>&1


section() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}


fail() {
    echo
    echo "FALHA: $*" >&2
    return 1
}


diagnostico_falha() {
    rc=$?

    trap - ERR
    set +e

    section "DIAGNOSTICO AUTOMATICO APOS FALHA"

    docker ps -a \
        --filter name=conectaeduca-bacula \
        --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

    echo
    echo "--- LOG DIRECTOR ---"
    docker logs --tail 100 conectaeduca-bacula-director 2>&1 || true

    echo
    echo "--- LOG STORAGE ---"
    docker logs --tail 100 conectaeduca-bacula-storage 2>&1 || true

    echo
    echo "--- LOG CATALOG ---"
    docker logs --tail 60 conectaeduca-bacula-catalog 2>&1 || true

    echo
    echo "--- GIT ---"
    cd "$ROOT" || true
    git status --short || true
    git diff --check || true

    echo
    echo "CHECKPOINT_RESULTADO=FALHA"
    echo "ARQUIVO_SAIDA=$OUT"

    exit "$rc"
}

trap diagnostico_falha ERR


wait_running() {
    local container="$1"
    local tentativas=30

    for ((i=1; i<=tentativas; i++)); do
        local status
        local restarting

        status="$(
            docker inspect \
                --format '{{.State.Status}}' \
                "$container" \
                2>/dev/null || true
        )"

        restarting="$(
            docker inspect \
                --format '{{.State.Restarting}}' \
                "$container" \
                2>/dev/null || true
        )"

        echo \
            "$container tentativa=$i status=${status:-ausente} restarting=${restarting:-?}"

        if [[ "$status" == "running" && "$restarting" == "false" ]]; then
            sleep 3

            status="$(
                docker inspect \
                    --format '{{.State.Status}}' \
                    "$container" \
                    2>/dev/null || true
            )"

            restarting="$(
                docker inspect \
                    --format '{{.State.Restarting}}' \
                    "$container" \
                    2>/dev/null || true
            )"

            if [[ "$status" == "running" && "$restarting" == "false" ]]; then
                echo "OK: $container permaneceu estável."
                return 0
            fi
        fi

        sleep 2
    done

    fail "$container não permaneceu em execução"
}


assert_no_published_ports() {
    local container="$1"
    local portas

    portas="$(docker port "$container" 2>/dev/null || true)"

    if [[ -n "$portas" ]]; then
        echo "$portas"
        fail "$container possui porta publicada no host"
    fi

    echo "OK: $container não possui porta publicada no host."
}


cd "$ROOT"


section "1. INFORMACOES DO CHECKPOINT"

echo "data=$(date --iso-8601=seconds)"
echo "host=$(hostname)"
echo "repo=$ROOT"
echo "branch=$(git branch --show-current)"
echo "saida=$OUT"


section "2. VALIDACAO PREVIA"

test -s "$COMPOSE"
test -s deploy/interna/bacula/.runtime/config/bacula-dir.conf
test -s deploy/interna/bacula/.runtime/config/bacula-sd.conf
test -s deploy/interna/bacula/.runtime/config/bconsole.conf

docker compose \
    -f "$COMPOSE" \
    --profile tools \
    config >/dev/null

echo "OK: Compose válido."

git diff --check

echo "OK: git diff --check."


section "3. PROTECAO DO RUNTIME"

stat -c '%a %U:%G %n' \
    deploy/interna/bacula/.runtime \
    deploy/interna/bacula/.runtime/core.env \
    deploy/interna/bacula/.runtime/director-db.env \
    deploy/interna/bacula/.runtime/config \
    deploy/interna/bacula/.runtime/config/bacula-dir.conf \
    deploy/interna/bacula/.runtime/config/bacula-sd.conf \
    deploy/interna/bacula/.runtime/config/bconsole.conf

git check-ignore -v \
    deploy/interna/bacula/.runtime/core.env \
    deploy/interna/bacula/.runtime/director-db.env \
    deploy/interna/bacula/.runtime/config/bacula-dir.conf

echo "OK: runtime permanece fora do Git."


section "4. SUBINDO NUCLEO BACULA"

docker compose \
    -f "$COMPOSE" \
    up -d catalog storage director


section "5. ESTABILIDADE DOS CONTAINERS"

wait_running conectaeduca-bacula-catalog
wait_running conectaeduca-bacula-storage
wait_running conectaeduca-bacula-director


section "6. ESTADO DOS CONTAINERS"

docker ps \
    --filter name=conectaeduca-bacula \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

echo
echo "restart_count_catalog=$(
    docker inspect \
        --format '{{.RestartCount}}' \
        conectaeduca-bacula-catalog
)"

echo "restart_count_storage=$(
    docker inspect \
        --format '{{.RestartCount}}' \
        conectaeduca-bacula-storage
)"

echo "restart_count_director=$(
    docker inspect \
        --format '{{.RestartCount}}' \
        conectaeduca-bacula-director
)"


section "7. PRIVILEGIOS DOS DAEMONS"

echo "--- STORAGE PID 1 ---"

docker exec conectaeduca-bacula-storage \
    sh -c '
        grep -E "^(Name|Uid|Gid):" /proc/1/status
    '

echo
echo "--- DIRECTOR PID 1 ---"

docker exec conectaeduca-bacula-director \
    sh -c '
        grep -E "^(Name|Uid|Gid):" /proc/1/status
    '


section "8. VOLUME DE STORAGE"

docker exec conectaeduca-bacula-storage \
    sh -c '
        stat -c "backup_mode=%a backup_uid=%u backup_gid=%g path=%n" /backup
    '

docker inspect \
    conectaeduca-bacula-storage \
    --format \
    '{{range .Mounts}}{{if eq .Destination "/backup"}}volume={{.Name}} type={{.Type}} destino={{.Destination}}{{end}}{{end}}'


section "9. SUPERFICIE DE REDE"

assert_no_published_ports conectaeduca-bacula-catalog
assert_no_published_ports conectaeduca-bacula-storage
assert_no_published_ports conectaeduca-bacula-director

echo
echo "--- DNS visto pelo Director ---"

docker exec conectaeduca-bacula-director \
    getent hosts catalog storage


section "10. CATALOG"

docker exec conectaeduca-bacula-catalog \
    sh -c '
        echo -n "encoding="
        psql \
          -U "$POSTGRES_USER" \
          -d "$POSTGRES_DB" \
          -Atc "
            SELECT pg_encoding_to_char(encoding)
            FROM pg_database
            WHERE datname = '\''bacula'\'';
          "

        echo -n "version_id="
        psql \
          -U "$POSTGRES_USER" \
          -d "$POSTGRES_DB" \
          -Atc "SELECT VersionId FROM Version;"

        echo -n "role_bacula_director="
        psql \
          -U "$POSTGRES_USER" \
          -d "$POSTGRES_DB" \
          -Atc "
            SELECT
              rolname ||
              '\''|superuser='\'' || rolsuper ||
              '\''|createdb='\'' || rolcreatedb ||
              '\''|createrole='\'' || rolcreaterole ||
              '\''|replication='\'' || rolreplication
            FROM pg_roles
            WHERE rolname = '\''bacula_director'\'';
          "
    '


section "11. BCONSOLE -> DIRECTOR -> STORAGE"

printf '%s\n' \
    'status director' \
    'status storage=ConectaEducaStorage' \
    'quit' \
    | timeout 25s docker compose \
        -f "$COMPOSE" \
        --profile tools \
        run --rm -T bconsole

echo
echo "OK: sessão bconsole concluída."


section "12. LOGS RECENTES DO DIRECTOR"

docker logs \
    --tail 80 \
    conectaeduca-bacula-director \
    2>&1


section "13. LOGS RECENTES DO STORAGE"

docker logs \
    --tail 80 \
    conectaeduca-bacula-storage \
    2>&1


section "14. ESTADO FINAL"

docker ps \
    --filter name=conectaeduca-bacula \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

echo
echo "--- GIT ---"

git status --short
git diff --check


section "RESULTADO"

echo "CHECKPOINT_RESULTADO=SUCESSO"
echo "ARQUIVO_SAIDA=$OUT"
