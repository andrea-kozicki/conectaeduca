#!/bin/sh
# ConectaEduca — pfSense preflight v2 (somente leitura)
set -u

OUTDIR="${CONECTAEDUCA_EVIDENCE_DIR:-/tmp}"
OUT=""
SELF_TEST=0
FAIL=0

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
    for cmd in awk grep sed; do
        command -v "$cmd" >/dev/null 2>&1 || {
            echo "SELF_TEST_PREFLIGHT=FALHA comando=$cmd" >&2
            exit 1
        }
    done
    echo "SELF_TEST_PREFLIGHT=APROVADO"
    exit 0
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
[ -n "$OUT" ] || OUT="$OUTDIR/conectaeduca-pfsense-preflight-$STAMP.txt"
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

log "=== ConectaEduca / pfSense preflight v2 ==="
log "data=$(date 2>/dev/null || true)"
log "host=$(hostname 2>/dev/null || echo desconhecido)"
UID_NOW="$(id -u 2>/dev/null || echo desconhecido)"
log "uid=$UID_NOW"
log "modo=SOMENTE_LEITURA"
log "config_xml_lido=NAO"
log "config_xml_alterado=NAO"

OS="$(uname -s 2>/dev/null || echo desconhecido)"
log "os=$OS"

if [ -r /etc/version ]; then
    log "pfsense_version=$(cat /etc/version 2>/dev/null)"
else
    log "pfsense_version=NAO_DETECTADA"
    FAIL=1
fi

MISSING=""
for cmd in awk cat date df dirname grep hostname id ifconfig mkdir netstat pfctl rm route sed sysctl uname; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING="$MISSING $cmd"
    fi
done

if [ -n "$MISSING" ]; then
    log "FALHA comandos_essenciais_ausentes=$MISSING"
    FAIL=1
fi

if [ "$OS" != "FreeBSD" ]; then
    log "FALHA host_alvo=NAO_FREEBSD"
    FAIL=1
fi

if [ "$UID_NOW" != "0" ]; then
    log "FALHA privilegio=execute a coleta operacional como root/admin no console do pfSense"
    FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
    capture_required "interfaces resumidas" ifconfig -l || true
    capture_required "interfaces detalhadas" ifconfig || true
    capture_required "rota externa de referência" route -n get 8.8.8.8 || true
    capture_required "tabela de rotas" netstat -rWn || true
    capture_required "estado do packet filter" pfctl -si || true
    capture_required "memória física" sysctl hw.physmem || true
    capture_required "disco" df -h || true
fi

log ""
log "### DNS (sem exibir outros arquivos de configuração)"
if command -v grep >/dev/null 2>&1 && [ -r /etc/resolv.conf ]; then
    DNS_INFO="$(grep -E '^[[:space:]]*(nameserver|search|domain)[[:space:]]' /etc/resolv.conf 2>/dev/null || true)"
    if [ -n "$DNS_INFO" ]; then
        printf '%s\n' "$DNS_INFO"
        printf '%s\n' "$DNS_INFO" >>"$OUT" || exit 1
    else
        log "INFO: nenhum nameserver/search/domain encontrado"
    fi
else
    log "INFO: DNS não coletado"
fi

IFCOUNT=""
if command -v ifconfig >/dev/null 2>&1 && command -v awk >/dev/null 2>&1; then
    IFCOUNT="$(ifconfig -l 2>/dev/null | awk '{print NF}')"
fi
log ""
log "interfaces_detectadas=${IFCOUNT:-INDETERMINADO}"
if [ -n "$IFCOUNT" ] && [ "$IFCOUNT" -lt 4 ] 2>/dev/null; then
    log "AVISO: menos de 4 interfaces contando loopback; conferir NICs de WAN/DMZ/INTERNA."
fi

if [ "$FAIL" -eq 0 ]; then
    log "PREFLIGHT_PFSENSE=APROVADO"
    RC=0
else
    log "PREFLIGHT_PFSENSE=REPROVADO"
    RC=1
fi
log "ARQUIVO_SAIDA=$OUT"
exit "$RC"
