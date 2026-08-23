#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
export LANG=C

PROFILE="local"
START_IF_NEEDED=1
ALLOW_WILDCARD=0
TIMEOUT=180
ROOT="${PROJECT_ROOT:-}"

usage() {
    cat <<'EOF'
Uso:
  validar_wazuh_operacional.sh [opções]

Opções:
  --perfil local|vm          local exige loopback; vm aceita IP específico
  --somente-validar          não executa docker compose up
  --subir-se-necessario      permite compose up -d (padrão)
  --permitir-wildcard        permite 0.0.0.0/:: nas portas publicadas
  --timeout SEGUNDOS         tempo máximo de espera (padrão: 180)
  --ajuda

O script nunca executa docker compose down e nunca remove volumes.
EOF
}

while (($#)); do
    case "$1" in
        --perfil)
            [[ $# -ge 2 ]] || { echo "ERRO: --perfil exige valor" >&2; exit 64; }
            PROFILE="$2"; shift 2 ;;
        --somente-validar)
            START_IF_NEEDED=0; shift ;;
        --subir-se-necessario)
            START_IF_NEEDED=1; shift ;;
        --permitir-wildcard)
            ALLOW_WILDCARD=1; shift ;;
        --timeout)
            [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || { echo "ERRO: timeout inválido" >&2; exit 64; }
            TIMEOUT="$2"; shift 2 ;;
        --ajuda|-h)
            usage; exit 0 ;;
        *)
            echo "ERRO: opção desconhecida: $1" >&2
            usage >&2
            exit 64 ;;
    esac
done

case "$PROFILE" in local|vm) ;; *) echo "ERRO: perfil inválido: $PROFILE" >&2; exit 64 ;; esac

if [[ "$PROFILE" == "local" ]]; then
    : "${CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS:=127.0.0.1}"
    : "${CONECTAEDUCA_WAZUH_DASHBOARD_BIND_ADDRESS:=127.0.0.1}"

    case "$CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS" in
        127.0.0.1|::1) ;;
        *)
            echo "ERRO: perfil local exige Manager em loopback; valor recebido: $CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS" >&2
            exit 64
            ;;
    esac

    case "$CONECTAEDUCA_WAZUH_DASHBOARD_BIND_ADDRESS" in
        127.0.0.1|::1) ;;
        *)
            echo "ERRO: perfil local exige Dashboard em loopback; valor recebido: $CONECTAEDUCA_WAZUH_DASHBOARD_BIND_ADDRESS" >&2
            exit 64
            ;;
    esac

    export CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS
    export CONECTAEDUCA_WAZUH_DASHBOARD_BIND_ADDRESS
else
    [[ -n "${CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS:-}" ]] || {
        echo "ERRO: perfil vm exige CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS com IP específico." >&2
        exit 64
    }
    [[ -n "${CONECTAEDUCA_WAZUH_DASHBOARD_BIND_ADDRESS:-}" ]] || {
        echo "ERRO: perfil vm exige CONECTAEDUCA_WAZUH_DASHBOARD_BIND_ADDRESS com IP específico." >&2
        exit 64
    }
fi

if [[ -z "$ROOT" ]]; then
    ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$ROOT" || ! -d "$ROOT/.git" ]]; then
    echo "ERRO: execute dentro do repositório ConectaEduca ou defina PROJECT_ROOT." >&2
    exit 1
fi

for cmd in docker git curl python3 grep awk sed stat; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "ERRO: comando obrigatório ausente: $cmd" >&2
        exit 1
    }
done

WAZUH_DIR="$ROOT/deploy/interna/wazuh"
BASE="$WAZUH_DIR/compose.yml"
HOST="$WAZUH_DIR/compose.host.yml"
PROJECT="${CONECTAEDUCA_WAZUH_PROJECT:-conectaeduca-wazuh}"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${CONECTAEDUCA_OUTPUT_DIR:-$HOME/Downloads}"
OUT="$OUT_DIR/conectaeduca-validacao-wazuh-operacional-$STAMP.txt"

cd "$ROOT"
exec > >(tee "$OUT") 2>&1

section() {
    printf '\n============================================================\n%s\n============================================================\n' "$1"
}
die() {
    echo "ERRO: $*" >&2
    echo "WAZUH_OPERACIONAL=REPROVADO" >&2
    echo "ARQUIVO_SAIDA=$OUT" >&2
    exit 1
}

compose() {
    docker compose -p "$PROJECT" -f "$BASE" -f "$HOST" "$@"
}
service_id() {
    compose ps -q "$1" 2>/dev/null || true
}
wait_running() {
    local service="$1" elapsed=0 id="" state=""
    while (( elapsed <= TIMEOUT )); do
        id="$(service_id "$service")"
        [[ -z "$id" ]] || state="$(docker inspect -f '{{.State.Status}}' "$id" 2>/dev/null || true)"
        echo "WAIT=$service|t=${elapsed}|state=${state:-ausente}" >&2
        if [[ -n "$id" && "$state" == "running" ]]; then
            printf '%s' "$id"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed+5))
    done
    return 1
}
port_mappings() {
    local id="$1" port="$2"
    docker port "$id" "$port/tcp" 2>/dev/null || true
}
parse_mapping() {
    python3 - "$1" <<'PY'
import re, sys
v=sys.argv[1].strip()
patterns=[
    (r"^\[([^\]]+)\]:(\d+)$", "v6"),
    (r"^([^:]+):(\d+)$", "v4"),
]
for pat,_ in patterns:
    m=re.match(pat,v)
    if m:
        print(m.group(1))
        print(m.group(2))
        raise SystemExit(0)
raise SystemExit(1)
PY
}
validate_mappings() {
    local label="$1" mappings="$2" mapping parsed addr port count=0
    local -a parts=()
    [[ -n "$mappings" ]] || die "$label sem porta publicada"

    while IFS= read -r mapping; do
        [[ -n "$mapping" ]] || continue
        parsed="$(parse_mapping "$mapping")" \
            || die "$label possui binding não reconhecido: $mapping"
        parts=()
        mapfile -t parts <<<"$parsed"
        (( ${#parts[@]} == 2 )) \
            || die "$label possui binding incompleto: $mapping"
        addr="${parts[0]}"
        port="${parts[1]}"
        count=$((count+1))
        echo "BINDING=$label|address=$addr|host_port=$port"

        if [[ "$PROFILE" == "local" ]]; then
            [[ "$addr" == "127.0.0.1" || "$addr" == "::1" ]] \
                || die "$label deve usar apenas loopback no perfil local; atual=$addr"
        elif (( ALLOW_WILDCARD == 0 )); then
            [[ "$addr" != "0.0.0.0" && "$addr" != "::" ]] \
                || die "$label está em wildcard no perfil vm; informe IP específico ou use --permitir-wildcard conscientemente"
        fi
    done <<<"$mappings"

    (( count > 0 )) || die "$label sem binding válido"
    echo "BINDINGS_COUNT=$label|count=$count"
}
wait_manager_processes() {
    local id="$1" elapsed=0 status=""
    while (( elapsed <= TIMEOUT )); do
        status="$(docker exec "$id" /var/ossec/bin/wazuh-control status 2>/dev/null || true)"
        if grep -Eq 'wazuh-analysisd.*running' <<<"$status" && grep -Eq 'wazuh-remoted.*running' <<<"$status"; then
            return 0
        fi
        echo "WAIT_MANAGER_PROCESSES=t=${elapsed}"
        sleep 5
        elapsed=$((elapsed+5))
    done
    return 1
}
wait_dashboard() {
    local mapping="$1" parsed
    local -a parts=()
    parsed="$(parse_mapping "$mapping")" || return 1
    mapfile -t parts <<<"$parsed"
    (( ${#parts[@]} == 2 )) || return 1
    local addr port host elapsed=0 code=000
    addr="${parts[0]}"
    port="${parts[1]}"
    host="$addr"
    [[ "$addr" == *:* ]] && host="[$addr]"
    while (( elapsed <= TIMEOUT )); do
        code="$(curl -sk --max-time 5 -o /dev/null -w '%{http_code}' "https://${host}:${port}/" 2>/dev/null || true)"
        [[ "$code" =~ ^[0-9]{3}$ ]] || code=000
        echo "WAIT_DASHBOARD=t=${elapsed}|http=$code" >&2
        case "$code" in 200|301|302|303) echo "$code"; return 0 ;; esac
        sleep 5
        elapsed=$((elapsed+5))
    done
    return 1
}

section "CONECTAEDUCA - VALIDACAO WAZUH OPERACIONAL"
echo "data=$(date --iso-8601=seconds)"
echo "root=$ROOT"
echo "branch=$(git branch --show-current)"
echo "head=$(git rev-parse HEAD)"
echo "perfil=$PROFILE"
echo "manager_bind_address=$CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS"
echo "dashboard_bind_address=$CONECTAEDUCA_WAZUH_DASHBOARD_BIND_ADDRESS"
echo "start_if_needed=$START_IF_NEEDED"
echo "timeout=$TIMEOUT"
echo "saida=$OUT"
echo "GARANTIA=SEM_COMPOSE_DOWN_SEM_REMOCAO_DE_VOLUMES"

[[ -f "$BASE" ]] || die "compose.yml ausente"
[[ -f "$HOST" ]] || die "compose.host.yml ausente"
docker info >/dev/null 2>&1 || die "Docker Engine indisponível"
docker compose version >/dev/null 2>&1 || die "Docker Compose indisponível"
compose config >/dev/null || die "Compose Wazuh inválido"
git diff --check

section "1. RUNTIME NECESSARIO"
for file in \
    "$WAZUH_DIR/.runtime/manager.env" \
    "$WAZUH_DIR/.runtime/dashboard.env" \
    "$WAZUH_DIR/.runtime/internal_users.yml" \
    "$WAZUH_DIR/.runtime/wazuh.yml"
do
    if [[ -s "$file" ]]; then
        mode="$(stat -c '%a' "$file")"
        echo "RUNTIME=$(basename "$file")|state=PRESENT|mode=$mode|content=NOT_READ"
        [[ "$mode" == "600" || "$mode" == "400" ]] || die "runtime fora de 600/400: $file"
        git check-ignore -q -- "${file#"$ROOT/"}" || die "runtime não ignorado pelo Git: $file"
    elif (( START_IF_NEEDED == 1 )); then
        die "runtime necessário para start ausente/vazio: $file"
    else
        echo "RUNTIME=$(basename "$file")|state=ABSENT"
    fi
done

MAP_COUNT="$(cat /proc/sys/vm/max_map_count 2>/dev/null || true)"
[[ "$MAP_COUNT" =~ ^[0-9]+$ && "$MAP_COUNT" -ge 262144 ]] || die "vm.max_map_count insuficiente/indisponível: ${MAP_COUNT:-?}"
echo "vm.max_map_count=$MAP_COUNT"

section "2. GARANTIR STACK"
MANAGER_ID="$(service_id wazuh.manager)"
INDEXER_ID="$(service_id wazuh.indexer)"
DASHBOARD_ID="$(service_id wazuh.dashboard)"

all_running=1
for id in "$MANAGER_ID" "$INDEXER_ID" "$DASHBOARD_ID"; do
    if [[ -z "$id" || "$(docker inspect -f '{{.State.Status}}' "$id" 2>/dev/null || true)" != "running" ]]; then
        all_running=0
    fi
done

if (( all_running == 0 )); then
    (( START_IF_NEEDED == 1 )) || die "stack não está integralmente running e --somente-validar foi usado"
    echo "STACK_JA_ESTAVA_RUNNING=NAO"
    compose up -d || die "compose up -d falhou"
else
    echo "STACK_JA_ESTAVA_RUNNING=SIM"
fi

MANAGER_ID="$(wait_running wazuh.manager)" || die "Manager não ficou running"
INDEXER_ID="$(wait_running wazuh.indexer)" || die "Indexer não ficou running"
DASHBOARD_ID="$(wait_running wazuh.dashboard)" || die "Dashboard não ficou running"
echo "CONTAINERS_RUNNING=SIM"

section "3. SUPERFICIE DE REDE"
if port_mappings "$INDEXER_ID" 9200 | grep -q .; then
    die "Indexer API 9200 está publicada no host"
fi
if port_mappings "$MANAGER_ID" 55000 | grep -q .; then
    die "Manager API 55000 está publicada no host"
fi
echo "INDEXER_API_HOST=PRIVADA"
echo "MANAGER_API_HOST=PRIVADA"

AGENT_MAPPINGS="$(port_mappings "$MANAGER_ID" 1514)"
ENROLL_MAPPINGS="$(port_mappings "$MANAGER_ID" 1515)"
DASH_MAPPINGS="$(port_mappings "$DASHBOARD_ID" 5601)"
validate_mappings "manager-agent-1514" "$AGENT_MAPPINGS"
validate_mappings "manager-enrollment-1515" "$ENROLL_MAPPINGS"
validate_mappings "dashboard-5601" "$DASH_MAPPINGS"
DASH_MAPPING="$(printf '%s\n' "$DASH_MAPPINGS" | sed -n '1p')"

section "4. MANAGER / INDEXER / DASHBOARD"
wait_manager_processes "$MANAGER_ID" || die "analysisd/remoted não ficaram running"
echo "MANAGER_OPERACIONAL=SIM"

INDEXER_HTTP="$(
    docker exec "$MANAGER_ID" bash -lc '
      curl -sk --max-time 5 -o /dev/null -w "%{http_code}" https://wazuh.indexer:9200/ 2>/dev/null || true
    ' 2>/dev/null || true
)"
[[ "$INDEXER_HTTP" =~ ^[0-9]{3}$ ]] || INDEXER_HTTP=000
case "$INDEXER_HTTP" in 200|401|403) ;; *) die "Indexer interno não respondeu por HTTPS: $INDEXER_HTTP" ;; esac
echo "INDEXER_INTERNAL_HTTPS=$INDEXER_HTTP"
echo "INDEXER_OPERACIONAL=SIM"

DASH_HTTP="$(wait_dashboard "$DASH_MAPPING")" || die "Dashboard não respondeu no binding publicado"
echo "DASHBOARD_HTTPS=$DASH_HTTP"
echo "DASHBOARD_OPERACIONAL=SIM"

section "5. RESTART / VOLUMES"
for id in "$MANAGER_ID" "$INDEXER_ID" "$DASHBOARD_ID"; do
    name="$(docker inspect -f '{{.Name}}' "$id" | sed 's#^/##')"
    policy="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$id")"
    echo "RESTART_POLICY=$name|$policy"
    [[ "$policy" == "unless-stopped" || "$policy" == "always" ]] || die "restart policy inadequada em $name: $policy"
done

VOLUME_COUNT="$(
    docker volume ls --filter "label=com.docker.compose.project=$PROJECT" --format '{{.Name}}' 2>/dev/null | wc -l
)"
if (( VOLUME_COUNT < 14 )); then
    VOLUME_COUNT="$(
        docker volume ls --format '{{.Name}}' 2>/dev/null | grep -c "^${PROJECT}_" || true
    )"
fi
echo "WAZUH_VOLUMES=$VOLUME_COUNT"
(( VOLUME_COUNT >= 14 )) || die "menos de 14 volumes persistentes Wazuh"
echo "VOLUMES_PRESERVADOS=SIM"

section "6. ESTADO FINAL"
docker ps --filter "label=com.docker.compose.project=$PROJECT" \
    --format 'WAZUH={{.Names}}|STATUS={{.Status}}|PORTS={{.Ports}}' || true
git diff --check
echo "GIT_MODIFICADO_PELO_SCRIPT=NAO"
echo "CONTAINERS_DEIXADOS_RUNNING=SIM"
echo "COMPOSE_DOWN_EXECUTADO=NAO"

section "RESULTADO"
echo "WAZUH_OPERACIONAL=APROVADO"
echo "WAZUH_MANAGER=OPERACIONAL"
echo "WAZUH_INDEXER=OPERACIONAL"
echo "WAZUH_DASHBOARD=OPERACIONAL"
echo "PERFIL=$PROFILE"
echo "ARQUIVO_SAIDA=$OUT"
