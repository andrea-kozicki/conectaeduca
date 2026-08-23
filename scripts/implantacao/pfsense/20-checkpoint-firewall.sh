#!/bin/sh
# ConectaEduca — checkpoint firewall/NAT pfSense v2 (somente leitura)
set -u

OUTDIR="${CONECTAEDUCA_EVIDENCE_DIR:-/tmp}"
OUT=""
SELF_TEST=0
FAIL=0

usage() {
    cat <<'EOF'
Uso:
  sh 20-checkpoint-firewall.sh [--out ARQUIVO] [--self-test]

Somente leitura. Coleta regras compiladas, NAT e estado do PF.
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
    for cmd in awk sed; do
        command -v "$cmd" >/dev/null 2>&1 || {
            echo "SELF_TEST_FIREWALL=FALHA comando=$cmd" >&2
            exit 1
        }
    done
    echo "SELF_TEST_FIREWALL=APROVADO"
    exit 0
fi

for cmd in awk cat date dirname hostname mkdir pfctl rm wc; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "ERRO: comando obrigatório ausente no host alvo: $cmd" >&2
        exit 1
    }
done

STAMP="$(date +%Y%m%d-%H%M%S)"
[ -n "$OUT" ] || OUT="$OUTDIR/conectaeduca-pfsense-firewall-$STAMP.txt"
mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
: > "$OUT" || { echo "ERRO: não foi possível criar $OUT" >&2; exit 1; }

log() {
    printf '%s\n' "$*"
    printf '%s\n' "$*" >>"$OUT" || {
        printf '%s\n' "ERRO: falha ao gravar evidência em $OUT" >&2
        exit 1
    }
}

capture_required() {
    title="$1"; shift
    tmp="${OUT}.cmd.$$"
    log ""
    log "### $title"
    if "$@" >"$tmp" 2>&1; then
        cat "$tmp"
        cat "$tmp" >>"$OUT" || {
            rm -f "$tmp"
            printf '%s\n' "ERRO: falha ao gravar evidência em $OUT" >&2
            exit 1
        }
        rm -f "$tmp"
        return 0
    else
        rc=$?
        cat "$tmp"
        cat "$tmp" >>"$OUT" || {
            rm -f "$tmp"
            printf '%s\n' "ERRO: falha ao gravar evidência em $OUT" >&2
            exit 1
        }
        rm -f "$tmp"
        log "FALHA comando=$* rc=$rc"
        FAIL=1
        return "$rc"
    fi
}

log "=== ConectaEduca / checkpoint firewall pfSense v2 ==="
log "data=$(date 2>/dev/null || true)"
log "host=$(hostname 2>/dev/null || echo desconhecido)"
log "modo=SOMENTE_LEITURA"
log "config_xml_lido=NAO"

PF_INFO="$(pfctl -si 2>/dev/null)"
PF_RC=$?
PF_STATUS="$(printf '%s\n' "$PF_INFO" | awk -F: '/^Status:/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')"

if [ "$PF_RC" -ne 0 ]; then
    log "FALHA pfctl_status_rc=$PF_RC"
    FAIL=1
fi

[ -n "$PF_STATUS" ] || PF_STATUS="desconhecido"
log "pf_status=$PF_STATUS"

capture_required "regras de filtro compiladas" pfctl -vvsr || true
capture_required "NAT compilado" pfctl -sn || true
capture_required "estatísticas PF" pfctl -si || true

if FILTER_RAW="$(pfctl -sr 2>/dev/null)"; then
    FILTER_COUNT="$(printf '%s\n' "$FILTER_RAW" | awk 'NF {n++} END {print n+0}')"
else
    FILTER_COUNT="INDETERMINADO"
    FAIL=1
fi

if NAT_RAW="$(pfctl -sn 2>/dev/null)"; then
    NAT_COUNT="$(printf '%s\n' "$NAT_RAW" | awk 'NF {n++} END {print n+0}')"
else
    NAT_COUNT="INDETERMINADO"
    FAIL=1
fi

if STATE_RAW="$(pfctl -ss 2>/dev/null)"; then
    STATE_COUNT="$(printf '%s\n' "$STATE_RAW" | awk 'NF {n++} END {print n+0}')"
else
    STATE_COUNT="INDETERMINADO"
    FAIL=1
fi

log ""
log "filter_rules_count=$FILTER_COUNT"
log "nat_rules_count=$NAT_COUNT"
log "state_count=$STATE_COUNT"

case "$PF_STATUS" in
    Enabled*|enabled*)
        log "PF_ATIVO=SIM" ;;
    *)
        log "PF_ATIVO=NAO_OU_INDETERMINADO"
        FAIL=1 ;;
esac

log "VALIDACAO_SEMANTICA_REGRAS=MANUAL_OBRIGATORIA"
log "TESTE_DMZ_PARA_INTERNA=EXECUTAR_NA_VM_DMZ"
log "TESTE_WAN_PARA_INTERNA=EXECUTAR_DE_ORIGEM_EXTERNA"

if [ "$FAIL" -eq 0 ]; then
    log "CHECKPOINT_PFSENSE_FIREWALL=COLETA_APROVADA"
    RC=0
else
    log "CHECKPOINT_PFSENSE_FIREWALL=COLETA_REPROVADA"
    RC=1
fi
log "ARQUIVO_SAIDA=$OUT"
exit "$RC"
