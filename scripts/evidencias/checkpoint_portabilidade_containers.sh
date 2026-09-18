#!/usr/bin/env bash
set -u
export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEFAULT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
ROOT="${PROJECT_ROOT:-$DEFAULT_ROOT}"
CHECK_MODE="${CHECK_MODE:-local}"
TARGET_PLATFORM="${TARGET_PLATFORM:-linux/amd64}"
PORTABILITY_SCOPE="${PORTABILITY_SCOPE:-auto}"

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
echo " Escopo solicitado: $PORTABILITY_SCOPE"
echo " Plataforma alvo: $TARGET_PLATFORM"
echo " Data: $(date --iso-8601=seconds)"
echo "======================================================================"

cd "$ROOT" || exit 1

echo
echo "=== 1. ORIGEM / FREEZE ==="
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT" status -sb

  BRANCH="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
  echo "branch_atual=$BRANCH"

  [[ "$BRANCH" == "main" ]] \
    && ok "branch main confirmada" \
    || fail "branch deve ser main"

  git -C "$ROOT" diff --check \
    && ok "git diff --check" \
    || fail "git diff --check"
else
  META="$ROOT/RELEASE-METADATA.txt"
  if [[ -f "$META" ]] \
     && grep -Eq '^git_commit=[0-9a-f]{40}
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

if [[ "$PORTABILITY_SCOPE" == "auto" ]]; then
  if [[ -d "$ROOT/deploy/dmz" && -d "$ROOT/deploy/interna/mariadb" ]]; then
    PORTABILITY_SCOPE="full"
  elif [[ -d "$ROOT/deploy/dmz" ]]; then
    PORTABILITY_SCOPE="dmz"
  elif [[ -d "$ROOT/deploy/interna/mariadb" ]]; then
    PORTABILITY_SCOPE="interna"
  else
    fail "não foi possível detectar escopo do handoff"
    PORTABILITY_SCOPE="invalid"
  fi
fi

case "$PORTABILITY_SCOPE" in
  full|dmz|interna) ;;
  *)
    fail "PORTABILITY_SCOPE inválido: $PORTABILITY_SCOPE"
    ;;
esac

echo "portability_scope=$PORTABILITY_SCOPE"

if [[ "$PORTABILITY_SCOPE" != "full" ]]; then
  echo
  echo "=== 3. PREFLIGHT TARGET-SPECIFIC ==="

  if [[ "$PORTABILITY_SCOPE" == "dmz" ]]; then
    TARGET_REQUIRED=(
      deploy/CONTRATO-IMPLANTACAO.md
      deploy/dmz/compose.yml
      deploy/dmz/compose.host.yml
      deploy/dmz/compose.app-secrets.yml
      deploy/dmz/compose.app-tls.yml
      deploy/dmz/compose.waf.yml
      deploy/dmz/compose.waf-tls.yml
      deploy/dmz/compose.waf-policy.yml
      deploy/dmz/nginx/Dockerfile
      deploy/dmz/php/Dockerfile
    )

    for rel in "${TARGET_REQUIRED[@]}"; do
      [[ -f "$ROOT/$rel" ]] && ok "$rel" || fail "ausente: $rel"
    done

    [[ ! -e "$ROOT/deploy/interna" ]] \
      && ok "handoff DMZ não contém árvore interna" \
      || fail "handoff DMZ contém árvore interna"

    grep -q 'CONECTAEDUCA_DB_HOST' "$ROOT/deploy/dmz/compose.host.yml" \
      && ok "endpoint DB da DMZ continua parametrizável" \
      || fail "DMZ sem CONECTAEDUCA_DB_HOST"

    if grep -RInE 'network_mode:[[:space:]]*host|privileged:[[:space:]]*true|/var/run/docker.sock' \
      "$ROOT/deploy/dmz" 2>/dev/null | grep -q .; then
      fail "superfície proibida encontrada no handoff DMZ"
    else
      ok "DMZ sem host-network/privileged/docker.sock"
    fi

  else
    TARGET_REQUIRED=(
      deploy/CONTRATO-IMPLANTACAO.md
      deploy/interna/mariadb/compose.yml
      deploy/interna/mariadb/compose.host.yml
      deploy/interna/wazuh/compose.yml
      deploy/interna/ferret/compose.yml
      deploy/interna/openbao/compose.yml
      deploy/interna/bacula/compose.yml
      deploy/interna/twingate/compose.yml
    )

    for rel in "${TARGET_REQUIRED[@]}"; do
      [[ -f "$ROOT/$rel" ]] && ok "$rel" || fail "ausente: $rel"
    done

    [[ ! -e "$ROOT/deploy/dmz" ]] \
      && ok "handoff interno não contém árvore DMZ" \
      || fail "handoff interno contém árvore DMZ"

    grep -q 'CONECTAEDUCA_DB_BIND_ADDRESS' "$ROOT/deploy/interna/mariadb/compose.host.yml" \
      && ok "binding MariaDB continua parametrizável" \
      || fail "MariaDB sem CONECTAEDUCA_DB_BIND_ADDRESS"

    if grep -RInE 'privileged:[[:space:]]*true|/var/run/docker.sock' \
      "$ROOT/deploy/interna" 2>/dev/null | grep -q .; then
      fail "privileged/docker.sock encontrado no handoff interno"
    else
      ok "interno sem privileged/docker.sock"
    fi

    if grep -RInE 'network_mode:[[:space:]]*host' "$ROOT/deploy/interna" 2>/dev/null \
      | grep -v '/twingate/compose.yml:' | grep -q .; then
      fail "host-network fora da exceção Twingate"
    else
      ok "host-network restrito à exceção Twingate"
    fi
  fi

  echo
  echo "PORTABILITY_TARGET_PREFLIGHT=$([[ "$FAIL" -eq 0 ]] && echo APROVADO || echo REPROVADO)"
  echo "PORTABILITY_DYNAMIC_CROSSZONE=NAO_APLICAVEL_A_HANDOFF_ISOLADO"
  echo "Falhas: $FAIL"
  echo "Advertências: $WARN"
  echo "Relatório: $REPORT"
  [[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
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

grep -q 'CONECTAEDUCA_DB_HOST' deploy/dmz/compose.host.yml \ "$META" \
     && grep -Fxq 'runtime_secrets_included=no' "$META"; then
    ok "handoff sem .git possui metadata de freeze válida"
    echo "git_commit=$(sed -n 's/^git_commit=//p' "$META")"
  else
    fail "fora de Git sem RELEASE-METADATA.txt válido"
  fi
fi

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