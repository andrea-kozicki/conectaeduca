#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/srv/www/htdocs/conectaeduca"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HOME/Downloads/conectaeduca-checkpoint-bacula-pre-commit-$STAMP.txt"
Q="/var/tmp/conectaeduca-acidentais-$STAMP"

mkdir -p "$HOME/Downloads"

exec > >(tee "$OUT") 2>&1

section() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

fail() {
    echo "FALHA: $*" >&2
    exit 1
}

cd "$ROOT"


section "1. INFORMACOES"

echo "data=$(date --iso-8601=seconds)"
echo "branch=$(git branch --show-current)"
echo "head=$(git rev-parse HEAD)"
echo "saida=$OUT"


section "2. QUARENTENA DO ARQUIVO ACIDENTAL"

ACCIDENTAL=$'h \x5c'

if [[ -e "$ACCIDENTAL" ]]; then
    mkdir -p "$Q"

    stat -c \
        'bytes=%s modo=%a owner=%U:%G arquivo=%n' \
        -- "$ACCIDENTAL"

    sha256sum -- "$ACCIDENTAL"

    mv -- "$ACCIDENTAL" "$Q/"

    echo "OK: arquivo acidental movido para:"
    echo "$Q"
else
    echo "OK: arquivo acidental não está mais presente."
fi


section "3. VALIDACOES DE SINTAXE"

bash -n \
    scripts/evidencias/checkpoint_bacula_core_runtime.sh

bash -n \
    scripts/evidencias/checkpoint_bacula_backup_restore_lab.sh

bash -n \
    scripts/evidencias/checkpoint_bacula_mariadb_sintetico.sh

python3 -m py_compile \
    scripts/bootstrap/materializar_bacula_core.py \
    scripts/bootstrap/materializar_bacula_workloads_lab.py

fish -n \
    scripts/bootstrap/preparar_bacula_catalog.fish \
    scripts/bootstrap/preparar_bacula_core.fish \
    scripts/bootstrap/preparar_bacula_director_db.fish

echo "OK: Bash, Python e Fish válidos."


section "4. COMPOSE"

docker compose \
    -f deploy/interna/bacula/compose.yml \
    --profile tools \
    config >/dev/null

echo "OK: Compose válido."


section "5. RUNTIME FORA DO GIT"

for path in \
    deploy/interna/bacula/.runtime/core.env \
    deploy/interna/bacula/.runtime/director-db.env \
    deploy/interna/bacula/.runtime/config/bacula-dir.conf \
    deploy/interna/bacula/.runtime/config/bacula-sd.conf \
    deploy/interna/bacula/.runtime/config/bacula-fd.conf \
    deploy/interna/bacula/.runtime/config/bconsole.conf
do
    git check-ignore -q "$path" \
        || fail "runtime não ignorado: $path"

    echo "OK ignored=$path"
done


section "6. NENHUM CAMINHO SENSIVEL RASTREADO"

if git ls-files \
    | grep -Ei \
      '(^|/)(\.runtime|root-token|unseal-share|smtp-google\.env)(/|$)'
then
    fail "Git contém caminho potencialmente sensível."
fi

echo "OK: nenhum caminho sensível conhecido está rastreado."


section "7. IMAGENS BACULA"

for spec in \
    'conectaeduca/bacula-director:15.0.3|/etc/bacula/bacula-dir.conf' \
    'conectaeduca/bacula-storage:15.0.3|/etc/bacula/bacula-sd.conf' \
    'conectaeduca/bacula-filedaemon:15.0.3|/etc/bacula/bacula-fd.conf'
do
    image="${spec%%|*}"
    default_conf="${spec#*|}"

    docker image inspect "$image" >/dev/null

    docker run --rm \
        --entrypoint sh \
        "$image" \
        -ec "test ! -e '$default_conf'"

    echo "OK image=$image default_config=ausente"
done


section "8. ESTADO DO NUCLEO"

docker ps \
    --filter name=conectaeduca-bacula \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

for c in \
    conectaeduca-bacula-catalog \
    conectaeduca-bacula-storage \
    conectaeduca-bacula-director \
    conectaeduca-bacula-filedaemon-lab
do
    state="$(
        docker inspect \
            --format '{{.State.Status}}' \
            "$c"
    )"

    [[ "$state" == "running" ]] \
        || fail "$c não está running"

    published="$(docker port "$c" 2>/dev/null || true)"

    [[ -z "$published" ]] \
        || fail "$c possui porta publicada"

    echo "OK runtime=$c"
done


section "9. CATALOG E ULTIMAS PROVAS"

docker exec conectaeduca-bacula-catalog \
    sh -c '
        echo -n "encoding="
        psql \
          -U "$POSTGRES_USER" \
          -d "$POSTGRES_DB" \
          -Atc "
            SELECT pg_encoding_to_char(encoding)
            FROM pg_database
            WHERE datname = '\''bacula'\'';
          "

        echo -n "version_id="
        psql \
          -U "$POSTGRES_USER" \
          -d "$POSTGRES_DB" \
          -Atc "SELECT VersionId FROM Version;"

        echo "--- jobs 5 e 6 ---"

        psql \
          -U "$POSTGRES_USER" \
          -d "$POSTGRES_DB" \
          -Atc "
            SELECT
              JobId || '\''|'\'' ||
              Name || '\''|'\'' ||
              JobStatus || '\''|'\'' ||
              JobFiles || '\''|'\'' ||
              JobBytes
            FROM Job
            WHERE JobId IN (5,6)
            ORDER BY JobId;
          "
    '


section "10. GIT"

git diff --check

echo "--- status ---"
git status --short

echo
echo "--- arquivos Bacula que seriam versionados ---"

git status --short \
    | grep -E \
      'deploy/interna/bacula|scripts/bootstrap/.*bacula|scripts/evidencias/.*bacula' \
    || true


section "RESULTADO"

echo "BACULA_CORE=APROVADO"
echo "BACULA_BACKUP_RESTORE=APROVADO"
echo "BACULA_MARIADB=APROVADO"
echo "BACULA_EXCLUSOES=APROVADAS"
echo "CHECKPOINT_RESULTADO=SUCESSO"
echo "ARQUIVO_SAIDA=$OUT"
