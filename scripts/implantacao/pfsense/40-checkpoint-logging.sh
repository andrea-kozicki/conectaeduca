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

Nesta fase, o parser valida a sintaxe BSD syslogd (@host:port) E a cobertura
de System, Firewall, DNS, Authentication e Gateway Monitor (ou Everything).
Se syslog-ng for o daemon ativo, o checkpoint falha fechado em vez de aplicar
um parser incompatível à configuração do daemon.
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

# Parser EXCLUSIVO da sintaxe BSD syslogd.
# Aprova somente se o destino UDP cobre as categorias necessárias do pfSense:
# System, Firewall, DNS, Authentication e Gateway Monitor. Uma regra global
# !* + *.<nivel> também é aceita por cobrir todas as categorias.
# Não deve ser reutilizado para syslog-ng, que possui gramática própria.
has_syslogd_required_forwarding() {
 awk -v target="@${WAZUH_HOST}:${WAZUH_PORT}" '
 function trim(s) {
   sub(/^[[:space:]]+/, "", s)
   sub(/[[:space:]]+$/, "", s)
   return s
 }
 function exact_target(line, n, action_parts) {
   # A action BSD syslogd precisa ser exatamente o endpoint esperado.
   # Sufixos/argumentos extras tornam a linha inelegível para provar cobertura.
   n=split(line, action_parts, /[[:space:]]+/)
   return (n == 2 && action_parts[2] == target)
 }
 function strip_compat_prefix(line) {
   # FreeBSD aceita #!, #+, #- e #: por compatibilidade. Um # comum segue
   # sendo comentário e não pode alterar estado.
   if (substr(line,1,1) == "#" && substr(line,2,1) ~ /[!+\-:]/)
     return substr(line,2)
   return line
 }
 function auth_selector_ok(selector, n, parts, i, auth_all, authpriv_all) {
   n=split(selector, parts, ";")
   if (n != 2) return 0
   auth_all=authpriv_all=0
   for (i=1; i<=n; i++) {
     if (parts[i] == "auth.*") auth_all++
     else if (parts[i] == "authpriv.*") authpriv_all++
     else return 0
   }
   return (auth_all == 1 && authpriv_all == 1)
 }
 function system_selector_ok(selector, n, parts, i, a, b, c, d, e, f) {
   n=split(selector, parts, ";")
   if (n != 6) return 0
   a=b=c=d=e=f=0
   for (i=1; i<=n; i++) {
     if (parts[i] == "*.notice") a++
     else if (parts[i] == "kern.debug") b++
     else if (parts[i] == "security.*") c++
     else if (parts[i] == "auth.info") d++
     else if (parts[i] == "authpriv.info") e++
     else if (parts[i] == "daemon.notice") f++
     else return 0
   }
   return (a==1 && b==1 && c==1 && d==1 && e==1 && f==1)
 }
 function exact_program_set(context, expected, raw, n, parts, i, m, wanted, seen) {
   if (substr(context,1,1) != "!") return 0
   raw=substr(context,2)
   if (substr(raw,1,1) == "-") raw=substr(raw,2)
   n=split(raw, parts, ",")
   m=split(expected, wanted, ",")
   if (n != m) return 0
   delete seen
   for (i=1; i<=n; i++) seen[parts[i]]++
   for (i=1; i<=m; i++) {
     if (seen[wanted[i]] != 1) return 0
   }
   return 1
 }
 function host_unrestricted() {
   return host_ctx == "*"
 }
 function prop_unrestricted() {
   return prop_ctx == "*"
 }
 BEGIN {
   prog_ctx="*"
   host_ctx="*"
   prop_ctx="*"
   all_ok=system_ok=firewall_ok=dns_group_ok=dns_unbound_ok=auth_ok=gateway_ok=0
 }
 {
   line=$0
   sub(/^[[:space:]]*/, "", line)
   if (line == "") next

   # Comentários comuns são ignorados; formas especiais #!, #+, #- e #:
   # seguem a semântica compatível do syslogd.
   if (substr(line,1,1) == "#" && substr(line,2,1) !~ /[!+\-:]/) next
   line=strip_compat_prefix(line)

   # Filtros de hostname e de programa são estados INDEPENDENTES no BSD
   # syslogd. Alterar !program nunca reseta +host/-host.
   if (substr(line,1,1) == "+" || substr(line,1,1) == "-") {
     spec=trim(substr(line,2))
     split(spec, tmp, /[[:space:]]+/)
     spec=tmp[1]
     if (spec == "" || spec == "*") host_ctx="*"
     else host_ctx=substr(line,1,1) spec
     next
   }

   if (substr(line,1,1) == "!") {
     spec=trim(substr(line,2))
     split(spec, tmp, /[[:space:]]+/)
     spec=tmp[1]
     if (spec == "" || spec == "*") prog_ctx="*"
     else prog_ctx="!" spec
     next
   }

   # Property filters também persistem independentemente; só :* os reseta.
   if (substr(line,1,1) == ":") {
     spec=trim(substr(line,2))
     if (spec == "" || spec == "*") prop_ctx="*"
     else prop_ctx=":" spec
     next
   }

   # Remove comentário inline apenas das linhas de selector/action.
   hash=index(line,"#")
   if (hash > 0) line=substr(line,1,hash-1)
   line=trim(line)
   if (line == "" || !exact_target(line)) next

   # Nenhuma regra restrita por host/property pode provar cobertura global.
   if (!host_unrestricted() || !prop_unrestricted()) next

   n=split(line, fields, /[[:space:]]+/)
   selector=fields[1]

   if (prog_ctx == "*" && selector == "*.*") all_ok=1

   if (selector == "*.*") {
     if (prog_ctx == "!filterlog") firewall_ok=1
     if (prog_ctx == "!dpinger") gateway_ok=1
     if (prog_ctx == "!unbound") dns_unbound_ok=1
     if (prog_ctx == "!dnsmasq,named,filterdns") dns_group_ok=1
   }

   if (prog_ctx == "*" && auth_selector_ok(selector)) auth_ok=1

   if (exact_program_set(prog_ctx, "bgpd,filterlog,unbound,dpinger") &&
       substr(prog_ctx,1,2) == "!-" &&
       system_selector_ok(selector)) system_ok=1
 }
 END {
   if (all_ok || (system_ok && firewall_ok && dns_group_ok && dns_unbound_ok && auth_ok && gateway_ok))
     exit 0
   exit 1
 }
 ' "$@"
}

extract_f_config() {
 printf '%s\n' "$1" | awk '
 {
   for (i=1; i<=NF; i++) {
     if ($i == "-f" && i < NF) { print $(i+1); exit }
     if (substr($i,1,2) == "-f" && length($i) > 2) {
       print substr($i,3); exit
     }
   }
 }'
}

if [ "$SELF_TEST" -eq 1 ]; then
 for c in awk date find grep ps sed uname; do
  command -v "$c" >/dev/null 2>&1 || {
   echo "SELF_TEST_LOGGING=FALHA comando=$c" >&2
   exit 1
  }
 done

 # Destino/sintaxe básicos.
 printf '%s\n' "# comentário" "*.* @${WAZUH_HOST}:${WAZUH_PORT}" | has_syslogd_required_forwarding || {
  echo "SELF_TEST_LOGGING=FALHA comentario_comum_interferiu" >&2; exit 1;
 }
 printf '%s\n' "!*" "*.* @${WAZUH_HOST}:${WAZUH_PORT}0" | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA porta_prefixo_aceita" >&2; exit 1;
 }
 printf '%s\n' "!*" "*.* @@${WAZUH_HOST}:${WAZUH_PORT}" | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA tcp_double_at_aceito" >&2; exit 1;
 }
 printf '%s\n' "!*" "*.* @${WAZUH_HOST}:${WAZUH_PORT},invalid" | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA action_sufixo_virgula_aceito" >&2; exit 1;
 }
 printf '%s\n' "!*" "*.* @${WAZUH_HOST}:${WAZUH_PORT} extra" | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA action_argumento_extra_aceito" >&2; exit 1;
 }
 printf '%s\n' "!*" "mail.* @${WAZUH_HOST}:${WAZUH_PORT}" | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA seletor_irrelevante_aceito" >&2; exit 1;
 }
 printf '%s\n' "!*" "*.none @${WAZUH_HOST}:${WAZUH_PORT}" | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA everything_none_aceito" >&2; exit 1;
 }
 printf '%s\n' "!*" "*.* @${WAZUH_HOST}:${WAZUH_PORT}" | has_syslogd_required_forwarding || {
  echo "SELF_TEST_LOGGING=FALHA forwarding_global_rejeitado" >&2; exit 1;
 }

 # Hostname filter é independente do program filter.
 printf '%s\n' "+other-host" "!*" "*.* @${WAZUH_HOST}:${WAZUH_PORT}" | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA host_restrito_sobrescrito_por_programa" >&2; exit 1;
 }
 printf '%s\n' "+other-host" "+*" "!*" "*.* @${WAZUH_HOST}:${WAZUH_PORT}" | has_syslogd_required_forwarding || {
  echo "SELF_TEST_LOGGING=FALHA reset_host_explicito_rejeitado" >&2; exit 1;
 }
 printf '%s\n' "#+other-host" "#!*" "*.* @${WAZUH_HOST}:${WAZUH_PORT}" | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA host_compat_restrito_ignorado" >&2; exit 1;
 }
 printf '%s\n' "#+other-host" "#+*" "#!*" "*.* @${WAZUH_HOST}:${WAZUH_PORT}" | has_syslogd_required_forwarding || {
  echo "SELF_TEST_LOGGING=FALHA reset_host_compat_rejeitado" >&2; exit 1;
 }

 # Property filter é independente e exige reset próprio.
 printf '%s\n' ':msg, contains, "foo"' "!*" "*.* @${WAZUH_HOST}:${WAZUH_PORT}" | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA property_filter_restrito_aceito" >&2; exit 1;
 }
 printf '%s\n' ':msg, contains, "foo"' ":*" "!*" "*.* @${WAZUH_HOST}:${WAZUH_PORT}" | has_syslogd_required_forwarding || {
  echo "SELF_TEST_LOGGING=FALHA reset_property_rejeitado" >&2; exit 1;
 }

 # Casos negativos de categoria.
 printf '%s\n' "!filterlog" "mail.* @${WAZUH_HOST}:${WAZUH_PORT}" | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA firewall_mail_aceito" >&2; exit 1;
 }
 printf '%s\n' "!sshd" "auth.*;authpriv.* @${WAZUH_HOST}:${WAZUH_PORT}" | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA auth_restrito_a_sshd_aceito" >&2; exit 1;
 }
 printf '%s\n' "!*" "auth.emerg;authpriv.emerg @${WAZUH_HOST}:${WAZUH_PORT}" | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA auth_prioridade_restrita_aceita" >&2; exit 1;
 }
 printf '%s\n' "!*" "auth.*;authpriv.*;auth.none;authpriv.none @${WAZUH_HOST}:${WAZUH_PORT}" | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA auth_override_none_aceito" >&2; exit 1;
 }

 REQUIRED_SAMPLE="$(cat <<EOF_SAMPLE
!*
auth.*;authpriv.* @${WAZUH_HOST}:${WAZUH_PORT}
!dpinger
*.* @${WAZUH_HOST}:${WAZUH_PORT}
!dnsmasq,named,filterdns
*.* @${WAZUH_HOST}:${WAZUH_PORT}
!unbound
*.* @${WAZUH_HOST}:${WAZUH_PORT}
!filterlog
*.* @${WAZUH_HOST}:${WAZUH_PORT}
!-bgpd,filterlog,unbound,dpinger
*.notice;kern.debug;security.*;auth.info;authpriv.info;daemon.notice @${WAZUH_HOST}:${WAZUH_PORT}
EOF_SAMPLE
)"

 printf '%s\n' "$REQUIRED_SAMPLE" | has_syslogd_required_forwarding || {
  echo "SELF_TEST_LOGGING=FALHA categorias_requeridas_rejeitadas" >&2; exit 1;
 }

 printf '%s\n' "$REQUIRED_SAMPLE" | sed   's/^\*\.notice;kern\.debug;security\.\*;auth\.info;authpriv\.info;daemon\.notice /kern.emerg;security.emerg;daemon.emerg /'   | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA system_prioridade_restrita_aceita" >&2; exit 1;
 }
 printf '%s\n' "$REQUIRED_SAMPLE" | sed   's/^!-bgpd,filterlog,unbound,dpinger$/!-cron,filterlog,unbound,dpinger/'   | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA system_exclusao_extra_aceita" >&2; exit 1;
 }
 printf '%s\n' "$REQUIRED_SAMPLE" | sed   's/^auth\.\*;authpriv\.\* /auth.*;authpriv.*;auth.none;authpriv.none /'   | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA auth_override_none_no_conjunto_aceito" >&2; exit 1;
 }
 printf '%s\n' "$REQUIRED_SAMPLE" | awk '
   /^!dpinger$/ { skip=1; next }
   skip > 0 { skip--; next }
   { print }
 ' | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA gateway_ausente_aceito" >&2; exit 1;
 }

 # Um host filter que aparece antes do conjunto deve bloquear TODAS as regras
 # até um reset explícito, mesmo que !program mude várias vezes depois.
 {
  printf '%s\n' "+other-host"
  printf '%s\n' "$REQUIRED_SAMPLE"
 } | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA host_filter_persistente_aceito" >&2; exit 1;
 }

 printf '%s\n' "destination d_wazuh { udp(\"${WAZUH_HOST}\" port(${WAZUH_PORT})); };" | has_syslogd_required_forwarding && {
  echo "SELF_TEST_LOGGING=FALHA sintaxe_syslog_ng_aceita_pelo_parser_syslogd" >&2; exit 1;
 }

 [ "$(extract_f_config '/usr/sbin/syslogd -c -f /var/etc/syslog.conf')" = "/var/etc/syslog.conf" ] || {
  echo "SELF_TEST_LOGGING=FALHA parse_f_separado" >&2; exit 1;
 }
 [ "$(extract_f_config '/usr/local/sbin/syslog-ng -f/var/etc/syslog-ng.conf')" = "/var/etc/syslog-ng.conf" ] || {
  echo "SELF_TEST_LOGGING=FALHA parse_f_colado" >&2; exit 1;
 }

 echo "SELF_TEST_LOGGING=APROVADO"
 exit 0
fi

[ "$(uname -s 2>/dev/null)" = "FreeBSD" ] || {
 echo "ERRO: checkpoint operacional deve rodar no pfSense/FreeBSD." >&2; exit 1;
}
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
log "WAZUH_FORWARDING_VALIDATOR=BSD_SYSLOGD_CANONICAL_FAIL_CLOSED"
log "WAZUH_FORWARDING_FILTER_STATE=PROGRAM_HOST_PROPERTY_INDEPENDENT"

PF_LOGS=0
for f in /var/log/system.log /var/log/filter.log; do
 if [ -e "$f" ]; then PF_LOGS=$((PF_LOGS+1)); log "LOG_PFSENSE_PRESENTE=$f"; fi
done
[ "$PF_LOGS" -gt 0 ] 2>/dev/null || { log "LOG_PFSENSE_PADRAO=NAO_DETECTADO"; FAIL=1; }

SUR_DIRS="$(find /var/log/suricata -type d 2>/dev/null | awk 'END{print NR+0}')"
SUR_FILES="$(find /var/log/suricata -type f 2>/dev/null | awk 'END{print NR+0}')"
log "SURICATA_LOG_DIRS=$SUR_DIRS"
log "SURICATA_LOG_FILES=$SUR_FILES"
[ "$SUR_DIRS" -gt 0 ] 2>/dev/null || { log "SURICATA_LOGGING=NAO_DETECTADO"; FAIL=1; }

SYSLOGD_CMD="$(ps ax -o command= 2>/dev/null | awk '/(^|\/)syslogd([[:space:]]|$)/ {print; exit}')"
SYSLOGNG_CMD="$(ps ax -o command= 2>/dev/null | awk '/(^|\/)syslog-ng([[:space:]]|$)/ {print; exit}')"

SYSLOG_DAEMON=""
SYSLOG_CMD=""
SYSLOG_CFG=""

if [ -n "$SYSLOGD_CMD" ] && [ -n "$SYSLOGNG_CMD" ]; then
 log "SYSLOG_DAEMON=AMBIGUO_MULTIPLOS"
 FAIL=1
elif [ -n "$SYSLOGD_CMD" ]; then
 SYSLOG_DAEMON="syslogd"
 SYSLOG_CMD="$SYSLOGD_CMD"
 SYSLOG_CFG="$(extract_f_config "$SYSLOG_CMD")"
 [ -n "$SYSLOG_CFG" ] || SYSLOG_CFG="/etc/syslog.conf"
 log "SYSLOG_DAEMON=ATIVO"
 log "SYSLOG_DAEMON_TIPO=syslogd"
elif [ -n "$SYSLOGNG_CMD" ]; then
 SYSLOG_DAEMON="syslog-ng"
 SYSLOG_CMD="$SYSLOGNG_CMD"
 SYSLOG_CFG="$(extract_f_config "$SYSLOG_CMD")"
 [ -n "$SYSLOG_CFG" ] || SYSLOG_CFG="/usr/local/etc/syslog-ng.conf"
 log "SYSLOG_DAEMON=ATIVO"
 log "SYSLOG_DAEMON_TIPO=syslog-ng"
 log "SYSLOG_NG_VALIDACAO=NAO_IMPLEMENTADA_FAIL_CLOSED"
 # O checkpoint não tenta interpretar syslog-ng com gramática BSD syslogd.
 FAIL=1
else
 log "SYSLOG_DAEMON=NAO_DETECTADO"
 FAIL=1
fi

FORWARD_CFG=""
if [ "$SYSLOG_DAEMON" = "syslogd" ]; then
 log "SYSLOG_DAEMON_CONFIG_ESPERADA=$SYSLOG_CFG"
 if [ -r "$SYSLOG_CFG" ] && has_syslogd_required_forwarding "$SYSLOG_CFG" 2>/dev/null; then
  FORWARD_CFG="$SYSLOG_CFG"
 fi
elif [ "$SYSLOG_DAEMON" = "syslog-ng" ]; then
 log "SYSLOG_DAEMON_CONFIG_ESPERADA=$SYSLOG_CFG"
 log "WAZUH_FORWARDING_VALIDATOR=INCOMPATIVEL_COM_SYSLOG_NG"
fi

if [ -n "$FORWARD_CFG" ]; then
 log "WAZUH_FORWARDING=CONFIGURADO_NO_RUNTIME"
 log "WAZUH_FORWARDING_CONFIG=$FORWARD_CFG"
 log "WAZUH_FORWARDING_TARGET=${WAZUH_HOST}:${WAZUH_PORT}"
 log "WAZUH_FORWARDING_MATCH=ATIVO_UDP_COM_COBERTURA_REQUERIDA"
 log "WAZUH_FORWARDING_COVERAGE=SYSTEM,FIREWALL,DNS,AUTH,GATEWAY"
else
 log "WAZUH_FORWARDING=NAO_CONFIRMADO_NO_RUNTIME"
 log "WAZUH_FORWARDING_TARGET=${WAZUH_HOST}:${WAZUH_PORT}"
 log "WAZUH_FORWARDING_MATCH=DESTINO_OU_COBERTURA_REQUERIDA_NAO_CONFIRMADOS"
 FAIL=1
fi

log "WAZUH_TRANSPORTE_HISTORICO=CONFIRMADO_EM_20260916"
log "WAZUH_CORRELACAO_RECEIVER=CONFIRMADA_EM_20260917"
log "WAZUH_CORRELACAO_ANALITICA_INDEXER=PENDENTE"

if [ "$FAIL" -eq 0 ]; then
 log "CHECKPOINT_LOGGING=APROVADO"; RC=0
else
 log "CHECKPOINT_LOGGING=REPROVADO"; RC=1
fi
log "ARQUIVO_SAIDA=$OUT"
exit "$RC"
