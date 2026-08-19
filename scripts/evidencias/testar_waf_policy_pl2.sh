#!/usr/bin/env bash
set -u
export LC_ALL=C
export LANG=C

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"

DMZ_BASE="$ROOT/deploy/dmz/compose.yml"
DMZ_DB="$ROOT/deploy/dmz/compose.database.yml"
DMZ_APP_SECRETS="$ROOT/deploy/dmz/compose.app-secrets.yml"
DMZ_WAF="$ROOT/deploy/dmz/compose.waf.yml"
DMZ_WAF_TLS="$ROOT/deploy/dmz/compose.waf-tls.yml"
DMZ_WAF_POLICY="$ROOT/deploy/dmz/compose.waf-policy.yml"

INTERNAL="$ROOT/deploy/interna/mariadb/compose.yml"

DMZ_PROJECT="conectaeduca-dmz-waf-policy-test"
INTERNAL_PROJECT="conectaeduca-mariadb-waf-policy-test"

NETWORK="${CONECTAEDUCA_TRANSIT_NETWORK:-conectaeduca-transit-waf-policy}"
SUBNET="${CONECTAEDUCA_TRANSIT_SUBNET:-172.30.253.0/24}"
DB_IP="${CONECTAEDUCA_DB_HOST:-172.30.253.10}"
PHP_IP="${CONECTAEDUCA_PHP_TRANSIT_IP:-172.30.253.20}"

HTTPS_PORT="${HTTPS_PORT:-18443}"
HOST_NAME="${CONECTAEDUCA_HOST_HEADER:-conectaeduca.local}"

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/conectaeduca-waf-policy-pl2-${STAMP}.txt"

FAIL=0
ABORT=0
STARTED=0
SECRET_DIR=""
TMPDIR_TEST=""

ok(){ echo "OK       $*"; }
fail(){ echo "FALHA    $*"; FAIL=$((FAIL+1)); }
info(){ echo "INFO     $*"; }

dmz() {
  docker compose \
    -p "$DMZ_PROJECT" \
    -f "$DMZ_BASE" \
    -f "$DMZ_DB" \
    -f "$DMZ_APP_SECRETS" \
    -f "$DMZ_WAF" \
    -f "$DMZ_WAF_TLS" \
    -f "$DMZ_WAF_POLICY" \
    "$@"
}

internal() {
  docker compose \
    -p "$INTERNAL_PROJECT" \
    -f "$INTERNAL" \
    "$@"
}

cleanup() {
  set +e

  if [[ "$STARTED" -eq 1 ]]; then
    dmz down --remove-orphans >/dev/null 2>&1 || true
    internal down -v --remove-orphans >/dev/null 2>&1 || true
  fi

  docker network rm "$NETWORK" >/dev/null 2>&1 || true

  [[ -n "${SECRET_DIR:-}" && -d "$SECRET_DIR" ]] && rm -rf "$SECRET_DIR"
  [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]] && rm -rf "$TMPDIR_TEST"

  unset CONECTAEDUCA_DB_ROOT_PASSWORD_FILE
  unset CONECTAEDUCA_DB_PASSWORD_FILE
  unset CONECTAEDUCA_DB_HOST
  unset CONECTAEDUCA_PRIVATE_KEY_FILE
  unset CONECTAEDUCA_PUBLIC_KEY_FILE
  unset CONECTAEDUCA_WAF_TLS_CERT_FILE
  unset CONECTAEDUCA_WAF_TLS_KEY_FILE
}
trap cleanup EXIT INT TERM

wait_healthy() {
  local label="$1"
  local id="$2"
  local timeout="${3:-150}"
  local elapsed=0 state health

  while (( elapsed <= timeout )); do
    state="$(docker inspect "$id" --format '{{.State.Status}}' 2>/dev/null || true)"
    health="$(docker inspect "$id" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}sem-healthcheck{{end}}' 2>/dev/null || true)"

    if (( elapsed % 5 == 0 )); then
      echo "health_wait label=$label t=${elapsed}s state=${state:-?} health=${health:-?}"
    fi

    if [[ "$state" == "running" && "$health" == "healthy" ]]; then
      return 0
    fi

    if [[ "$state" == "exited" || "$state" == "dead" ]]; then
      return 1
    fi

    sleep 1
    elapsed=$((elapsed+1))
  done

  return 1
}

https_code() {
  local path="$1"
  curl -ksS \
    --max-time 12 \
    --resolve "${HOST_NAME}:${HTTPS_PORT}:127.0.0.1" \
    -o /dev/null \
    -w '%{http_code}' \
    "https://${HOST_NAME}:${HTTPS_PORT}${path}" \
    2>/dev/null || true
}

extract_csrf() {
  local html_file="$1"

  python3 - "$html_file" <<'PY'
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
if p.token:
    print(p.token)
PY
}

request_expect() {
  local label="$1"
  local path="$2"
  local expected="$3"
  local code

  code="$(https_code "$path")"
  echo "route=$path http=$code esperado=$expected"

  if [[ "$code" == "$expected" ]]; then
    ok "$label"
  elif [[ "$code" == "403" && "$expected" != "403" ]]; then
    fail "$label: possível falso positivo CRS PL2 (esperado $expected, recebeu 403)"
  else
    fail "$label: esperado $expected, recebeu ${code:-sem-resposta}"
  fi
}

container_is_member() {
  local network_json="$1"
  local target_id="$2"

  printf '%s' "$network_json" | python3 -c '
import json, sys
network = json.load(sys.stdin)[0]
containers = network.get("Containers") or {}
target = sys.argv[1]

for cid in containers:
    if cid == target or target.startswith(cid) or cid.startswith(target):
        raise SystemExit(0)

raise SystemExit(1)
' "$target_id"
}

exec > >(tee "$REPORT") 2>&1

echo "======================================================================"
echo " CONECTAEDUCA - WAF / POLÍTICA PL2"
echo " Validação de PL2 em bloqueio com política candidata final"
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
  || { fail "execute em feature/auth-local"; ABORT=1; }

git diff --check \
  && ok "git diff --check" \
  || { fail "git diff --check"; ABORT=1; }

echo
echo "=== 2. ARQUIVOS ==="
for f in \
  deploy/dmz/compose.yml \
  deploy/dmz/compose.database.yml \
  deploy/dmz/compose.app-secrets.yml \
  deploy/dmz/compose.waf.yml \
  deploy/dmz/compose.waf-tls.yml \
  deploy/dmz/compose.waf-policy.yml \
  deploy/dmz/waf/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf \
  deploy/dmz/waf/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf \
  deploy/interna/mariadb/compose.yml
do
  [[ -f "$ROOT/$f" ]] \
    && ok "$f" \
    || { fail "ausente: $f"; ABORT=1; }
done

echo
echo "=== 3. POLÍTICA CANDIDATA FINAL ==="
if grep -q 'BLOCKING_PARANOIA: "2"' "$DMZ_WAF_POLICY" &&
   grep -q 'DETECTION_PARANOIA: "2"' "$DMZ_WAF_POLICY" &&
   grep -q 'MODSEC_AUDIT_ENGINE: "RelevantOnly"' "$DMZ_WAF_POLICY" &&
   grep -q 'MODSEC_AUDIT_LOG_PARTS: "AFHZ"' "$DMZ_WAF_POLICY"; then
  ok "PL2 em bloqueio e detecção"
  ok "audit log RelevantOnly / AFHZ"
else
  fail "compose.waf-policy.yml diverge da política esperada"
  ABORT=1
fi

NONCOMMENT_BEFORE="$(
  grep -Ev '^[[:space:]]*(#|$)' \
    deploy/dmz/waf/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf \
    2>/dev/null || true
)"
NONCOMMENT_AFTER="$(
  grep -Ev '^[[:space:]]*(#|$)' \
    deploy/dmz/waf/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf \
    2>/dev/null || true
)"

if [[ -z "$NONCOMMENT_BEFORE" && -z "$NONCOMMENT_AFTER" ]]; then
  ok "nenhuma exclusão CRS configurada"
else
  info "existem exclusões CRS; revisar antes de tratar política como baseline final"
fi

echo
echo "=== 4. SEGREDOS EFÊMEROS ==="
SECRET_DIR="$(mktemp -d /tmp/conectaeduca-waf-policy-secrets.XXXXXX)"
TMPDIR_TEST="$(mktemp -d /tmp/conectaeduca-waf-policy-tmp.XXXXXX)"
chmod 0700 "$SECRET_DIR" "$TMPDIR_TEST"

ROOT_SECRET="$SECRET_DIR/mariadb_root_password"
APP_SECRET="$SECRET_DIR/conectaeduca_db_password"
APP_PRIVATE="$SECRET_DIR/conectaeduca_private_key"
APP_PUBLIC="$SECRET_DIR/conectaeduca_public_key"
WAF_TLS_KEY="$SECRET_DIR/waf_tls_key"
WAF_TLS_CERT="$SECRET_DIR/waf_tls_cert"

openssl rand -hex 32 > "$ROOT_SECRET"
openssl rand -hex 32 > "$APP_SECRET"

openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:2048 \
  -out "$APP_PRIVATE" \
  >/dev/null 2>&1

openssl pkey \
  -in "$APP_PRIVATE" \
  -pubout \
  -out "$APP_PUBLIC" \
  >/dev/null 2>&1

openssl req \
  -x509 \
  -newkey rsa:2048 \
  -sha256 \
  -nodes \
  -days 1 \
  -subj "/CN=${HOST_NAME}" \
  -addext "subjectAltName=DNS:${HOST_NAME}" \
  -keyout "$WAF_TLS_KEY" \
  -out "$WAF_TLS_CERT" \
  >/dev/null 2>&1

chmod 0444 \
  "$ROOT_SECRET" \
  "$APP_SECRET" \
  "$APP_PRIVATE" \
  "$APP_PUBLIC" \
  "$WAF_TLS_KEY" \
  "$WAF_TLS_CERT"

export CONECTAEDUCA_DB_ROOT_PASSWORD_FILE="$ROOT_SECRET"
export CONECTAEDUCA_DB_PASSWORD_FILE="$APP_SECRET"
export CONECTAEDUCA_DB_HOST="$DB_IP"
export CONECTAEDUCA_PRIVATE_KEY_FILE="$APP_PRIVATE"
export CONECTAEDUCA_PUBLIC_KEY_FILE="$APP_PUBLIC"
export CONECTAEDUCA_WAF_TLS_CERT_FILE="$WAF_TLS_CERT"
export CONECTAEDUCA_WAF_TLS_KEY_FILE="$WAF_TLS_KEY"

ok "segredos sintéticos preparados fora do Git"

echo
echo "=== 5. COMPOSE ==="
internal config >/dev/null \
  && ok "Compose MariaDB válido" \
  || { fail "Compose MariaDB inválido"; ABORT=1; }

dmz config >/dev/null \
  && ok "Compose DMZ completo com política PL2 válido" \
  || { fail "Compose DMZ inválido"; ABORT=1; }

CONFIG_JSON="$(dmz config --format json 2>/dev/null || true)"

if printf '%s' "$CONFIG_JSON" | python3 -c '
import json,sys
c=json.load(sys.stdin)["services"]
assert set(c)=={"nginx","php","waf"}
assert not c["nginx"].get("ports")
assert not c["php"].get("ports")
e=c["waf"]["environment"]
assert str(e["BLOCKING_PARANOIA"])=="2"
assert str(e["DETECTION_PARANOIA"])=="2"
assert e["MODSEC_AUDIT_ENGINE"]=="RelevantOnly"
assert e["MODSEC_AUDIT_LOG_PARTS"]=="AFHZ"
assert e["BACKEND"]=="http://nginx:8080"
'
then
  ok "Compose resultante confirma PL2 + RelevantOnly"
else
  fail "Compose resultante diverge da política candidata final"
  ABORT=1
fi

if [[ "$ABORT" -ne 0 ]]; then
  echo "Validação interrompida antes da subida."
  echo "Falhas: $FAIL"
  echo "Relatório: $REPORT"
  exit 1
fi

echo
echo "=== 6. BUILD / REDE DE TRÂNSITO ==="
dmz build nginx php \
  && ok "imagens Nginx/PHP construídas" \
  || { fail "build DMZ falhou"; ABORT=1; }

if docker network inspect "$NETWORK" >/dev/null 2>&1; then
  fail "rede $NETWORK já existe; resíduo de teste"
  ABORT=1
else
  docker network create \
    --driver bridge \
    --subnet "$SUBNET" \
    "$NETWORK" \
    >/dev/null \
    && ok "rede de trânsito criada" \
    || { fail "falha ao criar rede de trânsito"; ABORT=1; }
fi

echo
echo "=== 7. MARIADB INTERNO ==="
if internal up -d; then
  STARTED=1
  ok "MariaDB iniciado"
else
  fail "MariaDB não iniciou"
  ABORT=1
fi

DB_ID="$(internal ps -q mariadb 2>/dev/null || true)"

if [[ "$ABORT" -eq 0 && -n "$DB_ID" ]] &&
   wait_healthy "mariadb" "$DB_ID" 150; then
  ok "MariaDB healthy"
else
  fail "MariaDB não ficou healthy"
  ABORT=1
fi

if [[ "$ABORT" -eq 0 ]] &&
   docker network connect --ip "$DB_IP" "$NETWORK" "$DB_ID"; then
  ok "MariaDB conectado à rede de trânsito"
else
  fail "MariaDB não conectado à rede de trânsito"
  ABORT=1
fi

echo
echo "=== 8. DMZ COMPLETA ==="
if [[ "$ABORT" -eq 0 ]] && dmz up -d; then
  ok "DMZ iniciada"
else
  fail "DMZ não iniciou"
  ABORT=1
fi

PHP_ID="$(dmz ps -q php 2>/dev/null || true)"
NGINX_ID="$(dmz ps -q nginx 2>/dev/null || true)"
WAF_ID="$(dmz ps -q waf 2>/dev/null || true)"

if [[ "$ABORT" -eq 0 && -n "$PHP_ID" ]] &&
   wait_healthy "php-fpm" "$PHP_ID" 90; then
  ok "PHP-FPM healthy"
else
  fail "PHP-FPM não ficou healthy"
  ABORT=1
fi

if [[ "$ABORT" -eq 0 ]] &&
   docker network connect --ip "$PHP_IP" "$NETWORK" "$PHP_ID"; then
  ok "PHP conectado à rede de trânsito"
else
  fail "PHP não conectado à rede de trânsito"
  ABORT=1
fi

if [[ "$ABORT" -eq 0 && -n "$NGINX_ID" ]] &&
   wait_healthy "nginx" "$NGINX_ID" 90; then
  ok "Nginx healthy"
else
  fail "Nginx não ficou healthy"
  ABORT=1
fi

if [[ "$ABORT" -eq 0 && -n "$WAF_ID" ]] &&
   wait_healthy "waf" "$WAF_ID" 150; then
  ok "WAF TLS healthy"
else
  fail "WAF não ficou healthy"
  dmz logs --no-color --tail=120 waf || true
  ABORT=1
fi

if [[ "$ABORT" -ne 0 ]]; then
  echo "Validação interrompida após falha de infraestrutura."
  echo "Falhas: $FAIL"
  echo "Relatório: $REPORT"
  exit 1
fi

echo
echo "=== 9. SEGMENTAÇÃO ==="
MEMBERS="$(
  docker network inspect "$NETWORK" \
    --format '{{range .Containers}}{{.Name}}|{{.IPv4Address}}{{println}}{{end}}' \
    2>/dev/null | sort || true
)"
printf '%s\n' "$MEMBERS"

NETWORK_JSON="$(docker network inspect "$NETWORK" 2>/dev/null || true)"

container_is_member "$NETWORK_JSON" "$WAF_ID" \
  && fail "WAF participa indevidamente da rede do banco" \
  || ok "WAF fora da rede do banco"

container_is_member "$NETWORK_JSON" "$NGINX_ID" \
  && fail "Nginx participa indevidamente da rede do banco" \
  || ok "Nginx fora da rede do banco"

container_is_member "$NETWORK_JSON" "$PHP_ID" \
  && ok "PHP na rede de trânsito" \
  || fail "PHP fora da rede de trânsito"

container_is_member "$NETWORK_JSON" "$DB_ID" \
  && ok "MariaDB na rede de trânsito" \
  || fail "MariaDB fora da rede de trânsito"

echo
echo "=== 10. ROTAS LEGÍTIMAS COM PL2 BLOQUEANDO ==="
request_expect "página inicial" "/index.php" "200"
request_expect "oportunidades" "/oportunidades.php" "200"
request_expect "cadastro" "/cadastro_usuario.php" "200"
request_expect "login" "/login.php" "200"
request_expect "CSS" "/assets/css/style.css" "200"
request_expect "JS CSRF" "/assets/js/csrf.js" "200"
request_expect "chave pública" "/api/public_key.php" "200"
request_expect "API oportunidades" "/api/oportunidades.php" "200"

FILTER_CODE="$(
  curl -ksS \
    --max-time 12 \
    --resolve "${HOST_NAME}:${HTTPS_PORT}:127.0.0.1" \
    -G \
    --data-urlencode "busca=Analista C/C++ e Node.js" \
    --data-urlencode "area=Pesquisa & Desenvolvimento" \
    --data-urlencode "modalidade=hibrido" \
    --data-urlencode "tipo=estagio" \
    -o /dev/null \
    -w '%{http_code}' \
    "https://${HOST_NAME}:${HTTPS_PORT}/oportunidades.php" \
    2>/dev/null || true
)"
echo "filtros_legitimos_http=$FILTER_CODE"

[[ "$FILTER_CODE" == "200" ]] \
  && ok "filtros legítimos atravessam PL2" \
  || { [[ "$FILTER_CODE" == "403" ]] && fail "falso positivo PL2 nos filtros legítimos" || fail "filtros retornaram $FILTER_CODE"; }

echo
echo "=== 11. CONTROLES DA APLICAÇÃO ==="
request_expect "dashboard sem sessão" "/dashboard.php" "401"
request_expect "perfil sem sessão" "/perfil.php" "401"
request_expect "empresa sem sessão" "/empresa/oportunidades.php" "401"
request_expect "admin sem sessão" "/admin/auditoria.php" "401"

NO_CSRF_CODE="$(
  curl -ksS \
    --max-time 12 \
    --resolve "${HOST_NAME}:${HTTPS_PORT}:127.0.0.1" \
    -o /dev/null \
    -w '%{http_code}' \
    --data-urlencode "email=teste+csrf@exemplo.test" \
    --data-urlencode "senha=Senha-Legitima-123!" \
    "https://${HOST_NAME}:${HTTPS_PORT}/login.php" \
    2>/dev/null || true
)"
echo "login_sem_csrf_http=$NO_CSRF_CODE"

[[ "$NO_CSRF_CODE" == "419" ]] \
  && ok "CSRF da aplicação continua atuando atrás do PL2" \
  || { [[ "$NO_CSRF_CODE" == "403" ]] && fail "PL2 bloqueou antes do CSRF da aplicação" || fail "esperado 419, recebeu $NO_CSRF_CODE"; }

echo
echo "=== 12. LOGIN INVÁLIDO E MFA ==="
COOKIE_JAR="$TMPDIR_TEST/cookies.txt"
LOGIN_BODY="$TMPDIR_TEST/login.html"

LOGIN_GET_CODE="$(
  curl -ksS \
    --max-time 12 \
    --resolve "${HOST_NAME}:${HTTPS_PORT}:127.0.0.1" \
    -c "$COOKIE_JAR" \
    -o "$LOGIN_BODY" \
    -w '%{http_code}' \
    "https://${HOST_NAME}:${HTTPS_PORT}/login.php" \
    2>/dev/null || true
)"
CSRF="$(extract_csrf "$LOGIN_BODY")"

echo "login_get_http=$LOGIN_GET_CODE"
echo "csrf_detectado=$([[ -n "$CSRF" ]] && echo sim || echo nao)"

INVALID_CODE="$(
  curl -ksS \
    --max-time 12 \
    --resolve "${HOST_NAME}:${HTTPS_PORT}:127.0.0.1" \
    -b "$COOKIE_JAR" \
    -c "$COOKIE_JAR" \
    -o /dev/null \
    -w '%{http_code}' \
    --data-urlencode "csrf_token=$CSRF" \
    --data-urlencode "email=usuario+teste@exemplo.test" \
    --data-urlencode "senha=Senha-Legitima-com-Pontuacao-#2026!" \
    "https://${HOST_NAME}:${HTTPS_PORT}/login.php" \
    2>/dev/null || true
)"
echo "login_invalido_http=$INVALID_CODE"

[[ "$INVALID_CODE" == "401" ]] \
  && ok "login inválido legítimo atravessa PL2" \
  || { [[ "$INVALID_CODE" == "403" ]] && fail "falso positivo PL2 no POST de login" || fail "login inválido retornou $INVALID_CODE"; }

FIXTURE_EMAIL="waf.policy+usuario@exemplo.test"
FIXTURE_PASS="PL2-$(openssl rand -hex 8)-Aa9!"

FIXTURE_ID="$(
  dmz exec -T \
    -e TUNE_EMAIL="$FIXTURE_EMAIL" \
    -e TUNE_PASS="$FIXTURE_PASS" \
    php php -r '
require "/var/www/conectaeduca/vendor/autoload.php";
$s=new \ConectaEduca\Service\UsuarioService();
echo $s->criarLocal([
  "nome"=>"Usuário Política WAF",
  "email"=>getenv("TUNE_EMAIL"),
  "role"=>"usuario",
  "senha"=>getenv("TUNE_PASS"),
  "confirmarSenha"=>getenv("TUNE_PASS"),
]),PHP_EOL;
' 2>&1 || true
)"
echo "fixture_id=$FIXTURE_ID"

[[ "$FIXTURE_ID" =~ ^[0-9]+$ ]] \
  && ok "fixture criada pelo serviço real" \
  || fail "fixture não foi criada"

LOGIN2_BODY="$TMPDIR_TEST/login2.html"
curl -ksS \
  --max-time 12 \
  --resolve "${HOST_NAME}:${HTTPS_PORT}:127.0.0.1" \
  -b "$COOKIE_JAR" \
  -c "$COOKIE_JAR" \
  -o "$LOGIN2_BODY" \
  "https://${HOST_NAME}:${HTTPS_PORT}/login.php" \
  >/dev/null 2>&1 || true

CSRF2="$(extract_csrf "$LOGIN2_BODY")"
VALID_HEADERS="$TMPDIR_TEST/valid.headers"

VALID_CODE="$(
  curl -ksS \
    --max-time 12 \
    --resolve "${HOST_NAME}:${HTTPS_PORT}:127.0.0.1" \
    -D "$VALID_HEADERS" \
    -b "$COOKIE_JAR" \
    -c "$COOKIE_JAR" \
    -o /dev/null \
    -w '%{http_code}' \
    --data-urlencode "csrf_token=$CSRF2" \
    --data-urlencode "email=$FIXTURE_EMAIL" \
    --data-urlencode "senha=$FIXTURE_PASS" \
    "https://${HOST_NAME}:${HTTPS_PORT}/login.php" \
    2>/dev/null || true
)"

VALID_LOCATION="$(
  awk 'BEGIN{IGNORECASE=1} /^Location:/{gsub("\r",""); print $2; exit}' "$VALID_HEADERS" 2>/dev/null || true
)"

echo "login_valido_http=$VALID_CODE"
echo "login_valido_location=$VALID_LOCATION"

[[ "$VALID_CODE" == "302" ]] \
  && ok "login válido atravessa PL2" \
  || { [[ "$VALID_CODE" == "403" ]] && fail "falso positivo PL2 no login válido" || fail "login válido retornou $VALID_CODE"; }

if [[ "$VALID_LOCATION" == /mfa* ]]; then
  ok "fluxo segue para MFA"
else
  fail "Location esperado para MFA não observado"
fi

MFA_CODE="$(
  curl -ksS \
    --max-time 12 \
    --resolve "${HOST_NAME}:${HTTPS_PORT}:127.0.0.1" \
    -b "$COOKIE_JAR" \
    -o /dev/null \
    -w '%{http_code}' \
    "https://${HOST_NAME}:${HTTPS_PORT}${VALID_LOCATION}" \
    2>/dev/null || true
)"
echo "mfa_http=$MFA_CODE"

[[ "$MFA_CODE" == "200" ]] \
  && ok "MFA atravessa PL2" \
  || { [[ "$MFA_CODE" == "403" ]] && fail "falso positivo PL2 na rota MFA" || fail "MFA retornou $MFA_CODE"; }

echo
echo "=== 13. ATAQUES CONTINUAM BLOQUEADOS ==="
XSS_CODE="$(
  curl -ksS \
    --max-time 12 \
    --resolve "${HOST_NAME}:${HTTPS_PORT}:127.0.0.1" \
    -G \
    --data-urlencode 'q=<script>alert(1)</script>' \
    -o /dev/null \
    -w '%{http_code}' \
    "https://${HOST_NAME}:${HTTPS_PORT}/" \
    2>/dev/null || true
)"
echo "xss_http=$XSS_CODE"

[[ "$XSS_CODE" == "403" ]] \
  && ok "XSS bloqueado em PL2" \
  || fail "XSS não foi bloqueado"

SQLI_CODE="$(
  curl -ksS \
    --max-time 12 \
    --resolve "${HOST_NAME}:${HTTPS_PORT}:127.0.0.1" \
    -G \
    --data-urlencode "id=1' OR '1'='1" \
    -o /dev/null \
    -w '%{http_code}' \
    "https://${HOST_NAME}:${HTTPS_PORT}/" \
    2>/dev/null || true
)"
echo "sqli_http=$SQLI_CODE"

[[ "$SQLI_CODE" == "403" ]] \
  && ok "SQLi bloqueado em PL2" \
  || fail "SQLi não foi bloqueado"

TRAVERSAL_CODE="$(
  curl -ksS \
    --max-time 12 \
    --resolve "${HOST_NAME}:${HTTPS_PORT}:127.0.0.1" \
    -G \
    --data-urlencode 'file=../../../../etc/passwd' \
    -o /dev/null \
    -w '%{http_code}' \
    "https://${HOST_NAME}:${HTTPS_PORT}/" \
    2>/dev/null || true
)"
echo "traversal_http=$TRAVERSAL_CODE"

[[ "$TRAVERSAL_CODE" == "403" ]] \
  && ok "path traversal bloqueado em PL2" \
  || fail "path traversal não foi bloqueado"

echo
echo "=== 14. AUDIT LOG / PRIVACIDADE ==="
PROBE="nao-logar-policy-${STAMP}"

curl -ksS \
  --max-time 12 \
  --resolve "${HOST_NAME}:${HTTPS_PORT}:127.0.0.1" \
  -H "X-ConectaEduca-Probe: ${PROBE}" \
  -H "Cookie: CONECTAEDUCASESSID=${PROBE}" \
  -G \
  --data-urlencode 'q=<script>alert(1)</script>' \
  -o /dev/null \
  "https://${HOST_NAME}:${HTTPS_PORT}/" \
  2>/dev/null || true

ALL_WAF_LOGS="$(docker logs "$WAF_ID" 2>&1 || true)"

if printf '%s' "$ALL_WAF_LOGS" | grep -Eq 'ruleId|ModSecurity|id "[0-9]{6}"'; then
  ok "RelevantOnly registra transações de segurança"
else
  fail "audit log sem evidência das regras"
fi

if printf '%s' "$ALL_WAF_LOGS" | grep -Fq "$PROBE"; then
  fail "cookie/header de prova apareceu no audit log"
else
  ok "cookie/header de prova não foi persistido"
fi

if printf '%s' "$ALL_WAF_LOGS" | grep -Fq '"request_body"'; then
  fail "request_body apareceu no audit log"
else
  ok "request_body não foi observado"
fi

echo
echo "=== 15. SUPERFÍCIE / RECURSOS ==="
DB_BINDINGS="$(docker inspect "$DB_ID" --format '{{json .HostConfig.PortBindings}}' 2>/dev/null || true)"
PHP_BINDINGS="$(docker port "$PHP_ID" 2>/dev/null || true)"
NGINX_BINDINGS="$(docker port "$NGINX_ID" 2>/dev/null || true)"
WAF_BINDINGS="$(docker port "$WAF_ID" 2>/dev/null || true)"

echo "db_bindings=$DB_BINDINGS"
echo "php_bindings=${PHP_BINDINGS:-<nenhum>}"
echo "nginx_bindings=${NGINX_BINDINGS:-<nenhum>}"
echo "waf_bindings=$WAF_BINDINGS"

[[ "$DB_BINDINGS" == "{}" || "$DB_BINDINGS" == "null" ]] \
  && ok "MariaDB sem publicação no host" \
  || fail "MariaDB publicou porta"

[[ -z "$PHP_BINDINGS" ]] \
  && ok "PHP-FPM sem publicação no host" \
  || fail "PHP-FPM publicou porta"

[[ -z "$NGINX_BINDINGS" ]] \
  && ok "Nginx sem publicação no host" \
  || fail "Nginx publicou porta"

IDS="$(dmz ps -q)"
docker stats --no-stream \
  --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.BlockIO}}' \
  $IDS || true

echo
echo "=== 16. ENCERRAMENTO ==="
if dmz down --remove-orphans; then
  ok "DMZ removida"
else
  fail "falha ao remover DMZ"
fi

if internal down -v --remove-orphans; then
  ok "MariaDB/volume de teste removidos"
else
  fail "falha ao remover MariaDB"
fi

docker network rm "$NETWORK" >/dev/null 2>&1 \
  && ok "rede de trânsito removida" \
  || fail "falha ao remover rede de trânsito"

STARTED=0

echo
echo "=== 17. GIT FINAL ==="
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
  echo "WAF / POLÍTICA PL2: APROVADO."
  echo "PL2 foi validado em modo de bloqueio sem falso positivo nos fluxos testados."
  echo "RelevantOnly/AFHZ funcionou como política de audit log."
  echo "Nenhuma exclusão CRS foi necessária para esta baseline."
  echo "O conjunto de containers está pronto para checkpoint final do bloco WAF."
else
  echo "WAF / POLÍTICA PL2: REPROVADO."
fi

echo "Relatório: $REPORT"
echo "======================================================================"

[[ "$FAIL" -eq 0 ]]
