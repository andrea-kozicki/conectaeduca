#!/usr/bin/env bash
set -u
export LC_ALL=C
export LANG=C

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"
DMZ="$ROOT/deploy/dmz"
BASE_COMPOSE="$DMZ/compose.yml"
WAF_COMPOSE="$DMZ/compose.waf.yml"
PROJECT="conectaeduca-dmz-waf-test"

NGINX_PORT="${NGINX_PORT:-8088}"
WAF_PORT="${WAF_PORT:-18080}"
WAF_IMAGE="owasp/modsecurity-crs:4.25.1-nginx-lts"

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/conectaeduca-waf-fase4h-b-${STAMP}.txt"
PRIVACY_PROBE="nao-registrar-${STAMP}"

FAIL=0
STARTED=0

ok(){ echo "OK       $*"; }
fail(){ echo "FALHA    $*"; FAIL=$((FAIL+1)); }
info(){ echo "INFO     $*"; }

compose() {
  docker compose \
    -p "$PROJECT" \
    -f "$BASE_COMPOSE" \
    -f "$WAF_COMPOSE" \
    "$@"
}

cleanup() {
  set +e
  if [[ "$STARTED" -eq 1 ]]; then
    compose down --remove-orphans >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

wait_health() {
  local svc="$1"
  local label="$2"
  local elapsed=0 cid state health

  cid="$(compose ps -q "$svc" 2>/dev/null || true)"
  if [[ -z "$cid" ]]; then
    return 1
  fi

  while (( elapsed <= 120 )); do
    state="$(docker inspect "$cid" --format '{{.State.Status}}' 2>/dev/null || true)"
    health="$(docker inspect "$cid" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}sem-healthcheck{{end}}' 2>/dev/null || true)"
    echo "health_wait label=$label t=${elapsed}s state=${state:-?} health=${health:-?}"

    if [[ "$state" == "running" && "$health" == "healthy" ]]; then
      return 0
    fi

    if [[ "$state" == "exited" || "$state" == "dead" ]]; then
      return 1
    fi

    sleep 5
    elapsed=$((elapsed+5))
  done
  return 1
}

exec > >(tee "$REPORT") 2>&1

echo "======================================================================"
echo " CONECTAEDUCA - FASE 4H-B"
echo " WAF versionado no deploy real da DMZ"
echo " Data: $(date --iso-8601=seconds)"
echo "======================================================================"

cd "$ROOT" || exit 1

echo
echo "=== 1. BRANCH / GIT ==="
git status -sb

BRANCH="$(git branch --show-current 2>/dev/null || true)"
echo "branch_atual=$BRANCH"

[[ "$BRANCH" == "feature/auth-local" ]] \
  && ok "branch feature/auth-local confirmada" \
  || fail "execute exclusivamente em feature/auth-local"

git diff --check \
  && ok "git diff --check" \
  || fail "git diff --check"

echo
echo "=== 2. ARQUIVOS DA 4H-B ==="
for f in \
  deploy/dmz/compose.yml \
  deploy/dmz/compose.waf.yml \
  deploy/dmz/waf/README.md \
  scripts/evidencias/diagnosticar_waf_fase4h_a.sh \
  scripts/evidencias/testar_waf_fase4h_b.sh
do
  [[ -f "$ROOT/$f" ]] \
    && ok "$f" \
    || fail "ausente: $f"
done

echo
echo "=== 3. COMPOSE VERSIONADO ==="
if compose config >/dev/null; then
  ok "Compose base + 4H-B válido"
else
  fail "Compose base + 4H-B inválido"
fi

CONFIG_JSON="$(compose config --format json 2>/dev/null || true)"

if printf '%s' "$CONFIG_JSON" | python3 -c '
import json,sys
c=json.load(sys.stdin)["services"]
assert set(c)=={"nginx","php","waf"}
assert c["waf"]["image"]=="owasp/modsecurity-crs:4.25.1-nginx-lts"
'
then
  ok "serviços esperados: nginx + php + waf"
  ok "imagem WAF fixada em 4.25.1-nginx-lts"
else
  fail "serviços/imagem do Compose não correspondem à 4H-B"
fi

echo
echo "=== 4. TOPOLOGIA DECLARADA ==="
if printf '%s' "$CONFIG_JSON" | python3 -c '
import json,sys
c=json.load(sys.stdin)["services"]

wp=c["waf"].get("ports",[])
assert len(wp)==1
assert wp[0].get("host_ip")=="127.0.0.1"
assert int(wp[0].get("published"))==18080
assert int(wp[0].get("target"))==8080

np=c["nginx"].get("ports",[])
assert len(np)==1
assert np[0].get("host_ip")=="127.0.0.1"
assert int(np[0].get("published"))==8088
assert int(np[0].get("target"))==8080

assert not c["php"].get("ports")
'
then
  ok "WAF publicado somente em 127.0.0.1:18080"
  info "Nginx 127.0.0.1:8088 permanece temporariamente na 4H-B"
  ok "PHP-FPM continua sem publicação"
else
  fail "topologia declarada diverge do modo transitório 4H-B"
fi

echo
echo "=== 5. CONFIGURAÇÃO DE SEGURANÇA / PRIVACIDADE ==="
if printf '%s' "$CONFIG_JSON" | python3 -c '
import json,sys
w=json.load(sys.stdin)["services"]["waf"]["environment"]

def val(k):
    return str(w.get(k,""))

assert val("BACKEND")=="http://nginx:8080"
assert val("MODSEC_RULE_ENGINE").lower()=="on"
assert val("MODSEC_AUDIT_ENGINE")=="RelevantOnly"
assert val("MODSEC_AUDIT_LOG_FORMAT")=="JSON"
parts=val("MODSEC_AUDIT_LOG_PARTS")
assert parts=="AFHZ"
assert "B" not in parts
assert "C" not in parts
assert val("BLOCKING_PARANOIA")=="1"
assert val("DETECTION_PARANOIA")=="1"
assert val("ANOMALY_INBOUND")=="5"
assert val("ANOMALY_OUTBOUND")=="4"
'
then
  ok "WAF aponta para nginx:8080"
  ok "ModSecurity em modo bloqueio"
  ok "audit log RelevantOnly/JSON"
  ok "partes B e C omitidas do audit log"
  ok "baseline CRS PL1 / thresholds 5 e 4"
else
  fail "configuração WAF diverge da baseline segura"
fi

echo
echo "=== 6. IMAGEM WAF ==="
if docker image inspect "$WAF_IMAGE" >/dev/null 2>&1 ||
   docker pull "$WAF_IMAGE" >/dev/null
then
  DIGEST="$(docker image inspect "$WAF_IMAGE" --format '{{join .RepoDigests "\n"}}' 2>/dev/null || true)"
  echo "waf_digest=$DIGEST"
  ok "imagem WAF disponível"
else
  fail "imagem WAF indisponível"
fi

echo
echo "=== 7. PORTAS DO HOST ==="
for port in "$NGINX_PORT" "$WAF_PORT"; do
  if ss -H -ltn "( sport = :$port )" 2>/dev/null | grep -q .; then
    fail "porta TCP $port já está ocupada"
  else
    ok "porta TCP $port livre"
  fi
done

echo
echo "=== 8. BUILD NGINX/PHP ==="
if compose build nginx php; then
  ok "imagens Nginx/PHP construídas"
else
  fail "build da DMZ falhou"
fi

echo
echo "=== 9. SUBIDA DO DEPLOY 4H-B ==="
if compose up -d; then
  STARTED=1
  ok "nginx + php + waf iniciados"
else
  fail "compose up falhou"
fi

compose ps || true

if wait_health php "php-fpm"; then
  ok "PHP-FPM healthy"
else
  fail "PHP-FPM não ficou healthy"
fi

if wait_health nginx "nginx"; then
  ok "Nginx healthy"
else
  fail "Nginx não ficou healthy"
fi

if wait_health waf "waf"; then
  ok "WAF healthy"
else
  fail "WAF não ficou healthy"
fi

echo
echo "=== 10. TRÁFEGO BENIGNO ==="
DIRECT_CODE="$(
  curl -sS --max-time 10 \
    -H 'Host: conectaeduca.local' \
    -o /dev/null \
    -w '%{http_code}' \
    "http://127.0.0.1:${NGINX_PORT}/_container_health" \
    2>/dev/null || true
)"
echo "nginx_direto_health=$DIRECT_CODE"

[[ "$DIRECT_CODE" == "200" ]] \
  && ok "baseline Nginx direta continua funcional" \
  || fail "baseline Nginx direta não respondeu 200"

WAF_CODE="$(
  curl -sS --max-time 10 \
    -H 'Host: conectaeduca.local' \
    -o /dev/null \
    -w '%{http_code}' \
    "http://127.0.0.1:${WAF_PORT}/_container_health" \
    2>/dev/null || true
)"
echo "waf_health=$WAF_CODE"

[[ "$WAF_CODE" == "200" ]] \
  && ok "WAF encaminha requisição benigna ao Nginx real" \
  || fail "WAF não alcançou o Nginx real"

CSS_CODE="$(
  curl -sS --max-time 10 \
    -H 'Host: conectaeduca.local' \
    -o /dev/null \
    -w '%{http_code}' \
    "http://127.0.0.1:${WAF_PORT}/assets/css/style.css" \
    2>/dev/null || true
)"
echo "waf_css_http=$CSS_CODE"

case "$CSS_CODE" in
  200|304)
    ok "ativo público atravessa o WAF"
    ;;
  *)
    fail "ativo público não atravessou o WAF"
    ;;
esac

echo
echo "=== 11. BLOQUEIO CRS NO DEPLOY REAL ==="
XSS_CODE="$(
  curl -sS --max-time 10 \
    -H 'Host: conectaeduca.local' \
    -H "X-ConectaEduca-Privacy-Probe: ${PRIVACY_PROBE}" \
    -H "Cookie: CONECTAEDUCASESSID=${PRIVACY_PROBE}" \
    -G \
    --data-urlencode 'q=<script>alert(1)</script>' \
    -o /dev/null \
    -w '%{http_code}' \
    "http://127.0.0.1:${WAF_PORT}/" \
    2>/dev/null || true
)"
echo "xss_http=$XSS_CODE"

[[ "$XSS_CODE" == "403" ]] \
  && ok "XSS sintético bloqueado no deploy versionado" \
  || fail "XSS não foi bloqueado"

SQLI_CODE="$(
  curl -sS --max-time 10 \
    -H 'Host: conectaeduca.local' \
    -G \
    --data-urlencode "id=1' OR '1'='1" \
    -o /dev/null \
    -w '%{http_code}' \
    "http://127.0.0.1:${WAF_PORT}/" \
    2>/dev/null || true
)"
echo "sqli_http=$SQLI_CODE"

[[ "$SQLI_CODE" == "403" ]] \
  && ok "SQLi sintético bloqueado no deploy versionado" \
  || fail "SQLi não foi bloqueado"

echo
echo "=== 12. AUDIT LOG E PRIVACIDADE ==="
WAF_CONTAINER="$(compose ps -q waf 2>/dev/null || true)"
WAF_LOGS="$(docker logs "$WAF_CONTAINER" 2>&1 || true)"

if printf '%s' "$WAF_LOGS" | grep -Eq 'ruleId|ModSecurity|id "[0-9]{6}"'; then
  ok "audit log contém evidência de regras acionadas"
else
  fail "audit log sem evidência de bloqueio"
fi

if printf '%s' "$WAF_LOGS" | grep -Fq "$PRIVACY_PROBE"; then
  fail "probe de header/cookie apareceu no audit log"
else
  ok "header/cookie de prova não foi persistido no audit log"
fi

if printf '%s' "$WAF_LOGS" | grep -Fq '"request_body"'; then
  fail "campo request_body apareceu no audit log"
else
  ok "request_body não foi observado no audit log"
fi

echo "--- IDs de regras observados ---"
printf '%s\n' "$WAF_LOGS" |
  grep -Eo 'id "[0-9]{6}"|ruleId["=: ]+[0-9]{6}' |
  sort -u |
  head -20 || true

echo
echo "=== 13. SUPERFÍCIE REAL ==="
docker ps \
  --filter "label=com.docker.compose.project=$PROJECT" \
  --format 'table {{.Names}}\t{{.Ports}}'

PHP_BINDINGS="$(docker port "$(compose ps -q php)" 2>/dev/null || true)"
[[ -z "$PHP_BINDINGS" ]] \
  && ok "PHP-FPM sem porta publicada" \
  || fail "PHP-FPM possui binding no host"

WAF_BINDINGS="$(docker port "$(compose ps -q waf)" 8080/tcp 2>/dev/null || true)"
NGINX_BINDINGS="$(docker port "$(compose ps -q nginx)" 8080/tcp 2>/dev/null || true)"

echo "waf_bindings=$WAF_BINDINGS"
echo "nginx_bindings=$NGINX_BINDINGS"

printf '%s' "$WAF_BINDINGS" | grep -Fxq "127.0.0.1:${WAF_PORT}" \
  && ok "binding real do WAF correto" \
  || fail "binding real do WAF inesperado"

printf '%s' "$NGINX_BINDINGS" | grep -Fxq "127.0.0.1:${NGINX_PORT}" \
  && info "binding direto do Nginx permanece apenas nesta etapa transitória" \
  || fail "binding legado do Nginx diverge da baseline"

echo
echo "=== 14. RECURSOS ==="
IDS="$(compose ps -q)"
docker stats --no-stream \
  --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.BlockIO}}' \
  $IDS || true

echo
echo "=== 15. ENCERRAMENTO ==="
if compose down --remove-orphans; then
  STARTED=0
  ok "stack 4H-B removida"
else
  fail "falha ao encerrar stack"
fi

RESIDUAL="$(
  docker ps -aq \
    --filter "label=com.docker.compose.project=$PROJECT" \
    2>/dev/null || true
)"
[[ -z "$RESIDUAL" ]] \
  && ok "nenhum container residual" \
  || fail "container residual encontrado"

echo
echo "=== 16. GIT FINAL ==="
cd "$ROOT"
git status -sb

git diff --check \
  && ok "git diff --check final" \
  || fail "git diff --check final"

if git ls-files | grep -Eq '(^|/)\.env$|\.pem$|\.key$|(^|/)\.runtime/'; then
  info "repositório contém nomes potencialmente sensíveis; checkpoint global continuará responsável pela análise contextual"
else
  ok "nenhum nome sensível novo detectado"
fi

echo
echo "======================================================================"
echo " RESULTADO"
echo "======================================================================"
echo "Falhas: $FAIL"

if [[ "$FAIL" -eq 0 ]]; then
  echo "FASE 4H-B: APROVADA."
  echo "WAF ModSecurity + OWASP CRS está versionado e conectado ao Nginx real da DMZ."
  echo "A exposição direta do Nginx foi mantida apenas para compatibilidade nesta fase."
  echo "A Fase 4H-C deverá tornar o WAF o único caminho de entrada."
else
  echo "FASE 4H-B: REPROVADA."
fi

echo "Relatório: $REPORT"
echo "======================================================================"

[[ "$FAIL" -eq 0 ]]
