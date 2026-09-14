#!/usr/bin/env bash
set -Eeuo pipefail

umask 077
export LC_ALL=C
export LANG=C

BASE_URL="${BASE_URL:-https://192.168.6.34}"
DMZ_PROJECT="${DMZ_PROJECT:-conectaeduca-dmz}"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="${REPORT:-$HOME/conectaeduca-evidencia-waf-login-senha-${STAMP}.txt}"
TMPDIR_TEST="$(mktemp -d)"
COOKIE_JAR="$TMPDIR_TEST/cookies.txt"
LOGIN_HTML="$TMPDIR_TEST/login.html"
HEADERS="$TMPDIR_TEST/headers.txt"

PASS=0
WARN=0
FAIL=0

cleanup() {
  rm -rf "$TMPDIR_TEST"
}
trap cleanup EXIT INT TERM

pass() { printf '[PASS] %s\n' "$*"; PASS=$((PASS+1)); }
warn() { printf '[WARN] %s\n' "$*"; WARN=$((WARN+1)); }
fail() { printf '[FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }

extract_csrf() {
  python3 - "$1" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import sys

class Parser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.token = None

    def handle_starttag(self, tag, attrs):
        if tag.lower() != "input":
            return
        data = dict(attrs)
        if data.get("name") == "csrf_token" and data.get("value"):
            self.token = data["value"]

p = Parser()
p.feed(Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace"))
if not p.token:
    raise SystemExit(1)
print(p.token)
PY
}

main() {
  set -Eeuo pipefail

printf '%s\n' '======================================================================'
printf '%s\n' ' ConectaEduca - regressão WAF / senha opaca no login'
printf ' Data: %s\n' "$(date --iso-8601=seconds)"
printf ' Base URL: %s\n' "$BASE_URL"
printf '%s\n' '======================================================================'

printf '\n=== 1. RUNTIME ===\n'

resolve_container() {
  local service="$1"
  local explicit="${2:-}"
  local matches=()

  if [[ -n "$explicit" ]]; then
    if sudo docker inspect "$explicit" >/dev/null 2>&1; then
      printf '%s' "$explicit"
      return 0
    fi

    return 1
  fi

  mapfile -t matches < <(
    sudo docker ps \
      --filter "label=com.docker.compose.project=$DMZ_PROJECT" \
      --filter "label=com.docker.compose.service=$service" \
      --format '{{.Names}}'
  )

  if [[ "${#matches[@]}" -ne 1 ]]; then
    return 1
  fi

  printf '%s' "${matches[0]}"
}

WAF_CONTAINER="$(resolve_container waf "${WAF_CONTAINER:-}" || true)"
PHP_CONTAINER="$(resolve_container php "${PHP_CONTAINER:-}" || true)"

printf 'BASE_URL=%s\n' "$BASE_URL"
printf 'DMZ_PROJECT=%s\n' "$DMZ_PROJECT"
printf 'WAF_CONTAINER=%s\n' "${WAF_CONTAINER:-<vazio>}"
printf 'PHP_CONTAINER=%s\n' "${PHP_CONTAINER:-<vazio>}"

if [[ -n "$WAF_CONTAINER" && -n "$PHP_CONTAINER" ]]; then
  pass "WAF e PHP pertencem ao stack alvo ou foram informados explicitamente"
else
  fail "não foi possível resolver unicamente WAF/PHP do projeto $DMZ_PROJECT"
fi

WAF_HEALTH="$(sudo docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$WAF_CONTAINER" 2>/dev/null || true)"
PHP_HEALTH="$(sudo docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$PHP_CONTAINER" 2>/dev/null || true)"
printf 'WAF_HEALTH=%s\n' "$WAF_HEALTH"
printf 'PHP_HEALTH=%s\n' "$PHP_HEALTH"

[[ "$WAF_HEALTH" == "healthy" ]] && pass "WAF healthy" || fail "WAF não está healthy"
[[ "$PHP_HEALTH" == "healthy" ]] && pass "PHP healthy" || fail "PHP não está healthy"

printf '\n=== 2. POLÍTICA LIVE ===\n'

LIVE_POLICY='/etc/modsecurity.d/owasp-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf'

POLICY_TEXT="$(sudo docker exec "$WAF_CONTAINER" cat "$LIVE_POLICY" 2>/dev/null || true)"

if printf '%s\n' "$POLICY_TEXT" | grep -Fq '@streq /login.php' &&
   printf '%s\n' "$POLICY_TEXT" | grep -Fq 'ruleRemoveTargetById=932240;ARGS:senha'; then
  pass "exclusão granular /login.php + 932240 + ARGS:senha presente"
else
  fail "exclusão granular esperada não está ativa no WAF"
fi

printf '\n=== 3. LOGIN LEGÍTIMO/INVÁLIDO COM SENHA SINTÉTICA ===\n'

LOGIN_GET="$(
  curl -sS \
    --max-time 12 \
    -c "$COOKIE_JAR" \
    -o "$LOGIN_HTML" \
    -w '%{http_code}' \
    "$BASE_URL/login.php" \
    2>/dev/null || true
)"
printf 'LOGIN_GET_HTTP=%s\n' "$LOGIN_GET"

[[ "$LOGIN_GET" == "200" ]] && pass "GET /login.php" || fail "GET /login.php retornou $LOGIN_GET"

CSRF="$(extract_csrf "$LOGIN_HTML" 2>/dev/null || true)"
[[ -n "$CSRF" ]] && pass "CSRF obtido" || fail "CSRF não encontrado"

PROBE_EMAIL="waf-regressao-${STAMP}@example.invalid"
# Não é credencial real: contém deliberadamente um padrão que já causou
# falso positivo na regra CRS 932240 em campo de senha legítima.
PROBE_VALUE="$(printf "CE-WAF-Teste%s%s%s-Aa%s!" 7 "'" 8 9)"

LOGIN_POST="$(
  curl -sS \
    --max-time 12 \
    -b "$COOKIE_JAR" \
    -c "$COOKIE_JAR" \
    -D "$HEADERS" \
    -o /dev/null \
    -w '%{http_code}' \
    --data-urlencode "csrf_token=$CSRF" \
    --data-urlencode "email=$PROBE_EMAIL" \
    --data-urlencode "senha=$PROBE_VALUE" \
    "$BASE_URL/login.php" \
    2>/dev/null || true
)"
printf 'LOGIN_PROBE_HTTP=%s\n' "$LOGIN_POST"

if [[ "$LOGIN_POST" == "401" ]]; then
  pass "senha sintética atravessou o WAF e chegou à autenticação"
elif [[ "$LOGIN_POST" == "403" ]]; then
  fail "WAF ainda bloqueou o campo senha"
else
  fail "login sintético retornou HTTP ${LOGIN_POST:-sem-resposta}; esperado 401"
fi

EMAIL_HASH="$(printf '%s' "$PROBE_EMAIL" | sha256sum | awk '{print $1}')"
APP_LOG="$(sudo docker exec "$PHP_CONTAINER" tail -n 200 /var/www/conectaeduca/storage/logs/audit.log 2>/dev/null || true)"

if printf '%s\n' "$APP_LOG" | grep -F "$EMAIL_HASH" | grep -Fq '"event":"login_failed"'; then
  pass "aplicação registrou login_failed para o probe; requisição chegou ao PHP"
else
  fail "não foi localizado login_failed correlacionado ao probe"
fi

printf '\n=== 4. REGRA 932240 CONTINUA ATIVA FORA DE ARGS:senha ===\n'

curl -sS --max-time 12 -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  -o "$LOGIN_HTML" "$BASE_URL/login.php" 2>/dev/null || true
CSRF2="$(extract_csrf "$LOGIN_HTML" 2>/dev/null || true)"
CONTROL_VALUE="$(printf 'CE-Controle-Aa%s!' 9)"
CONTROL_MARKER="cectrl-${STAMP}-$(date +%s%N)-${RANDOM}"
CONTROL_ARG="$(printf '%s-%s%s%s' "$CONTROL_MARKER" 7 "'" 8)"
CONTROL_SINCE="$(date --iso-8601=ns)"

CONTROL_POST="$(
  curl -sS \
    --max-time 12 \
    -b "$COOKIE_JAR" \
    -c "$COOKIE_JAR" \
    -o /dev/null \
    -w '%{http_code}' \
    --data-urlencode "csrf_token=$CSRF2" \
    --data-urlencode "email=$PROBE_EMAIL" \
    --data-urlencode "senha=$CONTROL_VALUE" \
    --data-urlencode "comando=$CONTROL_ARG" \
    "$BASE_URL/login.php" \
    2>/dev/null || true
)"
printf 'CONTROL_OTHER_ARG_HTTP=%s\n' "$CONTROL_POST"
printf 'CONTROL_MARKER=%s\n' "$CONTROL_MARKER"

if [[ "$CONTROL_POST" == "403" ]]; then
  pass "WAF continua bloqueando padrão 932240 em argumento diferente de senha"
else
  fail "controle de outro argumento retornou $CONTROL_POST; regra 932240 não ficou comprovadamente bloqueante"
fi

sleep 1
CONTROL_WAF="$(sudo docker logs --since "$CONTROL_SINCE" "$WAF_CONTAINER" 2>&1 || true)"

if printf '%s\n' "$CONTROL_WAF" \
    | grep -F "$CONTROL_MARKER" \
    | grep -F '932240' \
    | grep -Fq 'ARGS:comando'; then
  pass "regra 932240 correlacionada à requisição de controle atual"
else
  fail "não foi possível correlacionar a requisição atual com 932240 em ARGS:comando"
fi

printf '\n=== 5. CONTROLE CRS GERAL ===\n'

XSS_CODE="$(
  curl -sS \
    --max-time 12 \
    -G \
    --data-urlencode 'q=<script>alert(1)</script>' \
    -o /dev/null \
    -w '%{http_code}' \
    "$BASE_URL/" \
    2>/dev/null || true
)"
printf 'XSS_HTTP=%s\n' "$XSS_CODE"

[[ "$XSS_CODE" == "403" ]] && pass "XSS sintético continua bloqueado" || fail "XSS sintético retornou $XSS_CODE"

printf '\n=== RESULTADO ===\n'
printf 'PASS=%d WARN=%d FAIL=%d\n' "$PASS" "$WARN" "$FAIL"
printf 'REPORT=%s\n' "$REPORT"

if [[ "$FAIL" -eq 0 ]]; then
  printf '%s\n' 'STATUS=APROVADO'
  return 0
fi

printf '%s\n' 'STATUS=REPROVADO'
return 1
}

# O relatório é fechado pelo tee antes do cálculo do digest. Isso garante
# que o SHA-256 corresponda exatamente ao arquivo final salvo em disco.
set +e
main 2>&1 | tee "$REPORT"
PIPE_STATUS=("${PIPESTATUS[@]}")
set -e

MAIN_RC="${PIPE_STATUS[0]:-1}"
TEE_RC="${PIPE_STATUS[1]:-1}"

if [[ "$MAIN_RC" -eq 0 && "$TEE_RC" -ne 0 ]]; then
  MAIN_RC="$TEE_RC"
fi

SHA_FILE="${REPORT}.sha256"
sha256sum "$REPORT" > "$SHA_FILE"

printf '\nSHA256 do relatório final:\n'
cat "$SHA_FILE"
printf 'SHA256_FILE=%s\n' "$SHA_FILE"

exit "$MAIN_RC"
