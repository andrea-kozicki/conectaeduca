#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
VMS_DIR="$(cd -P "$SCRIPT_DIR/.." && pwd -P)"
# shellcheck source=../lib/comum.sh
source "$VMS_DIR/lib/comum.sh"

usage() {
    cat <<'EOF'
Uso:
  bash scripts/implantacao/vms/00-base/05-preflight-ubuntu.sh \
      --role dmz|interna \
      [--stage base|network|deploy] \
      [--config ARQUIVO] \
      [--topology ARQUIVO] \
      [--output ARQUIVO]

  bash scripts/implantacao/vms/00-base/05-preflight-ubuntu.sh --self-test

Stages:
  base     Ubuntu, arquitetura, capacidade, Docker/Compose e repositório.
  network  inclui interface/IP/gateway/DNS esperados.
  deploy   inclui parâmetros por papel e arquivos runtime/secrets necessários.

O script é de diagnóstico. Não instala pacotes, não altera sysctl, rede,
firewall, Docker, Compose nem conteúdo de secrets.
EOF
}

ROLE=""
STAGE="base"
CONFIG=""
TOPOLOGY=""
OUTPUT=""
SELF_TEST=0

while (($#)); do
    case "$1" in
        --role)
            [[ $# -ge 2 ]] || { echo "ERRO: --role exige valor" >&2; exit 64; }
            ROLE="$2"; shift 2 ;;
        --stage)
            [[ $# -ge 2 ]] || { echo "ERRO: --stage exige valor" >&2; exit 64; }
            STAGE="$2"; shift 2 ;;
        --config)
            [[ $# -ge 2 ]] || { echo "ERRO: --config exige arquivo" >&2; exit 64; }
            CONFIG="$2"; shift 2 ;;
        --topology)
            [[ $# -ge 2 ]] || { echo "ERRO: --topology exige arquivo" >&2; exit 64; }
            TOPOLOGY="$2"; shift 2 ;;
        --output)
            [[ $# -ge 2 ]] || { echo "ERRO: --output exige arquivo" >&2; exit 64; }
            OUTPUT="$2"; shift 2 ;;
        --self-test)
            SELF_TEST=1; shift ;;
        --help|-h)
            usage; exit 0 ;;
        *)
            echo "ERRO: opção desconhecida: $1" >&2
            usage >&2
            exit 64 ;;
    esac
done

self_test() {
    local tmp marker cfg v

    ce_valid_ipv4 "192.0.2.10" || { echo "SELF_TEST_PREFLIGHT=REPROVADO ipv4-valido"; return 1; }
    ! ce_valid_ipv4 "999.0.0.1" || { echo "SELF_TEST_PREFLIGHT=REPROVADO ipv4-invalido"; return 1; }
    ce_valid_iface "ens33" || { echo "SELF_TEST_PREFLIGHT=REPROVADO iface"; return 1; }
    ! ce_valid_iface "-a" || { echo "SELF_TEST_PREFLIGHT=REPROVADO iface-opcao"; return 1; }
    ce_version_ge "2.24.4" "2.24.4" || { echo "SELF_TEST_PREFLIGHT=REPROVADO semver-igual"; return 1; }
    ce_version_ge "2.39.1" "2.24.4" || { echo "SELF_TEST_PREFLIGHT=REPROVADO semver-maior"; return 1; }
    ! ce_version_ge "2.23.9" "2.24.4" || { echo "SELF_TEST_PREFLIGHT=REPROVADO semver-menor"; return 1; }

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    marker="$tmp/EXECUTOU"
    cfg="$tmp/test.env"
    cat >"$cfg" <<EOF
CONECTAEDUCA_VM_ROLE=dmz
CONECTAEDUCA_EXPECTED_IPV4=\$(touch $marker)
EOF

    v="$(ce_cfg_get CONECTAEDUCA_EXPECTED_IPV4 "$cfg")" || {
        echo "SELF_TEST_PREFLIGHT=REPROVADO parser"
        return 1
    }
    [[ "$v" == "\$(touch $marker)" ]] || {
        echo "SELF_TEST_PREFLIGHT=REPROVADO parser-conteudo"
        return 1
    }
    [[ ! -e "$marker" ]] || {
        echo "SELF_TEST_PREFLIGHT=REPROVADO parser-executou-shell"
        return 1
    }

    cat >"$cfg" <<'EOF'
CONECTAEDUCA_VM_ROLE=dmz
CHAVE_DESCONHECIDA=nao
EOF
    if ce_cfg_validate_keys "$cfg" CONECTAEDUCA_VM_ROLE >/dev/null; then
        echo "SELF_TEST_PREFLIGHT=REPROVADO chave-desconhecida"
        return 1
    fi

    [[ "CE-UBUNTU-DMZ" != "CE-UBUNTU-INT" ]] || {
        echo "SELF_TEST_PREFLIGHT=REPROVADO vm-id"
        return 1
    }

    local grepo head
    grepo="$tmp/repo"
    mkdir -p "$grepo"
    git -C "$grepo" init -q
    git -C "$grepo" config user.email selftest@example.test
    git -C "$grepo" config user.name selftest
    printf 'ok\n' >"$grepo/a"
    git -C "$grepo" add a
    git -C "$grepo" commit -qm baseline
    git -C "$grepo" tag ce-selftest-freeze
    head="$(git -C "$grepo" rev-parse HEAD)"
    ce_git_baseline_matches "$grepo" "$head" ce-selftest-freeze || {
        echo "SELF_TEST_PREFLIGHT=REPROVADO baseline"
        return 1
    }
    ! ce_git_baseline_matches "$grepo" 0000000000000000000000000000000000000000 ce-selftest-freeze || {
        echo "SELF_TEST_PREFLIGHT=REPROVADO baseline-divergente"
        return 1
    }

    echo "SELF_TEST_PREFLIGHT=APROVADO"
}

if (( SELF_TEST )); then
    self_test
    exit $?
fi

ce_valid_stage "$STAGE" || {
    echo "ERRO: stage inválido: $STAGE" >&2
    exit 64
}

ALLOWED_KEYS=(
    CONECTAEDUCA_VM_ROLE
    CONECTAEDUCA_VM_ID
    CONECTAEDUCA_EXPECTED_HOSTNAME
    CONECTAEDUCA_APP_URL
    CONECTAEDUCA_STACK_SECRET_GID
    CONECTAEDUCA_OPENBAO_BIND_ADDRESS
    CONECTAEDUCA_OPENBAO_HOST_PORT
    CONECTAEDUCA_EXPECTED_INTERFACE
    CONECTAEDUCA_EXPECTED_IPV4
    CONECTAEDUCA_EXPECTED_GATEWAY
    CONECTAEDUCA_TARGET_PLATFORM
    CONECTAEDUCA_MIN_COMPOSE_VERSION
    CONECTAEDUCA_WAF_BIND_ADDRESS
    CONECTAEDUCA_HTTP_PORT
    CONECTAEDUCA_HTTPS_PORT
    CONECTAEDUCA_DB_HOST
    CONECTAEDUCA_DB_BIND_ADDRESS
    CONECTAEDUCA_DB_PORT
    CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS
    CONECTAEDUCA_WAZUH_DASHBOARD_BIND_ADDRESS
    CONECTAEDUCA_WAZUH_AGENT_PORT
    CONECTAEDUCA_WAZUH_ENROLLMENT_PORT
    CONECTAEDUCA_WAZUH_DASHBOARD_PORT
    FERRET_BIND_ADDRESS
    FERRET_WEB_PORT
    CONECTAEDUCA_DB_ROOT_PASSWORD_FILE
    CONECTAEDUCA_DB_PASSWORD_FILE
    CONECTAEDUCA_PRIVATE_KEY_FILE
    CONECTAEDUCA_PUBLIC_KEY_FILE
    CONECTAEDUCA_WAF_TLS_CERT_FILE
    CONECTAEDUCA_WAF_TLS_KEY_FILE
)

if [[ -n "$CONFIG" ]]; then
    [[ -r "$CONFIG" ]] || {
        echo "ERRO: arquivo de configuração não legível: $CONFIG" >&2
        exit 64
    }
    unknown="$(ce_cfg_validate_keys "$CONFIG" "${ALLOWED_KEYS[@]}" 2>/dev/null || true)"
    if [[ -n "$unknown" ]]; then
        printf 'ERRO: chave/linha não reconhecida no arquivo de configuração:\n%s\n' "$unknown" >&2
        exit 64
    fi
fi

TOPOLOGY_KEYS=(
    CONECTAEDUCA_PFSENSE_IPV4
    CONECTAEDUCA_DMZ_IPV4
    CONECTAEDUCA_INTERNA_IPV4
    CONECTAEDUCA_BASELINE_COMMIT
    CONECTAEDUCA_BASELINE_TAG
)
if [[ -n "$TOPOLOGY" ]]; then
    [[ -r "$TOPOLOGY" ]] || { echo "ERRO: arquivo de topologia não legível: $TOPOLOGY" >&2; exit 64; }
    topo_unknown="$(ce_cfg_validate_keys "$TOPOLOGY" "${TOPOLOGY_KEYS[@]}" 2>/dev/null || true)"
    if [[ -n "$topo_unknown" ]]; then
        printf 'ERRO: chave/linha não reconhecida no arquivo de topologia:\n%s\n' "$topo_unknown" >&2
        exit 64
    fi
fi

cfg_assign() {
    local variable="$1" key="$2" value="" rc=0
    [[ -n "$CONFIG" ]] || { printf -v "$variable" '%s' ""; return 0; }
    value="$(ce_cfg_get "$key" "$CONFIG")" || rc=$?
    if (( rc == 3 )); then
        echo "ERRO: chave duplicada em $CONFIG: $key" >&2
        exit 64
    elif (( rc != 0 )); then
        echo "ERRO: falha lendo $key em $CONFIG" >&2
        exit 64
    fi
    printf -v "$variable" '%s' "$value"
}

cfg_assign CFG_ROLE CONECTAEDUCA_VM_ROLE
if [[ -z "$ROLE" ]]; then ROLE="$CFG_ROLE"; fi
ce_valid_role "$ROLE" || {
    echo "ERRO: informe --role dmz|interna ou CONECTAEDUCA_VM_ROLE no arquivo." >&2
    exit 64
}

cfg_assign CFG_VM_ID CONECTAEDUCA_VM_ID
cfg_assign CFG_EXPECTED_HOSTNAME CONECTAEDUCA_EXPECTED_HOSTNAME

if [[ "$ROLE" == "dmz" ]]; then
    DEFAULT_VM_ID="CE-UBUNTU-DMZ"
    DEFAULT_HOSTNAME="conectaeduca-dmz"
else
    DEFAULT_VM_ID="CE-UBUNTU-INT"
    DEFAULT_HOSTNAME="conectaeduca-interna"
fi

VM_ID="${CFG_VM_ID:-$DEFAULT_VM_ID}"
EXPECTED_HOSTNAME="${CFG_EXPECTED_HOSTNAME:-$DEFAULT_HOSTNAME}"

if [[ "$VM_ID" != "$DEFAULT_VM_ID" ]]; then
    echo "ERRO: CONECTAEDUCA_VM_ID incompatível com role=$ROLE; esperado $DEFAULT_VM_ID" >&2
    exit 64
fi

if [[ "$EXPECTED_HOSTNAME" != "$DEFAULT_HOSTNAME" ]]; then
    echo "ERRO: CONECTAEDUCA_EXPECTED_HOSTNAME incompatível com role=$ROLE; esperado $DEFAULT_HOSTNAME" >&2
    exit 64
fi

if [[ "$STAGE" != "base" && -z "$CONFIG" ]]; then
    echo "ERRO: stage $STAGE exige --config com parâmetros esperados." >&2
    exit 64
fi
if [[ "$STAGE" != "base" && -z "$TOPOLOGY" ]]; then
    echo "ERRO: stage $STAGE exige --topology com o cartão de rede/baseline." >&2
    exit 64
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -z "$OUTPUT" ]]; then
    OUT_DIR="$HOME/Downloads"
    [[ -d "$OUT_DIR" && -w "$OUT_DIR" ]] || OUT_DIR="$PWD"
    OUTPUT="$OUT_DIR/conectaeduca-preflight-ubuntu-${ROLE}-${STAGE}-${STAMP}.txt"
fi
mkdir -p "$(dirname "$OUTPUT")" || {
    echo "ERRO: não foi possível criar diretório do relatório." >&2
    exit 1
}
: >"$OUTPUT" || {
    echo "ERRO: não foi possível criar relatório: $OUTPUT" >&2
    exit 1
}
ce_set_report "$OUTPUT"

ce_section "ConectaEduca / preflight Ubuntu v2.2-final"
ce_emit "DATA=$(date --iso-8601=seconds 2>/dev/null || date)"
ce_emit "VM_ID=$VM_ID"
ce_emit "VM_ROLE=$ROLE"
ce_emit "HOSTNAME_ESPERADO=$EXPECTED_HOSTNAME"
ce_emit "STAGE=$STAGE"
ce_emit "MODO=SOMENTE_LEITURA_EXCETO_RELATORIO"
ce_emit "SEGREDOS_CONTEUDO_LIDO=NAO"
ce_emit "OUTPUT=$OUTPUT"

# Dependências mínimas do próprio preflight.
for cmd in awk cat date df git grep hostname ip lsblk mkdir nproc stat uname; do
    if ce_have "$cmd"; then ce_ok "CMD_$cmd=PRESENTE"; else ce_fail "CMD_$cmd=AUSENTE"; fi
done

ce_section "1. Host e sistema operacional"

OS_ID=""
OS_VERSION=""
if [[ -r /etc/os-release ]]; then
    OS_ID="$(awk -F= '$1=="ID" {gsub(/^"|"$/, "", $2); print $2; exit}' /etc/os-release)"
    OS_VERSION="$(awk -F= '$1=="VERSION_ID" {gsub(/^"|"$/, "", $2); print $2; exit}' /etc/os-release)"
fi
KERNEL="$(uname -s 2>/dev/null || true)"
ARCH="$(uname -m 2>/dev/null || true)"

ce_emit "OS_ID=${OS_ID:-INDETERMINADO}"
ce_emit "OS_VERSION=${OS_VERSION:-INDETERMINADO}"
ce_emit "KERNEL=${KERNEL:-INDETERMINADO}"
ce_emit "ARCH=${ARCH:-INDETERMINADO}"

CURRENT_HOSTNAME="$(hostname 2>/dev/null || true)"
ce_emit "HOSTNAME_ATUAL=${CURRENT_HOSTNAME:-INDETERMINADO}"
if [[ "$STAGE" == "base" ]]; then
    if [[ "$CURRENT_HOSTNAME" == "$EXPECTED_HOSTNAME" ]]; then
        ce_ok "HOSTNAME=IDENTIDADE_ESPERADA"
    else
        ce_warn "HOSTNAME_AINDA_NAO_PADRONIZADO esperado=$EXPECTED_HOSTNAME atual=${CURRENT_HOSTNAME:-?}"
    fi
else
    if [[ "$CURRENT_HOSTNAME" == "$EXPECTED_HOSTNAME" ]]; then
        ce_ok "HOSTNAME=IDENTIDADE_ESPERADA"
    else
        ce_fail "HOSTNAME_DIVERGENTE esperado=$EXPECTED_HOSTNAME atual=${CURRENT_HOSTNAME:-?}"
    fi
fi

[[ "$KERNEL" == "Linux" ]] && ce_ok "KERNEL=Linux" || ce_fail "KERNEL_ESPERADO=Linux atual=${KERNEL:-?}"
[[ "$OS_ID" == "ubuntu" ]] && ce_ok "OS=Ubuntu" || ce_fail "OS_ESPERADO=ubuntu atual=${OS_ID:-?}"
[[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]] \
    && ce_ok "ARQUITETURA=linux/amd64" \
    || ce_fail "ARQUITETURA_ESPERADA=linux/amd64 atual=${ARCH:-?}"

CPU="$(nproc 2>/dev/null || echo 0)"
ce_emit "CPU_VCPUS=$CPU"

MEM_KB="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || true)"
if [[ "$MEM_KB" =~ ^[0-9]+$ ]]; then
    MEM_GIB="$(awk -v kb="$MEM_KB" 'BEGIN {printf "%.2f", kb/1024/1024}')"
    ce_emit "RAM_GIB=$MEM_GIB"
    if [[ "$ROLE" == "dmz" ]]; then
        (( MEM_KB >= 7*1024*1024 )) && ce_ok "RAM_CLASSE=8GiB_DMZ" || ce_fail "RAM_DMZ_INSUFICIENTE=${MEM_GIB}GiB"
    else
        (( MEM_KB >= 15*1024*1024 )) && ce_ok "RAM_CLASSE=16GiB_INTERNA" || ce_fail "RAM_INTERNA_INSUFICIENTE=${MEM_GIB}GiB"
    fi
else
    ce_fail "RAM=INDETERMINADA"
fi

MAX_DISK_BYTES="$(lsblk -b -dn -o TYPE,SIZE 2>/dev/null | awk '$1=="disk" && $2>max {max=$2} END {print max+0}')"
if [[ "$MAX_DISK_BYTES" =~ ^[0-9]+$ && "$MAX_DISK_BYTES" -gt 0 ]]; then
    MAX_DISK_GIB="$(awk -v b="$MAX_DISK_BYTES" 'BEGIN {printf "%.2f", b/1024/1024/1024}')"
    ce_emit "MAIOR_DISCO_GIB=$MAX_DISK_GIB"
    (( MAX_DISK_BYTES >= 175000000000 )) \
        && ce_ok "DISCO=CLASSE_180GB_OU_MAIOR" \
        || ce_fail "DISCO_INSUFICIENTE=${MAX_DISK_GIB}GiB esperado_classe_180GB"
else
    ce_fail "DISCO=INDETERMINADO"
fi

ROOT_FREE_KB="$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4}')"
if [[ "$ROOT_FREE_KB" =~ ^[0-9]+$ ]]; then
    ROOT_FREE_GIB="$(awk -v kb="$ROOT_FREE_KB" 'BEGIN {printf "%.2f", kb/1024/1024}')"
    ce_emit "ROOT_FREE_GIB=$ROOT_FREE_GIB"
fi

ce_section "2. Docker e Compose"

if ce_have docker; then
    ce_ok "DOCKER_CLI=PRESENTE"
    if docker info >/dev/null 2>&1; then
        ce_ok "DOCKER_ENGINE=ACESSIVEL"
        DOCKER_ARCH="$(docker info --format '{{.Architecture}}' 2>/dev/null || true)"
        ce_emit "DOCKER_ARCH=${DOCKER_ARCH:-INDETERMINADA}"
    else
        ce_fail "DOCKER_ENGINE=INACESSIVEL"
    fi

    COMPOSE_VERSION="$(docker compose version --short 2>/dev/null || true)"
    if [[ -z "$COMPOSE_VERSION" ]]; then
        COMPOSE_VERSION="$(docker compose version 2>/dev/null | grep -Eo 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    fi
    REQUIRED_COMPOSE="2.24.4"
    cfg_assign CFG_MIN_COMPOSE CONECTAEDUCA_MIN_COMPOSE_VERSION
    [[ -n "$CFG_MIN_COMPOSE" ]] && REQUIRED_COMPOSE="$CFG_MIN_COMPOSE"

    ce_emit "COMPOSE_VERSION=${COMPOSE_VERSION:-AUSENTE}"
    ce_emit "COMPOSE_MINIMO=$REQUIRED_COMPOSE"
    if [[ -n "$COMPOSE_VERSION" ]] && ce_version_ge "$COMPOSE_VERSION" "$REQUIRED_COMPOSE"; then
        ce_ok "DOCKER_COMPOSE=COMPATIVEL"
    else
        ce_fail "DOCKER_COMPOSE=INCOMPATIVEL_OU_AUSENTE"
    fi
else
    ce_fail "DOCKER_CLI=AUSENTE"
    ce_fail "DOCKER_ENGINE=NAO_TESTADO"
    ce_fail "DOCKER_COMPOSE=AUSENTE"
fi

ce_section "3. Repositório e baseline"

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "$PROJECT_ROOT" && -d "$PROJECT_ROOT/.git" ]]; then
    ce_ok "REPOSITORIO=DETECTADO"
    ce_emit "PROJECT_ROOT=$PROJECT_ROOT"
    ce_emit "GIT_BRANCH=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || true)"
    CURRENT_GIT_HEAD="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || true)"
    CURRENT_GIT_TAGS="$(ce_git_exact_tags "$PROJECT_ROOT")"
    ce_emit "GIT_HEAD=${CURRENT_GIT_HEAD:-INDETERMINADO}"
    ce_emit "GIT_TAG_EXATO=${CURRENT_GIT_TAGS:-NENHUMA}"

    BASELINE_COMMIT=""
    BASELINE_TAG=""
    if [[ -n "$TOPOLOGY" ]]; then
        BASELINE_COMMIT="$(ce_cfg_get CONECTAEDUCA_BASELINE_COMMIT "$TOPOLOGY")"
        BASELINE_TAG="$(ce_cfg_get CONECTAEDUCA_BASELINE_TAG "$TOPOLOGY")"
    fi
    ce_emit "BASELINE_COMMIT_ESPERADO=${BASELINE_COMMIT:-NAO_FIXADO}"
    ce_emit "BASELINE_TAG_ESPERADA=${BASELINE_TAG:-NAO_FIXADA}"

    BASELINE_FIXED=1
    [[ -n "$BASELINE_COMMIT" && "$BASELINE_COMMIT" != ALTERAR_APOS_FREEZE ]] || BASELINE_FIXED=0
    [[ -n "$BASELINE_TAG" && "$BASELINE_TAG" != ALTERAR_APOS_FREEZE ]] || BASELINE_FIXED=0
    if (( BASELINE_FIXED )); then
        if ce_git_baseline_matches "$PROJECT_ROOT" "$BASELINE_COMMIT" "$BASELINE_TAG"; then
            ce_ok "BASELINE_GIT=APROVADO"
        else
            rc=$?
            ce_fail "BASELINE_GIT=DIVERGENTE rc=$rc"
        fi
    elif [[ "$STAGE" == deploy ]]; then
        ce_fail "BASELINE_GIT=NAO_FIXADO_PARA_DEPLOY"
    else
        ce_warn "BASELINE_GIT=AINDA_NAO_FIXADO"
    fi

    for f in \
        deploy/CONTRATO-IMPLANTACAO.md \
        deploy/ARQUITETURA-VMs.md \
        deploy/dmz/compose.host.yml \
        deploy/interna/mariadb/compose.host.yml \
        deploy/interna/wazuh/compose.host.yml \
        deploy/interna/bacula/compose.vm.yml
    do
        [[ -f "$PROJECT_ROOT/$f" ]] && ce_ok "ARTEFATO=$f" || ce_fail "ARTEFATO_AUSENTE=$f"
    done

    if git -C "$PROJECT_ROOT" diff --quiet -- && git -C "$PROJECT_ROOT" diff --cached --quiet --; then
        ce_ok "WORKTREE=LIMPO"
    elif [[ "$STAGE" == "deploy" ]]; then
        ce_fail "WORKTREE=SUJO_EM_STAGE_DEPLOY"
    else
        ce_warn "WORKTREE=SUJO"
    fi
else
    PROJECT_ROOT=""
    ce_fail "REPOSITORIO=CONECTAEDUCA_NAO_DETECTADO"
fi

ce_section "4. Requisitos por papel"

if [[ "$ROLE" == "interna" ]]; then
    MAP_COUNT="$(cat /proc/sys/vm/max_map_count 2>/dev/null || true)"
    ce_emit "VM_MAX_MAP_COUNT=${MAP_COUNT:-INDETERMINADO}"
    if [[ "$MAP_COUNT" =~ ^[0-9]+$ ]] && (( MAP_COUNT >= 262144 )); then
        ce_ok "VM_MAX_MAP_COUNT=COMPATIVEL_WAZUH"
    else
        ce_fail "VM_MAX_MAP_COUNT=INSUFICIENTE_WAZUH"
    fi
else
    ce_emit "VM_MAX_MAP_COUNT=NAO_APLICAVEL_DMZ"
fi

if ce_have docker && docker info >/dev/null 2>&1; then
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -Eiq '(^|[-_.])twingate([-_.]|$)'; then
        ce_fail "TWINGATE=ATIVO_NA_FASE1"
    else
        ce_ok "TWINGATE=NAO_ATIVO_NA_FASE1"
    fi
else
    ce_emit "TWINGATE=NAO_VERIFICADO_SEM_DOCKER"
fi

if [[ "$STAGE" == "network" || "$STAGE" == "deploy" ]]; then
    ce_section "5. Rede esperada"

    cfg_assign EXPECTED_IFACE CONECTAEDUCA_EXPECTED_INTERFACE
    CFG_EXPECTED_IP="$(ce_cfg_get CONECTAEDUCA_EXPECTED_IPV4 "$CONFIG")"
    CFG_EXPECTED_GW="$(ce_cfg_get CONECTAEDUCA_EXPECTED_GATEWAY "$CONFIG")"
    if [[ "$ROLE" == dmz ]]; then
        TOPO_EXPECTED_IP="$(ce_cfg_required CONECTAEDUCA_DMZ_IPV4 "$TOPOLOGY")"
        TOPO_EXPECTED_GW="$(ce_cfg_required CONECTAEDUCA_PFSENSE_IPV4 "$TOPOLOGY")"
    else
        TOPO_EXPECTED_IP="$(ce_cfg_required CONECTAEDUCA_INTERNA_IPV4 "$TOPOLOGY")"
        TOPO_EXPECTED_GW="$(ce_cfg_required CONECTAEDUCA_PFSENSE_IPV4 "$TOPOLOGY")"
    fi
    EXPECTED_IP="${CFG_EXPECTED_IP:-$TOPO_EXPECTED_IP}"
    EXPECTED_GW="${CFG_EXPECTED_GW:-$TOPO_EXPECTED_GW}"

    ce_valid_iface "$EXPECTED_IFACE" || ce_fail "EXPECTED_INTERFACE=INVALIDA_OU_AUSENTE"
    ce_valid_ipv4 "$TOPO_EXPECTED_IP" || ce_fail "TOPOLOGIA_IPV4=INVALIDO"
    ce_valid_ipv4 "$TOPO_EXPECTED_GW" || ce_fail "TOPOLOGIA_GATEWAY=INVALIDO"
    [[ "$EXPECTED_IP" == "$TOPO_EXPECTED_IP" ]] || ce_fail "CONFIG_IPV4_DIVERGE_TOPOLOGIA config=$EXPECTED_IP topologia=$TOPO_EXPECTED_IP"
    [[ "$EXPECTED_GW" == "$TOPO_EXPECTED_GW" ]] || ce_fail "CONFIG_GATEWAY_DIVERGE_TOPOLOGIA config=$EXPECTED_GW topologia=$TOPO_EXPECTED_GW"

    if ce_valid_iface "$EXPECTED_IFACE" && ip link show dev "$EXPECTED_IFACE" >/dev/null 2>&1; then
        ce_ok "INTERFACE=$EXPECTED_IFACE"
        MAC="$(cat "/sys/class/net/$EXPECTED_IFACE/address" 2>/dev/null || true)"
        ce_emit "INTERFACE_MAC=${MAC:-INDETERMINADO}"

        CURRENT_IPS="$(ip -o -4 addr show dev "$EXPECTED_IFACE" 2>/dev/null | awk '{split($4,a,"/"); print a[1]}')"
        ce_emit "INTERFACE_IPV4_ATUAIS=$(tr '\n' ',' <<<"$CURRENT_IPS" | sed 's/,$//')"
        if grep -Fxq "$EXPECTED_IP" <<<"$CURRENT_IPS"; then
            ce_ok "IP_ESPERADO=$EXPECTED_IP"
        else
            ce_fail "IP_ESPERADO_AUSENTE=$EXPECTED_IP"
        fi
    else
        ce_fail "INTERFACE_ESPERADA_AUSENTE=${EXPECTED_IFACE:-?}"
    fi

    DEFAULT_ROUTE="$(ip -4 route show default 2>/dev/null | head -1 || true)"
    ce_emit "DEFAULT_ROUTE=${DEFAULT_ROUTE:-AUSENTE}"
    if [[ -n "$DEFAULT_ROUTE" && "$DEFAULT_ROUTE" == *" dev $EXPECTED_IFACE"* && "$DEFAULT_ROUTE" == *" via $EXPECTED_GW"* ]]; then
        ce_ok "ROTA_DEFAULT=INTERFACE_E_GATEWAY_ESPERADOS"
    else
        ce_fail "ROTA_DEFAULT=DIVERGENTE"
    fi

    DNS_COUNT="$(grep -Ec '^[[:space:]]*nameserver[[:space:]]+' /etc/resolv.conf 2>/dev/null || true)"
    if [[ "$DNS_COUNT" =~ ^[0-9]+$ && "$DNS_COUNT" -gt 0 ]]; then
        ce_ok "DNS=CONFIGURADO"
        ce_emit "DNS_NAMESERVERS=$DNS_COUNT"
    else
        ce_fail "DNS=NAO_CONFIGURADO"
    fi
fi

check_secret_file() {
    local label="$1" path="$2" private="$3"
    if [[ -z "$path" ]]; then
        ce_fail "$label=CAMINHO_AUSENTE"
        return
    fi
    if [[ ! -s "$path" ]]; then
        ce_fail "$label=ARQUIVO_AUSENTE_OU_VAZIO path=$path"
        return
    fi
    if [[ "$private" == "yes" ]] && ! ce_file_mode_private "$path"; then
        ce_fail "$label=PERMISSAO_EXCESSIVA path=$path"
    else
        ce_ok "$label=PRESENTE_SEM_LER_CONTEUDO"
    fi
    if [[ -n "$PROJECT_ROOT" ]] && ce_is_tracked "$PROJECT_ROOT" "$path"; then
        ce_fail "$label=RASTREADO_PELO_GIT"
    fi
}

if [[ "$STAGE" == "deploy" ]]; then
    ce_section "6. Parâmetros e runtime para deploy"

    if [[ "$ROLE" == "interna" ]]; then
        cfg_assign DB_BIND CONECTAEDUCA_DB_BIND_ADDRESS
        cfg_assign WAZUH_MANAGER_BIND CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS
        cfg_assign WAZUH_DASH_BIND CONECTAEDUCA_WAZUH_DASHBOARD_BIND_ADDRESS

        ce_valid_ipv4 "$DB_BIND" && ce_ok "DB_BIND=$DB_BIND" || ce_fail "DB_BIND=INVALIDO"
        ce_valid_ipv4 "$WAZUH_MANAGER_BIND" && ce_ok "WAZUH_MANAGER_BIND=$WAZUH_MANAGER_BIND" || ce_fail "WAZUH_MANAGER_BIND=INVALIDO"
        ce_valid_ipv4 "$WAZUH_DASH_BIND" && ce_ok "WAZUH_DASHBOARD_BIND=$WAZUH_DASH_BIND" || ce_fail "WAZUH_DASHBOARD_BIND=INVALIDO"

        [[ "$DB_BIND" == "$EXPECTED_IP" ]] || ce_fail "DB_BIND_NAO_CORRESPONDE_IP_VM"
        [[ "$WAZUH_MANAGER_BIND" == "$EXPECTED_IP" ]] || ce_fail "WAZUH_MANAGER_BIND_NAO_CORRESPONDE_IP_VM"

        cfg_assign DB_ROOT_FILE CONECTAEDUCA_DB_ROOT_PASSWORD_FILE
        cfg_assign DB_APP_FILE CONECTAEDUCA_DB_PASSWORD_FILE
        check_secret_file "SECRET_MARIADB_ROOT" "$DB_ROOT_FILE" yes
        check_secret_file "SECRET_DB_APP" "$DB_APP_FILE" yes

        WAZUH_RUNTIME="$PROJECT_ROOT/deploy/interna/wazuh/.runtime"
        for f in manager.env dashboard.env internal_users.yml wazuh.yml; do
            check_secret_file "WAZUH_RUNTIME_$f" "$WAZUH_RUNTIME/$f" yes
        done
    else
        cfg_assign WAF_BIND CONECTAEDUCA_WAF_BIND_ADDRESS
        cfg_assign DB_HOST CONECTAEDUCA_DB_HOST

        ce_valid_ipv4 "$WAF_BIND" && ce_ok "WAF_BIND=$WAF_BIND" || ce_fail "WAF_BIND=INVALIDO"
        [[ "$WAF_BIND" == "$EXPECTED_IP" ]] || ce_fail "WAF_BIND_NAO_CORRESPONDE_IP_VM"

        if ce_valid_ipv4 "$DB_HOST"; then
            [[ "$DB_HOST" != "127.0.0.1" && "$DB_HOST" != "$EXPECTED_IP" ]] \
                && ce_ok "DB_HOST=ENDPOINT_REMOTO" \
                || ce_fail "DB_HOST=NAO_DEVE_SER_LOOPBACK_NEM_IP_DA_DMZ"
        elif [[ "$DB_HOST" =~ ^[A-Za-z0-9.-]+$ && "$DB_HOST" == *.* ]]; then
            ce_ok "DB_HOST=FQDN_CONFIGURADO"
        else
            ce_fail "DB_HOST=INVALIDO"
        fi

        cfg_assign DB_APP_FILE CONECTAEDUCA_DB_PASSWORD_FILE
        cfg_assign PRIVATE_KEY_FILE CONECTAEDUCA_PRIVATE_KEY_FILE
        cfg_assign PUBLIC_KEY_FILE CONECTAEDUCA_PUBLIC_KEY_FILE
        cfg_assign WAF_CERT_FILE CONECTAEDUCA_WAF_TLS_CERT_FILE
        cfg_assign WAF_KEY_FILE CONECTAEDUCA_WAF_TLS_KEY_FILE

        check_secret_file "SECRET_DB_APP" "$DB_APP_FILE" yes
        check_secret_file "SECRET_APP_PRIVATE_KEY" "$PRIVATE_KEY_FILE" yes
        check_secret_file "APP_PUBLIC_KEY" "$PUBLIC_KEY_FILE" no
        check_secret_file "WAF_TLS_CERT" "$WAF_CERT_FILE" no
        check_secret_file "SECRET_WAF_TLS_KEY" "$WAF_KEY_FILE" yes
    fi
fi

ce_section "Resultado"

ce_emit "FAILURES=$CE_FAILURES"
ce_emit "WARNINGS=$CE_WARNINGS"

if (( CE_FAILURES == 0 )); then
    ce_emit "PREFLIGHT_UBUNTU=APROVADO"
    ce_emit "PRONTO_PARA_ETAPA_${STAGE^^}=SIM"
    ce_emit "ARQUIVO_SAIDA=$OUTPUT"
    exit 0
else
    ce_emit "PREFLIGHT_UBUNTU=REPROVADO"
    ce_emit "PRONTO_PARA_ETAPA_${STAGE^^}=NAO"
    ce_emit "ARQUIVO_SAIDA=$OUTPUT"
    exit 1
fi
