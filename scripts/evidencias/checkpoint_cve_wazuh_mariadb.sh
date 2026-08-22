#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/srv/www/htdocs/conectaeduca"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HOME/Downloads/conectaeduca-checkpoint-cve-wazuh-mariadb-$STAMP.txt"

cd "$ROOT"
exec > >(tee "$OUT") 2>&1

fail() {
    echo "FALHA: $*" >&2
    echo "CHECKPOINT_CVE_WAZUH_MARIADB=REPROVADO" >&2
    echo "ARQUIVO_SAIDA=$OUT" >&2
    exit 1
}

echo "data=$(date --iso-8601=seconds)"
echo "branch=$(git branch --show-current)"
echo "head=$(git rev-parse HEAD)"

[[ "$(git branch --show-current)" == "feature/auth-local" ]] \
    || fail "branch inesperada"

[[ -s deploy/interna/wazuh/CVE-TRIAGEM.md ]] \
    || fail "triagem Wazuh ausente"

[[ -s deploy/interna/mariadb/CVE-TRIAGEM.md ]] \
    || fail "triagem MariaDB ausente"

docker info >/dev/null 2>&1 || fail "Docker indisponível"

manager="$(
    docker ps \
        --filter label=com.docker.compose.project=conectaeduca-wazuh \
        --filter label=com.docker.compose.service=wazuh.manager \
        --format '{{.ID}}' \
        | head -n1
)"
indexer="$(
    docker ps \
        --filter label=com.docker.compose.project=conectaeduca-wazuh \
        --filter label=com.docker.compose.service=wazuh.indexer \
        --format '{{.ID}}' \
        | head -n1
)"
dashboard="$(
    docker ps \
        --filter label=com.docker.compose.project=conectaeduca-wazuh \
        --filter label=com.docker.compose.service=wazuh.dashboard \
        --format '{{.ID}}' \
        | head -n1
)"

[[ -n "$manager" && -n "$indexer" && -n "$dashboard" ]] \
    || fail "Wazuh não está integralmente running"

for pair in \
    "manager:$manager" \
    "indexer:$indexer" \
    "dashboard:$dashboard"
do
    label="${pair%%:*}"
    id="${pair#*:}"
    state="$(docker inspect -f '{{.State.Status}}' "$id")"
    image="$(docker inspect -f '{{.Config.Image}}' "$id")"
    echo "WAZUH=$label|state=$state|image=$image"
    [[ "$state" == "running" ]] || fail "$label não está running"
    [[ "$image" == *"4.14.7"* ]] || fail "$label não está em Wazuh 4.14.7"
done

if docker port "$indexer" 9200/tcp 2>/dev/null | grep -q .; then
    fail "Indexer 9200 publicado no host"
fi

if docker port "$manager" 55000/tcp 2>/dev/null | grep -q .; then
    fail "Manager API 55000 publicada no host"
fi

for spec in \
    "$manager:1514" \
    "$manager:1515" \
    "$dashboard:5601"
do
    id="${spec%%:*}"
    port="${spec#*:}"
    mapping="$(docker port "$id" "$port/tcp" 2>/dev/null | head -n1 || true)"
    echo "BINDING=$port|$mapping"
    [[ "$mapping" == 127.0.0.1:* || "$mapping" == "[::1]:"* ]] \
        || fail "porta $port não está limitada a loopback"
done

mariadb="$(
    docker ps \
        --filter name=conectaeduca-mariadb-local-mariadb-1 \
        --format '{{.ID}}' \
        | head -n1
)"

[[ -n "$mariadb" ]] || fail "MariaDB não encontrado"

db_state="$(docker inspect -f '{{.State.Status}}' "$mariadb")"
db_health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}sem-healthcheck{{end}}' "$mariadb")"
db_image="$(docker inspect -f '{{.Config.Image}}' "$mariadb")"
db_privileged="$(docker inspect -f '{{.HostConfig.Privileged}}' "$mariadb")"

echo "MARIADB=state=$db_state|health=$db_health|privileged=$db_privileged|image=$db_image"

[[ "$db_state" == "running" ]] || fail "MariaDB não está running"
[[ "$db_health" == "healthy" ]] || fail "MariaDB não está healthy"
[[ "$db_privileged" == "false" ]] || fail "MariaDB privilegiado"
[[ "$db_image" == *"12.3.2-ubi10"* ]] || fail "MariaDB fora do baseline 12.3.2-ubi10"

if docker port "$mariadb" 3306/tcp 2>/dev/null \
    | grep -Eq '^(0\.0\.0\.0:|\[::\]:)'
then
    fail "MariaDB 3306 publicado em wildcard"
fi

health_cnf="/var/lib/mysql/.my-healthcheck.cnf"

if docker exec "$mariadb" test -r "$health_cnf" 2>/dev/null; then
    vars="$(
        docker exec "$mariadb" \
            mariadb \
            --defaults-extra-file="$health_cnf" \
            -NBe 'SELECT @@local_infile; SELECT @@have_ssl;' \
            2>/dev/null
    )"

    mapfile -t values <<< "$vars"
    echo "MARIADB_SQL=local_infile=${values[0]:-?}|have_ssl=${values[1]:-?}"

    [[ "${values[0]:-}" == "0" ]] || fail "local_infile não está 0"
    [[ "${values[1]:-}" == "YES" ]] || fail "have_ssl não confirmou YES"
else
    fail "healthcheck cnf não disponível"
fi

certgen_running="$(
    docker ps \
        --filter ancestor=wazuh/wazuh-certs-generator:0.0.4 \
        --format '{{.ID}}' \
        | wc -l
)"

echo "CERT_GENERATOR_RUNNING=$certgen_running"
[[ "$certgen_running" -eq 0 ]] || fail "cert generator está rodando permanentemente"

git diff --check || fail "git diff --check reprovou"

echo "CHECKPOINT_CVE_WAZUH_MARIADB=APROVADO"
echo "WAZUH_CONTROLES_COMPENSATORIOS=APROVADOS"
echo "MARIADB_HARDENING=APROVADO"
echo "CERT_GENERATOR_RUNTIME=AUSENTE"
echo "ARQUIVO_SAIDA=$OUT"
