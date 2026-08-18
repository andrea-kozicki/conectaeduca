#!/usr/bin/env bash
set -u

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"
DMZ_BASE="$ROOT/deploy/dmz/compose.yml"
DMZ_OVERRIDE="$ROOT/deploy/dmz/compose.database.yml"
INTERNAL_BASE="$ROOT/deploy/interna/mariadb/compose.yml"

DMZ_PROJECT="conectaeduca-dmz-database-test"
INTERNAL_PROJECT="conectaeduca-mariadb-integration-test"

NETWORK="${CONECTAEDUCA_TRANSIT_NETWORK:-conectaeduca-transit-database-test}"
SUBNET="${CONECTAEDUCA_TRANSIT_SUBNET:-172.30.250.0/24}"
DB_IP="${CONECTAEDUCA_DB_HOST:-172.30.250.10}"
PHP_IP="${CONECTAEDUCA_PHP_TRANSIT_IP:-172.30.250.20}"

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/conectaeduca-fase4d-integracao-v2-${STAMP}.txt"
SECRET_DIR="$(mktemp -d /tmp/conectaeduca-fase4d-secrets.XXXXXX)"
FAIL=0

cd "$ROOT" || exit 1

ok(){ echo "OK    $*"; }
fail(){ echo "FALHA $*"; FAIL=$((FAIL+1)); }

ROOT_SECRET="$SECRET_DIR/mariadb_root_password"
APP_SECRET="$SECRET_DIR/conectaeduca_db_password"

openssl rand -hex 32 > "$ROOT_SECRET"
openssl rand -hex 32 > "$APP_SECRET"
chmod 0700 "$SECRET_DIR"
chmod 0444 "$ROOT_SECRET" "$APP_SECRET"

export CONECTAEDUCA_DB_ROOT_PASSWORD_FILE="$ROOT_SECRET"
export CONECTAEDUCA_DB_PASSWORD_FILE="$APP_SECRET"
export CONECTAEDUCA_DB_HOST="$DB_IP"

DMZ=(docker compose -p "$DMZ_PROJECT" -f "$DMZ_BASE" -f "$DMZ_OVERRIDE")
INTERNAL=(docker compose -p "$INTERNAL_PROJECT" -f "$INTERNAL_BASE")

cleanup() {
    set +e
    "${DMZ[@]}" down --remove-orphans >/dev/null 2>&1
    "${INTERNAL[@]}" down -v --remove-orphans >/dev/null 2>&1
    docker network rm "$NETWORK" >/dev/null 2>&1
    rm -rf "$SECRET_DIR"
}
trap cleanup EXIT

wait_healthy_verbose() {
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

if db not in subnet:
    raise SystemExit(f"DB_IP {db} não pertence à rede {subnet}")
if php not in subnet:
    raise SystemExit(f"PHP_IP {php} não pertence à rede {subnet}")
if db == php:
    raise SystemExit("DB_IP e PHP_IP não podem ser iguais")
if db in (subnet.network_address, subnet.broadcast_address):
    raise SystemExit("DB_IP inválido para host")
if php in (subnet.network_address, subnet.broadcast_address):
    raise SystemExit("PHP_IP inválido para host")
PY
}

php_pdo_probe() {
    "${DMZ[@]}" exec -T php php -r '
        $host = getenv("DB_HOST");
        $port = getenv("DB_PORT") ?: "3306";
        $name = getenv("DB_NAME");
        $user = getenv("DB_USER");
        $charset = getenv("DB_CHARSET") ?: "utf8mb4";
        $passFile = getenv("DB_PASS_FILE");

        if (!$host || !$name || !$user || !$passFile) {
            fwrite(STDERR, "variáveis DB incompletas\n");
            exit(20);
        }

        $password = trim((string) @file_get_contents($passFile));
        if ($password === "") {
            fwrite(STDERR, "secret DB vazio ou ilegível\n");
            exit(21);
        }

        $dsn = sprintf(
            "mysql:host=%s;port=%s;dbname=%s;charset=%s",
            $host,
            $port,
            $name,
            $charset
        );

        try {
            $pdo = new PDO($dsn, $user, $password, [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
            ]);

            $row = $pdo->query(
                "SELECT DATABASE() AS db, VERSION() AS version, @@character_set_connection AS charset"
            )->fetch();

            echo $row["db"], "|", $row["version"], "|", $row["charset"], PHP_EOL;
        } catch (Throwable $e) {
            fwrite(STDERR, get_class($e) . ": " . $e->getMessage() . PHP_EOL);
            exit(22);
        }
    '
}

php_ddl_must_fail() {
    "${DMZ[@]}" exec -T php php -r '
        $password = trim((string) file_get_contents(getenv("DB_PASS_FILE")));
        $dsn = sprintf(
            "mysql:host=%s;port=%s;dbname=%s;charset=%s",
            getenv("DB_HOST"),
            getenv("DB_PORT") ?: "3306",
            getenv("DB_NAME"),
            getenv("DB_CHARSET") ?: "utf8mb4"
        );

        try {
            $pdo = new PDO($dsn, getenv("DB_USER"), $password, [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            ]);
            $pdo->exec("CREATE TABLE __fase4d_nao_deve_criar (id INT)");
            fwrite(STDERR, "DDL foi permitido\n");
            exit(30);
        } catch (PDOException $e) {
            echo "DDL negado como esperado\n";
            exit(0);
        }
    '
}

{
echo "======================================================================"
echo " CONECTAEDUCA - FASE 4D v2"
echo " Integração DMZ ↔ MariaDB em projetos Compose separados"
echo " Data: $(date --iso-8601=seconds)"
echo "======================================================================"

echo
echo "=== GIT ==="
git status -sb

echo
echo "=== PARÂMETROS DO LAB ==="
echo "network=$NETWORK"
echo "subnet=$SUBNET"
echo "db_ip=$DB_IP"
echo "php_ip=$PHP_IP"

validate_lab_addresses && ok "endereçamento do laboratório válido" || fail "endereçamento do laboratório inválido"

echo
echo "=== CONFIGURAÇÕES COMPOSE ==="
"${INTERNAL[@]}" config >/dev/null && ok "Compose interno válido" || fail "Compose interno inválido"
"${DMZ[@]}" config >/dev/null && ok "Compose DMZ + override 4D válido" || fail "Compose DMZ + override 4D inválido"

echo
echo "=== REDE DE TRÂNSITO ==="
if docker network inspect "$NETWORK" >/dev/null 2>&1; then
    fail "rede $NETWORK já existe; estado residual detectado"
else
    docker network create --driver bridge --subnet "$SUBNET" "$NETWORK" >/dev/null \
        && ok "rede de trânsito criada" \
        || fail "não foi possível criar a rede de trânsito"
fi

echo
echo "=== REDE INTERNA / MARIADB ==="
"${INTERNAL[@]}" up -d && ok "MariaDB iniciou" || fail "falha no compose interno"

DB_ID="$("${INTERNAL[@]}" ps -q mariadb 2>/dev/null || true)"
echo "db_container_id=$DB_ID"

if [[ -n "$DB_ID" ]] && wait_healthy_verbose "mariadb" "$DB_ID" 120; then
    ok "MariaDB healthy"
else
    fail "MariaDB não ficou healthy"
    echo
    echo "=== HEALTH LOG MARIADB ==="
    docker inspect "$DB_ID" \
      --format '{{range .State.Health.Log}}{{println "exit=" .ExitCode " start=" .Start " end=" .End}}{{println .Output}}{{end}}' \
      2>/dev/null || true
    echo
    echo "=== LOGS MARIADB ==="
    "${INTERNAL[@]}" logs --no-color --tail=120 mariadb || true
fi

if [[ -n "$DB_ID" ]] && docker network connect --ip "$DB_IP" "$NETWORK" "$DB_ID"; then
    ok "MariaDB conectado à rede de trânsito em $DB_IP"
else
    fail "não foi possível conectar MariaDB à rede de trânsito"
fi

echo
echo "=== DMZ / NGINX + PHP ==="
"${DMZ[@]}" up -d && ok "DMZ iniciou" || fail "falha no compose DMZ"

PHP_ID="$("${DMZ[@]}" ps -q php 2>/dev/null || true)"
NGINX_ID="$("${DMZ[@]}" ps -q nginx 2>/dev/null || true)"

if [[ -n "$PHP_ID" ]] && wait_healthy_verbose "php-fpm" "$PHP_ID" 60; then
    ok "PHP-FPM healthy"
else
    fail "PHP-FPM não ficou healthy"
fi

if [[ -n "$PHP_ID" ]] && docker network connect --ip "$PHP_IP" "$NETWORK" "$PHP_ID"; then
    ok "PHP conectado à rede de trânsito em $PHP_IP"
else
    fail "não foi possível conectar PHP à rede de trânsito"
fi

echo
echo "=== MEMBROS DA REDE DE TRÂNSITO ==="
MEMBERS="$(docker network inspect "$NETWORK" --format '{{range .Containers}}{{.Name}}|{{.IPv4Address}}{{println}}{{end}}' 2>/dev/null | sort || true)"
printf '%s\n' "$MEMBERS"

MEMBER_COUNT="$(printf '%s\n' "$MEMBERS" | sed '/^$/d' | wc -l)"
[[ "$MEMBER_COUNT" == "2" ]] && ok "somente PHP e MariaDB participam da rede de trânsito" || fail "quantidade inesperada de membros na rede"

if printf '%s\n' "$MEMBERS" | grep -Fq 'nginx'; then
    fail "Nginx foi conectado indevidamente à rede do banco"
else
    ok "Nginx não participa da rede do banco"
fi

echo
echo "=== EXPOSIÇÃO DO MARIADB NO HOST ==="
DB_BINDINGS="$(docker inspect "$DB_ID" --format '{{json .HostConfig.PortBindings}}' 2>/dev/null || true)"
echo "db_port_bindings=$DB_BINDINGS"
[[ "$DB_BINDINGS" == "{}" || "$DB_BINDINGS" == "null" ]] \
    && ok "3306 continua sem publicação no host" \
    || fail "MariaDB possui porta publicada no host"

echo
echo "=== SECRET NO PHP ==="
"${DMZ[@]}" exec -T php test -r /run/secrets/conectaeduca_db_password \
    && ok "secret do banco legível pelo PHP" \
    || fail "secret do banco não é legível pelo PHP"

echo
echo "=== CONECTIVIDADE TCP PHP → MARIADB ==="
TCP_RESULT="$("${DMZ[@]}" exec -T php php -r '
    $h = getenv("DB_HOST");
    $p = (int) (getenv("DB_PORT") ?: 3306);
    $errno = 0;
    $errstr = "";
    $s = @fsockopen($h, $p, $errno, $errstr, 3);
    if (!$s) {
        fwrite(STDERR, "$errno|$errstr\n");
        exit(1);
    }
    fclose($s);
    echo "tcp-ok\n";
' 2>/dev/null || true)"
echo "tcp_result=$TCP_RESULT"
[[ "$TCP_RESULT" == "tcp-ok" ]] \
    && ok "PHP alcança $DB_IP:3306 pela rede de trânsito" \
    || fail "PHP não alcançou o MariaDB por TCP"

echo
echo "=== CONEXÃO PDO PHP → MARIADB ==="
PDO_RESULT="$(php_pdo_probe 2>&1 || true)"
echo "pdo_result=$PDO_RESULT"
[[ "$PDO_RESULT" == conectaeduca\|12.3.2-MariaDB*\|utf8mb4 ]] \
    && ok "PDO autenticou no MariaDB remoto simulado" \
    || fail "PDO não validou a conexão esperada"

echo
echo "=== MENOR PRIVILÉGIO ATRAVÉS DA DMZ ==="
DDL_RESULT="$(php_ddl_must_fail 2>&1 || true)"
echo "ddl_result=$DDL_RESULT"
[[ "$DDL_RESULT" == "DDL negado como esperado" ]] \
    && ok "DDL continua negado ao usuário da aplicação" \
    || fail "teste de DDL não produziu a negação esperada"

echo
echo "=== ISOLAMENTO NGINX → BANCO ==="
if [[ -n "$NGINX_ID" ]]; then
    if docker exec "$NGINX_ID" sh -c "nc -z -w 2 '$DB_IP' 3306" >/dev/null 2>&1; then
        fail "Nginx conseguiu alcançar diretamente o MariaDB"
    else
        ok "Nginx não alcança diretamente o MariaDB"
    fi
else
    fail "container Nginx não encontrado"
fi

echo
echo "=== HTTP DA DMZ ==="
HTTP_CODE="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' http://127.0.0.1:8088/_container_health 2>/dev/null || true)"
echo "health_http=$HTTP_CODE"
[[ "$HTTP_CODE" == "200" ]] && ok "Nginx continua saudável" || fail "health HTTP da DMZ falhou"

echo
echo "=== RESULTADO ==="
echo "Falhas: $FAIL"
[[ "$FAIL" -eq 0 ]] && echo "FASE 4D v2: APROVADA." || echo "FASE 4D v2: REPROVADA."
echo "Containers, volumes, rede e secrets temporários serão removidos automaticamente."
echo "Relatório: $REPORT"
echo "======================================================================"
} | tee "$REPORT"

[[ "$FAIL" -eq 0 ]]
