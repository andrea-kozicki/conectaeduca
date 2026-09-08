#!/usr/bin/env bash
set -u
set -o pipefail

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"
COMPOSE_FILE="$ROOT/deploy/interna/mariadb/compose.yml"
PROJECT="conectaeduca-mariadb-test"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/conectaeduca-fase4c-mariadb-v3-${STAMP}.txt"
SECRET_DIR="$(mktemp -d /tmp/conectaeduca-fase4c-secrets.XXXXXX)"
FAIL=0

cd "$ROOT" || exit 1

ok(){ echo "OK    $*"; }
fail(){ echo "FALHA $*"; FAIL=$((FAIL+1)); }

ROOT_SECRET="$SECRET_DIR/mariadb_root_password"
APP_SECRET="$SECRET_DIR/conectaeduca_db_password"

# Secrets descartáveis usados apenas por este banco temporário.
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
echo " CONECTAEDUCA - FASE 4C v3"
echo " MariaDB conteinerizado / fresh volume / origem restrita"
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
  echo "FASE 4C v3: REPROVADA NA INICIALIZAÇÃO."
  echo "Relatório: $REPORT"
  echo "======================================================================"
  exit 1
fi

"${COMPOSE[@]}" ps

echo
echo "=== VERSÃO / CONFIG ==="
VERSION="$(root_query 'SELECT VERSION();' 2>/dev/null || true)"
LOCAL_INFILE="$(root_query 'SELECT @@local_infile;' 2>/dev/null || true)"
echo "version=$VERSION"
echo "local_infile=$LOCAL_INFILE"

[[ "$VERSION" == 12.3.2-MariaDB* ]] && ok "MariaDB 12.3.2" || fail "versão inesperada"
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

echo
echo "=== USUÁRIO DA APLICAÇÃO / ORIGEM RESTRITA ==="
APP_RESTRICTED_COUNT="$(root_query "SELECT COUNT(*) FROM mysql.global_priv WHERE User='conectaeduca_app' AND Host='192.168.6.34';" 2>/dev/null || true)"
APP_WILDCARD_COUNT="$(root_query "SELECT COUNT(*) FROM mysql.global_priv WHERE User='conectaeduca_app' AND Host='%';" 2>/dev/null || true)"
echo "conta_restrita_192.168.6.34=$APP_RESTRICTED_COUNT"
echo "conta_wildcard=$APP_WILDCARD_COUNT"

[[ "$APP_RESTRICTED_COUNT" == "1" ]] \
  && ok "conta conectaeduca_app restrita à EP125 (192.168.6.34)" \
  || fail "conta restrita à EP125 não encontrada"

[[ "$APP_WILDCARD_COUNT" == "0" ]] \
  && ok "conta wildcard conectaeduca_app@'%' ausente" \
  || fail "conta wildcard ainda existe"

PRIVS="$(root_query "SELECT PRIVILEGE_TYPE FROM information_schema.SCHEMA_PRIVILEGES WHERE GRANTEE=\"'conectaeduca_app'@'192.168.6.34'\" AND TABLE_SCHEMA='conectaeduca' ORDER BY PRIVILEGE_TYPE;" 2>/dev/null || true)"
printf 'privilégios:\n%s\n' "$PRIVS"
EXPECTED_PRIVS=$'DELETE\nINSERT\nSELECT\nUPDATE'
[[ "$PRIVS" == "$EXPECTED_PRIVS" ]] && ok "menor privilégio aplicado" || fail "privilégios divergiram"

GLOBAL_PRIVS="$(root_query "SELECT COUNT(*) FROM information_schema.USER_PRIVILEGES WHERE GRANTEE=\"'conectaeduca_app'@'192.168.6.34'\" AND PRIVILEGE_TYPE <> 'USAGE';" 2>/dev/null || true)"
echo "privilégios_globais_além_usage=$GLOBAL_PRIVS"
[[ "$GLOBAL_PRIVS" == "0" ]] \
  && ok "sem privilégios globais adicionais" \
  || fail "privilégios globais inesperados"

# O teste descartável roda dentro do próprio container; portanto ele NÃO deve
# autenticar a identidade que só é válida quando a origem real é a EP125.
if "${COMPOSE[@]}" exec -T mariadb sh -ec \
  'MYSQL_PWD="$(cat /run/secrets/conectaeduca_db_password)" mariadb --batch --skip-column-names -h127.0.0.1 -uconectaeduca_app conectaeduca -e "SELECT 1;"' \
  >/dev/null 2>&1
then
  fail "autenticação local 127.0.0.1 deveria ser negada após restrição de origem"
else
  ok "autenticação local 127.0.0.1 negada como esperado"
fi

echo "INFO: autenticação positiva é validada na topologia real EP125 -> EP126."
echo "INFO: este fresh-volume test valida a conta restrita, os grants e a negação fora da origem permitida."

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
  echo "FASE 4C v3: APROVADA."
else
  echo "FASE 4C v3: REPROVADA."
fi
echo "Banco, volume e secrets temporários serão removidos automaticamente."
echo "Relatório: $REPORT"
echo "======================================================================"
} | tee "$REPORT"

[[ "$FAIL" -eq 0 ]]
