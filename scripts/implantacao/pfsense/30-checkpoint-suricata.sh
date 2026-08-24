#!/bin/sh
set -u
OUT="${CONECTAEDUCA_EVIDENCE_DIR:-/tmp}/conectaeduca-pfsense-suricata-$(date +%Y%m%d-%H%M%S).txt"
SELF_TEST=0; FAIL=0
while [ "$#" -gt 0 ]; do
 case "$1" in
  --out) [ "$#" -ge 2 ] || exit 2; OUT="$2"; shift 2;;
  --self-test) SELF_TEST=1; shift;;
  -h|--help) echo "Uso: sh 30-checkpoint-suricata.sh [--out ARQUIVO] [--self-test]"; exit 0;;
  *) echo "ERRO: argumento desconhecido: $1" >&2; exit 2;;
 esac
done
if [ "$SELF_TEST" -eq 1 ]; then
 for c in awk date find grep uname; do
  command -v "$c" >/dev/null 2>&1 || { echo "SELF_TEST_SURICATA=FALHA comando=$c" >&2; exit 1; }
 done
 echo "SELF_TEST_SURICATA=APROVADO"; exit 0
fi
[ "$(uname -s 2>/dev/null)" = "FreeBSD" ] || { echo "ERRO: checkpoint operacional deve rodar no pfSense/FreeBSD." >&2; exit 1; }
[ -r /etc/version ] || { echo "ERRO: pfSense não detectado." >&2; exit 1; }
for c in pkg pgrep; do
 command -v "$c" >/dev/null 2>&1 || { echo "ERRO: comando obrigatório ausente no pfSense: $c" >&2; exit 1; }
done
mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
: >"$OUT" || exit 1
log(){ printf '%s\n' "$*"; printf '%s\n' "$*" >>"$OUT" || exit 1; }

log "=== ConectaEduca / Suricata checkpoint ==="
log "data=$(date 2>/dev/null || true)"
log "pfsense_version=$(cat /etc/version 2>/dev/null || echo desconhecida)"
log "modo=SOMENTE_LEITURA"
log "config_xml_lido=NAO"

if pkg info -e pfSense-pkg-suricata >/dev/null 2>&1; then log "SURICATA_PACOTE=INSTALADO"
else log "SURICATA_PACOTE=AUSENTE"; FAIL=1; fi

if pgrep -x suricata >/dev/null 2>&1; then
 COUNT="$(pgrep -x suricata 2>/dev/null | awk 'END{print NR+0}')"
 log "SURICATA_PROCESSOS=$COUNT"; log "SURICATA_SERVICO=ATIVO"
else log "SURICATA_SERVICO=INATIVO"; FAIL=1; fi

CFG_COUNT="$(find /usr/local/etc/suricata -type f -name 'suricata.yaml' 2>/dev/null | awk 'END{print NR+0}')"
log "SURICATA_CONFIGS_DETECTADAS=$CFG_COUNT"
[ "$CFG_COUNT" -gt 0 ] 2>/dev/null || { log "SURICATA_INTERFACE=PENDENTE_OU_NAO_DETECTADA"; FAIL=1; }

LOG_COUNT="$(find /var/log/suricata -type f 2>/dev/null | awk 'END{print NR+0}')"
log "SURICATA_ARQUIVOS_LOG=$LOG_COUNT"
[ "$LOG_COUNT" -gt 0 ] 2>/dev/null || log "AVISO=nenhum log Suricata ainda; gerar tráfego de teste antes da evidência final"

if [ "$FAIL" -eq 0 ]; then log "CHECKPOINT_SURICATA=APROVADO"; RC=0
else log "CHECKPOINT_SURICATA=REPROVADO"; RC=1; fi
log "ARQUIVO_SAIDA=$OUT"
exit "$RC"
