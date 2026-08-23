#!/usr/bin/env bash
set -u
export LC_ALL=C
export LANG=C

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"
CHECK_MODE="${CHECK_MODE:-local}"
TARGET_PLATFORM="${TARGET_PLATFORM:-linux/amd64}"

LAB_DB_PORT="${LAB_DB_PORT:-}"
LAB_HTTP_PORT="${LAB_HTTP_PORT:-}"
LAB_HTTPS_PORT="${LAB_HTTPS_PORT:-}"
LAB_DB_BIND_ADDRESS="${LAB_DB_BIND_ADDRESS:-}"
HOST_NAME="${CONECTAEDUCA_HOST_HEADER:-conectaeduca.local}"

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/conectaeduca-checkpoint-portabilidade-${STAMP}.txt"

DMZ_PROJECT="conectaeduca-dmz-portability-test"
DB_PROJECT="conectaeduca-mariadb-portability-test"

DMZ_FILES=(
  "$ROOT/deploy/dmz/compose.yml"
  "$ROOT/deploy/dmz/compose.database.yml"
  "$ROOT/deploy/dmz/compose.app-secrets.yml"
  "$ROOT/deploy/dmz/compose.waf.yml"
  "$ROOT/deploy/dmz/compose.waf-tls.yml"
  "$ROOT/deploy/dmz/compose.waf-policy.yml"
  "$ROOT/deploy/dmz/compose.host.yml"
)

DB_FILES=(
  "$ROOT/deploy/interna/mariadb/compose.yml"
  "$ROOT/deploy/interna/mariadb/compose.host.yml"
)

FAIL=0
WARN=0
STARTED=0
SECRET_DIR=""
TMP_DIR=""
TEST_OVERRIDE=""
DB_READY=0
PHP_READY=0
NGINX_READY=0
WAF_READY=0
DB_BINDING_OK=0
WAF_BINDING_OK=0

ok(){ echo "OK       $*"; }
fail(){ echo "FALHA    $*"; FAIL=$((FAIL+1)); }
warn(){ echo "ATENÇÃO  $*"; WARN=$((WARN+1)); }
info(){ echo "INFO     $*"; }

version_ge() {
  python3 - "$1" "$2" <<'PY'
import re, sys

def parts(v):
    nums = re.findall(r'\d+', v)
    return tuple(int(x) for x in (nums + ['0','0','0'])[:3])

raise SystemExit(0 if parts(sys.argv[1]) >= parts(sys.argv[2]) else 1)
PY
}

valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( 1 <= 10#$1 && 10#$1 <= 65535 ))
}

port_available() {
  local bind_address="$1"
  local port="$2"

  python3 - "$bind_address" "$port" <<'PY' >/dev/null 2>&1
import socket
import sys

address = sys.argv[1]
port = int(sys.argv[2])

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    s.bind((address, port))
except OSError:
    raise SystemExit(1)
finally:
    s.close()

raise SystemExit(0)
PY
}

select_test_port() {
  local var_name="$1"
  local bind_address="$2"
  local range_start="$3"
  local range_end="$4"
  local label="$5"
  local configured="${!var_name:-}"
  local port

  if [[ -n "$configured" ]]; then
    if ! valid_port "$configured"; then
      fail "$label: porta configurada inválida ($configured)"
      return 1
    fi

    if port_available "$bind_address" "$configured"; then
      printf -v "$var_name" '%s' "$configured"
      ok "$label: porta explícita $configured está livre em $bind_address"
      return 0
    fi

    fail "$label: porta explícita $configured está ocupada em $bind_address"
    return 1
  fi

  for (( port=range_start; port<=range_end; port++ )); do
    if port_available "$bind_address" "$port"; then
      printf -v "$var_name" '%s' "$port"
      ok "$label: porta de teste selecionada dinamicamente: $bind_address:$port"
      return 0
    fi
  done

  fail "$label: nenhuma porta livre encontrada em ${range_start}-${range_end} para $bind_address"
  return 1
}

dmz() {
  local args=()
  local f
  for f in "${DMZ_FILES[@]}"; do
    args+=(-f "$f")
  done
  if [[ -n "${TEST_OVERRIDE:-}" ]]; then
    args+=(-f "$TEST_OVERRIDE")
  fi
  docker compose -p "$DMZ_PROJECT" "${args[@]}" "$@"
}

db() {
  docker compose \
    -p "$DB_PROJECT" \
    -f "${DB_FILES[0]}" \
    -f "${DB_FILES[1]}" \
    "$@"
}

wait_healthy() {
  local label="$1"
  local id="$2"
  local timeout="${3:-180}"
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

cleanup() {
  set +e
  if [[ "$STARTED" -eq 1 ]]; then
    dmz down --remove-orphans >/dev/null 2>&1 || true
    db down -v --remove-orphans >/dev/null 2>&1 || true
  fi

  [[ -n "${SECRET_DIR:-}" && -d "$SECRET_DIR" ]] && rm -rf "$SECRET_DIR"
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"

  unset CONECTAEDUCA_DB_ROOT_PASSWORD_FILE
  unset CONECTAEDUCA_DB_PASSWORD_FILE
  unset CONECTAEDUCA_DB_HOST
  unset CONECTAEDUCA_DB_BIND_ADDRESS
  unset CONECTAEDUCA_DB_PORT
  unset CONECTAEDUCA_PRIVATE_KEY_FILE
  unset CONECTAEDUCA_PUBLIC_KEY_FILE
  unset CONECTAEDUCA_WAF_TLS_CERT_FILE
  unset CONECTAEDUCA_WAF_TLS_KEY_FILE
  unset CONECTAEDUCA_WAF_BIND_ADDRESS
  unset CONECTAEDUCA_HTTP_PORT
  unset CONECTAEDUCA_HTTPS_PORT
}
trap cleanup EXIT INT TERM

manifest_supports() {
  local image="$1"
  local platform="$2"
  local raw

  raw="$(docker buildx imagetools inspect "$image" --raw 2>/dev/null || true)"
  [[ -n "$raw" ]] || return 2

  printf '%s' "$raw" | python3 -c '
import json, sys

wanted = sys.argv[1]
os_name, arch = wanted.split("/", 1)
obj = json.load(sys.stdin)

manifests = obj.get("manifests")
if manifests is None:
    raise SystemExit(2)

for m in manifests:
    p = m.get("platform") or {}
    if p.get("os") == os_name and p.get("architecture") == arch:
        raise SystemExit(0)

raise SystemExit(1)
' "$platform"
}

exec > >(tee "$REPORT") 2>&1

echo "======================================================================"
echo " CONECTAEDUCA - CHECKPOINT DE PORTABILIDADE DOS CONTAINERS v4"
echo " Modo: $CHECK_MODE"
echo " Plataforma alvo: $TARGET_PLATFORM"
echo " Data: $(date --iso-8601=seconds)"
echo "======================================================================"

cd "$ROOT" || exit 1

echo
echo "=== 1. GIT / BRANCH ==="
git status -sb

BRANCH="$(git branch --show-current 2>/dev/null || true)"
echo "branch_atual=$BRANCH"

[[ "$BRANCH" == "main" ]] \
  && ok "branch main confirmada" \
  || fail "branch deve ser main"

git diff --check \
  && ok "git diff --check" \
  || fail "git diff --check"

echo
echo "=== 2. CONTRATO DO HOST ==="
DOCKER_VERSION="$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)"
COMPOSE_VERSION="$(docker compose version --short 2>/dev/null || true)"
HOST_ARCH="$(uname -m 2>/dev/null || true)"
HOST_OS="$(uname -s 2>/dev/null || true)"

echo "docker_engine=${DOCKER_VERSION:-indisponivel}"
echo "docker_compose=${COMPOSE_VERSION:-indisponivel}"
echo "host_os=${HOST_OS:-desconhecido}"
echo "host_arch=${HOST_ARCH:-desconhecido}"

if docker info >/dev/null 2>&1; then
  ok "acesso à API Docker confirmado"
else
  fail "sem permissão para acessar a API Docker"
  echo "INFO     grupos_atuais=$(id -nG 2>/dev/null || true)"
  echo "INFO     socket_docker=$(ls -l /var/run/docker.sock 2>/dev/null || true)"
  echo
  echo "CHECKPOINT INTERROMPIDO: os testes dinâmicos dependem da API Docker."
  echo "Corrija o acesso ao socket Docker e execute o mesmo checkpoint novamente."
  echo "Falhas: $FAIL"
  echo "Advertências: $WARN"
  echo "Relatório: $REPORT"
  exit 1
fi

[[ -n "$DOCKER_VERSION" ]] \
  && ok "Docker Engine disponível" \
  || fail "Docker Engine indisponível"

if [[ -n "$COMPOSE_VERSION" ]] && version_ge "$COMPOSE_VERSION" "2.24.4"; then
  ok "Docker Compose >= 2.24.4"
else
  fail "Docker Compose 2.24.4+ é obrigatório por !reset/!override"
fi

case "$TARGET_PLATFORM" in
  linux/amd64|linux/arm64)
    ok "plataforma alvo aceita pelo contrato do projeto: $TARGET_PLATFORM"
    ;;
  *)
    fail "plataforma alvo ainda não homologada pelo checkpoint: $TARGET_PLATFORM"
    ;;
esac

if [[ "$CHECK_MODE" == "target" ]]; then
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "target_os_id=${ID:-}"
    echo "target_os_version=${VERSION_ID:-}"

    if [[ "${ID:-}" == "ubuntu" ]]; then
      ok "host alvo é Ubuntu"
    else
      fail "modo target deve ser executado na VM Ubuntu"
    fi

    case "${VERSION_ID:-}" in
      22.04|24.04|26.04)
        ok "versão Ubuntu atualmente suportada pelo Docker: ${VERSION_ID}"
        ;;
      *)
        warn "Ubuntu ${VERSION_ID:-desconhecido}: confirmar suporte no Docker antes do deploy"
        ;;
    esac
  else
    fail "/etc/os-release indisponível no host alvo"
  fi
else
  info "modo local: o host atual não precisa ser Ubuntu"
fi

echo
echo "=== 3. ARQUIVOS DE HANDOFF ==="
REQUIRED=(
  deploy/CONTRATO-IMPLANTACAO.md
  deploy/dmz/compose.yml
  deploy/dmz/compose.database.yml
  deploy/dmz/compose.app-secrets.yml
  deploy/dmz/compose.waf.yml
  deploy/dmz/compose.waf-tls.yml
  deploy/dmz/compose.waf-policy.yml
  deploy/dmz/compose.host.yml
  deploy/interna/mariadb/compose.yml
  deploy/interna/mariadb/compose.host.yml
)

for rel in "${REQUIRED[@]}"; do
  [[ -f "$ROOT/$rel" ]] \
    && ok "$rel" \
    || fail "ausente: $rel"
done

echo
echo "=== 4. HIGIENE DE PORTABILIDADE ==="

HANDOFF_SCAN_FILES=(
  deploy/dmz/compose.yml
  deploy/dmz/compose.database.yml
  deploy/dmz/compose.app-secrets.yml
  deploy/dmz/compose.waf.yml
  deploy/dmz/compose.waf-tls.yml
  deploy/dmz/compose.waf-policy.yml
  deploy/dmz/compose.host.yml
  deploy/dmz/nginx/Dockerfile
  deploy/dmz/nginx/app-http.conf
  deploy/dmz/php/Dockerfile
  deploy/dmz/php/php.ini
  deploy/dmz/php/zz-conectaeduca.conf
  deploy/dmz/waf/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
  deploy/dmz/waf/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf
  deploy/interna/mariadb/compose.yml
  deploy/interna/mariadb/compose.host.yml
  deploy/interna/mariadb/conectaeduca.cnf
  deploy/interna/mariadb/20-minimos-privilegios.sql
)

EXISTING_HANDOFF_FILES=()
for f in "${HANDOFF_SCAN_FILES[@]}"; do
  [[ -f "$f" ]] && EXISTING_HANDOFF_FILES+=("$f")
done

if grep -nE 'network_mode:[[:space:]]*host' "${EXISTING_HANDOFF_FILES[@]}" 2>/dev/null | grep -q .; then
  fail "network_mode: host encontrado no conjunto de handoff"
else
  ok "nenhum network_mode: host no conjunto de handoff"
fi

if grep -nE 'privileged:[[:space:]]*true' "${EXISTING_HANDOFF_FILES[@]}" 2>/dev/null | grep -q .; then
  fail "privileged: true encontrado no conjunto de handoff"
else
  ok "nenhum privileged: true no conjunto de handoff"
fi

if grep -nF '/var/run/docker.sock' "${EXISTING_HANDOFF_FILES[@]}" 2>/dev/null | grep -q .; then
  fail "Docker socket montado no conjunto de handoff"
else
  ok "Docker socket não é montado no conjunto de handoff"
fi

LAB_IP_MATCHES="$(
  grep -nHE '172\.30\.25[0-9]\.' \
    "${EXISTING_HANDOFF_FILES[@]}" 2>/dev/null || true
)"

if [[ -n "$LAB_IP_MATCHES" ]]; then
  fail "IP de laboratório 172.30.25x.x encontrado no conjunto REAL de handoff"
  echo "--- ocorrências ---"
  printf '%s\n' "$LAB_IP_MATCHES"
else
  ok "nenhum IP 172.30.25x.x no conjunto real de handoff"
fi

info "overlays históricos/de laboratório fora do fechamento de handoff não reprovam esta checagem"

if grep -RInE 'DB_HOST[=:][[:space:]]*(mariadb|db)([[:space:]]|$)' \
  deploy/dmz/compose.yml \
  deploy/dmz/compose.database.yml \
  deploy/dmz/compose.app-secrets.yml \
  deploy/dmz/compose.waf.yml \
  deploy/dmz/compose.waf-tls.yml \
  deploy/dmz/compose.waf-policy.yml \
  deploy/dmz/compose.host.yml \
  2>/dev/null | grep -q .; then
  fail "DB_HOST do handoff depende de nome de serviço Docker"
else
  ok "DB_HOST do handoff não depende de DNS Docker entre hosts"
fi

grep -q 'CONECTAEDUCA_DB_HOST' deploy/dmz/compose.host.yml \
  && ok "endpoint do banco é configurável para a VM interna" \
  || fail "compose.host.yml da DMZ não parametriza DB_HOST"

grep -q 'CONECTAEDUCA_DB_BIND_ADDRESS' deploy/interna/mariadb/compose.host.yml \
  && ok "binding do MariaDB é configurável" \
  || fail "compose.host.yml do MariaDB não parametriza o endereço"

echo
echo "=== 5. BASE IMAGES / PLATAFORMA ==="
IMAGES=(
  "owasp/modsecurity-crs:4.25.1-nginx-lts"
  "mariadb:12.3.2-ubi10"
  "nginx:stable-alpine"
  "php:8.5-fpm-bookworm"
  "composer:2"
)

for image in "${IMAGES[@]}"; do
  if manifest_supports "$image" "$TARGET_PLATFORM"; then
    ok "$image oferece $TARGET_PLATFORM"
  else
    rc=$?
    if [[ "$rc" -eq 1 ]]; then
      fail "$image não oferece $TARGET_PLATFORM"
    else
      warn "não foi possível confirmar manifesto multi-arch de $image"
    fi
  fi
done

echo
echo "=== 6. REPRODUTIBILIDADE DAS IMAGENS ==="

PIN_CHECKS=(
  "deploy/dmz/nginx/Dockerfile|nginx:stable-alpine"
  "deploy/dmz/php/Dockerfile|php:8.5-fpm-bookworm"
  "deploy/dmz/php/Dockerfile|composer:2"
  "deploy/dmz/compose.waf.yml|owasp/modsecurity-crs:4.25.1-nginx-lts"
  "deploy/interna/mariadb/compose.yml|mariadb:12.3.2-ubi10"
)

for pair in "${PIN_CHECKS[@]}"; do
  file="${pair%%|*}"
  tag="${pair#*|}"

  if grep -F "$tag@sha256:" "$file" 2>/dev/null | grep -Eq '@sha256:[0-9a-f]{64}'; then
    ok "$tag está fixada por digest"
  else
    warn "$tag não está fixada por digest em $file"
  fi
done

info "digest fixa a referência de imagem; dependências obtidas durante build têm ciclo próprio"

echo
echo "=== 7. ISOLAMENTO DINÂMICO DO TESTE ==="

if [[ -z "$LAB_DB_BIND_ADDRESS" ]]; then
  LAB_DB_BIND_ADDRESS="$(
    docker network inspect bridge \
      --format '{{(index .IPAM.Config 0).Gateway}}' \
      2>/dev/null || true
  )"
fi

if [[ -z "$LAB_DB_BIND_ADDRESS" ]]; then
  fail "não foi possível determinar o gateway IPv4 da bridge Docker para o banco sintético"
  echo "CHECKPOINT INTERROMPIDO: não é seguro usar wildcard como fallback."
  echo "Falhas: $FAIL"
  echo "Advertências: $WARN"
  echo "Relatório: $REPORT"
  exit 1
fi

if ! select_test_port LAB_DB_PORT "$LAB_DB_BIND_ADDRESS" 23000 23999 "MariaDB sintético"; then
  echo "CHECKPOINT INTERROMPIDO: endpoint isolado do MariaDB indisponível."
  exit 1
fi

if ! select_test_port LAB_HTTP_PORT "127.0.0.1" 28000 28499 "WAF HTTP sintético"; then
  echo "CHECKPOINT INTERROMPIDO: endpoint HTTP isolado do WAF indisponível."
  exit 1
fi

if ! select_test_port LAB_HTTPS_PORT "127.0.0.1" 28500 28999 "WAF HTTPS sintético"; then
  echo "CHECKPOINT INTERROMPIDO: endpoint HTTPS isolado do WAF indisponível."
  exit 1
fi

echo "db_test_endpoint=${LAB_DB_BIND_ADDRESS}:${LAB_DB_PORT}"
echo "waf_http_test_endpoint=127.0.0.1:${LAB_HTTP_PORT}"
echo "waf_https_test_endpoint=127.0.0.1:${LAB_HTTPS_PORT}"
ok "portas do teste são independentes da stack local persistente"

echo
echo "=== 8. SEGREDOS SINTÉTICOS ==="
SECRET_DIR="$(mktemp -d /tmp/conectaeduca-portability-secrets.XXXXXX)"
TMP_DIR="$(mktemp -d /tmp/conectaeduca-portability-tmp.XXXXXX)"
chmod 0700 "$SECRET_DIR" "$TMP_DIR"

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
  -out "$APP_PRIVATE" >/dev/null 2>&1

openssl pkey \
  -in "$APP_PRIVATE" \
  -pubout \
  -out "$APP_PUBLIC" >/dev/null 2>&1

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
  "$ROOT_SECRET" "$APP_SECRET" \
  "$APP_PRIVATE" "$APP_PUBLIC" \
  "$WAF_TLS_KEY" "$WAF_TLS_CERT"

export CONECTAEDUCA_DB_ROOT_PASSWORD_FILE="$ROOT_SECRET"
export CONECTAEDUCA_DB_PASSWORD_FILE="$APP_SECRET"
export CONECTAEDUCA_PRIVATE_KEY_FILE="$APP_PRIVATE"
export CONECTAEDUCA_PUBLIC_KEY_FILE="$APP_PUBLIC"
export CONECTAEDUCA_WAF_TLS_CERT_FILE="$WAF_TLS_CERT"
export CONECTAEDUCA_WAF_TLS_KEY_FILE="$WAF_TLS_KEY"

# Valores de laboratório usados apenas para simular duas VMs sem compartilhar
# uma rede Docker.
export CONECTAEDUCA_DB_HOST="host.docker.internal"
export CONECTAEDUCA_DB_BIND_ADDRESS="$LAB_DB_BIND_ADDRESS"
export CONECTAEDUCA_DB_PORT="$LAB_DB_PORT"

export CONECTAEDUCA_WAF_BIND_ADDRESS="127.0.0.1"
export CONECTAEDUCA_HTTP_PORT="$LAB_HTTP_PORT"
export CONECTAEDUCA_HTTPS_PORT="$LAB_HTTPS_PORT"

ok "segredos e parâmetros sintéticos preparados fora do Git"

echo
echo "=== 9. COMPOSE DE HANDOFF ==="
if db config >/dev/null; then
  ok "Compose MariaDB + adaptador de VM válido"
else
  fail "Compose MariaDB de handoff inválido"
fi

TEST_OVERRIDE="$TMP_DIR/compose.host-gateway.yml"
cat > "$TEST_OVERRIDE" <<'YAML'
services:
  php:
    extra_hosts:
      - "host.docker.internal:host-gateway"
YAML

if dmz config >/dev/null; then
  ok "Compose DMZ completo + adaptador de VM válido"
else
  fail "Compose DMZ de handoff inválido"
fi

DMZ_JSON="$(dmz config --format json 2>/dev/null || true)"
DB_JSON="$(db config --format json 2>/dev/null || true)"

if printf '%s' "$DMZ_JSON" | python3 -c '
import json, sys

c=json.load(sys.stdin)["services"]
http_port=int(sys.argv[1])
https_port=int(sys.argv[2])
db_port=str(sys.argv[3])

assert set(c)=={"nginx","php","waf"}
assert not c["nginx"].get("ports")
assert not c["php"].get("ports")

ports=c["waf"].get("ports", [])
pairs={(p.get("host_ip"), int(p.get("published")), int(p.get("target"))) for p in ports}
assert ("127.0.0.1", http_port, 8080) in pairs
assert ("127.0.0.1", https_port, 8443) in pairs
assert not any(p[1] in (18080,18443) for p in pairs)

env=c["php"]["environment"]
assert env["DB_HOST"]=="host.docker.internal"
assert str(env["DB_PORT"])==db_port
' "$LAB_HTTP_PORT" "$LAB_HTTPS_PORT" "$LAB_DB_PORT"
then
  ok "adaptador DMZ substitui bindings de laboratório"
  ok "PHP usa endpoint DB configurável fora do DNS Docker"
else
  fail "Compose DMZ resultante ainda contém dependência de laboratório"
fi

if printf '%s' "$DB_JSON" | python3 -c '
import json, sys
c=json.load(sys.stdin)["services"]["mariadb"]
port=int(sys.argv[1])
bind=sys.argv[2]
ports=c.get("ports", [])
assert any(
    p.get("host_ip") == bind
    and int(p.get("published")) == port
    and int(p.get("target")) == 3306
    for p in ports
)
' "$LAB_DB_PORT" "$LAB_DB_BIND_ADDRESS"
then
  ok "MariaDB possui endpoint TCP configurável e restrito ao gateway Docker do teste"
else
  fail "MariaDB de handoff não publicou o endpoint configurado"
fi

echo
echo "=== 10. PORTAS DE TESTE ==="
if port_available "$LAB_DB_BIND_ADDRESS" "$LAB_DB_PORT"; then
  ok "endpoint MariaDB sintético ainda está livre antes da subida"
else
  fail "endpoint MariaDB sintético foi ocupado antes da subida"
fi

if port_available "127.0.0.1" "$LAB_HTTP_PORT"; then
  ok "endpoint HTTP sintético ainda está livre antes da subida"
else
  fail "endpoint HTTP sintético foi ocupado antes da subida"
fi

if port_available "127.0.0.1" "$LAB_HTTPS_PORT"; then
  ok "endpoint HTTPS sintético ainda está livre antes da subida"
else
  fail "endpoint HTTPS sintético foi ocupado antes da subida"
fi

echo
echo "=== 11. BUILD DMZ ==="
if dmz build nginx php; then
  ok "imagens da aplicação constroem com o conjunto de handoff"
else
  fail "build DMZ falhou"
fi

echo
echo "=== 12. MARIADB COMO ENDPOINT DE OUTRA VM ==="
STARTED=1
if db up -d; then
  ok "MariaDB iniciado com porta TCP publicada"
else
  fail "MariaDB não iniciou"
fi

DB_ID="$(db ps -q mariadb 2>/dev/null || true)"
if [[ -n "$DB_ID" ]] && wait_healthy "mariadb" "$DB_ID" 180; then
  DB_READY=1
  ok "MariaDB healthy"
else
  fail "MariaDB não ficou healthy"
  db logs --no-color --tail=120 mariadb || true
fi

DB_BINDINGS="$(docker port "$DB_ID" 3306/tcp 2>/dev/null || true)"
EXPECTED_DB_BINDING="${LAB_DB_BIND_ADDRESS}:${LAB_DB_PORT}"
echo "db_bindings=$DB_BINDINGS"

if printf '%s\n' "$DB_BINDINGS" | grep -Fxq "$EXPECTED_DB_BINDING"; then
  DB_BINDING_OK=1
  ok "MariaDB exposto exatamente no endpoint isolado do teste"
else
  fail "binding TCP do MariaDB divergiu do endpoint isolado esperado"
fi

echo
echo "=== 13. DMZ SEM REDE DOCKER COMPARTILHADA COM O BANCO ==="
if dmz up -d; then
  ok "DMZ completa iniciada"
else
  fail "DMZ não iniciou"
fi

PHP_ID="$(dmz ps -q php 2>/dev/null || true)"
NGINX_ID="$(dmz ps -q nginx 2>/dev/null || true)"
WAF_ID="$(dmz ps -q waf 2>/dev/null || true)"

if [[ -n "$PHP_ID" ]] && wait_healthy "php-fpm" "$PHP_ID" 120; then
  PHP_READY=1
  ok "PHP-FPM healthy"
else
  fail "PHP-FPM não ficou healthy"
fi

if [[ -n "$NGINX_ID" ]] && wait_healthy "nginx" "$NGINX_ID" 120; then
  NGINX_READY=1
  ok "Nginx healthy"
else
  fail "Nginx não ficou healthy"
fi

if [[ -n "$WAF_ID" ]] && wait_healthy "waf" "$WAF_ID" 180; then
  WAF_READY=1
  ok "WAF healthy"
else
  fail "WAF não ficou healthy"
  dmz logs --no-color --tail=120 waf || true
fi

WAF_HTTP_BINDINGS="$(docker port "$WAF_ID" 8080/tcp 2>/dev/null || true)"
WAF_HTTPS_BINDINGS="$(docker port "$WAF_ID" 8443/tcp 2>/dev/null || true)"
EXPECTED_WAF_HTTP="127.0.0.1:${LAB_HTTP_PORT}"
EXPECTED_WAF_HTTPS="127.0.0.1:${LAB_HTTPS_PORT}"

if printf '%s\n' "$WAF_HTTP_BINDINGS" | grep -Fxq "$EXPECTED_WAF_HTTP" \
   && printf '%s\n' "$WAF_HTTPS_BINDINGS" | grep -Fxq "$EXPECTED_WAF_HTTPS"; then
  WAF_BINDING_OK=1
  ok "WAF pertence aos endpoints isolados selecionados para este teste"
else
  fail "bindings do WAF não correspondem aos endpoints isolados esperados"
fi

DB_NETWORKS="$(docker inspect "$DB_ID" --format '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' 2>/dev/null | sort)"
PHP_NETWORKS="$(docker inspect "$PHP_ID" --format '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' 2>/dev/null | sort)"

echo "--- redes MariaDB ---"
printf '%s\n' "$DB_NETWORKS"
echo "--- redes PHP ---"
printf '%s\n' "$PHP_NETWORKS"

COMMON_NETWORK="$(
  comm -12 \
    <(printf '%s\n' "$DB_NETWORKS" | sed '/^$/d' | sort) \
    <(printf '%s\n' "$PHP_NETWORKS" | sed '/^$/d' | sort)
)"

if [[ -z "$COMMON_NETWORK" ]]; then
  ok "PHP e MariaDB não compartilham rede Docker"
else
  fail "PHP e MariaDB compartilham rede Docker indevidamente: $COMMON_NETWORK"
fi

echo
echo "=== 14. TCP / PDO PELO ENDPOINT DE HOST ==="
if [[ "$DB_READY" -eq 1 && "$DB_BINDING_OK" -eq 1 && "$PHP_READY" -eq 1 ]]; then
  TCP_RESULT="$(
    dmz exec -T php php -r '
$h=getenv("DB_HOST");
$p=(int)getenv("DB_PORT");
$s=@fsockopen($h,$p,$errno,$errstr,5);
if(!$s){fwrite(STDERR,"tcp-fail"); exit(2);}
fclose($s);
echo "tcp-ok";
' 2>/dev/null || true
  )"
  echo "tcp_result=$TCP_RESULT"

  [[ "$TCP_RESULT" == "tcp-ok" ]] \
    && ok "PHP alcança o MariaDB sintético pelo endpoint TCP isolado" \
    || fail "PHP não alcança o MariaDB sintético pelo endpoint inter-VM"

  PDO_RESULT="$(
    dmz exec -T php php -r '
require "/var/www/conectaeduca/vendor/autoload.php";
$pdo=\ConectaEduca\Config\Database::connect();
$r=$pdo->query("SELECT DATABASE() db, @@character_set_connection charset")->fetch(PDO::FETCH_ASSOC);
echo $r["db"],"|",$r["charset"];
' 2>&1 || true
  )"
  echo "pdo_result=$PDO_RESULT"

  [[ "$PDO_RESULT" == "conectaeduca|utf8mb4" ]] \
    && ok "PDO autentica no MariaDB sintético sem rede Docker compartilhada" \
    || fail "PDO falhou no cenário de fronteira entre VMs"
else
  fail "teste TCP/PDO não executado: endpoint MariaDB/PHP sintético não está íntegro"
fi

echo
echo "=== 15. WAF / APLICAÇÃO NO ADAPTADOR DE HOST ==="
if [[ "$WAF_READY" -eq 1 && "$WAF_BINDING_OK" -eq 1 && "$NGINX_READY" -eq 1 && "$PHP_READY" -eq 1 ]]; then
  HTTPS_CODE="$(
    curl -ksS \
      --max-time 12 \
      --resolve "${HOST_NAME}:${LAB_HTTPS_PORT}:127.0.0.1" \
      -o /dev/null \
      -w '%{http_code}' \
      "https://${HOST_NAME}:${LAB_HTTPS_PORT}/login.php" \
      2>/dev/null || true
  )"
  echo "https_login=$HTTPS_CODE"

  [[ "$HTTPS_CODE" == "200" ]] \
    && ok "WAF/TLS/Nginx/PHP funcionam no endpoint exclusivo deste teste" \
    || fail "aplicação HTTPS falhou no adaptador de VM"

  XSS_CODE="$(
    curl -ksS \
      --max-time 12 \
      --resolve "${HOST_NAME}:${LAB_HTTPS_PORT}:127.0.0.1" \
      -G \
      --data-urlencode 'q=<script>alert(1)</script>' \
      -o /dev/null \
      -w '%{http_code}' \
      "https://${HOST_NAME}:${LAB_HTTPS_PORT}/" \
      2>/dev/null || true
  )"
  echo "xss_http=$XSS_CODE"

  [[ "$XSS_CODE" == "403" ]] \
    && ok "política PL2 continua bloqueando no WAF sintético deste teste" \
    || fail "WAF não bloqueou XSS no cenário de handoff"
else
  fail "teste HTTP/WAF não executado: bindings sintéticos não foram confirmados"
fi

echo
echo "=== 16. HEALTH / RECRIAÇÃO / PERSISTÊNCIA ==="
for pair in "php:$PHP_ID" "nginx:$NGINX_ID" "waf:$WAF_ID" "mariadb:$DB_ID"; do
  svc="${pair%%:*}"
  cid="${pair#*:}"
  status="$(docker inspect "$cid" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}sem-healthcheck{{end}}' 2>/dev/null || true)"
  echo "$svc health=$status"
  [[ "$status" == "healthy" ]] \
    && ok "$svc possui healthcheck saudável" \
    || fail "$svc não está healthy"
done

MARKER="portability-${STAMP}"

MARKER_SQL="$TMP_DIR/marker.sql"
cat > "$MARKER_SQL" <<SQL
CREATE TABLE IF NOT EXISTS conectaeduca.__portability_checkpoint (
  valor VARCHAR(100) NOT NULL
);
DELETE FROM conectaeduca.__portability_checkpoint;
INSERT INTO conectaeduca.__portability_checkpoint (valor)
VALUES ('$MARKER');
SQL

if docker exec -i "$DB_ID" sh -ec '
  export MYSQL_PWD="$(cat /run/secrets/mariadb_root_password)"
  exec mariadb -uroot
' < "$MARKER_SQL" >/dev/null 2>&1
then
  ok "marcador de persistência criado com credencial root via secret"
else
  fail "não foi possível criar marcador de persistência"
fi

echo "--- recriando somente o container MariaDB, preservando o volume ---"

if db stop mariadb >/dev/null 2>&1 &&
   db rm -f mariadb >/dev/null 2>&1 &&
   db up -d mariadb >/dev/null 2>&1
then
  ok "container MariaDB recriado com o mesmo volume"
else
  fail "falha ao recriar o container MariaDB"
fi

DB_ID="$(db ps -q mariadb 2>/dev/null || true)"

if [[ -n "$DB_ID" ]] && wait_healthy "mariadb-recriado" "$DB_ID" 180; then
  ok "MariaDB recriado volta healthy"
else
  fail "MariaDB recriado não ficou healthy"
fi

PERSISTED="$(
  docker exec "$DB_ID" sh -ec '
    export MYSQL_PWD="$(cat /run/secrets/mariadb_root_password)"
    exec mariadb -uroot -Nse \
      "SELECT valor FROM conectaeduca.__portability_checkpoint LIMIT 1"
  ' 2>/dev/null || true
)"
echo "marker=$PERSISTED"

[[ "$PERSISTED" == "$MARKER" ]] \
  && ok "volume MariaDB preserva dados após recriação do container" \
  || fail "persistência MariaDB não confirmada após recriação"

echo
echo "=== 17. SUPERFÍCIE FINAL DO TESTE ==="
docker ps \
  --filter "label=com.docker.compose.project=$DMZ_PROJECT" \
  --format 'table {{.Names}}\t{{.Ports}}'
docker ps \
  --filter "label=com.docker.compose.project=$DB_PROJECT" \
  --format 'table {{.Names}}\t{{.Ports}}'

PHP_BINDINGS="$(docker port "$PHP_ID" 2>/dev/null || true)"
NGINX_BINDINGS="$(docker port "$NGINX_ID" 2>/dev/null || true)"

[[ -z "$PHP_BINDINGS" ]] \
  && ok "PHP-FPM sem publicação no host" \
  || fail "PHP-FPM publicou porta"

[[ -z "$NGINX_BINDINGS" ]] \
  && ok "Nginx sem publicação no host" \
  || fail "Nginx publicou porta"

echo
echo "=== 18. ENCERRAMENTO ==="
if dmz down --remove-orphans; then
  ok "DMZ removida"
else
  fail "falha ao remover DMZ"
fi

if db down -v --remove-orphans; then
  ok "MariaDB e volume de teste removidos"
else
  fail "falha ao remover MariaDB"
fi

STARTED=0

echo
echo "=== 19. GIT FINAL ==="
git status -sb
git diff --check \
  && ok "git diff --check final" \
  || fail "git diff --check final"

echo
echo "======================================================================"
echo " RESULTADO"
echo "======================================================================"
echo "Falhas: $FAIL"
echo "Advertências: $WARN"

if [[ "$FAIL" -eq 0 ]]; then
  echo "CHECKPOINT DE PORTABILIDADE v4: APROVADO."
  echo "DMZ e MariaDB funcionam sem rede Docker compartilhada entre os projetos."
  echo "Os endpoints de host/VM são parametrizáveis e os serviços ficam healthy."
  echo "Este resultado reduz riscos de migração para duas VMs, mas não substitui"
  echo "o teste final na rede real com pfSense, DNS e certificados da equipe."
else
  echo "CHECKPOINT DE PORTABILIDADE v4: REPROVADO."
fi

echo "Relatório: $REPORT"
echo "======================================================================"

[[ "$FAIL" -eq 0 ]]
