#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
COMPOSE="$ROOT/deploy/interna/twingate/compose.yml"
RUNTIME="/dev/shm/conectaeduca-twingate.env"
CONTAINER="conectaeduca-twingate-connector"
IMAGE_TAG="twingate/connector:1"
EXPECTED_DIGEST="sha256:833e7a968f1b3a5ad79b88b04f82aad1bfc8621f61b6b35f01be2411d35beba9"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HOME/Downloads/conectaeduca-checkpoint-twingate-prevm-$STAMP.txt"
TMP_LOG=""

CONSOLE_CONFIRMED="NAO"
ZERO_RESOURCES_CONFIRMED="NAO"

usage() {
    cat <<'EOF'
Uso:
  checkpoint_twingate_prevm_handoff.sh \
    --confirm-console-connected \
    --confirm-zero-resources

As confirmações são declarações manuais do operador sobre o Admin Console.
O script não consulta a API da Twingate e nunca imprime tokens.
EOF
}

secret_pattern='TWINGATE_(ACCESS|REFRESH)_TOKEN[[:space:]]*[:=][[:space:]]*["'\'']?[A-Za-z0-9_-]{20,}'

self_test() {
    bash -n "$0"

    local placeholder synthetic
    placeholder='TWINGATE_ACCESS_TOKEN=${TWINGATE_ACCESS_TOKEN:?ausente}'
    synthetic="TWINGATE_ACCESS_TOKEN=$(printf '%s%s' 'abcdefghijklmnop' 'qrstuvwxyz123456')"

    if grep -Eq "$secret_pattern" <<<"$placeholder"; then
        echo "SELF_TEST=FALHA_REGEX_PLACEHOLDER" >&2
        exit 1
    fi

    if ! grep -Eq "$secret_pattern" <<<"$synthetic"; then
        echo "SELF_TEST=FALHA_REGEX_LITERAL" >&2
        exit 1
    fi

    echo "SELF_TEST=APROVADO"
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        --confirm-console-connected)
            CONSOLE_CONFIRMED="SIM_OPERADOR"
            ;;
        --confirm-zero-resources)
            ZERO_RESOURCES_CONFIRMED="SIM_OPERADOR"
            ;;
        --self-test)
            self_test
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERRO: argumento desconhecido: $arg" >&2
            usage >&2
            exit 2
            ;;
    esac
done

mkdir -p "$HOME/Downloads"
exec > >(tee "$OUT") 2>&1

cleanup() {
    if [[ -n "${TMP_LOG:-}" && -f "$TMP_LOG" ]]; then
        rm -f "$TMP_LOG"
    fi
}
trap cleanup EXIT

fail() {
    echo "FALHA: $*" >&2
    echo "CHECKPOINT_TWINGATE_PREVM=REPROVADO"
    echo "ARQUIVO_SAIDA=$OUT"
    exit 1
}

warn() {
    echo "AVISO: $*"
}

section() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

cd "$ROOT"

section "1. CONTEXTO"
BRANCH="$(git branch --show-current)"
HEAD="$(git rev-parse HEAD)"
echo "data=$(date --iso-8601=seconds)"
echo "host=$(hostname)"
echo "raiz_projeto=$ROOT"
echo "branch=$BRANCH"
echo "head=$HEAD"
echo "saida=$OUT"

section "2. ARTEFATOS DECLARATIVOS"
test -s "$COMPOSE" || fail "compose Twingate ausente/vazio"

grep -Fq "twingate/connector@$EXPECTED_DIGEST" "$COMPOSE"     || fail "compose não fixa o digest esperado"

grep -Eq '^[[:space:]]*network_mode:[[:space:]]*host[[:space:]]*$' "$COMPOSE"     || fail "network_mode host ausente"

grep -Eq '^[[:space:]]*-[[:space:]]+twingate[[:space:]]*$' "$COMPOSE"     || fail "profile twingate ausente"

grep -Fq 'no-new-privileges:true' "$COMPOSE"     || fail "no-new-privileges ausente"

if grep -Eq '^[[:space:]]*(ports|volumes|devices|cap_add|privileged):' "$COMPOSE"; then
    fail "compose contém expansão de superfície não aprovada"
fi

TWINGATE_NETWORK=x TWINGATE_ACCESS_TOKEN=x TWINGATE_REFRESH_TOKEN=x docker compose     -f "$COMPOSE"     --profile twingate     config     >/dev/null

echo "OK compose_config=valido_com_fixture"
echo "OK digest_declarativo=$EXPECTED_DIGEST"
echo "OK profile=twingate"
echo "OK network_mode=host"
echo "OK compose_sem_ports_volumes_devices_caps_privileged=SIM"

section "3. IMAGEM LOCAL"
LOCAL_DIGEST="$(
    docker image inspect         "$IMAGE_TAG"         --format '{{index .RepoDigests 0}}'         2>/dev/null         || true
)"
[[ "$LOCAL_DIGEST" == "twingate/connector@$EXPECTED_DIGEST" ]]     || fail "digest local divergente: ${LOCAL_DIGEST:-ausente}"

ARCH="$(docker image inspect "$IMAGE_TAG" --format '{{.Architecture}}')"
OS_NAME="$(docker image inspect "$IMAGE_TAG" --format '{{.Os}}')"
IMAGE_USER="$(docker image inspect "$IMAGE_TAG" --format '{{.Config.User}}')"

[[ "$ARCH" == "amd64" ]] || fail "arquitetura inesperada=$ARCH"
[[ "$OS_NAME" == "linux" ]] || fail "SO inesperado=$OS_NAME"
[[ "$IMAGE_USER" == "nonroot" ]] || fail "usuário default inesperado=$IMAGE_USER"

echo "OK image_digest=$EXPECTED_DIGEST"
echo "OK platform=$OS_NAME/$ARCH"
echo "OK image_user=$IMAGE_USER"

section "4. RUNTIME EFEMERO"
test -f "$RUNTIME" || fail "runtime efêmero ausente"

MODE="$(stat -c '%a' "$RUNTIME")"
OWNER="$(stat -c '%U:%G' "$RUNTIME")"
BYTES="$(stat -c '%s' "$RUNTIME")"

[[ "$MODE" == "600" ]] || fail "runtime modo=$MODE; esperado=600"

for key in     TWINGATE_NETWORK     TWINGATE_ACCESS_TOKEN     TWINGATE_REFRESH_TOKEN
do
    grep -Eq "^${key}=.+$" "$RUNTIME"         || fail "runtime sem $key"
done

echo "OK runtime=/dev/shm/conectaeduca-twingate.env"
echo "OK runtime_mode=$MODE"
echo "runtime_owner=$OWNER"
echo "runtime_bytes=$BYTES"
echo "SEGREDOS_EXIBIDOS=NAO"
echo "RUNTIME_PERSISTENTE=NAO"

section "5. CONTAINER OPERACIONAL"
STATUS="$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || true)"
RESTARTING="$(docker inspect -f '{{.State.Restarting}}' "$CONTAINER" 2>/dev/null || true)"
HEALTH="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER" 2>/dev/null || true)"

[[ "$STATUS" == "running" ]] || fail "container status=${STATUS:-ausente}"
[[ "$RESTARTING" == "false" ]] || fail "container restarting=$RESTARTING"
[[ "$HEALTH" == "healthy" ]] || fail "container health=$HEALTH"

CONTAINER_IMAGE_ID="$(docker inspect -f '{{.Image}}' "$CONTAINER")"
LOCAL_IMAGE_ID="$(docker image inspect "$IMAGE_TAG" -f '{{.Id}}')"
[[ "$CONTAINER_IMAGE_ID" == "$LOCAL_IMAGE_ID" ]]     || fail "container não usa a imagem local validada"

NETMODE="$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$CONTAINER")"
PRIVILEGED="$(docker inspect -f '{{.HostConfig.Privileged}}' "$CONTAINER")"
RESTART_POLICY="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$CONTAINER")"
CONFIG_USER="$(docker inspect -f '{{.Config.User}}' "$CONTAINER")"
MOUNT_COUNT="$(docker inspect -f '{{len .Mounts}}' "$CONTAINER")"
CAP_ADD="$(docker inspect -f '{{json .HostConfig.CapAdd}}' "$CONTAINER")"
SECOPT="$(docker inspect -f '{{json .HostConfig.SecurityOpt}}' "$CONTAINER")"
PUBLISHED="$(docker port "$CONTAINER" 2>/dev/null || true)"

[[ "$NETMODE" == "host" ]] || fail "network mode runtime=$NETMODE"
[[ "$PRIVILEGED" == "false" ]] || fail "container privilegiado"
[[ "$CONFIG_USER" == "nonroot" ]] || fail "Config.User=$CONFIG_USER"
[[ "$MOUNT_COUNT" == "0" ]] || fail "container possui $MOUNT_COUNT mounts"
[[ "$CAP_ADD" == "null" || "$CAP_ADD" == "[]" ]]     || fail "cap_add inesperado=$CAP_ADD"
grep -Fq 'no-new-privileges:true' <<<"$SECOPT"     || fail "no-new-privileges ausente no runtime"
[[ -z "$PUBLISHED" ]] || fail "porta publicada no host"

echo "OK container_status=$STATUS"
echo "OK container_health=$HEALTH"
echo "OK restarting=$RESTARTING"
echo "OK network_mode=$NETMODE"
echo "OK privileged=$PRIVILEGED"
echo "OK image_user=$CONFIG_USER"
echo "OK mounts=$MOUNT_COUNT"
echo "OK cap_add=nenhuma"
echo "OK host_ports=nenhuma"
echo "OK no_new_privileges=true"
echo "restart_policy=$RESTART_POLICY"

section "6. LOGS SEM EXPOR CONTEUDO"
TMP_LOG="$(mktemp /tmp/conectaeduca-twingate-prevm-log.XXXXXX)"
chmod 600 "$TMP_LOG"
docker logs --tail 300 "$CONTAINER" >"$TMP_LOG" 2>&1 || true

if grep -Eqi     'Invalid token|failed to get an access token|Gone, code 410|authentication failed'     "$TMP_LOG"
then
    fail "logs indicam falha de autenticação; detalhes omitidos"
fi

if grep -Eqi     'Failed to preconnect a relay listener|Connection timed out'     "$TMP_LOG"
then
    warn "logs contêm padrão de falha de Relay/egress; revisar antes da VM"
    RELAY_LOG_STATUS="AVISO"
else
    RELAY_LOG_STATUS="SEM_PADRAO_DE_ERRO"
fi

echo "OK auth_error_patterns=ausentes"
echo "relay_log_status=$RELAY_LOG_STATUS"
echo "LOGS_BRUTOS_EXIBIDOS=NAO"

section "7. REDE LOCAL PRE-VM"
DEFAULT_ROUTE="$(ip -4 route show default 2>/dev/null | head -n1 || true)"
DEFAULT_IF="$(awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}' <<<"$DEFAULT_ROUTE")"

echo "default_route_interface=${DEFAULT_IF:-nao_detectada}"

if ip -br -4 addr show virbr10 >/dev/null 2>&1; then
    VIRBR10_LINE="$(ip -br -4 addr show virbr10)"
    VIRBR10_STATE="$(awk '{print $2}' <<<"$VIRBR10_LINE")"
    VIRBR10_ADDR="$(awk '{print $3}' <<<"$VIRBR10_LINE")"
    echo "virbr10_state=$VIRBR10_STATE"
    echo "virbr10_ipv4=$VIRBR10_ADDR"

    if [[ "$VIRBR10_STATE" == "DOWN" ]]; then
        echo "OK virbr10_10_10_10_254=BRIDGE_LOCAL_DESLIGADA_NAO_IP_DEFINITIVO_VM"
    else
        warn "virbr10 não está DOWN; interpretar manualmente antes do handoff"
    fi
else
    echo "INFO virbr10=ausente"
fi

echo "IP_DEFINITIVO_VM_INTERNA=NAO_DEFINIDO"
echo "PFSENSE_SEGMENTACAO_FINAL=AINDA_NAO_VALIDADA"

section "8. HIGIENE GIT / SEGREDOS"

SCAN_FILES=(
    "$ROOT/deploy/interna/twingate/README.md"
    "$ROOT/deploy/interna/twingate/compose.yml"
    "$ROOT/scripts/bootstrap/preparar_twingate_runtime.fish"
    "$ROOT/scripts/implantacao/ativar_twingate_connector.fish"
    "$ROOT/scripts/evidencias/checkpoint_twingate_readiness.sh"
    "$ROOT/scripts/evidencias/checkpoint_twingate_operacional.sh"
    "$ROOT/scripts/evidencias/checkpoint_twingate_prevm_handoff.sh"
)

for file in "${SCAN_FILES[@]}"; do
    [[ -f "$file" ]] || fail "arquivo esperado ausente: $file"

    whitespace="$(
        git diff --no-index --check /dev/null "$file" 2>&1 || true
    )"
    [[ -z "$whitespace" ]]         || fail "whitespace inválido em $(realpath --relative-to="$ROOT" "$file")"
done

if grep -nEH "$secret_pattern" "${SCAN_FILES[@]}" >/dev/null 2>&1; then
    fail "possível token Twingate literal encontrado nos artefatos"
fi

if git ls-files     deploy/interna/twingate     scripts/bootstrap/preparar_twingate_runtime.fish     scripts/implantacao/ativar_twingate_connector.fish     scripts/evidencias     | grep -Ei '(^|/)(\.env|.*token|.*secret|.*credential)(\.|$)'     >/dev/null
then
    fail "arquivo potencialmente sensível rastreado"
fi

git diff --check

echo "OK whitespace_arquivos_twingate=limpo"
echo "OK token_literal_artefatos=NAO"
echo "OK runtime_em_dev_shm_rastreado=NAO"

section "9. CONFIRMACOES DO OPERADOR"
echo "admin_console_connected=$CONSOLE_CONFIRMED"
echo "resources_zero=$ZERO_RESOURCES_CONFIRMED"

[[ "$CONSOLE_CONFIRMED" == "SIM_OPERADOR" ]]     || fail "execute novamente com --confirm-console-connected após verificar o painel"

[[ "$ZERO_RESOURCES_CONFIRMED" == "SIM_OPERADOR" ]]     || fail "execute novamente com --confirm-zero-resources após verificar Resources=0"

section "10. RESULTADO / HANDOFF"
echo "CONNECTOR_LOCAL_VALIDADO=SIM"
echo "CONNECTOR_LOCAL_HEALTHY=SIM"
echo "ADMIN_CONSOLE_CONNECTED=SIM_OPERADOR"
echo "RESOURCES_DEFINITIVOS_CRIADOS=NAO"
echo "TOKENS_PERSISTIDOS_NO_GIT=NAO"
echo "TOKENS_REUTILIZAR_NA_VM=NAO"
echo "NOVOS_TOKENS_PARA_VM=OBRIGATORIO"
echo "DESTINO_FINAL=VM_UBUNTU_INTERNA"
echo "CONNECTOR_VM_NOVO=conectaeduca-interna-vm-01"
echo "CONNECTOR_LOCAL_APOS_MIGRACAO=REMOVER"
echo "IP_VM_INTERNA=DEFINIR_NA_IMPLANTACAO"
echo "PFSENSE_REVALIDACAO=OBRIGATORIA"
echo "CHECKPOINT_TWINGATE_PREVM=APROVADO"
echo "ARQUIVO_SAIDA=$OUT"
