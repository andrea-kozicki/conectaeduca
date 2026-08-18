#!/usr/bin/env bash
set -u
export LC_ALL=C
export LANG=C

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"
DMZ="$ROOT/deploy/dmz"

BASE_COMPOSE="$DMZ/compose.yml"
WAF_COMPOSE="$DMZ/compose.waf.yml"
TLS_COMPOSE="$DMZ/compose.waf-tls.yml"

PROJECT="conectaeduca-dmz-waf-tls-test"
HTTP_PORT="${HTTP_PORT:-18080}"
HTTPS_PORT="${HTTPS_PORT:-18443}"
LEGACY_NGINX_PORT="${LEGACY_NGINX_PORT:-8088}"

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/conectaeduca-waf-tls-${STAMP}.txt"

FAIL=0
STARTED=0
TMPDIR_TEST=""
TEST_OVERLAY=""
CTX_FILE=""

ok(){ echo "OK       $*"; }
fail(){ echo "FALHA    $*"; FAIL=$((FAIL+1)); }
info(){ echo "INFO     $*"; }

compose() {
  docker compose \
    -p "$PROJECT" \
    -f "$BASE_COMPOSE" \
    -f "$WAF_COMPOSE" \
    -f "$TLS_COMPOSE" \
    -f "$TEST_OVERLAY" \
    "$@"
}

cleanup() {
  set +e
  if [[ "$STARTED" -eq 1 && -n "${TEST_OVERLAY:-}" ]]; then
    compose down --remove-orphans >/dev/null 2>&1 || true
  fi

  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi

  unset CONECTAEDUCA_WAF_TLS_CERT_FILE
  unset CONECTAEDUCA_WAF_TLS_KEY_FILE
}
trap cleanup EXIT INT TERM

wait_health() {
  local svc="$1"
  local label="$2"
  local elapsed=0 cid state health

  cid="$(compose ps -q "$svc" 2>/dev/null || true)"
  [[ -n "$cid" ]] || return 1

  while (( elapsed <= 150 )); do
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
echo " CONECTAEDUCA - WAF / TLS"
echo " Terminação HTTPS no ModSecurity + CRS"
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
echo "=== 2. PRÉ-REQUISITOS ==="
for cmd in docker curl openssl python3 ss; do
  command -v "$cmd" >/dev/null 2>&1 \
    && ok "$cmd disponível" \
    || fail "$cmd ausente"
done

echo
echo "=== 3. ARQUIVOS VERSIONADOS ==="
for f in \
  deploy/dmz/compose.yml \
  deploy/dmz/compose.waf.yml \
  deploy/dmz/compose.waf-tls.yml \
  deploy/dmz/nginx/app-http.conf \
  deploy/dmz/waf/README.md \
  scripts/evidencias/testar_waf_tls.sh
do
  [[ -f "$ROOT/$f" ]] \
    && ok "$f" \
    || fail "ausente: $f"
done

echo
echo "=== 4. SEGREDOS TLS EFÊMEROS ==="
TMPDIR_TEST="$(mktemp -d /tmp/conectaeduca-waf-tls.XXXXXX)"
chmod 0700 "$TMPDIR_TEST"

CERT_FILE="$TMPDIR_TEST/waf.crt"
KEY_FILE="$TMPDIR_TEST/waf.key"

if openssl req \
  -x509 \
  -newkey rsa:2048 \
  -sha256 \
  -nodes \
  -days 1 \
  -subj "/CN=conectaeduca.local" \
  -addext "subjectAltName=DNS:conectaeduca.local" \
  -keyout "$KEY_FILE" \
  -out "$CERT_FILE" \
  >/dev/null 2>&1
then
  ok "certificado TLS sintético criado"
else
  fail "falha ao gerar certificado TLS sintético"
fi

chmod 0444 "$CERT_FILE" "$KEY_FILE"

MODE_DIR="$(stat -c '%a' "$TMPDIR_TEST" 2>/dev/null || true)"
MODE_CERT="$(stat -c '%a' "$CERT_FILE" 2>/dev/null || true)"
MODE_KEY="$(stat -c '%a' "$KEY_FILE" 2>/dev/null || true)"

echo "tmpdir_mode=$MODE_DIR"
echo "cert_mode=$MODE_CERT"
echo "key_mode=$MODE_KEY"

[[ "$MODE_DIR" == "700" ]] \
  && ok "diretório efêmero privado 0700" \
  || fail "diretório efêmero não está 0700"

export CONECTAEDUCA_WAF_TLS_CERT_FILE="$CERT_FILE"
export CONECTAEDUCA_WAF_TLS_KEY_FILE="$KEY_FILE"

EXPECTED_FP="$(
  openssl x509 -in "$CERT_FILE" -noout -fingerprint -sha256 2>/dev/null |
    sed 's/^sha256 Fingerprint=//I'
)"
echo "cert_sha256_esperado=$EXPECTED_FP"

echo
echo "=== 5. ENDPOINT EFÊMERO PARA VALIDAR HEADERS ==="
CTX_FILE="$TMPDIR_TEST/_waf_context.php"

cat > "$CTX_FILE" <<'PHP'
<?php
header('Content-Type: application/json; charset=utf-8');

echo json_encode([
    'forwarded_proto' => $_SERVER['HTTP_X_FORWARDED_PROTO'] ?? null,
    'forwarded_port' => $_SERVER['HTTP_X_FORWARDED_PORT'] ?? null,
    'client_ip' => $_SERVER['HTTP_X_CONECTAEDUCA_CLIENT_IP'] ?? null,
    'xff' => $_SERVER['HTTP_X_FORWARDED_FOR'] ?? null,
    'host' => $_SERVER['HTTP_HOST'] ?? null,
    'remote_addr' => $_SERVER['REMOTE_ADDR'] ?? null,
], JSON_UNESCAPED_SLASHES);
PHP

chmod 0444 "$CTX_FILE"

TEST_OVERLAY="$TMPDIR_TEST/compose.test.yml"

cat > "$TEST_OVERLAY" <<YAML
services:
  nginx:
    volumes:
      - "$CTX_FILE:/var/www/conectaeduca/public/_waf_context.php:ro"

  php:
    volumes:
      - "$CTX_FILE:/var/www/conectaeduca/public/_waf_context.php:ro"
YAML

ok "endpoint sintético criado somente em /tmp"

echo
echo "=== 6. COMPOSE RESULTANTE ==="
if compose config >/dev/null; then
  ok "Compose base + WAF + TLS + overlay de teste válido"
else
  fail "Compose TLS inválido"
fi

CONFIG_JSON="$(compose config --format json 2>/dev/null || true)"

if printf '%s' "$CONFIG_JSON" | python3 -c '
import json,sys
c=json.load(sys.stdin)
s=c["services"]

assert set(s) == {"nginx","php","waf"}
assert not s["nginx"].get("ports")
assert not s["php"].get("ports")

ports=s["waf"].get("ports",[])
pairs={(p.get("host_ip"),int(p.get("published")),int(p.get("target"))) for p in ports}
assert ("127.0.0.1",18080,8080) in pairs
assert ("127.0.0.1",18443,8443) in pairs

e=s["waf"]["environment"]
assert e["BACKEND"]=="http://nginx:8080"
assert e["SSL_PORT"]=="8443"
assert e["SSL_CERT_FILE"]=="/run/secrets/waf_tls_cert"
assert e["SSL_CERT_KEY_FILE"]=="/run/secrets/waf_tls_key"
assert e["SSL_PROTOCOLS"]=="TLSv1.2 TLSv1.3"
assert e["NGINX_ALWAYS_TLS_REDIRECT"]=="on"
assert e["NGINX_X_FORWARDED_PROTO"]=="https"
assert e["NGINX_X_FORWARDED_PORT"]=="443"
assert e["REAL_IP_PROXY_HEADER"]=="X-ConectaEduca-Client-IP"
assert e["SET_REAL_IP_FROM"]=="127.0.0.1"
assert e["REAL_IP_RECURSIVE"]=="off"

waf_secrets={x["source"] if isinstance(x,dict) else x for x in s["waf"].get("secrets",[])}
assert {"waf_tls_cert","waf_tls_key"} <= waf_secrets
assert not s["nginx"].get("secrets")
assert not s["php"].get("secrets")
'
then
  ok "somente o WAF recebe os secrets TLS"
  ok "TLS 1.2/1.3 configurado no WAF"
  ok "HTTP -> HTTPS habilitado"
  ok "backend continua HTTP privado nginx:8080"
  ok "contexto encaminhado como HTTPS/443"
  ok "header interno de IP configurado"
else
  fail "Compose resultante não corresponde à arquitetura TLS esperada"
fi

echo
echo "=== 7. PORTAS ANTES DA SUBIDA ==="
for port in "$HTTP_PORT" "$HTTPS_PORT" "$LEGACY_NGINX_PORT"; do
  if ss -H -ltn "( sport = :$port )" 2>/dev/null | grep -q .; then
    fail "porta TCP $port já está ocupada"
  else
    ok "porta TCP $port livre"
  fi
done

echo
echo "=== 8. BUILD / SUBIDA ==="
if compose build nginx php; then
  ok "imagens Nginx/PHP construídas"
else
  fail "build falhou"
fi

if compose up -d; then
  STARTED=1
  ok "stack TLS iniciada"
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

if wait_health waf "waf-tls"; then
  ok "WAF HTTPS healthy"
else
  fail "WAF HTTPS não ficou healthy"
fi

echo
echo "=== 9. SUPERFÍCIE REAL ==="
docker ps \
  --filter "label=com.docker.compose.project=$PROJECT" \
  --format 'table {{.Names}}\t{{.Ports}}'

NGINX_ID="$(compose ps -q nginx 2>/dev/null || true)"
PHP_ID="$(compose ps -q php 2>/dev/null || true)"
WAF_ID="$(compose ps -q waf 2>/dev/null || true)"

NGINX_BINDINGS="$(docker port "$NGINX_ID" 2>/dev/null || true)"
PHP_BINDINGS="$(docker port "$PHP_ID" 2>/dev/null || true)"
WAF_HTTP_BINDING="$(docker port "$WAF_ID" 8080/tcp 2>/dev/null || true)"
WAF_HTTPS_BINDING="$(docker port "$WAF_ID" 8443/tcp 2>/dev/null || true)"

echo "nginx_bindings=${NGINX_BINDINGS:-<nenhum>}"
echo "php_bindings=${PHP_BINDINGS:-<nenhum>}"
echo "waf_http_binding=${WAF_HTTP_BINDING:-<nenhum>}"
echo "waf_https_binding=${WAF_HTTPS_BINDING:-<nenhum>}"

[[ -z "$NGINX_BINDINGS" ]] \
  && ok "Nginx continua sem binding no host" \
  || fail "Nginx possui binding indevido"

[[ -z "$PHP_BINDINGS" ]] \
  && ok "PHP-FPM continua sem binding no host" \
  || fail "PHP-FPM possui binding indevido"

printf '%s' "$WAF_HTTP_BINDING" | grep -Fxq "127.0.0.1:${HTTP_PORT}" \
  && ok "HTTP do WAF publicado somente em loopback" \
  || fail "binding HTTP do WAF inesperado"

printf '%s' "$WAF_HTTPS_BINDING" | grep -Fxq "127.0.0.1:${HTTPS_PORT}" \
  && ok "HTTPS do WAF publicado somente em loopback" \
  || fail "binding HTTPS do WAF inesperado"

echo
echo "=== 10. SEPARAÇÃO DOS SECRETS TLS ==="
WAF_MOUNTS="$(docker inspect "$WAF_ID" --format '{{range .Mounts}}{{println .Destination}}{{end}}' 2>/dev/null || true)"
NGINX_MOUNTS="$(docker inspect "$NGINX_ID" --format '{{range .Mounts}}{{println .Destination}}{{end}}' 2>/dev/null || true)"
PHP_MOUNTS="$(docker inspect "$PHP_ID" --format '{{range .Mounts}}{{println .Destination}}{{end}}' 2>/dev/null || true)"

printf '%s\n' "$WAF_MOUNTS" | grep -Fxq '/run/secrets/waf_tls_cert' \
  && ok "WAF recebe certificado TLS" \
  || fail "certificado TLS não montado no WAF"

printf '%s\n' "$WAF_MOUNTS" | grep -Fxq '/run/secrets/waf_tls_key' \
  && ok "WAF recebe chave TLS" \
  || fail "chave TLS não montada no WAF"

if printf '%s\n%s\n' "$NGINX_MOUNTS" "$PHP_MOUNTS" | grep -Eq '/run/secrets/waf_tls_(cert|key)'; then
  fail "secret TLS vazou para Nginx/PHP"
else
  ok "Nginx/PHP não recebem secrets TLS do WAF"
fi

echo
echo "=== 11. CERTIFICADO APRESENTADO ==="
PRESENTED_CERT="$TMPDIR_TEST/presented.crt"

if openssl s_client \
  -connect "127.0.0.1:${HTTPS_PORT}" \
  -servername conectaeduca.local \
  </dev/null 2>/dev/null |
  openssl x509 -outform PEM > "$PRESENTED_CERT" 2>/dev/null
then
  PRESENTED_FP="$(
    openssl x509 -in "$PRESENTED_CERT" -noout -fingerprint -sha256 2>/dev/null |
      sed 's/^sha256 Fingerprint=//I'
  )"
  echo "cert_sha256_apresentado=$PRESENTED_FP"

  [[ -n "$EXPECTED_FP" && "$EXPECTED_FP" == "$PRESENTED_FP" ]] \
    && ok "WAF apresenta exatamente o certificado montado em runtime" \
    || fail "fingerprint do certificado apresentado diverge"
else
  fail "não foi possível obter certificado apresentado pelo WAF"
fi

SAN="$(
  openssl x509 -in "$PRESENTED_CERT" -noout -ext subjectAltName 2>/dev/null |
    tr '\n' ' ' || true
)"
echo "cert_san=$SAN"

printf '%s' "$SAN" | grep -Fq 'DNS:conectaeduca.local' \
  && ok "SAN contém conectaeduca.local" \
  || fail "SAN esperado ausente"

echo
echo "=== 12. TLS ==="
TLS12="$(
  echo | openssl s_client \
    -connect "127.0.0.1:${HTTPS_PORT}" \
    -servername conectaeduca.local \
    -tls1_2 \
    2>/dev/null |
    grep -E '^New, TLSv1\.2|^Protocol *: TLSv1\.2|Protocol  *: TLSv1\.2' |
    head -1 || true
)"
echo "tls12=${TLS12:-sem-negociacao}"

[[ -n "$TLS12" ]] \
  && ok "TLS 1.2 negociado" \
  || fail "TLS 1.2 não foi negociado"

TLS13="$(
  echo | openssl s_client \
    -connect "127.0.0.1:${HTTPS_PORT}" \
    -servername conectaeduca.local \
    -tls1_3 \
    2>/dev/null |
    grep -E '^New, TLSv1\.3|^Protocol *: TLSv1\.3|Protocol  *: TLSv1\.3' |
    head -1 || true
)"
echo "tls13=${TLS13:-sem-negociacao}"

[[ -n "$TLS13" ]] \
  && ok "TLS 1.3 negociado" \
  || info "TLS 1.3 não foi confirmado pelo cliente OpenSSL local"

echo
echo "=== 13. HTTP DEVE REDIRECIONAR PARA HTTPS ==="
HEADERS_HTTP="$TMPDIR_TEST/http-headers.txt"

curl -sS \
  --max-time 10 \
  -D "$HEADERS_HTTP" \
  -o /dev/null \
  -H 'Host: conectaeduca.local' \
  "http://127.0.0.1:${HTTP_PORT}/login.php" \
  2>/dev/null || true

HTTP_STATUS="$(awk 'toupper($1) ~ /^HTTP\// {print $2; exit}' "$HEADERS_HTTP" 2>/dev/null || true)"
LOCATION="$(awk 'BEGIN{IGNORECASE=1} /^Location:/ {sub(/\r$/,""); sub(/^Location:[[:space:]]*/,""); print; exit}' "$HEADERS_HTTP" 2>/dev/null || true)"

echo "http_status=$HTTP_STATUS"
echo "http_location=$LOCATION"

case "$HTTP_STATUS" in
  301|302|307|308)
    ok "HTTP redireciona"
    ;;
  *)
    fail "HTTP não redirecionou para HTTPS"
    ;;
esac

printf '%s' "$LOCATION" | grep -Eq '^https://conectaeduca\.local(/|$)' \
  && ok "Location aponta para HTTPS do host esperado" \
  || fail "Location HTTPS inesperado"

echo
echo "=== 14. HTTPS BENIGNO ==="
HTTPS_HEALTH="$(
  curl -ksS \
    --max-time 10 \
    --resolve "conectaeduca.local:${HTTPS_PORT}:127.0.0.1" \
    -o /dev/null \
    -w '%{http_code}' \
    "https://conectaeduca.local:${HTTPS_PORT}/_container_health" \
    2>/dev/null || true
)"
echo "https_health=$HTTPS_HEALTH"

[[ "$HTTPS_HEALTH" == "200" ]] \
  && ok "requisição HTTPS atravessa WAF e alcança Nginx" \
  || fail "health HTTPS falhou"

CSS_CODE="$(
  curl -ksS \
    --max-time 10 \
    --resolve "conectaeduca.local:${HTTPS_PORT}:127.0.0.1" \
    -o /dev/null \
    -w '%{http_code}' \
    "https://conectaeduca.local:${HTTPS_PORT}/assets/css/style.css" \
    2>/dev/null || true
)"
echo "https_css=$CSS_CODE"

case "$CSS_CODE" in
  200|304)
    ok "ativo público atravessa HTTPS + WAF"
    ;;
  *)
    fail "ativo público não atravessou HTTPS + WAF"
    ;;
esac

echo
echo "=== 15. CONTEXTO HTTPS E ANTI-SPOOFING ==="
CTX_JSON="$(
  curl -ksS \
    --max-time 10 \
    --resolve "conectaeduca.local:${HTTPS_PORT}:127.0.0.1" \
    -H 'X-ConectaEduca-Client-IP: 203.0.113.77' \
    -H 'X-Forwarded-For: 198.51.100.88' \
    "https://conectaeduca.local:${HTTPS_PORT}/_waf_context.php" \
    2>/dev/null || true
)"

echo "contexto_backend=$CTX_JSON"

if printf '%s' "$CTX_JSON" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["forwarded_proto"]=="https"
assert d["forwarded_port"]=="443"
assert d["client_ip"]
assert d["client_ip"]!="203.0.113.77"
'
then
  ok "backend recebe X-Forwarded-Proto=https"
  ok "backend recebe X-Forwarded-Port=443"
  ok "header interno de IP foi sobrescrito pelo WAF"
else
  fail "contexto HTTPS/IP encaminhado ao backend divergiu"
fi

XFF_VALUE="$(
  printf '%s' "$CTX_JSON" |
  python3 -c 'import json,sys; print((json.load(sys.stdin).get("xff") or ""))' 2>/dev/null || true
)"
echo "xff_recebido=${XFF_VALUE:-<vazio>}"
info "X-Forwarded-For é apenas evidência; não será tratado como origem confiável pelo backend"

echo
echo "=== 16. BLOQUEIO CRS SOBRE HTTPS ==="
XSS_CODE="$(
  curl -ksS \
    --max-time 10 \
    --resolve "conectaeduca.local:${HTTPS_PORT}:127.0.0.1" \
    -G \
    --data-urlencode 'q=<script>alert(1)</script>' \
    -o /dev/null \
    -w '%{http_code}' \
    "https://conectaeduca.local:${HTTPS_PORT}/" \
    2>/dev/null || true
)"
echo "https_xss=$XSS_CODE"

[[ "$XSS_CODE" == "403" ]] \
  && ok "XSS sintético bloqueado após terminação TLS" \
  || fail "XSS não foi bloqueado sobre HTTPS"

SQLI_CODE="$(
  curl -ksS \
    --max-time 10 \
    --resolve "conectaeduca.local:${HTTPS_PORT}:127.0.0.1" \
    -G \
    --data-urlencode "id=1' OR '1'='1" \
    -o /dev/null \
    -w '%{http_code}' \
    "https://conectaeduca.local:${HTTPS_PORT}/" \
    2>/dev/null || true
)"
echo "https_sqli=$SQLI_CODE"

[[ "$SQLI_CODE" == "403" ]] \
  && ok "SQLi sintético bloqueado após terminação TLS" \
  || fail "SQLi não foi bloqueado sobre HTTPS"

echo
echo "=== 17. AUDIT LOG / PRIVACIDADE ==="
PROBE="segredo-nao-logar-${STAMP}"

curl -ksS \
  --max-time 10 \
  --resolve "conectaeduca.local:${HTTPS_PORT}:127.0.0.1" \
  -H "X-ConectaEduca-Probe: ${PROBE}" \
  -H "Cookie: CONECTAEDUCASESSID=${PROBE}" \
  -G \
  --data-urlencode 'q=<script>alert(1)</script>' \
  -o /dev/null \
  "https://conectaeduca.local:${HTTPS_PORT}/" \
  2>/dev/null || true

WAF_LOGS="$(docker logs "$WAF_ID" 2>&1 || true)"

if printf '%s' "$WAF_LOGS" | grep -Eq 'ruleId|ModSecurity|id "[0-9]{6}"'; then
  ok "audit log contém evidência de regras acionadas"
else
  fail "audit log sem evidência de bloqueio"
fi

if printf '%s' "$WAF_LOGS" | grep -Fq "$PROBE"; then
  fail "probe de cookie/header apareceu no audit log"
else
  ok "cookie/header de prova não foi persistido no audit log"
fi

if printf '%s' "$WAF_LOGS" | grep -Fq '"request_body"'; then
  fail "request_body apareceu no audit log"
else
  ok "request_body não foi observado no audit log"
fi

echo "--- IDs de regras observados ---"
printf '%s\n' "$WAF_LOGS" |
  grep -Eo 'id "[0-9]{6}"|ruleId["=: ]+[0-9]{6}' |
  sort -u |
  head -20 || true

echo
echo "=== 18. RECURSOS ==="
IDS="$(compose ps -q)"
docker stats --no-stream \
  --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.BlockIO}}' \
  $IDS || true

echo
echo "=== 19. ENCERRAMENTO ==="
if compose down --remove-orphans; then
  STARTED=0
  ok "stack TLS removida"
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
echo "=== 20. GIT FINAL ==="
git status -sb

git diff --check \
  && ok "git diff --check final" \
  || fail "git diff --check final"

if git ls-files | grep -Eq '(^|/)\.runtime/|(^|/)\.env$|\.pem$|\.key$|\.p12$|\.pfx$'; then
  info "há nomes sensíveis rastreados previamente; revisão contextual continua necessária"
else
  ok "nenhum nome sensível óbvio rastreado pelo Git"
fi

echo
echo "======================================================================"
echo " RESULTADO"
echo "======================================================================"
echo "Falhas: $FAIL"

if [[ "$FAIL" -eq 0 ]]; then
  echo "WAF / TLS: APROVADO."
  echo "TLS termina no WAF; Nginx e PHP-FPM permanecem internos."
  echo "HTTP redireciona para HTTPS e TLS 1.2 foi confirmado."
  echo "O backend recebe contexto HTTPS/443 e header interno de IP não aceita spoof direto."
  echo "XSS e SQLi continuaram bloqueados após a terminação TLS."
else
  echo "WAF / TLS: REPROVADO."
fi

echo "Relatório: $REPORT"
echo "======================================================================"

[[ "$FAIL" -eq 0 ]]
