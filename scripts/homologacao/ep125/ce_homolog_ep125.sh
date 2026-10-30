#!/usr/bin/env bash
# ConectaEduca EP125 — kit de homologação reconstruído em 30/10/2026.
# Execução LOCAL na EP125, via checkout GitHub. Não é GitHub Actions.
set -Eeuo pipefail
umask 077
ETAPA="${1:-}"
case "$ETAPA" in 16A2|16A3|16A4|16B|16B1|16B2|16C|17A|17A1|17B0) ;; *)
 echo "Uso: bash $0 {16A2|16A3|16A4|16B|16B1|16B2|16C|17A|17A1|17B0}" >&2; exit 2;; esac
BASE="${HOME}/ConectaEduca_Fase2_Evidencias/EP125"
DIR="$BASE/HOMOLOG"; DIARIO="$BASE/diario.md"; mkdir -p "$DIR"
STAMP="$(date +%Y%m%dT%H%M%S)"
OUT="$DIR/EP125_HOMOLOG_ETAPA${ETAPA}_${STAMP}.txt"
WAF="${WAF_CONTAINER:-conectaeduca-dmz-waf-1}"
PHP="${PHP_CONTAINER:-conectaeduca-dmz-php-1}"
HOST="${CE_HOST:-conectaeduca.local}"
IP="${CE_IP:-192.168.6.34}"
echo "Evidencia: $OUT"
{
 echo "PROJETO=ConectaEduca"; echo "ETAPA=$ETAPA"; echo "DATA=$(date --iso-8601=seconds)"
 echo "HOST=$(hostname)"; echo "MODO=HOMOLOGACAO_CONTROLADA"
 docker inspect "$WAF" --format 'WAF={{.State.Status}}/{{if .State.Health}}{{.State.Health.Status}}{{else}}NA{{end}}'
 case "$ETAPA" in
 16A2)
  docker exec -i "$WAF" sh -s <<'INNER'
set -eu
echo SCRIPT_INTERNO_EXECUTADO=SIM
for p in /etc/modsecurity.d /etc/nginx /opt/owasp-crs; do [ ! -d "$p" ] || echo "DIRETORIO_PRESENTE=$p"; done
INNER
 ;;
 16A3|16A4)
  docker exec -i "$WAF" sh -s <<'INNER'
set -eu
for p in /opt/owasp-crs/rules/REQUEST-941-APPLICATION-ATTACK-XSS.conf /opt/owasp-crs/rules/REQUEST-942-APPLICATION-ATTACK-SQLI.conf /opt/owasp-crs/rules/REQUEST-949-BLOCKING-EVALUATION.conf /opt/owasp-crs/rules/RESPONSE-959-BLOCKING-EVALUATION.conf /opt/owasp-crs/crs-setup.conf; do
 [ -f "$p" ] || continue
 echo "ARQUIVO_PRESENTE=$p"
 for t in deny block anomaly_score blocking_paranoia_level inbound_anomaly_score outbound_anomaly_score; do
  n=$(grep -ic "$t" "$p" || true); echo "TERMO=$t OCORRENCIAS=$n"
 done
done
INNER
 ;;
 16B)
  echo "HISTORICO: baseline 127.0.0.1 incorreto na EP125; somente diagnóstico."
  curl --silent --show-error --noproxy '*' --resolve "$HOST:443:127.0.0.1" --connect-timeout 4 --max-time 10 -o /dev/null -w 'HTTP_BASELINE=%{http_code}\n' "https://$HOST/" || echo BASELINE_FALHOU=SIM
 ;;
 16B1)
  docker port "$WAF"; docker inspect "$WAF" --format '{{json .NetworkSettings.Ports}}'
  getent ahostsv4 "$HOST" || echo DNS_NAO_RESOLVIDO=SIM
  ss -H -ltn | awk '$4 ~ /:(443|8443|9443|8080|8088)$/ {print "ESCUTA=" $4}' || true
 ;;
 16B2)
  [ "${CE_ALLOW_HTTP_TEST:-NO}" = YES ] || { echo 'ABORTADO: export CE_ALLOW_HTTP_TEST=YES para autorizar 2 GETs.'; exit 3; }
  status=$(docker inspect "$WAF" --format '{{.State.Status}}/{{if .State.Health}}{{.State.Health.Status}}{{else}}NA{{end}}')
  [ "$status" = running/healthy ] || { echo "WAF_NAO_SAUDAVEL=$status"; exit 4; }
  published=$(docker port "$WAF" 8443/tcp 2>/dev/null || true)
  [ "$published" = "$IP:443" ] || { echo "PORTA_DIVERGENTE=$published"; exit 5; }
  opts=(--silent --show-error --noproxy '*' --resolve "$HOST:443:$IP" --connect-timeout 5 --max-time 15 --output /dev/null --write-out '%{http_code}')
  base=$(curl "${opts[@]}" "https://$HOST/"); echo "HTTP_BASELINE=$base"
  [ "$base" = 200 ] || { echo BASELINE_NAO_200; exit 6; }
  marker="CEWAF16B2_${STAMP}_$$"; echo "MARCADOR=$marker"
  begin=$(date --iso-8601=seconds)
  testcode=$(curl "${opts[@]}" --get --data-urlencode "ce_probe=$marker" --data-urlencode 'ce_payload=<script>alert(1)</script>' "https://$HOST/")
  echo "HTTP_TESTE=$testcode"; sleep 2
  docker logs --since "$begin" "$WAF" 2>/dev/null | grep -Fc "$marker" | awk '{print "LINHAS_COM_MARCADOR=" $1}' || true
 ;;
 16C)
  marker="${MARCADOR:-}"; [ -n "$marker" ] || { echo 'Defina MARCADOR=<valor da 16B2> antes de executar.'; exit 7; }
  begin="${INICIO:-2026-10-30T18:31:00-03:00}"; end="${FIM:-2026-10-30T18:34:00-03:00}"
  echo "MARCADOR=$marker"
  docker logs --since "$begin" --until "$end" "$WAF" 2>/dev/null | python3 -c '
import sys,re
m=sys.argv[1]; lines=0; ids=set(); status=set()
for line in sys.stdin:
 if m not in line:continue
 lines+=1
 ids.update(re.findall(r"\\b(?:941|942|949|959)\\d{3}\\b",line))
 if re.search(r"\\b403\\b",line):status.add("403")
print("LINHAS_COM_MARCADOR="+str(lines))
print("IDS_REGRAS="+(",".join(sorted(ids)) or "NAO_IDENTIFICADOS"))
print("STATUS="+(",".join(sorted(status)) or "NAO_IDENTIFICADO"))
' "$marker"
 ;;
 17A|17A1|17B0)
  docker exec -i "$PHP" sh -s "$ETAPA" <<'INNER'
set -eu
etapa="$1"; app=/var/www/conectaeduca
[ -d "$app" ] || { echo APP_AUSENTE=SIM; exit 8; }
echo "USUARIO=$(id -u):$(id -g)"
for d in public src; do [ ! -d "$app/$d" ] || echo "DIRETORIO_PRESENTE=$d"; done
if [ "$etapa" = 17A1 ]; then
 find "$app/public" "$app/src" -type f \( -name '*.php' -o -name '*.js' \) -print 2>/dev/null | awk 'END{print "ARQUIVOS_CODIGO="NR}'
 find "$app/public" "$app/src" -type f \( -name '*.php' -o -name '*.js' \) -exec sh -c 'for f do [ -r "$f" ] && echo LEGIVEL || echo ILEGIVEL; done' sh {} + 2>/dev/null | sort | uniq -c
fi
case "$etapa" in
 17B0) terms='role perfil admin candidato empresa middleware authorization permission';;
 *) terms='csrf token csrf_token csrfToken X-CSRF-TOKEN hash_equals POST REQUEST_METHOD session_start SameSite HttpOnly Secure';;
esac
for term in $terms; do
 n=$(grep -RIl -i -F --include='*.php' --include='*.js' --exclude-dir=vendor --exclude-dir=node_modules --exclude-dir=storage -- "$term" "$app/public" "$app/src" 2>/dev/null | wc -l)
 echo "INDICADOR=$term ARQUIVOS=$n"
done
echo INSPECAO_INTERNA_CONCLUIDA=SIM
INNER
 ;;
 esac
 echo "RESTARTS=NAO"; echo "CONFIGURACAO_ALTERADA=NAO"
} > "$OUT" 2>&1 || { rc=$?; cat "$OUT"; echo "EXIT_CODE=$rc"; exit "$rc"; }
cat "$OUT"
sha=$(sha256sum "$OUT" | awk '{print $1}')
echo "SHA256=$sha"
if [ -f "$DIARIO" ]; then
 cp -p "$DIARIO" "$DIARIO.backup-$STAMP"
 printf '\n## EP125 — Etapa %s (%s)\n- Evidencia: `%s`\n- SHA256: `%s`\n- Execucao: kit GitHub, sem alteracao de configuracao.\n' "$ETAPA" "$(date --iso-8601=seconds)" "$OUT" "$sha" >> "$DIARIO"
 echo DIARIO_ATUALIZADO=SIM
fi
