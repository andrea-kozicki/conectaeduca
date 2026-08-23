#!/bin/sh
# ConectaEduca — checkpoint de interfaces pfSense v2 (somente leitura)
set -u

CONFIG="${CONECTAEDUCA_PFSENSE_ENV:-/tmp/conectaeduca-pfsense.env}"
OUTDIR="${CONECTAEDUCA_EVIDENCE_DIR:-/tmp}"
OUT=""
SELF_TEST=0

usage() {
    cat <<'EOF'
Uso:
  sh 10-checkpoint-interfaces.sh [--config ARQUIVO] [--out ARQUIVO] [--self-test]

O arquivo de configuração contém SOMENTE parâmetros de rede não secretos.

Obrigatórios para aprovação:
  PFSENSE_WAN_IF
  PFSENSE_DMZ_IF
  PFSENSE_INTERNA_IF
  PFSENSE_WAN_IP
  PFSENSE_DMZ_IP
  PFSENSE_INTERNA_IP
  WAN_GATEWAY

Opcionais nesta etapa:
  VM_DMZ_IP
  VM_INTERNA_IP

Os IPs acima devem ser IPv4 sem /CIDR.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --config)
            [ "$#" -ge 2 ] || { echo "ERRO: --config exige caminho." >&2; exit 2; }
            CONFIG="$2"; shift 2 ;;
        --out)
            [ "$#" -ge 2 ] || { echo "ERRO: --out exige caminho." >&2; exit 2; }
            OUT="$2"; shift 2 ;;
        --self-test)
            SELF_TEST=1; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "ERRO: argumento desconhecido: $1" >&2
            usage >&2
            exit 2 ;;
    esac
done

if [ "$SELF_TEST" -eq 1 ]; then
    for cmd in awk grep sed; do
        command -v "$cmd" >/dev/null 2>&1 || {
            echo "SELF_TEST_INTERFACES=FALHA comando=$cmd" >&2
            exit 1
        }
    done
    echo "SELF_TEST_INTERFACES=APROVADO"
    exit 0
fi

for cmd in awk date dirname grep hostname ifconfig mkdir route sed tail; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "ERRO: comando obrigatório ausente no host alvo: $cmd" >&2
        exit 1
    }
done

[ -r "$CONFIG" ] || {
    echo "ERRO: configuração não encontrada: $CONFIG" >&2
    exit 1
}

read_cfg() {
    key="$1"
    line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$CONFIG" 2>/dev/null | tail -n 1)"
    [ -n "$line" ] || { printf '%s' ""; return 0; }
    value="${line#*=}"
    value="$(printf '%s' "$value" | sed \
        -e 's/^[[:space:]]*//' \
        -e 's/[[:space:]]*$//' \
        -e "s/^'//" -e "s/'$//" \
        -e 's/^"//' -e 's/"$//')"
    case "$value" in
        *[!A-Za-z0-9._:/-]*)
            echo "ERRO: valor inválido para $key no arquivo de configuração." >&2
            return 1 ;;
    esac
    printf '%s' "$value"
}

valid_iface() {
    value="$1"
    case "$value" in
        ""|-*|*[!A-Za-z0-9._]*)
            return 1 ;;
        *)
            return 0 ;;
    esac
}

valid_ipv4() {
    printf '%s\n' "$1" | awk -F. '
        NF != 4 { bad = 1 }
        {
            for (i = 1; i <= 4; i++) {
                if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) bad = 1
            }
        }
        END { exit bad ? 1 : 0 }
    '
}

PFSENSE_WAN_IF="$(read_cfg PFSENSE_WAN_IF)" || exit 1
PFSENSE_DMZ_IF="$(read_cfg PFSENSE_DMZ_IF)" || exit 1
PFSENSE_INTERNA_IF="$(read_cfg PFSENSE_INTERNA_IF)" || exit 1
PFSENSE_WAN_IP="$(read_cfg PFSENSE_WAN_IP)" || exit 1
PFSENSE_DMZ_IP="$(read_cfg PFSENSE_DMZ_IP)" || exit 1
PFSENSE_INTERNA_IP="$(read_cfg PFSENSE_INTERNA_IP)" || exit 1
WAN_GATEWAY="$(read_cfg WAN_GATEWAY)" || exit 1
VM_DMZ_IP="$(read_cfg VM_DMZ_IP)" || exit 1
VM_INTERNA_IP="$(read_cfg VM_INTERNA_IP)" || exit 1

for pair in \
    "PFSENSE_WAN_IF:$PFSENSE_WAN_IF" \
    "PFSENSE_DMZ_IF:$PFSENSE_DMZ_IF" \
    "PFSENSE_INTERNA_IF:$PFSENSE_INTERNA_IF"
do
    key="${pair%%:*}"
    value="${pair#*:}"
    [ -n "$value" ] || { echo "ERRO: defina $key" >&2; exit 1; }
    valid_iface "$value" || { echo "ERRO: interface inválida em $key: $value" >&2; exit 1; }
done

for pair in \
    "PFSENSE_WAN_IP:$PFSENSE_WAN_IP" \
    "PFSENSE_DMZ_IP:$PFSENSE_DMZ_IP" \
    "PFSENSE_INTERNA_IP:$PFSENSE_INTERNA_IP" \
    "WAN_GATEWAY:$WAN_GATEWAY"
do
    key="${pair%%:*}"
    value="${pair#*:}"
    [ -n "$value" ] || { echo "ERRO: defina $key" >&2; exit 1; }
    valid_ipv4 "$value" || { echo "ERRO: IPv4 inválido em $key: $value" >&2; exit 1; }
done

if [ "$PFSENSE_WAN_IF" = "$PFSENSE_DMZ_IF" ] || \
   [ "$PFSENSE_WAN_IF" = "$PFSENSE_INTERNA_IF" ] || \
   [ "$PFSENSE_DMZ_IF" = "$PFSENSE_INTERNA_IF" ]; then
    echo "ERRO: WAN, DMZ e INTERNA devem usar interfaces distintas." >&2
    exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
[ -n "$OUT" ] || OUT="$OUTDIR/conectaeduca-pfsense-interfaces-$STAMP.txt"
mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
: > "$OUT" || { echo "ERRO: não foi possível criar $OUT" >&2; exit 1; }

log() {
    printf '%s\n' "$*"
    printf '%s\n' "$*" >>"$OUT" || {
        printf '%s\n' "ERRO: falha ao gravar evidência em $OUT" >&2
        exit 1
    }
}

get_ipv4() {
    ifconfig "$1" 2>/dev/null | awk '/^[[:space:]]*inet[[:space:]]/ {print $2; exit}'
}

check_if() {
    role="$1"
    iface="$2"
    expected="$3"

    if ! ifconfig "$iface" >/dev/null 2>&1; then
        log "FALHA $role interface=$iface inexistente"
        return 1
    fi

    actual="$(get_ipv4 "$iface")"
    if [ -z "$actual" ]; then
        log "FALHA $role interface=$iface ipv4=ausente"
        return 1
    fi

    log "OK $role interface=$iface ipv4=$actual"

    if [ -n "$expected" ] && [ "$actual" != "$expected" ]; then
        log "FALHA $role ipv4_esperado=$expected ipv4_atual=$actual"
        return 1
    fi
    return 0
}

log "=== ConectaEduca / checkpoint interfaces pfSense v2 ==="
log "data=$(date 2>/dev/null || true)"
log "host=$(hostname 2>/dev/null || echo desconhecido)"
log "config=$CONFIG"
log "modo=SOMENTE_LEITURA"
log "config_executado_como_shell=NAO"

FAIL=0
check_if WAN "$PFSENSE_WAN_IF" "$PFSENSE_WAN_IP" || FAIL=1
check_if DMZ "$PFSENSE_DMZ_IF" "$PFSENSE_DMZ_IP" || FAIL=1
check_if INTERNA "$PFSENSE_INTERNA_IF" "$PFSENSE_INTERNA_IP" || FAIL=1

ROUTE_INFO="$(route -n get 8.8.8.8 2>/dev/null)"
ROUTE_RC=$?
DEFAULT_GW="$(printf '%s\n' "$ROUTE_INFO" | awk '/gateway:/ {print $2; exit}')"
DEFAULT_IF="$(printf '%s\n' "$ROUTE_INFO" | awk '/interface:/ {print $2; exit}')"

if [ "$ROUTE_RC" -ne 0 ] || [ -z "$DEFAULT_GW" ]; then
    log "FALHA rota_externa=ausente"
    FAIL=1
else
    log "OK default_gateway=$DEFAULT_GW"
fi

if [ -n "$DEFAULT_IF" ]; then
    log "default_route_interface=$DEFAULT_IF"
    if [ "$DEFAULT_IF" != "$PFSENSE_WAN_IF" ]; then
        log "FALHA interface_rota_default_esperada=$PFSENSE_WAN_IF interface_atual=$DEFAULT_IF"
        FAIL=1
    fi
else
    log "FALHA interface_rota_default=ausente"
    FAIL=1
fi

if [ -n "$WAN_GATEWAY" ] && [ "$DEFAULT_GW" != "$WAN_GATEWAY" ]; then
    log "FALHA gateway_esperado=$WAN_GATEWAY gateway_atual=$DEFAULT_GW"
    FAIL=1
fi

log "vm_dmz_ip=${VM_DMZ_IP:-NAO_DEFINIDO}"
log "vm_interna_ip=${VM_INTERNA_IP:-NAO_DEFINIDO}"
log "SEGMENTACAO_VALIDADA=NAO"
log "OBSERVACAO=segmentacao exige regras no pfSense e testes originados das VMs"

if [ "$FAIL" -eq 0 ]; then
    log "CHECKPOINT_PFSENSE_INTERFACES=APROVADO"
    RC=0
else
    log "CHECKPOINT_PFSENSE_INTERFACES=REPROVADO"
    RC=1
fi

log "ARQUIVO_SAIDA=$OUT"
exit "$RC"
