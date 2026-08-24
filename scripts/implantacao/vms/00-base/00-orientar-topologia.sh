#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
VMS_DIR="$(cd -P "$SCRIPT_DIR/.." && pwd -P)"
source "$VMS_DIR/lib/comum.sh"

TOPOLOGY=""
SELF_TEST=0
while (($#)); do
    case "$1" in
        --topology) TOPOLOGY="${2:-}"; shift 2 ;;
        --self-test) SELF_TEST=1; shift ;;
        -h|--help)
            echo "Uso: $0 --topology /etc/conectaeduca/vms/topologia.env"
            exit 0 ;;
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
    if (( hits > 1 )); then printf 'AMBIGUA'; return 2; fi
    if (( hits == 1 )); then printf '%s' "$found"; return 0; fi
    printf 'desconhecida'; return 1
}

if (( SELF_TEST )); then
    [[ "$(detect_machine '192.0.2.1' '192.0.2.1' '192.0.2.10' '192.0.2.20')" == pfsense ]] || exit 1
    [[ "$(detect_machine '192.0.2.10' '192.0.2.1' '192.0.2.10' '192.0.2.20')" == dmz ]] || exit 1
    [[ "$(detect_machine '192.0.2.20' '192.0.2.1' '192.0.2.10' '192.0.2.20')" == interna ]] || exit 1
    set +e
    got="$(detect_machine '192.0.2.10,192.0.2.20' '192.0.2.1' '192.0.2.10' '192.0.2.20')"; rc=$?
    set -e
    [[ "$got" == AMBIGUA && $rc -eq 2 ]] || exit 1
    echo 'SELF_TEST_TOPOLOGIA=APROVADO'
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
[[ -z "$unknown" ]] || { printf 'ERRO: chave inválida na topologia:\n%s\n' "$unknown" >&2; exit 64; }

PF="$(ce_cfg_required CONECTAEDUCA_PFSENSE_IPV4 "$TOPOLOGY")"
DMZ="$(ce_cfg_required CONECTAEDUCA_DMZ_IPV4 "$TOPOLOGY")"
INT="$(ce_cfg_required CONECTAEDUCA_INTERNA_IPV4 "$TOPOLOGY")"
BASE_COMMIT="$(ce_cfg_get CONECTAEDUCA_BASELINE_COMMIT "$TOPOLOGY")"
BASE_TAG="$(ce_cfg_get CONECTAEDUCA_BASELINE_TAG "$TOPOLOGY")"

for ip in "$PF" "$DMZ" "$INT"; do
    ce_valid_ipv4 "$ip" || { echo "ERRO: IPv4 inválido na topologia: $ip" >&2; exit 64; }
done
[[ "$PF" != "$DMZ" && "$PF" != "$INT" && "$DMZ" != "$INT" ]] || {
    echo 'ERRO: os três endereços da topologia devem ser diferentes' >&2
    exit 64
}

CURRENT_IPS="$(ip -o -4 addr show 2>/dev/null | awk '$2!="lo" {split($4,a,"/"); print a[1]}' | paste -sd, -)"
set +e
MACHINE="$(detect_machine "$CURRENT_IPS" "$PF" "$DMZ" "$INT")"; DETECT_RC=$?
set -e

printf '=== ConectaEduca / orientação de topologia ===\n'
printf 'HOSTNAME_ATUAL=%s\n' "$(hostname 2>/dev/null || echo INDETERMINADO)"
printf 'IPV4_ATUAIS=%s\n' "${CURRENT_IPS:-NENHUM}"
printf 'PFSENSE_IPV4=%s\n' "$PF"
printf 'DMZ_IPV4=%s\n' "$DMZ"
printf 'INTERNA_IPV4=%s\n' "$INT"
printf 'BASELINE_COMMIT=%s\n' "${BASE_COMMIT:-NAO_FIXADO}"
printf 'BASELINE_TAG=%s\n' "${BASE_TAG:-NAO_FIXADA}"

if (( DETECT_RC == 2 )); then
    echo 'MAQUINA_DETECTADA=AMBIGUA'
    echo 'ACAO=CORRIGIR_ENDERECAMENTO_ANTES_DE_INSTALAR'
    exit 1
elif (( DETECT_RC != 0 )); then
    echo 'MAQUINA_DETECTADA=NAO_IDENTIFICADA'
    echo 'ACAO=CONFIGURAR_IP_DA_VM_ANTES_DE_INSTALAR'
    exit 1
fi

case "$MACHINE" in
    pfsense)
        cat <<EOF
MAQUINA_DETECTADA=CE-PFSENSE
ROLE=pfsense
IP_ESPERADO=$PF
CONTAINERS_FASE1=NENHUM
ACAO=USAR_SCRIPTS_PFSENSE_NAO_DOCKER
PROXIMO_DIRETORIO=scripts/implantacao/pfsense
EOF
        ;;
    interna)
        cat <<EOF
MAQUINA_DETECTADA=CE-UBUNTU-INT
ROLE=interna
HOSTNAME_ESPERADO=conectaeduca-interna
IP_ESPERADO=$INT
PFSENSE_ESPERADO=$PF
CONFIG_SERVICOS=/etc/conectaeduca/vms/interna.env
HOST_PREREQUISITOS=git,docker-engine,docker-compose-plugin
CONTAINERS_FASE1=MariaDB,Wazuh-Manager,Wazuh-Indexer,Wazuh-Dashboard,OpenBao,Ferret
NATIVO_POSTERIOR=Bacula-File-Daemon
CONTAINERS_BACULA_POSTERIOR=Bacula-Director,Bacula-Storage,Bacula-Catalog
PROXIMO_SCRIPT=scripts/implantacao/vms/00-base/02-configurar-identidade-ubuntu.sh --role interna --check
PROXIMO_DISQUETE=10-interna
EOF
        ;;
    dmz)
        cat <<EOF
MAQUINA_DETECTADA=CE-UBUNTU-DMZ
ROLE=dmz
HOSTNAME_ESPERADO=conectaeduca-dmz
IP_ESPERADO=$DMZ
PFSENSE_ESPERADO=$PF
DB_HOST_ESPERADO=$INT
CONFIG_SERVICOS=/etc/conectaeduca/vms/dmz.env
HOST_PREREQUISITOS=git,docker-engine,docker-compose-plugin
CONTAINERS_FASE1=PHP-FPM,Nginx,WAF-ModSecurity-CRS
NATIVO_POSTERIOR=Bacula-File-Daemon
PROXIMO_SCRIPT=scripts/implantacao/vms/00-base/02-configurar-identidade-ubuntu.sh --role dmz --check
PROXIMO_DISQUETE=20-dmz
EOF
        ;;
esac

echo 'TOPOLOGIA_HOST=APROVADA'
