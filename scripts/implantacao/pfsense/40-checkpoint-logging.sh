#!/bin/sh
set -u

OUT="${CONECTAEDUCA_EVIDENCE_DIR:-/tmp}/conectaeduca-pfsense-logging-$(date +%Y%m%d-%H%M%S).txt"
SELF_TEST=0
FAIL=0
WAZUH_HOST="${CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS:-192.168.6.50}"
WAZUH_PORT="${CONECTAEDUCA_WAZUH_SYSLOG_PORT:-5514}"

usage() {
 cat <<'EOF'
Uso:
  sh 40-checkpoint-logging.sh [--out ARQUIVO] [--wazuh-host HOST] [--wazuh-port PORTA] [--self-test]

Somente leitura. O checkpoint não lê /conf/config.xml nem copia payloads de log.
Por padrão, o destino esperado vem de:
  CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS (default 192.168.6.50)
  CONECTAEDUCA_WAZUH_SYSLOG_PORT (default 5514)
EOF
}

while [ "$#" -gt 0 ]; do
 case "$1" in
  --out) [ "$#" -ge 2 ] || exit 2; OUT="$2"; shift 2;;
  --wazuh-host) [ "$#" -ge 2 ] || exit 2; WAZUH_HOST="$2"; shift 2;;
  --wazuh-port) [ "$#" -ge 2 ] || exit 2; WAZUH_PORT="$2"; shift 2;;
  --self-test) SELF_TEST=1; shift;;
  -h|--help) usage; exit 0;;
  *) echo "ERRO: argumento desconhecido: $1" >&2; usage >&2; exit 2;;
 esac
done

case "$WAZUH_HOST" in
 ""|*[!A-Za-z0-9._:-]*) echo "ERRO: host Wazuh inválido." >&2; exit 2;;
esac
case "$WAZUH_PORT" in
 ""|*[!0-9]*) echo "ERRO: porta Wazuh inválida." >&2; exit 2;;
esac
[ "$WAZUH_PORT" -ge 1 ] 2>/dev/null && [ "$WAZUH_PORT" -le 65535 ] 2>/dev/null || {
 echo "ERRO: porta Wazuh fora do intervalo 1..65535." >&2
 exit 2
}

# Aceita apenas uma diretiva ativa com o alvo exato. Linhas comentadas e
# ocorrências com porta prefix-sharing (ex.: 55140 para alvo 5514) são rejeitadas.
# Também rejeita @@host:port, pois o runtime esperado nesta fase é UDP (@).
has_active_forward_target() {
 awk -v target="@${WAZUH_HOST}:${WAZUH_PORT}" '
 {
   line=$0
   sub(/^[[:space:]]*/, "", line)
   if (line == "" || substr(line,1,1) == "#") next
   hash=index(line,"#")
   if (hash > 0) line=substr(line,1,hash-1)
   pos=index(line,target)
   if (pos == 0) next
   before=(pos > 1 ? substr(line,pos-1,1) : "")
   after=substr(line,pos+length(target),1)
   if ((pos == 1 || before ~ /[[:space:]]/) &&
       (after == "" || after ~ /[[:space:];,]/)) {
     found=1
     exit
   }
 }
 END { exit(found ? 0 : 1) }
 ' "$@"
}

if [ "$SELF_TEST" -eq 1 ]; then
 for c in awk date find grep ps uname; do
  command -v "$c" >/dev/null 2>&1 || { echo "SELF_TEST_LOGGING=FALHA comando=$c" >&2; exit 1; }
 done
 printf '%s\n' "# *.* @${WAZUH_HOST}:${WAZUH_PORT}" | has_active_forward_target && {
  echo "SELF_TEST_LOGGING=FALHA comentario_aceito" >&2; exit 1;
 }
 printf '%s\n' "*.* @${WAZUH_HOST}:${WAZUH_PORT}0" | has_active_forward_target && {
  echo "SELF_TEST_LOGGING=FALHA porta_prefixo_aceita" >&2; exit 1;
 }
 printf '%s\n' "*.* @@${WAZUH_HOST}:${WAZUH_PORT}" | has_active_forward_target && {
  echo "SELF_TEST_LOGGING=FALHA tcp_double_at_aceito" >&2; exit 1;
 }
 printf '%s\n' "*.* @${WAZUH_HOST}:${WAZUH_PORT}" | has_active_forward_target || {
  echo "SELF_TEST_LOGGING=FALHA diretiva_exata_rejeitada" >&2; exit 1;
 }
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
log "WAZUH_DESTINO_ESPERADO=${WAZUH_HOST}:${WAZUH_PORT}"

PF_LOGS=0
for f in /var/log/system.log /var/log/filter.log; do
 if [ -e "$f" ]; then PF_LOGS=$((PF_LOGS+1)); log "LOG_PFSENSE_PRESENTE=$f"; fi
done
[ "$PF_LOGS" -gt 0 ] 2>/dev/null || { log "LOG_PFSENSE_PADRAO=NAO_DETECTADO"; FAIL=1; }

SUR_DIRS="$(find /var/log/suricata -type d 2>/dev/null | awk 'END{print NR+0}')"
SUR_FILES="$(find /var/log/suricata -type f 2>/dev/null | awk 'END{print NR+0}')"
log "SURICATA_LOG_DIRS=$SUR_DIRS"; log "SURICATA_LOG_FILES=$SUR_FILES"
[ "$SUR_DIRS" -gt 0 ] 2>/dev/null || { log "SURICATA_LOGGING=NAO_DETECTADO"; FAIL=1; }

# O pfSense gera arquivos runtime a partir de /conf/config.xml. Este checkpoint
# não lê config.xml; ele verifica somente o estado já renderizado para o daemon.
if ps ax -o command= 2>/dev/null | grep -E '[s]yslogd|[s]yslog-ng' >/dev/null 2>&1; then
 log "SYSLOG_DAEMON=ATIVO"
else
 log "SYSLOG_DAEMON=NAO_DETECTADO"
 FAIL=1
fi

FORWARD_CFG=""
for f in /etc/syslog.conf /var/etc/syslog.conf /var/etc/syslog-ng.conf /var/etc/syslog.d/*.conf; do
 [ -r "$f" ] || continue
 if has_active_forward_target "$f" 2>/dev/null; then
  FORWARD_CFG="$f"
  break
 fi
done

if [ -n "$FORWARD_CFG" ]; then
 log "WAZUH_FORWARDING=CONFIGURADO_NO_RUNTIME"
 log "WAZUH_FORWARDING_CONFIG=$FORWARD_CFG"
 log "WAZUH_FORWARDING_TARGET=${WAZUH_HOST}:${WAZUH_PORT}"
 log "WAZUH_FORWARDING_MATCH=ATIVO_EXATO_UDP"
else
 log "WAZUH_FORWARDING=NAO_CONFIRMADO_NO_RUNTIME"
 log "WAZUH_FORWARDING_TARGET=${WAZUH_HOST}:${WAZUH_PORT}"
 log "WAZUH_FORWARDING_MATCH=NAO_ENCONTRADO_ATIVO_EXATO"
 FAIL=1
fi

# Este host confirma a configuração de forwarding, não a correlação do evento no SIEM.
log "WAZUH_TRANSPORTE_HISTORICO=CONFIRMADO_EM_20260916"
log "WAZUH_CORRELACAO_INGESTAO=PENDENTE"
log "SYSLOG_NG_EXTRA=NAO_NECESSARIO_NESTA_FASE"

if [ "$FAIL" -eq 0 ]; then log "CHECKPOINT_LOGGING=APROVADO"; RC=0
else log "CHECKPOINT_LOGGING=REPROVADO"; RC=1; fi
log "ARQUIVO_SAIDA=$OUT"
exit "$RC"
