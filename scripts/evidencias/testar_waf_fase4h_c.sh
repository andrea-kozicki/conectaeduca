#!/usr/bin/env bash
set -u
export LC_ALL=C
export LANG=C

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"
DMZ="$ROOT/deploy/dmz"
BASE_COMPOSE="$DMZ/compose.yml"
WAF_COMPOSE="$DMZ/compose.waf.yml"

PROJECT="conectaeduca-dmz-waf-exclusive-test"
WAF_PORT="${WAF_PORT:-18080}"
LEGACY_NGINX_PORT="${LEGACY_NGINX_PORT:-8088}"

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/conectaeduca-waf-fase4h-c-${STAMP}.txt"
PRIVACY_PROBE="nao-registrar-4hc-${STAMP}"

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
  [[ -n "$cid" ]] || return 1

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
echo " CONECTAEDUCA - FASE 4H-C"
echo " WAF como único ponto de entrada HTTP da DMZ"
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
echo "=== 2. ARQUIVOS ==="
for f in \
  deploy/dmz/compose.yml \
  deploy/dmz/compose.waf.yml \
  deploy/dmz/nginx/app-http.conf \
  deploy/dmz/waf/README.md \
  scripts/evidencias/testar_waf_fase4h_c.sh
do
  [[ -f "$ROOT/$f" ]] \
    && ok "$f" \
    || fail "ausente: $f"
done

echo
echo "=== 3. COMPOSE RESULTANTE ==="
if compose config >/dev/null; then
  ok "Compose base + WAF válido"
else
  fail "Compose base + WAF inválido"
fi

CONFIG_JSON="$(compose config --format json 2>/dev/null || true)"

if printf '%s' "$CONFIG_JSON" | python3 -c '
import json,sys
c=json.load(sys.stdin)["services"]
assert set(c)=={"nginx","php","waf"}

assert not c["nginx"].get("ports")
assert not c["php"].get("ports")

wp=c["waf"].get("ports",[])
assert len(wp)==1
p=wp[0]
assert p.get("host_ip")=="127.0.0.1"
assert int(p.get("published"))==18080
assert int(p.get("target"))==8080

for svc in ("nginx","php","waf"):
    nets=set(c[svc].get("networks",{}))
    assert "frontend" in nets

assert c["waf"]["environment"]["BACKEND"]=="http://nginx:8080"
'
then
  ok "Nginx sem publicação no host"
  ok "PHP-FPM sem publicação no host"
  ok "somente WAF publicado em 127.0.0.1:18080"
  ok "WAF, Nginx e PHP compartilham rede frontend"
else
  fail "topologia final do Compose não corresponde ao ingresso exclusivo"
fi

echo
echo "=== 4. MECANISMO DE REMOÇÃO DO BINDING LEGADO ==="
if grep -Eq '^[[:space:]]*ports:[[:space:]]*!reset[[:space:]]*\[\]' "$WAF_COMPOSE"; then
  ok "compose.waf.yml remove explicitamente ports do Nginx com !reset []"
else
  fail "não foi localizado ports: !reset [] no override do Nginx"
fi

echo
echo "=== 5. PORTAS DO HOST ANTES DA SUBIDA ==="
for port in "$WAF_PORT" "$LEGACY_NGINX_PORT"; do
  if ss -H -ltn "( sport = :$port )" 2>/dev/null | grep -q .; then
    fail "porta TCP $port já está ocupada antes do teste"
  else
    ok "porta TCP $port livre"
  fi
done

echo
echo "=== 6. BUILD ==="
if compose build nginx php; then
  ok "imagens Nginx/PHP construídas"
else
  fail "build da DMZ falhou"
fi

echo
echo "=== 7. SUBIDA ==="
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
echo "=== 8. SUPERFÍCIE REAL ==="
docker ps \
  --filter "label=com.docker.compose.project=$PROJECT" \
  --format 'table {{.Names}}\t{{.Ports}}'

PHP_ID="$(compose ps -q php 2>/dev/null || true)"
NGINX_ID="$(compose ps -q nginx 2>/dev/null || true)"
WAF_ID="$(compose ps -q waf 2>/dev/null || true)"

PHP_BINDINGS="$(docker port "$PHP_ID" 2>/dev/null || true)"
NGINX_BINDINGS="$(docker port "$NGINX_ID" 2>/dev/null || true)"
WAF_BINDINGS="$(docker port "$WAF_ID" 8080/tcp 2>/dev/null || true)"

echo "php_bindings=${PHP_BINDINGS:-<nenhum>}"
echo "nginx_bindings=${NGINX_BINDINGS:-<nenhum>}"
echo "waf_bindings=${WAF_BINDINGS:-<nenhum>}"

[[ -z "$PHP_BINDINGS" ]] \
  && ok "PHP-FPM não possui binding no host" \
  || fail "PHP-FPM possui binding no host"

[[ -z "$NGINX_BINDINGS" ]] \
  && ok "Nginx não possui binding no host" \
  || fail "Nginx ainda está publicado diretamente"

printf '%s' "$WAF_BINDINGS" | grep -Fxq "127.0.0.1:${WAF_PORT}" \
  && ok "WAF é o único serviço HTTP publicado" \
  || fail "binding do WAF inesperado"

if ss -H -ltn "( sport = :$LEGACY_NGINX_PORT )" 2>/dev/null | grep -q .; then
  fail "porta legada 8088 continua escutando"
else
  ok "porta legada 8088 não está escutando"
fi

echo
echo "=== 9. PROVA DE QUE O NGINX CONTINUA INTERNO ==="
INTERNAL_CODE="$(
  compose exec -T waf sh -ec '
    if command -v curl >/dev/null 2>&1; then
      curl -sS --max-time 8 -o /dev/null -w "%{http_code}" \
        http://nginx:8080/_container_health
    elif command -v wget >/dev/null 2>&1; then
      wget -q -T 8 -O /dev/null \
        http://nginx:8080/_container_health && printf "200"
    else
      exit 12
    fi
  ' 2>/dev/null || true
)"
echo "waf_para_nginx_health=$INTERNAL_CODE"

[[ "$INTERNAL_CODE" == "200" ]] \
  && ok "WAF alcança Nginx internamente pela frontend" \
  || fail "WAF não alcança Nginx pela rede privada"

echo
echo "=== 10. ACESSO DIRETO DEVE FALHAR ==="
DIRECT_CODE="$(
  curl -sS --max-time 3 \
    -H 'Host: conectaeduca.local' \
    -o /dev/null \
    -w '%{http_code}' \
    "http://127.0.0.1:${LEGACY_NGINX_PORT}/_container_health" \
    2>/dev/null || true
)"
echo "nginx_direto_http=${DIRECT_CODE:-sem-resposta}"

case "${DIRECT_CODE:-}" in
  ""|000)
    ok "acesso direto ao antigo binding do Nginx não é possível"
    ;;
  *)
    fail "Nginx ainda respondeu diretamente no host: HTTP $DIRECT_CODE"
    ;;
esac

echo
echo "=== 11. TRÁFEGO BENIGNO PELO WAF ==="
WAF_HEALTH="$(
  curl -sS --max-time 10 \
    -H 'Host: conectaeduca.local' \
    -o /dev/null \
    -w '%{http_code}' \
    "http://127.0.0.1:${WAF_PORT}/_container_health" \
    2>/dev/null || true
)"
echo "waf_health_http=$WAF_HEALTH"

[[ "$WAF_HEALTH" == "200" ]] \
  && ok "health do Nginx acessível somente através do WAF" \
  || fail "requisição benigna via WAF falhou"

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
echo "=== 12. BLOQUEIO CRS ==="
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
  && ok "XSS sintético bloqueado" \
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
  && ok "SQLi sintético bloqueado" \
  || fail "SQLi não foi bloqueado"

TRAVERSAL_CODE="$(
  curl -sS --max-time 10 \
    -H 'Host: conectaeduca.local' \
    -G \
    --data-urlencode 'file=../../../../etc/passwd' \
    -o /dev/null \
    -w '%{http_code}' \
    "http://127.0.0.1:${WAF_PORT}/" \
    2>/dev/null || true
)"
echo "traversal_http=$TRAVERSAL_CODE"

[[ "$TRAVERSAL_CODE" == "403" ]] \
  && ok "path traversal sintético bloqueado" \
  || info "path traversal retornou HTTP $TRAVERSAL_CODE; XSS/SQLi são critérios obrigatórios"

echo
echo "=== 13. AUDIT LOG / PRIVACIDADE ==="
WAF_LOGS="$(docker logs "$WAF_ID" 2>&1 || true)"

if printf '%s' "$WAF_LOGS" | grep -Eq 'ruleId|ModSecurity|id "[0-9]{6}"'; then
  ok "audit log contém evidência das regras acionadas"
else
  fail "audit log sem evidência de bloqueio"
fi

if printf '%s' "$WAF_LOGS" | grep -Fq "$PRIVACY_PROBE"; then
  fail "header/cookie de prova apareceu no audit log"
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
echo "=== 14. SNAPSHOT DE RECURSOS ==="
IDS="$(compose ps -q)"
docker stats --no-stream \
  --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.BlockIO}}' \
  $IDS || true

echo
echo "=== 15. ENCERRAMENTO ==="
if compose down --remove-orphans; then
  STARTED=0
  ok "stack removida"
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

echo
echo "======================================================================"
echo " RESULTADO"
echo "======================================================================"
echo "Falhas: $FAIL"

if [[ "$FAIL" -eq 0 ]]; then
  echo "FASE 4H-C: APROVADA."
  echo "O WAF é o único ponto de entrada HTTP publicado da DMZ."
  echo "Nginx e PHP-FPM permanecem internos à rede Docker frontend."
  echo "Tráfego benigno passou e ataques sintéticos foram bloqueados."
  echo "A próxima etapa poderá migrar a terminação TLS para o WAF."
else
  echo "FASE 4H-C: REPROVADA."
fi

echo "Relatório: $REPORT"
echo "======================================================================"

[[ "$FAIL" -eq 0 ]]
