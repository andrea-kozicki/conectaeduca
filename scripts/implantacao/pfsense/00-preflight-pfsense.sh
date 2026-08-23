#!/bin/sh
# ConectaEduca — pfSense preflight (somente leitura)
set -u

OUTDIR="${CONECTAEDUCA_EVIDENCE_DIR:-/tmp}"
OUT=""
SELF_TEST=0

usage() {
    cat <<'EOF'
Uso:
  sh 00-preflight-pfsense.sh [--out ARQUIVO] [--self-test]

Somente leitura. Não altera config.xml, interfaces, firewall, NAT, SSH ou pacotes.
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
    command -v awk >/dev/null 2>&1 || exit 1
    command -v sed >/dev/null 2>&1 || exit 1
    command -v grep >/dev/null 2>&1 || exit 1
    echo "SELF_TEST_PREFLIGHT=APROVADO"
    exit 0
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
[ -n "$OUT" ] || OUT="$OUTDIR/conectaeduca-pfsense-preflight-$STAMP.txt"
mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
: > "$OUT" || { echo "ERRO: não foi possível criar $OUT" >&2; exit 1; }

log() {
    printf '%s\n' "$*" | tee -a "$OUT"
}

capture() {
    title="$1"; shift
    log ""
    log "### $title"
    if command -v "$1" >/dev/null 2>&1; then
        "$@" 2>&1 | tee -a "$OUT"
    else
        log "INFO: comando ausente: $1"
    fi
}

log "=== ConectaEduca / pfSense preflight ==="
log "data=$(date 2>/dev/null || true)"
log "host=$(hostname 2>/dev/null || echo desconhecido)"
log "uid=$(id -u 2>/dev/null || echo desconhecido)"
log "modo=SOMENTE_LEITURA"
log "config_xml_lido=NAO"
log "config_xml_alterado=NAO"

OS="$(uname -s 2>/dev/null || echo desconhecido)"
log "os=$OS"

if [ -r /etc/version ]; then
    log "pfsense_version=$(cat /etc/version 2>/dev/null)"
else
    log "pfsense_version=NAO_DETECTADA"
fi

MISSING=""
for cmd in ifconfig netstat route pfctl sysctl df awk grep sed; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING="$MISSING $cmd"
    fi
done

if [ -n "$MISSING" ]; then
    log "FALHA comandos_essenciais_ausentes=$MISSING"
    log "PREFLIGHT_PFSENSE=REPROVADO"
    log "ARQUIVO_SAIDA=$OUT"
    exit 1
fi

capture "interfaces resumidas" ifconfig -l
capture "interfaces detalhadas" ifconfig
capture "rota default" route -n get default
capture "tabela IPv4" netstat -rn -f inet
capture "estado do packet filter" pfctl -si
capture "memória física" sysctl hw.physmem
capture "disco" df -h

log ""
log "### DNS (sem exibir outros arquivos de configuração)"
if [ -r /etc/resolv.conf ]; then
    grep -E '^[[:space:]]*(nameserver|search|domain)[[:space:]]' /etc/resolv.conf 2>/dev/null \
        | tee -a "$OUT"
else
    log "INFO: /etc/resolv.conf indisponível"
fi

IFCOUNT="$(ifconfig -l 2>/dev/null | awk '{print NF}')"
log ""
log "interfaces_detectadas=$IFCOUNT"
if [ "$IFCOUNT" -lt 4 ] 2>/dev/null; then
    log "AVISO: menos de 4 interfaces contando loopback; conferir se a VM possui NICs suficientes para WAN/DMZ/INTERNA."
fi

if [ "$OS" != "FreeBSD" ]; then
    log "AVISO: host não identificado como FreeBSD; este script foi preparado para pfSense."
fi

log "PREFLIGHT_PFSENSE=APROVADO"
log "ARQUIVO_SAIDA=$OUT"
