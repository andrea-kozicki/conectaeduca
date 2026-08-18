#!/usr/bin/env bash
set -u

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"
COMPOSE_FILE="$ROOT/deploy/interna/mariadb/compose.yml"
PROJECT="conectaeduca-mariadb-test"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/conectaeduca-fase4c-mariadb-v2-${STAMP}.txt"
SECRET_DIR="$(mktemp -d /tmp/conectaeduca-fase4c-secrets.XXXXXX)"
FAIL=0

cd "$ROOT" || exit 1

ok(){ echo "OK    $*"; }
fail(){ echo "FALHA $*"; FAIL=$((FAIL+1)); }

ROOT_SECRET="$SECRET_DIR/mariadb_root_password"
APP_SECRET="$SECRET_DIR/conectaeduca_db_password"

# O MariaDB UBI executa como usuário mysql (UID 999). Em Docker Compose,
# secrets originados de "file:" são bind mounts e preservam as permissões
# do arquivo de origem. Por isso os arquivos precisam ser legíveis dentro
# do container. O diretório pai permanece 0700, protegendo os arquivos no host.
openssl rand -hex 32 > "$ROOT_SECRET"
openssl rand -hex 32 > "$APP_SECRET"
chmod 0700 "$SECRET_DIR"
chmod 0444 "$ROOT_SECRET" "$APP_SECRET"

export CONECTAEDUCA_DB_ROOT_PASSWORD_FILE="$ROOT_SECRET"
export CONECTAEDUCA_DB_PASSWORD_FILE="$APP_SECRET"

COMPOSE=(docker compose -p "$PROJECT" -f "$COMPOSE_FILE")

cleanup() {
  set +e
  "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1
  rm -rf "$SECRET_DIR"
}
trap cleanup EXIT

root_query() {
  local sql="$1"
  "${COMPOSE[@]}" exec -T mariadb sh -ec \
    'mariadb --batch --skip-column-names --protocol=socket -uroot --password="$(cat /run/secrets/mariadb_root_password)" -e "$1"' \
    sh "$sql"
}

app_query() {
  local sql="$1"
  "${COMPOSE[@]}" exec -T mariadb sh -ec \
    'mariadb --batch --skip-column-names -h127.0.0.1 -uconectaeduca_app --password="$(cat /run/secrets/conectaeduca_db_password)" conectaeduca -e "$1"' \
    sh "$sql"
}

wait_healthy() {
  local id status state
  id="$("${COMPOSE[@]}" ps -q mariadb 2>/dev/null)"
  [[ -n "$id" ]] || return 1

  for _ in $(seq 1 90); do
    status="$(docker inspect "$id" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null || true)"
    state="$(docker inspect "$id" --format '{{.State.Status}}' 2>/dev/null || true)"

    [[ "$status" == "healthy" ]] && return 0
    [[ "$state" == "exited" || "$state" == "dead" ]] && return 1
    sleep 1
  done
  return 1
}

{
echo "======================================================================"
echo " CONECTAEDUCA - FASE 4C v2"
echo " MariaDB conteinerizado / rede interna"
echo " Data: $(date --iso-8601=seconds)"
echo "======================================================================"

echo
echo "=== GIT ==="
git status -sb

echo
echo "=== ARQUIVOS ==="
for f in \
  deploy/interna/mariadb/compose.yml \
  deploy/interna/mariadb/conectaeduca.cnf \
  deploy/interna/mariadb/20-minimos-privilegios.sql \
  sql/conectaeduca.sql
do
  [[ -f "$f" ]] && ok "$f" || fail "ausente: $f"
done

echo
echo "=== SEGREDOS TEMPORÁRIOS ==="
echo "diretório=$SECRET_DIR"
DIR_MODE="$(stat -c '%a' "$SECRET_DIR")"
ROOT_MODE="$(stat -c '%a' "$ROOT_SECRET")"
APP_MODE="$(stat -c '%a' "$APP_SECRET")"
echo "diretório_mode=$DIR_MODE"
echo "root_secret_mode=$ROOT_MODE"
echo "app_secret_mode=$APP_MODE"

[[ "$DIR_MODE" == "700" ]] && ok "diretório privado 0700" || fail "diretório de secrets não está 0700"
[[ "$ROOT_MODE" == "444" ]] && ok "secret root legível pelo container" || fail "secret root não está 0444"
[[ "$APP_MODE" == "444" ]] && ok "secret app legível pelo container" || fail "secret app não está 0444"

echo
echo "=== COMPOSE ==="
if "${COMPOSE[@]}" config >/dev/null; then
  ok "compose válido"
else
  fail "compose inválido"
fi

SERVICES="$("${COMPOSE[@]}" config --services 2>/dev/null | tr '\n' ' ')"
echo "serviços=$SERVICES"
[[ "$SERVICES" == "mariadb " ]] && ok "somente MariaDB" || fail "serviços inesperados"

echo
echo "=== IMAGEM ==="
IMAGE_USER="$(docker image inspect mariadb:12.3.2-ubi10 --format '{{.Config.User}}' 2>/dev/null || true)"
echo "image_user=$IMAGE_USER"
[[ "$IMAGE_USER" == "mysql" || "$IMAGE_USER" == "999" ]] \
  && ok "imagem MariaDB roda como usuário não-root" \
  || fail "usuário da imagem inesperado"

echo
echo "=== SUBIDA / INICIALIZAÇÃO ==="
if "${COMPOSE[@]}" up -d; then
  ok "compose up"
else
  fail "compose up falhou"
fi

if wait_healthy; then
  ok "MariaDB healthy"
else
  fail "MariaDB não ficou healthy"
  echo
  echo "=== LOGS DA FALHA RAIZ ==="
  "${COMPOSE[@]}" logs --no-color mariadb || true
  echo
  echo "FASE 4C v2: REPROVADA NA INICIALIZAÇÃO."
  echo "As verificações dependentes foram interrompidas para evitar falhas em cascata."
  echo "Relatório: $REPORT"
  echo "======================================================================"
  exit 1
fi

"${COMPOSE[@]}" ps

echo
echo "=== SECRETS DENTRO DO CONTAINER ==="
for secret in mariadb_root_password conectaeduca_db_password; do
  LINE="$("${COMPOSE[@]}" exec -T mariadb stat -c '%a|%u:%g|%n' "/run/secrets/$secret" 2>/dev/null || true)"
  echo "$LINE"
  if "${COMPOSE[@]}" exec -T mariadb test -r "/run/secrets/$secret"; then
    ok "$secret é legível pelo usuário do MariaDB"
  else
    fail "$secret não é legível dentro do container"
  fi
done

echo
echo "=== VERSÃO / CONFIG ==="
VERSION="$(root_query 'SELECT VERSION();' 2>/dev/null || true)"
echo "version=$VERSION"
[[ "$VERSION" == 12.3.2-MariaDB* ]] && ok "MariaDB 12.3.2" || fail "versão inesperada"

DB_DEFAULTS="$(root_query "SELECT CONCAT(DEFAULT_CHARACTER_SET_NAME,'|',DEFAULT_COLLATION_NAME) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='conectaeduca';" 2>/dev/null || true)"
echo "database_defaults=$DB_DEFAULTS"
[[ "$DB_DEFAULTS" == "utf8mb4|utf8mb4_unicode_ci" ]] && ok "charset/collation" || fail "charset/collation inesperado"

LOCAL_INFILE="$(root_query 'SELECT @@local_infile;' 2>/dev/null || true)"
echo "local_infile=$LOCAL_INFILE"
[[ "$LOCAL_INFILE" == "0" ]] && ok "LOCAL INFILE desabilitado" || fail "LOCAL INFILE ativo"

echo
echo "=== BASELINE IMPORTADO ==="
TABLE_COUNT="$(root_query "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='conectaeduca' AND TABLE_TYPE='BASE TABLE';" 2>/dev/null || true)"
COLUMN_COUNT="$(root_query "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='conectaeduca';" 2>/dev/null || true)"
FK_COUNT="$(root_query "SELECT COUNT(*) FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA='conectaeduca' AND REFERENCED_TABLE_NAME IS NOT NULL;" 2>/dev/null || true)"
CHECK_COUNT="$(root_query "SELECT COUNT(*) FROM information_schema.CHECK_CONSTRAINTS WHERE CONSTRAINT_SCHEMA='conectaeduca';" 2>/dev/null || true)"
UNIQUE_COUNT="$(root_query "SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA='conectaeduca' AND CONSTRAINT_TYPE='UNIQUE';" 2>/dev/null || true)"

echo "tabelas=$TABLE_COUNT"
echo "colunas=$COLUMN_COUNT"
echo "foreign_keys=$FK_COUNT"
echo "checks=$CHECK_COUNT"
echo "unique_constraints=$UNIQUE_COUNT"

[[ "$TABLE_COUNT" == "13" ]] && ok "13 tabelas" || fail "tabelas inesperadas"
[[ "$COLUMN_COUNT" == "126" ]] && ok "126 colunas" || fail "colunas inesperadas"
[[ "$FK_COUNT" == "11" ]] && ok "11 foreign keys" || fail "FKs inesperadas"
[[ "$CHECK_COUNT" == "25" ]] && ok "25 CHECKs" || fail "CHECKs inesperados"
[[ "$UNIQUE_COUNT" == "12" ]] && ok "12 UNIQUEs" || fail "UNIQUEs inesperadas"

ROWS_EST="$(root_query "SELECT COALESCE(SUM(TABLE_ROWS),0) FROM information_schema.TABLES WHERE TABLE_SCHEMA='conectaeduca' AND TABLE_TYPE='BASE TABLE';" 2>/dev/null || true)"
echo "linhas_estimadas=$ROWS_EST"
[[ "$ROWS_EST" == "0" ]] && ok "baseline sem dados" || fail "banco inicial contém dados"

echo
echo "=== USUÁRIO DA APLICAÇÃO ==="
if app_query 'SELECT 1;' >/dev/null 2>&1; then
  ok "conectaeduca_app autentica"
else
  fail "falha de autenticação da aplicação"
fi

PRIVS="$(root_query "SELECT PRIVILEGE_TYPE FROM information_schema.SCHEMA_PRIVILEGES WHERE GRANTEE=\"'conectaeduca_app'@'%'\" AND TABLE_SCHEMA='conectaeduca' ORDER BY PRIVILEGE_TYPE;" 2>/dev/null || true)"
printf 'privilégios:\n%s\n' "$PRIVS"
EXPECTED_PRIVS=$'DELETE\nINSERT\nSELECT\nUPDATE'
[[ "$PRIVS" == "$EXPECTED_PRIVS" ]] && ok "menor privilégio aplicado" || fail "privilégios divergiram"

if app_query 'CREATE TABLE __fase4c_nao_deve_criar (id INT);' >/dev/null 2>&1; then
  fail "usuário app conseguiu DDL"
  root_query 'DROP TABLE IF EXISTS conectaeduca.__fase4c_nao_deve_criar;' >/dev/null 2>&1 || true
else
  ok "DDL negado ao usuário app"
fi

echo
echo "=== EXPOSIÇÃO DE REDE ==="
ID="$("${COMPOSE[@]}" ps -q mariadb)"
PORT_BINDINGS="$(docker inspect "$ID" --format '{{json .HostConfig.PortBindings}}' 2>/dev/null || true)"
echo "port_bindings=$PORT_BINDINGS"
[[ "$PORT_BINDINGS" == "{}" || "$PORT_BINDINGS" == "null" ]] \
  && ok "3306 não publicada" \
  || fail "porta publicada inesperadamente"

echo
echo "=== PERSISTÊNCIA ==="
root_query "CREATE TABLE conectaeduca.__fase4c_persistencia (id INT PRIMARY KEY, valor VARCHAR(32) NOT NULL); INSERT INTO conectaeduca.__fase4c_persistencia VALUES (1,'persistiu');"

if "${COMPOSE[@]}" restart mariadb >/dev/null && wait_healthy; then
  ok "restart saudável"
else
  fail "restart falhou"
fi

MARKER="$(root_query "SELECT valor FROM conectaeduca.__fase4c_persistencia WHERE id=1;" 2>/dev/null || true)"
echo "marker=$MARKER"
[[ "$MARKER" == "persistiu" ]] && ok "volume persistente" || fail "persistência não confirmada"

echo
echo "=== RESULTADO ==="
echo "Falhas: $FAIL"
if [[ "$FAIL" -eq 0 ]]; then
  echo "FASE 4C v2: APROVADA."
else
  echo "FASE 4C v2: REPROVADA."
fi
echo "Banco, volume e secrets temporários serão removidos automaticamente."
echo "Relatório: $REPORT"
echo "======================================================================"
} | tee "$REPORT"

[[ "$FAIL" -eq 0 ]]
