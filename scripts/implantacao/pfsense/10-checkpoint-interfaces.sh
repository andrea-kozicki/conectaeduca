#!/bin/sh
# ConectaEduca — checkpoint de interfaces pfSense (somente leitura)
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
Obrigatórios:
  PFSENSE_WAN_IF
  PFSENSE_DMZ_IF
  PFSENSE_INTERNA_IF

Opcionais:
  PFSENSE_WAN_IP
  PFSENSE_DMZ_IP
  PFSENSE_INTERNA_IP
  WAN_GATEWAY
  VM_DMZ_IP
  VM_INTERNA_IP
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
    echo "SELF_TEST_INTERFACES=APROVADO"
    exit 0
fi

[ -r "$CONFIG" ] || {
    echo "ERRO: configuração não encontrada: $CONFIG" >&2
    echo "Copie pfsense-rede.env.example para /tmp/conectaeduca-pfsense.env e preencha os dados fornecidos pelo laboratório." >&2
    exit 1
}

# shellcheck disable=SC1090
. "$CONFIG"

: "${PFSENSE_WAN_IF:?defina PFSENSE_WAN_IF}"
: "${PFSENSE_DMZ_IF:?defina PFSENSE_DMZ_IF}"
: "${PFSENSE_INTERNA_IF:?defina PFSENSE_INTERNA_IF}"

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

log() { printf '%s\n' "$*" | tee -a "$OUT"; }

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

log "=== ConectaEduca / checkpoint interfaces pfSense ==="
log "data=$(date 2>/dev/null || true)"
log "host=$(hostname 2>/dev/null || echo desconhecido)"
log "config=$CONFIG"
log "modo=SOMENTE_LEITURA"

FAIL=0
check_if WAN "$PFSENSE_WAN_IF" "${PFSENSE_WAN_IP:-}" || FAIL=1
check_if DMZ "$PFSENSE_DMZ_IF" "${PFSENSE_DMZ_IP:-}" || FAIL=1
check_if INTERNA "$PFSENSE_INTERNA_IF" "${PFSENSE_INTERNA_IP:-}" || FAIL=1

DEFAULT_GW="$(route -n get default 2>/dev/null | awk '/gateway:/ {print $2; exit}')"
DEFAULT_IF="$(route -n get default 2>/dev/null | awk '/interface:/ {print $2; exit}')"

if [ -n "$DEFAULT_GW" ]; then
    log "OK default_gateway=$DEFAULT_GW"
else
    log "FALHA default_gateway=ausente"
    FAIL=1
fi

[ -n "$DEFAULT_IF" ] && log "default_route_interface=$DEFAULT_IF"

if [ -n "${WAN_GATEWAY:-}" ] && [ "$DEFAULT_GW" != "$WAN_GATEWAY" ]; then
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
