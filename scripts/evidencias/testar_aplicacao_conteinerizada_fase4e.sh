#!/usr/bin/env bash
set -u

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"

DMZ_BASE="$ROOT/deploy/dmz/compose.yml"
DMZ_DB="$ROOT/deploy/dmz/compose.fase4d.yml"
DMZ_APP="$ROOT/deploy/dmz/compose.fase4e.yml"
INTERNAL_BASE="$ROOT/deploy/interna/compose.yml"

DMZ_PROJECT="conectaeduca-dmz-fase4e-test"
INTERNAL_PROJECT="conectaeduca-interna-fase4e-test"

NETWORK="${CONECTAEDUCA_TRANSIT_NETWORK:-conectaeduca-transit-fase4e}"
SUBNET="${CONECTAEDUCA_TRANSIT_SUBNET:-172.30.251.0/24}"
DB_IP="${CONECTAEDUCA_DB_HOST:-172.30.251.10}"
PHP_IP="${CONECTAEDUCA_PHP_TRANSIT_IP:-172.30.251.20}"

BASE_URL="${CONECTAEDUCA_BASE_URL:-https://127.0.0.1:8088}"
HOST_HEADER="${CONECTAEDUCA_HOST_HEADER:-conectaeduca.local}"

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/conectaeduca-fase4e-aplicacao-${STAMP}.txt"
SECRET_DIR="$(mktemp -d /tmp/conectaeduca-fase4e-secrets.XXXXXX)"
TMPDIR_PHASE="$(mktemp -d /tmp/conectaeduca-fase4e-tmp.XXXXXX)"
FAIL=0
ABORT=0

cd "$ROOT" || exit 1

ok(){ echo "OK    $*"; }
fail(){ echo "FALHA $*"; FAIL=$((FAIL+1)); }
warn(){ echo "AVISO $*"; }

ROOT_SECRET="$SECRET_DIR/mariadb_root_password"
APP_SECRET="$SECRET_DIR/conectaeduca_db_password"
APP_PRIVATE="$SECRET_DIR/conectaeduca_private_key"
APP_PUBLIC="$SECRET_DIR/conectaeduca_public_key"
TLS_KEY="$SECRET_DIR/conectaeduca_tls_key"
TLS_CERT="$SECRET_DIR/conectaeduca_tls_cert"

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
    -days 2 \
    -keyout "$TLS_KEY" \
    -out "$TLS_CERT" \
    -subj "/CN=conectaeduca.local" \
    -addext "subjectAltName=DNS:conectaeduca.local,DNS:localhost,IP:127.0.0.1" \
    >/dev/null 2>&1

chmod 0700 "$SECRET_DIR"
chmod 0444 \
    "$ROOT_SECRET" \
    "$APP_SECRET" \
    "$APP_PRIVATE" \
    "$APP_PUBLIC" \
    "$TLS_KEY" \
    "$TLS_CERT"

export CONECTAEDUCA_DB_ROOT_PASSWORD_FILE="$ROOT_SECRET"
export CONECTAEDUCA_DB_PASSWORD_FILE="$APP_SECRET"
export CONECTAEDUCA_DB_HOST="$DB_IP"
export CONECTAEDUCA_PRIVATE_KEY_FILE="$APP_PRIVATE"
export CONECTAEDUCA_PUBLIC_KEY_FILE="$APP_PUBLIC"
export CONECTAEDUCA_TLS_KEY_FILE="$TLS_KEY"
export CONECTAEDUCA_TLS_CERT_FILE="$TLS_CERT"

DMZ=(docker compose -p "$DMZ_PROJECT" -f "$DMZ_BASE" -f "$DMZ_DB" -f "$DMZ_APP")
INTERNAL=(docker compose -p "$INTERNAL_PROJECT" -f "$INTERNAL_BASE")

cleanup() {
    set +e
    "${DMZ[@]}" down --remove-orphans >/dev/null 2>&1
    "${INTERNAL[@]}" down -v --remove-orphans >/dev/null 2>&1
    docker network rm "$NETWORK" >/dev/null 2>&1
    rm -rf "$SECRET_DIR" "$TMPDIR_PHASE"
}
trap cleanup EXIT

wait_healthy() {
    local label="$1"
    local id="$2"
    local timeout="${3:-120}"
    local elapsed=0
    local status state

    while (( elapsed <= timeout )); do
        state="$(docker inspect "$id" --format '{{.State.Status}}' 2>/dev/null || true)"
        status="$(docker inspect "$id" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null || true)"

        if (( elapsed % 5 == 0 )); then
            echo "health_wait label=$label t=${elapsed}s state=${state:-<vazio>} health=${status:-<vazio>}"
        fi

        if [[ "$state" == "running" && "$status" == "healthy" ]]; then
            return 0
        fi

        if [[ "$state" == "exited" || "$state" == "dead" ]]; then
            return 1
        fi

        sleep 1
        elapsed=$((elapsed + 1))
    done

    return 1
}

validate_lab_addresses() {
    python3 - "$SUBNET" "$DB_IP" "$PHP_IP" <<'PY'
import ipaddress
import sys

subnet = ipaddress.ip_network(sys.argv[1], strict=True)
db = ipaddress.ip_address(sys.argv[2])
php = ipaddress.ip_address(sys.argv[3])

for label, ip in [("DB_IP", db), ("PHP_IP", php)]:
    if ip not in subnet:
        raise SystemExit(f"{label} {ip} não pertence à rede {subnet}")
    if ip in (subnet.network_address, subnet.broadcast_address):
        raise SystemExit(f"{label} inválido para host")

if db == php:
    raise SystemExit("DB_IP e PHP_IP não podem ser iguais")
PY
}

https_code() {
    local path="$1"
    curl -k -sS \
        --max-time 10 \
        -H "Host: $HOST_HEADER" \
        -o /dev/null \
        -w '%{http_code}' \
        "$BASE_URL$path" \
        2>/dev/null || true
}

root_query() {
    local sql="$1"
    "${INTERNAL[@]}" exec -T mariadb sh -ec \
        'mariadb --batch --skip-column-names --protocol=socket -uroot --password="$(cat /run/secrets/mariadb_root_password)" -e "$1"' \
        sh "$sql"
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

{
echo "======================================================================"
echo " CONECTAEDUCA - FASE 4E"
echo " Aplicação real + HTTPS + DB remoto + secrets em runtime"
echo " Data: $(date --iso-8601=seconds)"
echo "======================================================================"

echo
echo "=== GIT ==="
git status -sb

echo
echo "=== ARQUIVOS ==="
for f in \
    deploy/dmz/compose.yml \
    deploy/dmz/compose.fase4d.yml \
    deploy/dmz/compose.fase4e.yml \
    deploy/dmz/nginx/default.fase4e.conf \
    deploy/interna/compose.yml \
    sql/conectaeduca.sql
do
    [[ -f "$f" ]] && ok "$f" || { fail "ausente: $f"; ABORT=1; }
done

echo
echo "=== PARÂMETROS DO LAB ==="
echo "network=$NETWORK"
echo "subnet=$SUBNET"
echo "db_ip=$DB_IP"
echo "php_ip=$PHP_IP"
echo "base_url=$BASE_URL"
echo "host_header=$HOST_HEADER"

validate_lab_addresses \
    && ok "endereçamento do laboratório válido" \
    || { fail "endereçamento do laboratório inválido"; ABORT=1; }

echo
echo "=== SEGREDOS TEMPORÁRIOS ==="
echo "diretório=$SECRET_DIR"
echo "dir_mode=$(stat -c '%a' "$SECRET_DIR")"

[[ "$(stat -c '%a' "$SECRET_DIR")" == "700" ]] \
    && ok "diretório privado 0700" \
    || fail "diretório de secrets não está 0700"

for f in \
    "$ROOT_SECRET" \
    "$APP_SECRET" \
    "$APP_PRIVATE" \
    "$APP_PUBLIC" \
    "$TLS_KEY" \
    "$TLS_CERT"
do
    [[ "$(stat -c '%a' "$f")" == "444" ]] \
        && ok "$(basename "$f") preparado para bind secret" \
        || fail "$(basename "$f") com modo inesperado"
done

echo
echo "=== PAR CRIPTOGRÁFICO DE TESTE ==="
APP_PUB_FROM_PRIV="$TMPDIR_PHASE/public-from-private.pem"
openssl pkey -in "$APP_PRIVATE" -pubout -out "$APP_PUB_FROM_PRIV" >/dev/null 2>&1

if cmp -s "$APP_PUBLIC" "$APP_PUB_FROM_PRIV"; then
    ok "chave pública corresponde à privada"
else
    fail "par criptográfico não corresponde"
fi

echo
echo "=== COMPOSE ==="
"${INTERNAL[@]}" config >/dev/null \
    && ok "Compose interno válido" \
    || { fail "Compose interno inválido"; ABORT=1; }

"${DMZ[@]}" config >/dev/null \
    && ok "Compose DMZ 4B+4D+4E válido" \
    || { fail "Compose DMZ 4B+4D+4E inválido"; ABORT=1; }

if [[ "$ABORT" -ne 0 ]]; then
    echo
    echo "FASE 4E: INTERROMPIDA antes da subida por falha de pré-requisito."
    echo "Relatório: $REPORT"
    echo "======================================================================"
    exit 1
fi

echo
echo "=== BUILD DMZ ==="
if "${DMZ[@]}" build; then
    ok "imagens DMZ construídas"
else
    fail "build DMZ falhou"
    ABORT=1
fi

echo
echo "=== REDE DE TRÂNSITO ==="
if docker network inspect "$NETWORK" >/dev/null 2>&1; then
    fail "rede $NETWORK já existe; estado residual detectado"
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
echo "=== BANCO INTERNO ==="
"${INTERNAL[@]}" up -d \
    && ok "MariaDB iniciou" \
    || { fail "compose interno falhou"; ABORT=1; }

DB_ID="$("${INTERNAL[@]}" ps -q mariadb 2>/dev/null || true)"

if [[ -n "$DB_ID" ]] && wait_healthy "mariadb" "$DB_ID" 120; then
    ok "MariaDB healthy"
else
    fail "MariaDB não ficou healthy"
    "${INTERNAL[@]}" logs --no-color --tail=120 mariadb || true
    ABORT=1
fi

if [[ "$ABORT" -eq 0 ]] && docker network connect --ip "$DB_IP" "$NETWORK" "$DB_ID"; then
    ok "MariaDB conectado em $DB_IP"
else
    fail "MariaDB não foi conectado à rede de trânsito"
    ABORT=1
fi

echo
echo "=== DMZ ==="
if [[ "$ABORT" -eq 0 ]] && "${DMZ[@]}" up -d; then
    ok "DMZ iniciou"
else
    fail "compose DMZ falhou"
    ABORT=1
fi

PHP_ID="$("${DMZ[@]}" ps -q php 2>/dev/null || true)"
NGINX_ID="$("${DMZ[@]}" ps -q nginx 2>/dev/null || true)"

if [[ "$ABORT" -eq 0 && -n "$PHP_ID" ]] && wait_healthy "php-fpm" "$PHP_ID" 60; then
    ok "PHP-FPM healthy"
else
    fail "PHP-FPM não ficou healthy"
    ABORT=1
fi

if [[ "$ABORT" -eq 0 ]] && docker network connect --ip "$PHP_IP" "$NETWORK" "$PHP_ID"; then
    ok "PHP conectado em $PHP_IP"
else
    fail "PHP não foi conectado à rede de trânsito"
    ABORT=1
fi

if [[ "$ABORT" -eq 0 && -n "$NGINX_ID" ]] && wait_healthy "nginx" "$NGINX_ID" 60; then
    ok "Nginx HTTPS healthy"
else
    fail "Nginx não ficou healthy"
    "${DMZ[@]}" logs --no-color --tail=120 nginx || true
    ABORT=1
fi

if [[ "$ABORT" -ne 0 ]]; then
    echo
    echo "FASE 4E: INTERROMPIDA após falha de infraestrutura."
    echo "Falhas: $FAIL"
    echo "Relatório: $REPORT"
    echo "======================================================================"
    exit 1
fi

echo
echo "=== REDE DE TRÂNSITO ==="
MEMBERS="$(docker network inspect "$NETWORK" --format '{{range .Containers}}{{.Name}}|{{.IPv4Address}}{{println}}{{end}}' 2>/dev/null | sort || true)"
printf '%s\n' "$MEMBERS"

MEMBER_COUNT="$(printf '%s\n' "$MEMBERS" | sed '/^$/d' | wc -l)"
[[ "$MEMBER_COUNT" == "2" ]] \
    && ok "somente PHP e MariaDB participam da rede de trânsito" \
    || fail "quantidade inesperada de membros"

printf '%s\n' "$MEMBERS" | grep -Fq 'nginx' \
    && fail "Nginx participa indevidamente da rede do banco" \
    || ok "Nginx isolado da rede do banco"

echo
echo "=== SEPARAÇÃO DE SECRETS ==="
"${DMZ[@]}" exec -T php test -r /run/secrets/conectaeduca_db_password \
    && ok "PHP lê secret do banco" \
    || fail "PHP não lê secret do banco"

"${DMZ[@]}" exec -T php test -r /run/secrets/conectaeduca_private_key \
    && ok "PHP lê chave privada da aplicação" \
    || fail "PHP não lê chave privada da aplicação"

"${DMZ[@]}" exec -T php test -r /run/secrets/conectaeduca_public_key \
    && ok "PHP lê chave pública da aplicação" \
    || fail "PHP não lê chave pública da aplicação"

"${DMZ[@]}" exec -T php test ! -e /run/secrets/conectaeduca_tls_key \
    && ok "PHP não recebe chave TLS do Nginx" \
    || fail "PHP recebeu chave TLS indevidamente"

"${DMZ[@]}" exec -T nginx test -r /run/secrets/conectaeduca_tls_key \
    && ok "Nginx lê chave TLS" \
    || fail "Nginx não lê chave TLS"

"${DMZ[@]}" exec -T nginx test ! -e /run/secrets/conectaeduca_private_key \
    && ok "Nginx não recebe chave privada da aplicação" \
    || fail "Nginx recebeu chave privada da aplicação"

"${DMZ[@]}" exec -T nginx test ! -e /run/secrets/conectaeduca_db_password \
    && ok "Nginx não recebe senha do banco" \
    || fail "Nginx recebeu senha do banco"

echo
echo "=== DATABASE.PHP REAL ==="
DATABASE_RESULT="$("${DMZ[@]}" exec -T php php -r '
require "/var/www/conectaeduca/vendor/autoload.php";

$pdo = \ConectaEduca\Config\Database::connect();
$row = $pdo->query(
    "SELECT DATABASE() AS db, VERSION() AS version, @@character_set_connection AS charset"
)->fetch(PDO::FETCH_ASSOC);

echo $row["db"], "|", $row["version"], "|", $row["charset"], PHP_EOL;
' 2>&1 || true)"

echo "database_result=$DATABASE_RESULT"

[[ "$DATABASE_RESULT" == conectaeduca\|12.3.2-MariaDB*\|utf8mb4 ]] \
    && ok "Database::connect usa o MariaDB interno" \
    || fail "Database::connect não retornou o resultado esperado"

echo
echo "=== CRYPTOHYBRID REAL ==="
CRYPTO_RESULT="$("${DMZ[@]}" exec -T php php -r '
require "/var/www/conectaeduca/vendor/autoload.php";

$payload = \ConectaEduca\Security\CryptoHybrid::encryptString("fase4e-container");
$plain = \ConectaEduca\Security\CryptoHybrid::decryptString($payload);

echo $plain, "|", $payload["algorithm"], PHP_EOL;
' 2>&1 || true)"

echo "crypto_result=$CRYPTO_RESULT"

[[ "$CRYPTO_RESULT" == "fase4e-container|AES-256-GCM + RSA-OAEP" ]] \
    && ok "CryptoHybrid usa as chaves montadas em runtime" \
    || fail "CryptoHybrid não concluiu round-trip"

echo
echo "=== HTTPS / TLS ==="
HTTPS_HEALTH="$(https_code '/_container_health')"
echo "https_health=$HTTPS_HEALTH"
[[ "$HTTPS_HEALTH" == "200" ]] \
    && ok "HTTPS da DMZ responde" \
    || fail "health HTTPS falhou"

TLS_INFO="$(openssl s_client \
    -connect 127.0.0.1:8088 \
    -servername "$HOST_HEADER" \
    -tls1_2 \
    </dev/null 2>/dev/null \
    | grep -E 'Protocol *:|Cipher *:' \
    | tr '\n' ' ' || true)"
echo "tls_info=$TLS_INFO"

[[ "$TLS_INFO" == *"TLSv1.2"* ]] \
    && ok "TLS 1.2 aceito" \
    || fail "TLS 1.2 não foi confirmado"

echo
echo "=== ENDPOINT DE CHAVE PÚBLICA ==="
PUB_BODY="$TMPDIR_PHASE/public-key.json"
PUB_CODE="$(curl -k -sS \
    --max-time 10 \
    -H "Host: $HOST_HEADER" \
    -o "$PUB_BODY" \
    -w '%{http_code}' \
    "$BASE_URL/api/public_key.php" \
    2>/dev/null || true)"

echo "public_key_http=$PUB_CODE"

[[ "$PUB_CODE" == "200" ]] \
    && ok "public_key.php respondeu 200" \
    || fail "public_key.php não respondeu 200"

grep -Fq '"public_key_pem"' "$PUB_BODY" \
    && ok "endpoint contém chave pública" \
    || fail "endpoint não contém public_key_pem"

grep -Fq 'BEGIN PRIVATE KEY' "$PUB_BODY" \
    && fail "endpoint expôs chave privada" \
    || ok "endpoint não expõe chave privada"

echo
echo "=== ENDPOINT COM ACESSO AO BANCO ==="
OPP_CODE="$(https_code '/api/oportunidades.php')"
echo "oportunidades_http=$OPP_CODE"

[[ "$OPP_CODE" == "200" ]] \
    && ok "API de oportunidades usa aplicação + banco sem erro" \
    || fail "API de oportunidades não respondeu 200"

echo
echo "=== SESSÃO HTTPS / COOKIE ==="
COOKIE_JAR="$TMPDIR_PHASE/cookies.txt"
LOGIN_HEADERS="$TMPDIR_PHASE/login.headers"
LOGIN_BODY="$TMPDIR_PHASE/login.html"

LOGIN_CODE="$(curl -k -sS \
    --max-time 10 \
    -H "Host: $HOST_HEADER" \
    -D "$LOGIN_HEADERS" \
    -c "$COOKIE_JAR" \
    -o "$LOGIN_BODY" \
    -w '%{http_code}' \
    "$BASE_URL/login.php" \
    2>/dev/null || true)"

echo "login_get_http=$LOGIN_CODE"
[[ "$LOGIN_CODE" == "200" ]] \
    && ok "GET /login.php" \
    || fail "GET /login.php não respondeu 200"

COOKIE_LINE="$(grep -i '^Set-Cookie: CONECTAEDUCASESSID=' "$LOGIN_HEADERS" | head -n1 || true)"

if [[ -n "$COOKIE_LINE" ]]; then
    ok "cookie de sessão emitido"
else
    fail "cookie CONECTAEDUCASESSID não foi emitido"
fi

echo "$COOKIE_LINE" | grep -qi 'Secure' \
    && ok "cookie Secure" \
    || fail "cookie sem Secure"

echo "$COOKIE_LINE" | grep -qi 'HttpOnly' \
    && ok "cookie HttpOnly" \
    || fail "cookie sem HttpOnly"

echo "$COOKIE_LINE" | grep -qi 'SameSite=Lax' \
    && ok "cookie SameSite=Lax" \
    || fail "cookie sem SameSite=Lax"

CSRF="$(extract_csrf "$LOGIN_BODY")"
echo "csrf_detectado=$([[ -n "$CSRF" ]] && echo sim || echo nao)"

[[ -n "$CSRF" ]] \
    && ok "CSRF do login obtido" \
    || fail "CSRF do login não foi encontrado"

echo
echo "=== LOGIN INVÁLIDO / AUDITORIA ==="
INVALID_EMAIL="fase4e.invalido@exemplo.test"
INVALID_PASS="Senha-Invalida-Fase4E-123!"

INVALID_CODE="$(curl -k -sS \
    --max-time 10 \
    -H "Host: $HOST_HEADER" \
    -b "$COOKIE_JAR" \
    -c "$COOKIE_JAR" \
    -o "$TMPDIR_PHASE/login-invalid.html" \
    -w '%{http_code}' \
    --data-urlencode "csrf_token=$CSRF" \
    --data-urlencode "email=$INVALID_EMAIL" \
    --data-urlencode "senha=$INVALID_PASS" \
    "$BASE_URL/login.php" \
    2>/dev/null || true)"

echo "login_invalido_http=$INVALID_CODE"
[[ "$INVALID_CODE" == "401" ]] \
    && ok "credencial inválida rejeitada" \
    || fail "login inválido não retornou 401"

if "${DMZ[@]}" exec -T php sh -ec \
    'grep -q "\"event\":\"login_failed\"" /var/www/conectaeduca/storage/logs/audit.log'
then
    ok "auditoria registrou login_failed"
else
    fail "audit.log não registrou login_failed"
fi

if "${DMZ[@]}" exec -T php sh -ec \
    "grep -Fq '$INVALID_PASS' /var/www/conectaeduca/storage/logs/audit.log"
then
    fail "senha apareceu no audit.log"
else
    ok "senha não aparece no audit.log"
fi

echo
echo "=== FIXTURE DE USUÁRIO PELO SERVIÇO REAL ==="
FIXTURE_EMAIL="fase4e.usuario@exemplo.test"
FIXTURE_PASS="F4E-$(openssl rand -hex 12)-Aa9!"

FIXTURE_ID="$("${DMZ[@]}" exec -T \
    -e FASE4E_USER_EMAIL="$FIXTURE_EMAIL" \
    -e FASE4E_USER_PASS="$FIXTURE_PASS" \
    php php -r '
require "/var/www/conectaeduca/vendor/autoload.php";

$service = new \ConectaEduca\Service\UsuarioService();

$id = $service->criarLocal([
    "nome" => "Usuário Fase 4E",
    "email" => getenv("FASE4E_USER_EMAIL"),
    "role" => "usuario",
    "senha" => getenv("FASE4E_USER_PASS"),
    "confirmarSenha" => getenv("FASE4E_USER_PASS"),
]);

echo $id, PHP_EOL;
' 2>&1 || true)"

echo "fixture_id=$FIXTURE_ID"

[[ "$FIXTURE_ID" =~ ^[0-9]+$ ]] \
    && ok "UsuarioService criou fixture no banco remoto" \
    || fail "UsuarioService não criou fixture"

FIXTURE_STATE="$("${DMZ[@]}" exec -T \
    -e FASE4E_USER_ID="$FIXTURE_ID" \
    php php -r '
require "/var/www/conectaeduca/vendor/autoload.php";

$pdo = \ConectaEduca\Config\Database::connect();
$stmt = $pdo->prepare(
    "SELECT id, conta_ativada, mfa_ativo, role
     FROM usuarios
     WHERE id = :id"
);
$stmt->execute(["id" => (int) getenv("FASE4E_USER_ID")]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);

if ($row) {
    echo $row["id"], "|", $row["conta_ativada"], "|", $row["mfa_ativo"], "|", $row["role"], PHP_EOL;
}
' 2>&1 || true)"

echo "fixture_state=$FIXTURE_STATE"

[[ "$FIXTURE_STATE" == "$FIXTURE_ID|1|0|usuario" ]] \
    && ok "fixture ativa e ainda sem MFA configurado" \
    || fail "estado inicial da fixture inesperado"

echo
echo "=== LOGIN VÁLIDO DEVE EXIGIR MFA ==="
LOGIN2_HEADERS="$TMPDIR_PHASE/login2.headers"
LOGIN2_BODY="$TMPDIR_PHASE/login2.html"

curl -k -sS \
    --max-time 10 \
    -H "Host: $HOST_HEADER" \
    -D "$LOGIN2_HEADERS" \
    -b "$COOKIE_JAR" \
    -c "$COOKIE_JAR" \
    -o "$LOGIN2_BODY" \
    "$BASE_URL/login.php" \
    >/dev/null 2>&1 || true

CSRF2="$(extract_csrf "$LOGIN2_BODY")"

VALID_HEADERS="$TMPDIR_PHASE/valid.headers"
VALID_CODE="$(curl -k -sS \
    --max-time 10 \
    -H "Host: $HOST_HEADER" \
    -D "$VALID_HEADERS" \
    -b "$COOKIE_JAR" \
    -c "$COOKIE_JAR" \
    -o /dev/null \
    -w '%{http_code}' \
    --data-urlencode "csrf_token=$CSRF2" \
    --data-urlencode "email=$FIXTURE_EMAIL" \
    --data-urlencode "senha=$FIXTURE_PASS" \
    "$BASE_URL/login.php" \
    2>/dev/null || true)"

VALID_LOCATION="$(awk 'BEGIN{IGNORECASE=1} /^Location:/{gsub("\r",""); print $2; exit}' "$VALID_HEADERS")"

echo "login_valido_http=$VALID_CODE"
echo "login_valido_location=$VALID_LOCATION"

[[ "$VALID_CODE" == "302" ]] \
    && ok "senha válida inicia próxima etapa sem autenticação final" \
    || fail "login válido não retornou 302"

if [[ "$VALID_LOCATION" == /mfa* ]]; then
    ok "login válido direciona para MFA"
else
    fail "login válido não direcionou para rota MFA"
fi

MFA_CODE="$(curl -k -sS \
    --max-time 10 \
    -H "Host: $HOST_HEADER" \
    -b "$COOKIE_JAR" \
    -o /dev/null \
    -w '%{http_code}' \
    "$BASE_URL$VALID_LOCATION" \
    2>/dev/null || true)"

echo "mfa_http=$MFA_CODE"

[[ "$MFA_CODE" == "200" ]] \
    && ok "rota MFA acessível em pré-autenticação" \
    || fail "rota MFA não respondeu 200"

PENDING_DASHBOARD="$(curl -k -sS \
    --max-time 10 \
    -H "Host: $HOST_HEADER" \
    -b "$COOKIE_JAR" \
    -o /dev/null \
    -w '%{http_code}' \
    "$BASE_URL/dashboard.php" \
    2>/dev/null || true)"

echo "dashboard_durante_preauth=$PENDING_DASHBOARD"

[[ "$PENDING_DASHBOARD" == "401" ]] \
    && ok "pré-autenticação MFA não concede dashboard" \
    || fail "dashboard ficou acessível antes do MFA"

echo
echo "=== ROTA ADMINISTRATIVA SEM AUTENTICAÇÃO ==="
ADMIN_CODE="$(https_code '/admin/auditoria.php')"
echo "admin_sem_sessao=$ADMIN_CODE"

[[ "$ADMIN_CODE" == "401" ]] \
    && ok "admin protegido sem sessão" \
    || fail "rota admin não retornou 401"

echo
echo "=== EXPOSIÇÃO DE PORTAS ==="
DB_BINDINGS="$(docker inspect "$DB_ID" --format '{{json .HostConfig.PortBindings}}' 2>/dev/null || true)"
PHP_BINDINGS="$(docker inspect "$PHP_ID" --format '{{json .HostConfig.PortBindings}}' 2>/dev/null || true)"
NGINX_PORTS="$(docker inspect "$NGINX_ID" --format '{{json .NetworkSettings.Ports}}' 2>/dev/null || true)"

echo "db_bindings=$DB_BINDINGS"
echo "php_bindings=$PHP_BINDINGS"
echo "nginx_ports=$NGINX_PORTS"

[[ "$DB_BINDINGS" == "{}" || "$DB_BINDINGS" == "null" ]] \
    && ok "MariaDB sem porta publicada" \
    || fail "MariaDB publicou porta no host"

[[ "$PHP_BINDINGS" == "{}" || "$PHP_BINDINGS" == "null" || "$PHP_BINDINGS" == '{"9000/tcp":null}' ]] \
    && ok "PHP-FPM sem porta publicada" \
    || fail "PHP-FPM publicou porta no host"

echo "$NGINX_PORTS" | grep -Fq '"HostIp":"127.0.0.1"' \
    && echo "$NGINX_PORTS" | grep -Fq '"HostPort":"8088"' \
    && ok "Nginx limitado a 127.0.0.1:8088 no laboratório" \
    || fail "publicação do Nginx inesperada"

echo
echo "=== RESULTADO ==="
echo "Falhas: $FAIL"

if [[ "$FAIL" -eq 0 ]]; then
    echo "FASE 4E: APROVADA."
    echo "A aplicação real executou com HTTPS, DB remoto, secrets e MFA obrigatório."
else
    echo "FASE 4E: REPROVADA."
fi

echo "Containers, volumes, rede, fixtures e secrets temporários serão removidos automaticamente."
echo "Relatório: $REPORT"
echo "======================================================================"
} | tee "$REPORT"

[[ "$FAIL" -eq 0 ]]
