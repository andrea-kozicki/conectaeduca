#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE="$ROOT/deploy/dmz/compose.yml"
BASE_URL="${BASE_URL:-http://127.0.0.1:8088}"
FAIL=0

ok() { printf 'OK    %s\n' "$*"; }
fail() { printf 'FALHA %s\n' "$*"; FAIL=$((FAIL+1)); }

code() {
    curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "$1" || true
}

expect_code() {
    local label="$1"
    local url="$2"
    local expected="$3"
    local got
    got="$(code "$url")"
    if [[ "$got" == "$expected" ]]; then
        ok "$label ($got)"
    else
        fail "$label esperado=$expected obtido=$got"
    fi
}

cleanup() {
    docker compose -f "$COMPOSE" down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

cd "$ROOT"

echo "=== docker compose config ==="
docker compose -f "$COMPOSE" config >/dev/null
ok "compose válido"

echo "=== build ==="
docker compose -f "$COMPOSE" build --pull

echo "=== up ==="
docker compose -f "$COMPOSE" up -d

echo "=== ps ==="
docker compose -f "$COMPOSE" ps

echo "=== health ==="
for _ in $(seq 1 30); do
    if [[ "$(code "$BASE_URL/_container_health")" == "200" ]] \
       && [[ "$(curl -sS --max-time 5 "$BASE_URL/_fpm_ping" 2>/dev/null || true)" == "pong" ]]; then
        break
    fi
    sleep 1
done

expect_code "Nginx health" "$BASE_URL/_container_health" "200"

PING="$(curl -sS --max-time 10 "$BASE_URL/_fpm_ping" || true)"
if [[ "$PING" == "pong" ]]; then
    ok "PHP-FPM ping"
else
    fail "PHP-FPM ping esperado=pong obtido=${PING:-<vazio>}"
fi

expect_code "CSS público" "$BASE_URL/assets/css/style.css" "200"
expect_code "arquivo privado bootstrap" "$BASE_URL/bootstrap/app.php" "404"
expect_code "arquivo privado composer" "$BASE_URL/composer.json" "404"
expect_code "arquivo privado SQL" "$BASE_URL/sql/conectaeduca.sql" "404"
expect_code "chave privada" "$BASE_URL/storage/keys/private.pem" "404"

echo
echo "Falhas: $FAIL"

if [[ "$FAIL" -ne 0 ]]; then
    exit 1
fi

echo "FASE 4B: smoke test DMZ aprovado."
