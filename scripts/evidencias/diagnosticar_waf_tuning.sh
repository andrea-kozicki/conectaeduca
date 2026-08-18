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
DMZ_WAF_TUNING="$ROOT/deploy/dmz/compose.waf-tuning.yml"

INTERNAL="$ROOT/deploy/interna/mariadb/compose.yml"

DMZ_PROJECT="conectaeduca-dmz-waf-tuning-test"
INTERNAL_PROJECT="conectaeduca-mariadb-waf-tuning-test"

NETWORK="${CONECTAEDUCA_TRANSIT_NETWORK:-conectaeduca-transit-waf-tuning}"
SUBNET="${CONECTAEDUCA_TRANSIT_SUBNET:-172.30.252.0/24}"
DB_IP="${CONECTAEDUCA_DB_HOST:-172.30.252.10}"
PHP_IP="${CONECTAEDUCA_PHP_TRANSIT_IP:-172.30.252.20}"

HTTPS_PORT="${HTTPS_PORT:-18443}"
HOST_NAME="${CONECTAEDUCA_HOST_HEADER:-conectaeduca.local}"

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/conectaeduca-waf-tuning-${STAMP}.txt"

FAIL=0
ABORT=0
STARTED=0

SECRET_DIR=""
TMPDIR_TEST=""

ok(){ echo "OK       $*"; }
fail(){ echo "FALHA    $*"; FAIL=$((FAIL+1)); }
info(){ echo "INFO     $*"; }
candidate(){ echo "CANDIDATO $*"; }

dmz() {
  docker compose \
    -p "$DMZ_PROJECT" \
    -f "$DMZ_BASE" \
    -f "$DMZ_DB" \
    -f "$DMZ_APP_SECRETS" \
    -f "$DMZ_WAF" \
    -f "$DMZ_WAF_TLS" \
    -f "$DMZ_WAF_TUNING" \
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

  if [[ -n "${SECRET_DIR:-}" && -d "$SECRET_DIR" ]]; then
    rm -rf "$SECRET_DIR"
  fi

  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi

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

validate_lab_addresses() {
  python3 - "$SUBNET" "$DB_IP" "$PHP_IP" <<'PY'
import ipaddress, sys

subnet = ipaddress.ip_network(sys.argv[1], strict=True)
db = ipaddress.ip_address(sys.argv[2])
php = ipaddress.ip_address(sys.argv[3])

for label, ip in (("DB_IP", db), ("PHP_IP", php)):
    if ip not in subnet:
        raise SystemExit(f"{label} fora da subnet")
    if ip in (subnet.network_address, subnet.broadcast_address):
        raise SystemExit(f"{label} inválido para host")

if db == php:
    raise SystemExit("DB_IP e PHP_IP iguais")
PY
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

class P(HTMLParser):
    def __init__(self):
        super().__init__()
        self.token = None

    def handle_starttag(self, tag, attrs):
        if tag.lower() != "input":
            return
        d = dict(attrs)
        if d.get("name") == "csrf_token" and d.get("value"):
            self.token = d["value"]

p = P()
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
    fail "$label: possível falso positivo WAF (esperado $expected, recebeu 403)"
  else
    fail "$label: esperado $expected, recebeu ${code:-sem-resposta}"
  fi
}

exec > >(tee "$REPORT") 2>&1

echo "======================================================================"
echo " CONECTAEDUCA - WAF / TUNING v2"
echo " Tráfego legítimo real com PL2 em observação e PL1 em bloqueio"
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
echo "=== 2. ARQUIVOS DA ARQUITETURA COMPLETA ==="
for f in \
  deploy/dmz/compose.yml \
  deploy/dmz/compose.database.yml \
  deploy/dmz/compose.app-secrets.yml \
  deploy/dmz/compose.waf.yml \
  deploy/dmz/compose.waf-tls.yml \
  deploy/dmz/compose.waf-tuning.yml \
  deploy/dmz/waf/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf \
  deploy/dmz/waf/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf \
  deploy/interna/mariadb/compose.yml \
  sql/conectaeduca.sql
do
  [[ -f "$ROOT/$f" ]] \
    && ok "$f" \
    || { fail "ausente: $f"; ABORT=1; }
done

echo
echo "=== 3. POLÍTICA DE TUNING ==="
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
  ok "baseline começa sem exclusões CRS"
else
  info "já existem exclusões CRS; serão observadas no diagnóstico"
fi

if grep -q 'BLOCKING_PARANOIA: "1"' deploy/dmz/compose.waf-tuning.yml &&
   grep -q 'DETECTION_PARANOIA: "2"' deploy/dmz/compose.waf-tuning.yml; then
  ok "PL1 bloqueia; PL2 executa em observação"
else
  fail "níveis de paranoia não correspondem à estratégia de tuning"
  ABORT=1
fi

echo
echo "=== 4. SEGREDOS EFÊMEROS ==="
SECRET_DIR="$(mktemp -d /tmp/conectaeduca-waf-tuning-secrets.XXXXXX)"
TMPDIR_TEST="$(mktemp -d /tmp/conectaeduca-waf-tuning-tmp.XXXXXX)"
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

ok "segredos de laboratório preparados fora do Git"

echo
echo "=== 5. PARÂMETROS DO LAB ==="
echo "network=$NETWORK"
echo "subnet=$SUBNET"
echo "db_ip=$DB_IP"
echo "php_ip=$PHP_IP"
echo "https=https://${HOST_NAME}:${HTTPS_PORT}"

validate_lab_addresses \
  && ok "endereçamento válido" \
  || { fail "endereçamento inválido"; ABORT=1; }

echo
echo "=== 6. COMPOSE ==="
internal config >/dev/null \
  && ok "Compose MariaDB válido" \
  || { fail "Compose MariaDB inválido"; ABORT=1; }

dmz config >/dev/null \
  && ok "Compose DMZ + DB + app-secrets + WAF + TLS + tuning válido" \
  || { fail "Compose DMZ completo inválido"; ABORT=1; }

CONFIG_JSON="$(dmz config --format json 2>/dev/null || true)"

if printf '%s' "$CONFIG_JSON" | python3 -c '
import json,sys
c=json.load(sys.stdin)["services"]
assert set(c)=={"nginx","php","waf"}
assert not c["nginx"].get("ports")
assert not c["php"].get("ports")
e=c["waf"]["environment"]
assert str(e["BLOCKING_PARANOIA"])=="1"
assert str(e["DETECTION_PARANOIA"])=="2"
assert e["MODSEC_AUDIT_ENGINE"]=="On"
assert e["MODSEC_AUDIT_LOG_PARTS"]=="AFHZ"
assert e["BACKEND"]=="http://nginx:8080"
'
then
  ok "topologia e política de tuning confirmadas no Compose resultante"
else
  fail "Compose resultante diverge da política esperada"
  ABORT=1
fi

if [[ "$ABORT" -ne 0 ]]; then
  echo
  echo "TUNING: INTERROMPIDO antes da subida."
  echo "Falhas: $FAIL"
  echo "Relatório: $REPORT"
  exit 1
fi

echo
echo "=== 7. BUILD / REDE DE TRÂNSITO ==="
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
echo "=== 8. MARIADB INTERNO ==="
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
  internal logs --no-color --tail=100 mariadb || true
  ABORT=1
fi

if [[ "$ABORT" -eq 0 ]] &&
   docker network connect --ip "$DB_IP" "$NETWORK" "$DB_ID"; then
  ok "MariaDB conectado à rede de trânsito em $DB_IP"
else
  fail "MariaDB não conectado à rede de trânsito"
  ABORT=1
fi

echo
echo "=== 9. DMZ COMPLETA ==="
if [[ "$ABORT" -eq 0 ]] && dmz up -d; then
  ok "DMZ completa iniciada"
else
  fail "DMZ completa não iniciou"
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
  ok "PHP conectado à rede de trânsito em $PHP_IP"
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
  echo
  echo "TUNING: INTERROMPIDO após falha de infraestrutura."
  echo "Falhas: $FAIL"
  echo "Relatório: $REPORT"
  exit 1
fi

echo
echo "=== 10. SEGMENTAÇÃO / SECRETS ==="
MEMBERS="$(
  docker network inspect "$NETWORK" \
    --format '{{range .Containers}}{{.Name}}|{{.IPv4Address}}{{println}}{{end}}' \
    2>/dev/null | sort || true
)"
printf '%s\n' "$MEMBERS"

NETWORK_JSON="$(docker network inspect "$NETWORK" 2>/dev/null || true)"

container_is_member() {
  local target_id="$1"

  printf '%s' "$NETWORK_JSON" | python3 -c '
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

if container_is_member "$WAF_ID"; then
  fail "WAF participa indevidamente da rede do banco"
else
  ok "WAF não participa da rede do banco"
fi

if container_is_member "$NGINX_ID"; then
  fail "Nginx participa indevidamente da rede do banco"
else
  ok "Nginx não participa da rede do banco"
fi

if container_is_member "$PHP_ID"; then
  ok "PHP participa da rede de trânsito"
else
  fail "PHP não participa da rede de trânsito"
fi

if container_is_member "$DB_ID"; then
  ok "MariaDB participa da rede de trânsito"
else
  fail "MariaDB não participa da rede de trânsito"
fi

dmz exec -T php test -r /run/secrets/conectaeduca_private_key \
  && ok "PHP recebe chave privada da aplicação" \
  || fail "PHP sem chave privada da aplicação"

dmz exec -T waf test -r /run/secrets/waf_tls_key \
  && ok "WAF recebe chave TLS" \
  || fail "WAF sem chave TLS"

dmz exec -T nginx test ! -e /run/secrets/waf_tls_key \
  && ok "Nginx não recebe chave TLS do WAF" \
  || fail "chave TLS do WAF vazou para Nginx"

echo
echo "=== 11. BASELINE FUNCIONAL ANTES DO TUNING ==="
DATABASE_RESULT="$(
  dmz exec -T php php -r '
require "/var/www/conectaeduca/vendor/autoload.php";
$pdo=\ConectaEduca\Config\Database::connect();
$r=$pdo->query("SELECT DATABASE() db, @@character_set_connection charset")->fetch(PDO::FETCH_ASSOC);
echo $r["db"],"|",$r["charset"],PHP_EOL;
' 2>&1 || true
)"
echo "database_result=$DATABASE_RESULT"

[[ "$DATABASE_RESULT" == "conectaeduca|utf8mb4" ]] \
  && ok "aplicação alcança MariaDB interno" \
  || fail "conexão real com MariaDB falhou"

CRYPTO_RESULT="$(
  dmz exec -T php php -r '
require "/var/www/conectaeduca/vendor/autoload.php";
$p=\ConectaEduca\Security\CryptoHybrid::encryptString("waf-tuning");
echo \ConectaEduca\Security\CryptoHybrid::decryptString($p),"|",$p["algorithm"],PHP_EOL;
' 2>&1 || true
)"
echo "crypto_result=$CRYPTO_RESULT"

[[ "$CRYPTO_RESULT" == "waf-tuning|AES-256-GCM + RSA-OAEP" ]] \
  && ok "criptografia da aplicação funcional com app-secrets" \
  || fail "CryptoHybrid falhou"

echo
echo "=== 12. ROTAS PÚBLICAS LEGÍTIMAS ==="
BENIGN_SINCE="$(date --iso-8601=seconds)"

request_expect "página inicial" "/index.php" "200"
request_expect "listagem de oportunidades" "/oportunidades.php" "200"
request_expect "cadastro de usuário" "/cadastro_usuario.php" "200"
request_expect "login" "/login.php" "200"
request_expect "CSS" "/assets/css/style.css" "200"
request_expect "JS de CSRF" "/assets/js/csrf.js" "200"
request_expect "chave pública" "/api/public_key.php" "200"
request_expect "API pública de oportunidades" "/api/oportunidades.php" "200"

echo
echo "=== 13. FILTROS REAIS DE OPORTUNIDADES ==="
FILTER_CODE="$(
  curl -ksS \
    --max-time 12 \
    --resolve "${HOST_NAME}:${HTTPS_PORT}:127.0.0.1" \
    -G \
    --data-urlencode "busca=Analista C/C++ e Node.js" \
    --data-urlencode "area=Pesquisa & Desenvolvimento" \
    --data-urlencode "modalidade=hibrido" \
    --data-urlencode "tipo=estagio" \
    -o "$TMPDIR_TEST/filtros.html" \
    -w '%{http_code}' \
    "https://${HOST_NAME}:${HTTPS_PORT}/oportunidades.php" \
    2>/dev/null || true
)"
echo "filtros_legitimos_http=$FILTER_CODE"

[[ "$FILTER_CODE" == "200" ]] \
  && ok "filtros legítimos com pontuação atravessam o WAF" \
  || { [[ "$FILTER_CODE" == "403" ]] && fail "possível falso positivo CRS nos filtros legítimos" || fail "filtros retornaram $FILTER_CODE"; }

echo
echo "=== 14. ROTAS PROTEGIDAS SEM SESSÃO ==="
request_expect "dashboard protegido" "/dashboard.php" "401"
request_expect "favoritos protegidos" "/favoritos.php" "401"
request_expect "perfil protegido" "/perfil.php" "401"
request_expect "fale conosco protegido" "/fale_conosco.php" "401"
request_expect "empresa/oportunidades protegida" "/empresa/oportunidades.php" "401"
request_expect "empresa/inscrições protegida" "/empresa/inscricoes.php" "401"
request_expect "admin/auditoria protegida" "/admin/auditoria.php" "401"
request_expect "admin/relatório protegido" "/admin/relatorio.php" "401"
request_expect "admin/mensagens protegida" "/admin/mensagens_contato.php" "401"

echo
echo "=== 15. CSRF REAL ATRÁS DO WAF ==="
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
  && ok "requisição chega à aplicação e CSRF continua bloqueando" \
  || { [[ "$NO_CSRF_CODE" == "403" ]] && fail "WAF bloqueou antes do controle CSRF da aplicação" || fail "esperado 419, recebeu $NO_CSRF_CODE"; }

echo
echo "=== 16. LOGIN INVÁLIDO COM CSRF ==="
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

[[ "$LOGIN_GET_CODE" == "200" && -n "$CSRF" ]] \
  && ok "sessão e CSRF obtidos pelo caminho WAF/TLS" \
  || fail "não foi possível preparar login real"

INVALID_CODE="$(
  curl -ksS \
    --max-time 12 \
    --resolve "${HOST_NAME}:${HTTPS_PORT}:127.0.0.1" \
    -b "$COOKIE_JAR" \
    -c "$COOKIE_JAR" \
    -o "$TMPDIR_TEST/login-invalid.html" \
    -w '%{http_code}' \
    --data-urlencode "csrf_token=$CSRF" \
    --data-urlencode "email=usuario+teste@exemplo.test" \
    --data-urlencode "senha=Senha-Legitima-com-Pontuacao-#2026!" \
    "https://${HOST_NAME}:${HTTPS_PORT}/login.php" \
    2>/dev/null || true
)"
echo "login_invalido_http=$INVALID_CODE"

[[ "$INVALID_CODE" == "401" ]] \
  && ok "credenciais benignas inválidas chegam ao AuthController" \
  || { [[ "$INVALID_CODE" == "403" ]] && fail "possível falso positivo CRS no POST de login" || fail "login inválido retornou $INVALID_CODE"; }

echo
echo "=== 17. LOGIN VÁLIDO / PRÉ-AUTENTICAÇÃO MFA ==="
FIXTURE_EMAIL="waf.tuning+usuario@exemplo.test"
FIXTURE_PASS="Tune-$(openssl rand -hex 8)-Aa9!"

FIXTURE_ID="$(
  dmz exec -T \
    -e TUNE_EMAIL="$FIXTURE_EMAIL" \
    -e TUNE_PASS="$FIXTURE_PASS" \
    php php -r '
require "/var/www/conectaeduca/vendor/autoload.php";
$s=new \ConectaEduca\Service\UsuarioService();
echo $s->criarLocal([
  "nome"=>"Usuário Tuning WAF",
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
  && ok "login válido não sofreu falso positivo WAF" \
  || { [[ "$VALID_CODE" == "403" ]] && fail "possível falso positivo CRS no login válido" || fail "login válido retornou $VALID_CODE"; }

if [[ "$VALID_LOCATION" == /mfa* ]]; then
  ok "fluxo válido continua direcionando para MFA"
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
  && ok "tela MFA atravessa o WAF" \
  || { [[ "$MFA_CODE" == "403" ]] && fail "possível falso positivo CRS na tela MFA" || fail "MFA retornou $MFA_CODE"; }

PENDING_DASHBOARD="$(
  curl -ksS \
    --max-time 12 \
    --resolve "${HOST_NAME}:${HTTPS_PORT}:127.0.0.1" \
    -b "$COOKIE_JAR" \
    -o /dev/null \
    -w '%{http_code}' \
    "https://${HOST_NAME}:${HTTPS_PORT}/dashboard.php" \
    2>/dev/null || true
)"
echo "dashboard_durante_preauth=$PENDING_DASHBOARD"

[[ "$PENDING_DASHBOARD" == "401" ]] \
  && ok "WAF não interfere na proteção de pré-autenticação" \
  || fail "dashboard em pré-auth retornou $PENDING_DASHBOARD"

echo
echo "=== 18. ANÁLISE DE PL2 SOBRE TRÁFEGO LEGÍTIMO ==="
BENIGN_LOGS="$(docker logs --since "$BENIGN_SINCE" "$WAF_ID" 2>&1 || true)"

PL2_COUNT="$(
  printf '%s\n' "$BENIGN_LOGS" |
    grep -c 'paranoia-level/2' 2>/dev/null || true
)"
PL2_COUNT="${PL2_COUNT:-0}"
echo "pl2_matches_legitimos=$PL2_COUNT"

PL2_IDS="$(
  printf '%s\n' "$BENIGN_LOGS" |
  grep 'paranoia-level/2' |
  grep -Eo 'ruleId["=: ]+[0-9]{6}|id "[0-9]{6}"' |
  grep -Eo '[0-9]{6}' |
  sort -u || true
)"

if [[ -z "$PL2_IDS" ]]; then
  ok "nenhum rule ID PL2 observado no tráfego legítimo testado"
else
  candidate "PL2 gerou detecções em tráfego legítimo; NÃO criaremos exclusões automaticamente"
  echo "--- rule IDs PL2 candidatos a revisão ---"
  printf '%s\n' "$PL2_IDS"
fi

echo
echo "=== 19. AUSÊNCIA DE BLOQUEIOS WAF INDEVIDOS ==="
BENIGN_403_COUNT="$(
  grep -c 'possível falso positivo' "$REPORT" 2>/dev/null || true
)"
BENIGN_403_COUNT="${BENIGN_403_COUNT:-0}"
echo "falsos_positivos_bloqueantes=$BENIGN_403_COUNT"

[[ "$BENIGN_403_COUNT" == "0" ]] \
  && ok "nenhuma transação legítima testada foi bloqueada pelo PL1" \
  || fail "houve transação legítima bloqueada"

echo
echo "=== 20. CONTROLES MALICIOSOS CONTINUAM BLOQUEADOS ==="
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
  && ok "XSS continua bloqueado" \
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
  && ok "SQLi continua bloqueado" \
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
  && ok "path traversal continua bloqueado" \
  || fail "path traversal não foi bloqueado"

echo
echo "=== 21. PRIVACIDADE DO AUDIT LOG ==="
PRIVACY_PROBE="nao-logar-tuning-${STAMP}"

curl -ksS \
  --max-time 12 \
  --resolve "${HOST_NAME}:${HTTPS_PORT}:127.0.0.1" \
  -H "X-ConectaEduca-Probe: ${PRIVACY_PROBE}" \
  -H "Cookie: CONECTAEDUCASESSID=${PRIVACY_PROBE}" \
  -G \
  --data-urlencode 'q=<script>alert(1)</script>' \
  -o /dev/null \
  "https://${HOST_NAME}:${HTTPS_PORT}/" \
  2>/dev/null || true

ALL_WAF_LOGS="$(docker logs "$WAF_ID" 2>&1 || true)"

if printf '%s' "$ALL_WAF_LOGS" | grep -Fq "$PRIVACY_PROBE"; then
  fail "probe de cookie/header apareceu no audit log"
else
  ok "cookie/header de prova não foi persistido"
fi

if printf '%s' "$ALL_WAF_LOGS" | grep -Fq '"request_body"'; then
  fail "request_body apareceu no audit log"
else
  ok "request_body não foi observado"
fi

echo
echo "=== 22. SUPERFÍCIE / RECURSOS ==="
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
echo "=== 23. ENCERRAMENTO ==="
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
echo "=== 24. GIT FINAL ==="
git status -sb

git diff --check \
  && ok "git diff --check final" \
  || fail "git diff --check final"

echo
echo "======================================================================"
echo " RESULTADO"
echo "======================================================================"
echo "Falhas: $FAIL"
echo "PL2 matches legítimos: $PL2_COUNT"

if [[ "$FAIL" -eq 0 ]]; then
  echo "WAF / TUNING v2 - DIAGNÓSTICO: APROVADO."
  if [[ -z "$PL2_IDS" ]]; then
    echo "Nenhuma exclusão CRS é necessária para os fluxos legítimos testados."
    echo "Candidato natural: validar PL2 também em modo de bloqueio."
  else
    echo "Há detecções PL2 legítimas para revisão antes de elevar o blocking PL."
    echo "Nenhuma exclusão foi criada automaticamente."
  fi
  echo "PL1 continuou bloqueando XSS, SQLi e path traversal."
else
  echo "WAF / TUNING v2 - DIAGNÓSTICO: REPROVADO."
fi

echo "Relatório: $REPORT"
echo "======================================================================"

[[ "$FAIL" -eq 0 ]]
