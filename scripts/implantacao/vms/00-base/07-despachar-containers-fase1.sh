#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
VMS_DIR="$(cd -P "$SCRIPT_DIR/.." && pwd -P)"
source "$VMS_DIR/lib/comum.sh"

TOPOLOGY=""
CONFIG=""
MODE="plan"
SELF_TEST=0

usage() {
    cat <<'EOF'
Uso:
  07-despachar-containers-fase1.sh --topology ARQUIVO [--config ARQUIVO] --plan
  07-despachar-containers-fase1.sh --topology ARQUIVO [--config ARQUIVO] --apply
  07-despachar-containers-fase1.sh --self-test

--plan  detecta a máquina e mostra exatamente quais containers pertencem a ela.
--apply repete o preflight de deploy e chama SOMENTE o orquestrador da máquina
        detectada pelo IP.
EOF
}

while (($#)); do
    case "$1" in
        --topology) TOPOLOGY="${2:-}"; shift 2 ;;
        --config) CONFIG="${2:-}"; shift 2 ;;
        --plan) MODE="plan"; shift ;;
        --apply) MODE="apply"; shift ;;
        --self-test) SELF_TEST=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERRO: opção desconhecida: $1" >&2; exit 64 ;;
    esac
done

detect_machine() {
    local current="$1" pfsense="$2" dmz="$3" interna="$4"
    local hits=0 found="" ip
    IFS=',' read -r -a ips <<<"$current"
    for ip in "${ips[@]}"; do
        if [[ "$ip" == "$pfsense" ]]; then hits=$((hits+1)); found="pfsense"; fi
        if [[ "$ip" == "$dmz" ]]; then hits=$((hits+1)); found="dmz"; fi
        if [[ "$ip" == "$interna" ]]; then hits=$((hits+1)); found="interna"; fi
    done
    (( hits == 1 )) || return 1
    printf '%s' "$found"
}

if (( SELF_TEST )); then
    [[ "$(detect_machine 192.0.2.1 192.0.2.1 192.0.2.10 192.0.2.20)" == pfsense ]] || exit 1
    [[ "$(detect_machine 192.0.2.10 192.0.2.1 192.0.2.10 192.0.2.20)" == dmz ]] || exit 1
    [[ "$(detect_machine 192.0.2.20 192.0.2.1 192.0.2.10 192.0.2.20)" == interna ]] || exit 1
    echo 'SELF_TEST_DESPACHANTE_CONTAINERS=APROVADO'
    exit 0
fi

[[ -n "$TOPOLOGY" ]] || { echo "ERRO: informe --topology ARQUIVO" >&2; exit 64; }
[[ -r "$TOPOLOGY" ]] || { echo "ERRO: arquivo de topologia ausente ou não legível: $TOPOLOGY" >&2; exit 66; }

allowed=(
    CONECTAEDUCA_PFSENSE_IPV4
    CONECTAEDUCA_DMZ_IPV4
    CONECTAEDUCA_INTERNA_IPV4
    CONECTAEDUCA_BASELINE_COMMIT
    CONECTAEDUCA_BASELINE_TAG
)
unknown="$(ce_cfg_validate_keys "$TOPOLOGY" "${allowed[@]}" 2>/dev/null || true)"
[[ -z "$unknown" ]] || { printf 'ERRO: topologia inválida:\n%s\n' "$unknown" >&2; exit 64; }

PF="$(ce_cfg_required CONECTAEDUCA_PFSENSE_IPV4 "$TOPOLOGY")"
DMZ="$(ce_cfg_required CONECTAEDUCA_DMZ_IPV4 "$TOPOLOGY")"
INT="$(ce_cfg_required CONECTAEDUCA_INTERNA_IPV4 "$TOPOLOGY")"
for ip in "$PF" "$DMZ" "$INT"; do ce_valid_ipv4 "$ip" || exit 64; done

CURRENT_IPS="$(ip -o -4 addr show 2>/dev/null | awk '$2!="lo" {split($4,a,"/"); print a[1]}' | paste -sd, -)"
MACHINE="$(detect_machine "$CURRENT_IPS" "$PF" "$DMZ" "$INT" 2>/dev/null || true)"
[[ -n "$MACHINE" ]] || {
    echo "ERRO: esta máquina não corresponde unicamente aos três IPs da topologia." >&2
    exit 1
}

ROOT="$(ce_require_project_root)"

case "$MACHINE" in
    pfsense)
        cat <<EOF
MAQUINA=CE-PFSENSE
IP=$PF
DOCKER=NÃO_APLICÁVEL
CONTAINERS=NENHUM
AÇÃO=USE_scripts/implantacao/pfsense
EOF
        [[ "$MODE" == plan ]] && exit 0
        echo "ERRO: o despachante de containers não executa containers no pfSense." >&2
        exit 1
        ;;
    interna)
        [[ -n "$CONFIG" ]] || CONFIG="/etc/conectaeduca/vms/interna.env"
        cat <<EOF
MAQUINA=CE-UBUNTU-INT
IP=$INT
CONFIG=$CONFIG
CONTAINERS=MariaDB,Wazuh-Manager,Wazuh-Indexer,Wazuh-Dashboard,OpenBao,Ferret
COMANDO_INTERNO=scripts/implantacao/vms/10-interna/10-preparar-interna-fase1.sh --config $CONFIG --apply --all-services
EOF
        if [[ "$MODE" == plan ]]; then exit 0; fi
        [[ "$(hostname)" == "conectaeduca-interna" ]] || {
            echo "ERRO: hostname não é conectaeduca-interna." >&2; exit 1;
        }
        [[ -r "$CONFIG" ]] || { echo "ERRO: config ausente: $CONFIG" >&2; exit 1; }
        bash "$SCRIPT_DIR/05-preflight-ubuntu.sh" \
            --role interna --stage deploy --config "$CONFIG" --topology "$TOPOLOGY"
        bash "$VMS_DIR/10-interna/10-preparar-interna-fase1.sh" \
            --config "$CONFIG" --apply --all-services
        ;;
    dmz)
        [[ -n "$CONFIG" ]] || CONFIG="/etc/conectaeduca/vms/dmz.env"
        cat <<EOF
MAQUINA=CE-UBUNTU-DMZ
IP=$DMZ
CONFIG=$CONFIG
CONTAINERS=PHP-FPM,Nginx,WAF-ModSecurity-CRS
PRE_REQUISITO=runtime/secrets da DMZ já preparados
COMANDO_INTERNO=scripts/implantacao/vms/20-dmz/22-preparar-dmz-fase1.sh --config $CONFIG --apply
EOF
        if [[ "$MODE" == plan ]]; then exit 0; fi
        [[ "$(hostname)" == "conectaeduca-dmz" ]] || {
            echo "ERRO: hostname não é conectaeduca-dmz." >&2; exit 1;
        }
        [[ -r "$CONFIG" ]] || { echo "ERRO: config ausente: $CONFIG" >&2; exit 1; }
        bash "$SCRIPT_DIR/05-preflight-ubuntu.sh" \
            --role dmz --stage deploy --config "$CONFIG" --topology "$TOPOLOGY"
        bash "$VMS_DIR/20-dmz/20-preparar-segredos-dmz.sh" --config "$CONFIG"
        bash "$VMS_DIR/20-dmz/22-preparar-dmz-fase1.sh" --config "$CONFIG" --apply
        ;;
esac

echo 'DESPACHANTE_CONTAINERS=CONCLUIDO'
