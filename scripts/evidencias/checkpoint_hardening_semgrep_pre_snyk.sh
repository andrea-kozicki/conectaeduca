#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/srv/www/htdocs/conectaeduca"
COMPOSE="$ROOT/deploy/interna/bacula/compose.yml"
DOCKERFILE="$ROOT/deploy/interna/bacula/images/Dockerfile"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HOME/Downloads/conectaeduca-checkpoint-hardening-semgrep-$STAMP.txt"
DIAG_LOCK="/tmp/conectaeduca-hardening-semgrep-$STAMP.lock"

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


wait_running() {
    local container="$1"

    for i in $(seq 1 30); do
        local status restarting

        status="$(
            docker inspect \
                --format '{{.State.Status}}' \
                "$container" \
                2>/dev/null \
                || true
        )"

        restarting="$(
            docker inspect \
                --format '{{.State.Restarting}}' \
                "$container" \
                2>/dev/null \
                || true
        )"

        echo \
            "$container tentativa=$i status=${status:-ausente} restarting=${restarting:-?}"

        if [[ "$status" == "running" && "$restarting" == "false" ]]; then
            sleep 2

            status="$(
                docker inspect \
                    --format '{{.State.Status}}' \
                    "$container"
            )"

            restarting="$(
                docker inspect \
                    --format '{{.State.Restarting}}' \
                    "$container"
            )"

            if [[ "$status" == "running" && "$restarting" == "false" ]]; then
                echo "OK: $container está estável."
                return 0
            fi
        fi

        sleep 2
    done

    fail "$container não permaneceu em execução"
}


diagnostico_falha() {
    rc=$?

    trap - ERR

    if ! mkdir "$DIAG_LOCK" 2>/dev/null; then
        exit "$rc"
    fi

    set +e

    section "DIAGNOSTICO AUTOMATICO APOS FALHA"

    docker ps -a \
        --filter name=conectaeduca-bacula \
        --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' \
        || true

    echo
    echo "--- DIRECTOR ---"
    docker logs \
        --tail 80 \
        conectaeduca-bacula-director \
        2>&1 \
        || true

    echo
    echo "--- STORAGE ---"
    docker logs \
        --tail 80 \
        conectaeduca-bacula-storage \
        2>&1 \
        || true

    echo
    echo "--- FILE DAEMON ---"
    docker logs \
        --tail 80 \
        conectaeduca-bacula-filedaemon-lab \
        2>&1 \
        || true

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

cd "$ROOT"


section "1. INFORMACOES"

echo "data=$(date --iso-8601=seconds)"
echo "host=$(hostname)"
echo "branch=$(git branch --show-current)"
echo "head=$(git rev-parse HEAD)"
echo "saida=$OUT"


section "2. VALIDACAO DE SINTAXE"

python3 -m py_compile \
    scripts/bootstrap/materializar_openbao_smtp_runtime.py \
    scripts/bootstrap/retomar_lab_pos_reboot.py \
    scripts/recuperacao/recuperar_approle_smtp_pos_reboot.py

bash -n \
    scripts/evidencias/checkpoint_hardening_semgrep_pre_snyk.sh

docker compose \
    -f "$COMPOSE" \
    --profile tools \
    config \
    >/dev/null

git diff --check

echo "OK: Python, Bash, Compose e diff válidos."


section "3. URLLIB DINAMICO REMOVIDO"

for file in \
    scripts/bootstrap/materializar_openbao_smtp_runtime.py \
    scripts/bootstrap/retomar_lab_pos_reboot.py \
    scripts/recuperacao/recuperar_approle_smtp_pos_reboot.py
do

    if grep -Eq \
        '(^|[[:space:]])import urllib|urllib\.request|urllib\.error|urlopen\(' \
        "$file"
    then
        fail "urllib inseguro ainda encontrado em $file"
    fi

    grep -q \
        'http\.client' \
        "$file" \
        || fail \
            "http.client não encontrado em $file"

    echo "OK http_client=$file"

done

echo "OK: uso dinâmico de urllib removido dos três clientes."


section "4. OPENBAO RESTRITO AO LOOPBACK"

grep -q \
    'BAO_HOST = "127.0.0.1"' \
    scripts/bootstrap/materializar_openbao_smtp_runtime.py \
    || fail \
        "materializador SMTP não fixa BAO_HOST em loopback"

grep -q \
    'BAO_PORT = 18200' \
    scripts/bootstrap/materializar_openbao_smtp_runtime.py \
    || fail \
        "materializador SMTP não fixa BAO_PORT"

grep -q \
    'RAW_BAO_ADDR != "http://127.0.0.1:18200"' \
    scripts/bootstrap/materializar_openbao_smtp_runtime.py \
    || fail \
        "override de OpenBao não está restrito"

grep -q \
    'OPENBAO_HOST = "127.0.0.1"' \
    scripts/bootstrap/retomar_lab_pos_reboot.py \
    || fail \
        "retomada pós-reboot não fixa loopback"

grep -q \
    'OPENBAO_PORT = 18200' \
    scripts/bootstrap/retomar_lab_pos_reboot.py \
    || fail \
        "retomada pós-reboot não fixa porta"

grep -q \
    'BAO_HOST = "127.0.0.1"' \
    scripts/recuperacao/recuperar_approle_smtp_pos_reboot.py \
    || fail \
        "recuperação AppRole não fixa loopback"

grep -q \
    'BAO_PORT = 18200' \
    scripts/recuperacao/recuperar_approle_smtp_pos_reboot.py \
    || fail \
        "recuperação AppRole não fixa porta"

echo "OK: clientes OpenBao LAB presos a 127.0.0.1:18200."


section "5. PERMISSOES 0700 MANTIDAS E DOCUMENTADAS"

grep -Fq \
    'os.chmod(CUSTODIA_DIR, 0o700)' \
    scripts/bootstrap/retomar_lab_pos_reboot.py \
    || fail \
        "custódia não mantém 0700"

grep -Fq \
    'nosemgrep: python.lang.security.audit.insecure-file-permissions.insecure-file-permissions' \
    scripts/bootstrap/retomar_lab_pos_reboot.py \
    || fail \
        "exceção Semgrep da custódia não está documentada no código"

grep -Fq \
    'os.chmod(WORKLOAD, 0o700)' \
    scripts/recuperacao/recuperar_approle_smtp_pos_reboot.py \
    || fail \
        "workload AppRole não mantém 0700"

grep -Fq \
    'nosemgrep: python.lang.security.audit.insecure-file-permissions.insecure-file-permissions' \
    scripts/recuperacao/recuperar_approle_smtp_pos_reboot.py \
    || fail \
        "exceção Semgrep do AppRole não está documentada no código"

test -s \
    docs/seguranca/semgrep-excecoes.md \
    || fail \
        "documentação das exceções ausente"

echo "OK: 0700 mantido e exceções justificadas."


section "6. DOCKERFILE DECLARA USER NAO-ROOT"

USER_COUNT="$(
    grep -Ec \
        '^USER[[:space:]]+bacula:bacula[[:space:]]*$' \
        "$DOCKERFILE"
)"

echo "dockerfile_user_bacula_count=$USER_COUNT"

[[ "$USER_COUNT" -eq 3 ]] \
    || fail \
        "esperadas exatamente 3 declarações USER bacula:bacula"

echo "OK: três targets Bacula têm usuário default não-root."


section "7. REBUILD DAS IMAGENS"

for target in director storage filedaemon
do
    case "$target" in
        director)
            image="conectaeduca/bacula-director:15.0.3"
            ;;
        storage)
            image="conectaeduca/bacula-storage:15.0.3"
            ;;
        filedaemon)
            image="conectaeduca/bacula-filedaemon:15.0.3"
            ;;
    esac

    echo "--- target=$target image=$image ---"

    docker build \
        --platform linux/amd64 \
        --target "$target" \
        -t "$image" \
        -f "$DOCKERFILE" \
        "$ROOT"

done


section "8. DEFAULT USER DAS IMAGENS"

for image in \
    conectaeduca/bacula-director:15.0.3 \
    conectaeduca/bacula-storage:15.0.3 \
    conectaeduca/bacula-filedaemon:15.0.3
do

    user="$(
        docker image inspect \
            --format '{{.Config.User}}' \
            "$image"
    )"

    echo "$image|default_user=$user"

    [[ "$user" == "bacula:bacula" ]] \
        || fail \
            "$image não possui usuário default bacula:bacula"

done

echo "OK: imagens isoladas são non-root por padrão."


section "9. RUNTIME BACULA COM BOOTSTRAP EXPLICITO"

fish \
    scripts/bootstrap/preparar_bacula_core.fish

python3 \
    scripts/bootstrap/materializar_bacula_core.py

python3 \
    scripts/bootstrap/materializar_bacula_workloads_lab.py

docker compose \
    -f "$COMPOSE" \
    up -d \
    --force-recreate \
    storage \
    filedaemon-lab \
    director

wait_running \
    conectaeduca-bacula-catalog

wait_running \
    conectaeduca-bacula-storage

wait_running \
    conectaeduca-bacula-filedaemon-lab

wait_running \
    conectaeduca-bacula-director


section "10. IDENTIDADE EFETIVA DOS DAEMONS"

for spec in \
    'conectaeduca-bacula-director|bacula-dir' \
    'conectaeduca-bacula-storage|bacula-sd' \
    'conectaeduca-bacula-filedaemon-lab|bacula-fd'
do

    container="${spec%%|*}"
    expected="${spec#*|}"

    proc="$(
        docker exec \
            "$container" \
            sh -ec \
            'tr "\0" " " < /proc/1/cmdline'
    )"

    uid="$(
        docker exec \
            "$container" \
            sh -ec \
            'awk "/^Uid:/{print \$2}" /proc/1/status'
    )"

    gid="$(
        docker exec \
            "$container" \
            sh -ec \
            'awk "/^Gid:/{print \$2}" /proc/1/status'
    )"

    echo "$container|pid1=$proc|uid=$uid|gid=$gid"

    grep -Fq \
        "$expected" \
        <<<"$proc" \
        || fail \
            "$container PID1 inesperado"

    [[ "$uid" == "100" ]] \
        || fail \
            "$container PID1 não está em UID 100"

    [[ "$gid" == "101" ]] \
        || fail \
            "$container PID1 não está em GID 101"

done

echo "OK: daemons efetivos operam como bacula 100:101."


section "11. SEM PORTAS PUBLICADAS"

for container in \
    conectaeduca-bacula-catalog \
    conectaeduca-bacula-storage \
    conectaeduca-bacula-director \
    conectaeduca-bacula-filedaemon-lab
do

    published="$(
        docker port \
            "$container" \
            2>/dev/null \
            || true
    )"

    [[ -z "$published" ]] \
        || fail \
            "$container possui porta publicada no host"

    echo "OK no_host_ports=$container"

done


section "12. BCONSOLE POS-HARDENING"

BCONSOLE_OUT="$(
    printf '%s\n' \
        'status director' \
        'status client=conectaeduca-lab-fd' \
        'status storage=ConectaEducaStorage' \
        'quit' \
        | timeout 90s \
            docker compose \
                -f "$COMPOSE" \
                --profile tools \
                run --rm -T bconsole \
        2>&1
)"

echo "$BCONSOLE_OUT"

grep -Fq \
    'conectaeduca-dir Version:' \
    <<<"$BCONSOLE_OUT" \
    || fail \
        "bconsole não alcançou Director"

grep -Fq \
    'conectaeduca-lab-fd Version:' \
    <<<"$BCONSOLE_OUT" \
    || fail \
        "Director não alcançou File Daemon"

grep -Fq \
    'conectaeduca-sd Version:' \
    <<<"$BCONSOLE_OUT" \
    || fail \
        "Director não alcançou Storage"

echo "OK: bconsole/Director/FD/Storage operacionais."


section "13. GIT E RUNTIME"

git diff --check

echo "--- status ---"
git status --short

echo
echo "--- arquivos alterados desta fornada ---"

git status --short \
    | grep -E \
      'bacula/(compose.yml|images/Dockerfile)|materializar_openbao_smtp_runtime|retomar_lab_pos_reboot|recuperar_approle_smtp_pos_reboot|semgrep-excecoes|checkpoint_hardening_semgrep|checkpoint_bacula_openbao_raft' \
    || true


section "RESULTADO"

echo "BACULA_IMAGE_DEFAULT_NONROOT=SIM"
echo "BACULA_DAEMONS_UID_100_GID_101=SIM"
echo "OPENBAO_URLLIB_DINAMICO=REMOVIDO"
echo "OPENBAO_HTTP_LAB_LOOPBACK=VALIDADO"
echo "PERMISSAO_0700=JUSTIFICADA_E_MANTIDA"
echo "CHECKPOINT_RESULTADO=SUCESSO"
echo "ARQUIVO_SAIDA=$OUT"
