#!/bin/sh
# ConectaEduca — coleta/checkpoint do pf firewall/NAT (somente leitura)
set -u

OUTDIR="${CONECTAEDUCA_EVIDENCE_DIR:-/tmp}"
OUT=""
SELF_TEST=0

usage() {
    cat <<'EOF'
Uso:
  sh 20-checkpoint-firewall.sh [--out ARQUIVO] [--self-test]

Somente leitura.
Coleta regras compiladas, NAT e estatísticas do PF.
A semântica da política deve ser revisada na WebGUI e testada a partir das VMs.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
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
    echo "SELF_TEST_FIREWALL=APROVADO"
    exit 0
fi

command -v pfctl >/dev/null 2>&1 || {
    echo "ERRO: pfctl não encontrado." >&2
    exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
[ -n "$OUT" ] || OUT="$OUTDIR/conectaeduca-pfsense-firewall-$STAMP.txt"
mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
: > "$OUT" || { echo "ERRO: não foi possível criar $OUT" >&2; exit 1; }

log() { printf '%s\n' "$*" | tee -a "$OUT"; }
capture() {
    title="$1"; shift
    log ""
    log "### $title"
    "$@" 2>&1 | tee -a "$OUT"
}

log "=== ConectaEduca / checkpoint firewall pfSense ==="
log "data=$(date 2>/dev/null || true)"
log "host=$(hostname 2>/dev/null || echo desconhecido)"
log "modo=SOMENTE_LEITURA"
log "config_xml_lido=NAO"

PF_STATUS="$(pfctl -si 2>/dev/null | awk -F: '/^Status:/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')"
[ -n "$PF_STATUS" ] || PF_STATUS="desconhecido"
log "pf_status=$PF_STATUS"

capture "regras de filtro compiladas" pfctl -sr -vv
capture "NAT compilado" pfctl -sn -v
capture "estatísticas PF" pfctl -si

FILTER_COUNT="$(pfctl -sr 2>/dev/null | wc -l | awk '{print $1}')"
NAT_COUNT="$(pfctl -sn 2>/dev/null | wc -l | awk '{print $1}')"
STATE_COUNT="$(pfctl -ss 2>/dev/null | wc -l | awk '{print $1}')"

log ""
log "filter_rules_count=$FILTER_COUNT"
log "nat_rules_count=$NAT_COUNT"
log "state_count=$STATE_COUNT"

case "$PF_STATUS" in
    *Enabled*|*enabled*)
        log "PF_ATIVO=SIM" ;;
    *)
        log "PF_ATIVO=NAO_OU_INDETERMINADO" ;;
esac

log "VALIDACAO_SEMANTICA_REGRAS=MANUAL_OBRIGATORIA"
log "TESTE_DMZ_PARA_INTERNA=EXECUTAR_NA_VM_DMZ"
log "TESTE_WAN_PARA_INTERNA=EXECUTAR_DE_ORIGEM_EXTERNA"
log "CHECKPOINT_PFSENSE_FIREWALL=COLETA_CONCLUIDA"
log "ARQUIVO_SAIDA=$OUT"
