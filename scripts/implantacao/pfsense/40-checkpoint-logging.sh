#!/bin/sh
set -u
OUT="${CONECTAEDUCA_EVIDENCE_DIR:-/tmp}/conectaeduca-pfsense-logging-$(date +%Y%m%d-%H%M%S).txt"
SELF_TEST=0; FAIL=0
while [ "$#" -gt 0 ]; do
 case "$1" in
  --out) [ "$#" -ge 2 ] || exit 2; OUT="$2"; shift 2;;
  --self-test) SELF_TEST=1; shift;;
  -h|--help) echo "Uso: sh 40-checkpoint-logging.sh [--out ARQUIVO] [--self-test]"; exit 0;;
  *) echo "ERRO: argumento desconhecido: $1" >&2; exit 2;;
 esac
done
if [ "$SELF_TEST" -eq 1 ]; then
 for c in date find uname; do
  command -v "$c" >/dev/null 2>&1 || { echo "SELF_TEST_LOGGING=FALHA comando=$c" >&2; exit 1; }
 done
 echo "SELF_TEST_LOGGING=APROVADO"; exit 0
fi
[ "$(uname -s 2>/dev/null)" = "FreeBSD" ] || { echo "ERRO: checkpoint operacional deve rodar no pfSense/FreeBSD." >&2; exit 1; }
[ -r /etc/version ] || { echo "ERRO: pfSense não detectado." >&2; exit 1; }
mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
: >"$OUT" || exit 1
log(){ printf '%s\n' "$*"; printf '%s\n' "$*" >>"$OUT" || exit 1; }

log "=== ConectaEduca / logging pfSense + Suricata ==="
log "data=$(date 2>/dev/null || true)"
log "modo=SOMENTE_LEITURA"
log "config_xml_lido=NAO"
log "logs_brutos_copiados=NAO"

PF_LOGS=0
for f in /var/log/system.log /var/log/filter.log; do
 if [ -e "$f" ]; then PF_LOGS=$((PF_LOGS+1)); log "LOG_PFSENSE_PRESENTE=$f"; fi
done
[ "$PF_LOGS" -gt 0 ] 2>/dev/null || { log "LOG_PFSENSE_PADRAO=NAO_DETECTADO"; FAIL=1; }

SUR_DIRS="$(find /var/log/suricata -type d 2>/dev/null | awk 'END{print NR+0}')"
SUR_FILES="$(find /var/log/suricata -type f 2>/dev/null | awk 'END{print NR+0}')"
log "SURICATA_LOG_DIRS=$SUR_DIRS"; log "SURICATA_LOG_FILES=$SUR_FILES"
[ "$SUR_DIRS" -gt 0 ] 2>/dev/null || { log "SURICATA_LOGGING=NAO_DETECTADO"; FAIL=1; }

log "WAZUH_FORWARDING=ADIADO_ATE_RECEPTOR_SYSLOG_SER_DEFINIDO"
log "SYSLOG_NG_EXTRA=NAO_NECESSARIO_NESTA_FASE"

if [ "$FAIL" -eq 0 ]; then log "CHECKPOINT_LOGGING=APROVADO"; RC=0
else log "CHECKPOINT_LOGGING=REPROVADO"; RC=1; fi
log "ARQUIVO_SAIDA=$OUT"
exit "$RC"
