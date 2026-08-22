#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/srv/www/htdocs/conectaeduca"
COMPOSE="$ROOT/deploy/interna/bacula/compose.yml"
DOCKERFILE="$ROOT/deploy/interna/bacula/images/Dockerfile"

MARIADB_CONTAINER="conectaeduca-mariadb-local-mariadb-1"

DEBIAN_IMAGE="debian:trixie-slim@sha256:3a39a0592364683e6bab97937b72cad5a8fa6dcbbee90edb3bb48c7f8e94f258"

SOURCE_VOLUME="conectaeduca-bacula_fd-lab-source"
RESTORE_VOLUME="conectaeduca-bacula_fd-lab-restore"

LAB_DB="conectaeduca_bacula_lab"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HOME/Downloads/conectaeduca-checkpoint-bacula-mariadb-$STAMP.txt"
DIAG_LOCK="/tmp/conectaeduca-bacula-diag-$STAMP.lock"

mkdir -p "$HOME/Downloads"

exec > >(tee "$OUT") 2>&1


section() {
    echo
    echo "================================================================"
    echo "$1"
    echo "================================================================"
}


fail() {
    echo
    echo "FALHA: $*" >&2
    return 1
}


bconsole() {
    timeout 90s docker compose \
        -f "$COMPOSE" \
        --profile tools \
        run --rm -T bconsole
}


wait_running() {
    local container="$1"

    for i in $(seq 1 30); do
        local status restarting

        status="$(
            docker inspect \
                --format '{{.State.Status}}' \
                "$container" \
                2>/dev/null || true
        )"

        restarting="$(
            docker inspect \
                --format '{{.State.Restarting}}' \
                "$container" \
                2>/dev/null || true
        )"

        echo \
            "$container tentativa=$i status=${status:-ausente} restarting=${restarting:-?}"

        if [[ "$status" == "running" && "$restarting" == "false" ]]; then
            sleep 2

            status="$(
                docker inspect \
                    --format '{{.State.Status}}' \
                    "$container"
            )"

            restarting="$(
                docker inspect \
                    --format '{{.State.Restarting}}' \
                    "$container"
            )"

            if [[ "$status" == "running" && "$restarting" == "false" ]]; then
                echo "OK: $container está estável."
                return 0
            fi
        fi

        sleep 2
    done

    fail "$container não permaneceu em execução"
}


mariadb_root() {
    docker exec -i \
        "$MARIADB_CONTAINER" \
        sh -ec '
            if mariadb \
                --protocol=socket \
                --user=root \
                -Nse "SELECT 1" \
                >/dev/null 2>&1
            then
                echo "INFO: MariaDB auth=socket-root" >&2

                exec mariadb \
                    --protocol=socket \
                    --user=root
            fi


            if [ -r /root/.my.cnf ] \
                && mariadb \
                    --defaults-extra-file=/root/.my.cnf \
                    -Nse "SELECT 1" \
                    >/dev/null 2>&1
            then
                echo "INFO: MariaDB auth=/root/.my.cnf" >&2

                exec mariadb \
                    --defaults-extra-file=/root/.my.cnf
            fi


            PW=""
            ORIGEM=""


            if [ -n "${MARIADB_ROOT_PASSWORD:-}" ]; then

                PW="$MARIADB_ROOT_PASSWORD"
                ORIGEM="MARIADB_ROOT_PASSWORD"

            elif [ -n "${MYSQL_ROOT_PASSWORD:-}" ]; then

                PW="$MYSQL_ROOT_PASSWORD"
                ORIGEM="MYSQL_ROOT_PASSWORD"

            elif \
                [ -n "${MARIADB_ROOT_PASSWORD_FILE:-}" ] \
                && [ -r "$MARIADB_ROOT_PASSWORD_FILE" ]
            then

                PW="$(cat "$MARIADB_ROOT_PASSWORD_FILE")"
                ORIGEM="MARIADB_ROOT_PASSWORD_FILE"

            elif \
                [ -n "${MYSQL_ROOT_PASSWORD_FILE:-}" ] \
                && [ -r "$MYSQL_ROOT_PASSWORD_FILE" ]
            then

                PW="$(cat "$MYSQL_ROOT_PASSWORD_FILE")"
                ORIGEM="MYSQL_ROOT_PASSWORD_FILE"

            fi


            if [ -z "$PW" ]; then

                echo \
                    "ERRO: nenhum mecanismo root suportado foi encontrado." \
                    >&2

                echo \
                    "variaveis_mariadb_disponiveis_apenas_nomes:" \
                    >&2

                env \
                    | cut -d= -f1 \
                    | grep -E "^(MARIADB|MYSQL)" \
                    | sort \
                    | sed "s/^/  - /" \
                    >&2 \
                    || true

                echo \
                    "arquivos_run_secrets_apenas_nomes:" \
                    >&2

                find /run/secrets \
                    -maxdepth 1 \
                    -type f \
                    -printf "  - %f\n" \
                    2>/dev/null \
                    >&2 \
                    || true

                exit 20
            fi


            echo \
                "INFO: MariaDB auth=$ORIGEM" \
                >&2


            CNF="$(mktemp)"

            trap '\''rm -f "$CNF"'\'' \
                EXIT HUP INT TERM

            chmod 600 "$CNF"

            printf \
                "[client]\nuser=root\npassword=%s\n" \
                "$PW" \
                > "$CNF"

            mariadb \
                --defaults-extra-file="$CNF"
        '
}


mariadb_dump_lab() {
    docker exec \
        -e BACULA_LAB_DB="$LAB_DB" \
        "$MARIADB_CONTAINER" \
        sh -ec '
            dump_socket() {
                mariadb-dump \
                    --protocol=socket \
                    --user=root \
                    --single-transaction \
                    --quick \
                    --routines \
                    --events \
                    --triggers \
                    --hex-blob \
                    --databases "$BACULA_LAB_DB"
            }


            dump_cnf() {
                mariadb-dump \
                    --defaults-extra-file="$CNF" \
                    --single-transaction \
                    --quick \
                    --routines \
                    --events \
                    --triggers \
                    --hex-blob \
                    --databases "$BACULA_LAB_DB"
            }


            if mariadb \
                --protocol=socket \
                --user=root \
                -Nse "SELECT 1" \
                >/dev/null 2>&1
            then
                echo \
                    "INFO: mariadb-dump auth=socket-root" \
                    >&2

                dump_socket
                exit $?
            fi


            if [ -r /root/.my.cnf ] \
                && mariadb \
                    --defaults-extra-file=/root/.my.cnf \
                    -Nse "SELECT 1" \
                    >/dev/null 2>&1
            then

                echo \
                    "INFO: mariadb-dump auth=/root/.my.cnf" \
                    >&2

                mariadb-dump \
                    --defaults-extra-file=/root/.my.cnf \
                    --single-transaction \
                    --quick \
                    --routines \
                    --events \
                    --triggers \
                    --hex-blob \
                    --databases "$BACULA_LAB_DB"

                exit $?
            fi


            PW=""
            ORIGEM=""


            if [ -n "${MARIADB_ROOT_PASSWORD:-}" ]; then

                PW="$MARIADB_ROOT_PASSWORD"
                ORIGEM="MARIADB_ROOT_PASSWORD"

            elif [ -n "${MYSQL_ROOT_PASSWORD:-}" ]; then

                PW="$MYSQL_ROOT_PASSWORD"
                ORIGEM="MYSQL_ROOT_PASSWORD"

            elif \
                [ -n "${MARIADB_ROOT_PASSWORD_FILE:-}" ] \
                && [ -r "$MARIADB_ROOT_PASSWORD_FILE" ]
            then

                PW="$(cat "$MARIADB_ROOT_PASSWORD_FILE")"
                ORIGEM="MARIADB_ROOT_PASSWORD_FILE"

            elif \
                [ -n "${MYSQL_ROOT_PASSWORD_FILE:-}" ] \
                && [ -r "$MYSQL_ROOT_PASSWORD_FILE" ]
            then

                PW="$(cat "$MYSQL_ROOT_PASSWORD_FILE")"
                ORIGEM="MYSQL_ROOT_PASSWORD_FILE"

            fi


            [ -n "$PW" ] || {
                echo \
                    "ERRO: credencial para mariadb-dump não localizada." \
                    >&2
                exit 20
            }


            echo \
                "INFO: mariadb-dump auth=$ORIGEM" \
                >&2


            CNF="$(mktemp)"

            trap '\''rm -f "$CNF"'\'' \
                EXIT HUP INT TERM

            chmod 600 "$CNF"

            printf \
                "[client]\nuser=root\npassword=%s\n" \
                "$PW" \
                > "$CNF"

            dump_cnf
        '
}


diagnostico_falha() {
    rc=$?

    trap - ERR

    if ! mkdir "$DIAG_LOCK" 2>/dev/null; then
        exit "$rc"
    fi
    set +e

    section "DIAGNOSTICO AUTOMATICO APOS FALHA"

    docker ps -a \
        --filter name=conectaeduca-bacula \
        --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

    echo
    echo "--- LOG DIRECTOR ---"

    docker logs \
        --tail 120 \
        conectaeduca-bacula-director \
        2>&1 || true

    echo
    echo "--- LOG STORAGE ---"

    docker logs \
        --tail 100 \
        conectaeduca-bacula-storage \
        2>&1 || true

    echo
    echo "--- LOG FILE DAEMON LAB ---"

    docker logs \
        --tail 100 \
        conectaeduca-bacula-filedaemon-lab \
        2>&1 || true

    echo
    echo "--- MARIADB ---"

    docker ps \
        --filter name="$MARIADB_CONTAINER" \
        --format 'table {{.Names}}\t{{.Status}}' \
        || true

    echo
    echo "--- JOBS BACULA ---"

    docker exec conectaeduca-bacula-catalog \
        sh -c '
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
                ORDER BY JobId DESC
                LIMIT 12;
              "
        ' 2>/dev/null || true

    echo
    echo "--- GIT ---"

    cd "$ROOT" || true

    git status --short || true
    git diff --check || true

    echo
    echo "CHECKPOINT_RESULTADO=FALHA"
    echo "ARQUIVO_SAIDA=$OUT"

    exit "$rc"
}


trap diagnostico_falha ERR

cd "$ROOT"


section "1. INFORMACOES"

echo "data=$(date --iso-8601=seconds)"
echo "host=$(hostname)"
echo "branch=$(git branch --show-current)"
echo "saida=$OUT"


section "1A. QUARENTENA DE ARQUIVOS ACIDENTAIS"

ACCIDENTAL=$'h -n \x5c'

if [[ -e "$ACCIDENTAL" ]]; then
    Q="/var/tmp/conectaeduca-acidentais-$STAMP"

    mkdir -p "$Q"

    echo "arquivo=$ACCIDENTAL"
    stat -c 'bytes=%s modo=%a owner=%U:%G' -- "$ACCIDENTAL"
    sha256sum -- "$ACCIDENTAL"

    mv -- "$ACCIDENTAL" "$Q/"

    echo "OK: arquivo acidental movido para quarentena."
    echo "quarentena=$Q"
else
    echo "OK: arquivo acidental não está presente."
fi


section "2. CONSOLIDACAO DOS CHECKPOINTS"

if [[ \
    -f scripts/evidencias/tijolao_bacula_backup_restore_lab.sh \
    && ! -e scripts/evidencias/checkpoint_bacula_backup_restore_lab.sh \
]]; then

    mv \
        scripts/evidencias/tijolao_bacula_backup_restore_lab.sh \
        scripts/evidencias/checkpoint_bacula_backup_restore_lab.sh

    echo "OK: checkpoint de backup/restore recebeu nome definitivo."

else

    echo "OK: nenhuma renomeação necessária."

fi


section "3. HARDENING DAS IMAGENS BACULA"

python3 - <<'PY'
from pathlib import Path

p = Path("deploy/interna/bacula/images/Dockerfile")
s = p.read_text(encoding="utf-8")

rules = {
    "director": [
        "/etc/bacula/bacula-dir.conf",
        "/etc/bacula/bconsole.conf",
    ],
    "storage": [
        "/etc/bacula/bacula-sd.conf",
    ],
    "filedaemon": [
        "/etc/bacula/bacula-fd.conf",
    ],
}

for target, paths in rules.items():
    marker = f"FROM base AS {target}"

    start = s.find(marker)

    if start == -1:
        raise SystemExit(
            f"ERRO: target {target} não encontrado no Dockerfile"
        )

    next_from = s.find(
        "\nFROM ",
        start + len(marker),
    )

    end = (
        len(s)
        if next_from == -1
        else next_from
    )

    section = s[start:end]

    signature = (
        "        "
        + " \\\n        ".join(paths)
    )

    if (
        all(path in section for path in paths)
        and "rm -f" in section
    ):
        print(
            f"OK: {target} já remove configuração padrão "
            "no mesmo estágio."
        )
        continue

    needle = "    && rm -rf /var/lib/apt/lists/*"

    if needle not in section:
        raise SystemExit(
            f"ERRO: limpeza apt não encontrada no target {target}"
        )

    replacement = (
        "    && rm -f \\\n"
        + signature
        + " \\\n"
        + needle
    )

    section = section.replace(
        needle,
        replacement,
        1,
    )

    s = s[:start] + section + s[end:]

p.write_text(
    s,
    encoding="utf-8",
)

print(
    "OK: configs aleatórios criados pelos pacotes "
    "não permanecerão nas imagens finais."
)
PY

git diff --check


section "4. MATERIALIZADOR DE WORKLOADS DO LAB"

cat > scripts/bootstrap/materializar_bacula_workloads_lab.py <<'PY'
#!/usr/bin/env python3

from pathlib import Path


root = Path(__file__).resolve().parents[2]

conf = (
    root
    / "deploy/interna/bacula/.runtime/config/bacula-dir.conf"
)

if not conf.is_file():
    raise SystemExit(
        "ERRO: bacula-dir.conf runtime ausente; "
        "materialize o núcleo primeiro."
    )


begin = "# BEGIN CONECTAEDUCA BACULA WORKLOADS LAB"
end = "# END CONECTAEDUCA BACULA WORKLOADS LAB"


block = r'''
# BEGIN CONECTAEDUCA BACULA WORKLOADS LAB
# Bancada sintética.
# Não substitui os File Daemons nativos das VMs finais.

FileSet {
  Name = "ConectaEducaArtifactsSet"

  Include {
    Options {
      Signature = SHA256
    }

    File = /data/workloads
  }

  Exclude {
    File = /data/workloads/.runtime
    File = /data/workloads/secrets
    File = /data/workloads/openbao/custodia
    File = /data/workloads/smtp/private
    File = /data/workloads/ferret/inbox
    File = /data/workloads/ferret/raw
    File = /data/workloads/wazuh/indexer
  }
}

Job {
  Name = "ConectaEducaArtifactsBackup"
  Type = Backup
  Level = Full
  Client = conectaeduca-lab-fd
  FileSet = "ConectaEducaArtifactsSet"
  Pool = LabPool
  Storage = ConectaEducaStorage
  Messages = Standard
}

Job {
  Name = "ConectaEducaArtifactsRestore"
  Type = Restore
  Client = conectaeduca-lab-fd
  FileSet = "ConectaEducaArtifactsSet"
  Pool = LabPool
  Storage = ConectaEducaStorage
  Messages = Standard
  Where = /restore
  Replace = always
}

# END CONECTAEDUCA BACULA WORKLOADS LAB
'''.lstrip()


text = conf.read_text(
    encoding="utf-8",
)

if begin in text:
    start = text.index(begin)

    stop = text.find(
        end,
        start,
    )

    if stop == -1:
        raise SystemExit(
            "ERRO: marcador final do bloco workloads ausente."
        )

    stop += len(end)

    while (
        stop < len(text)
        and text[stop] in "\r\n"
    ):
        stop += 1

    text = (
        text[:start].rstrip()
        + "\n\n"
        + text[stop:].lstrip()
    )


text = (
    text.rstrip()
    + "\n\n"
    + block
)

tmp = conf.with_suffix(
    conf.suffix + ".tmp"
)

tmp.write_text(
    text,
    encoding="utf-8",
)

tmp.chmod(0o600)

tmp.replace(conf)

conf.chmod(0o600)

print(
    "OK: recursos Bacula de workloads sintéticos materializados."
)

print(
    "OK: exclusões sensíveis declaradas no FileSet."
)
PY

chmod 755 \
    scripts/bootstrap/materializar_bacula_workloads_lab.py

python3 -m py_compile \
    scripts/bootstrap/materializar_bacula_workloads_lab.py

echo "OK: materializador de workloads válido."


section "5. REBUILD DAS TRES IMAGENS BACULA"

for target in director storage filedaemon; do

    case "$target" in

        director)
            image="conectaeduca/bacula-director:15.0.3"
            ;;

        storage)
            image="conectaeduca/bacula-storage:15.0.3"
            ;;

        filedaemon)
            image="conectaeduca/bacula-filedaemon:15.0.3"
            ;;

    esac

    echo "--- build target=$target ---"

    docker build \
        --platform linux/amd64 \
        --target "$target" \
        -t "$image" \
        -f "$DOCKERFILE" \
        "$ROOT"

done


section "6. PROVA DE QUE CONFIGS PADRAO NAO FICARAM NAS IMAGENS"

docker run --rm \
    --entrypoint sh \
    conectaeduca/bacula-director:15.0.3 \
    -ec '
        test ! -e /etc/bacula/bacula-dir.conf
        test ! -e /etc/bacula/bconsole.conf

        test -e /etc/bacula/scripts/query.sql

        echo \
          "OK: Director sem configs padrão; query.sql preservado."
    '

docker run --rm \
    --entrypoint sh \
    conectaeduca/bacula-storage:15.0.3 \
    -ec '
        test ! -e /etc/bacula/bacula-sd.conf

        echo "OK: Storage sem config padrão."
    '

docker run --rm \
    --entrypoint sh \
    conectaeduca/bacula-filedaemon:15.0.3 \
    -ec '
        test ! -e /etc/bacula/bacula-fd.conf

        echo "OK: File Daemon sem config padrão."
    '

echo
echo "--- IDs DAS IMAGENS ---"

for image in \
    conectaeduca/bacula-director:15.0.3 \
    conectaeduca/bacula-storage:15.0.3 \
    conectaeduca/bacula-filedaemon:15.0.3
do

    echo \
      "$image|$(docker image inspect --format '{{.Id}}' "$image")"

done


section "7. REMATERIALIZACAO E VALIDACAO BACULA"

fish \
    scripts/bootstrap/preparar_bacula_core.fish

python3 \
    scripts/bootstrap/materializar_bacula_core.py

python3 \
    scripts/bootstrap/materializar_bacula_workloads_lab.py

stat \
    -c '%a %U:%G %n' \
    deploy/interna/bacula/.runtime/config/bacula-dir.conf \
    deploy/interna/bacula/.runtime/config/bacula-fd.conf

docker compose \
    -f "$COMPOSE" \
    --profile tools \
    config \
    >/dev/null

docker run --rm \
    --user 0:0 \
    --network conectaeduca-bacula_bacula-backend \
    --add-host storage:127.0.0.1 \
    --add-host filedaemon-lab:127.0.0.1 \
    --mount \
      type=bind,src="$ROOT/deploy/interna/bacula/.runtime/config/bacula-dir.conf",dst=/etc/bacula-runtime/bacula-dir.conf,readonly \
    --entrypoint bacula-dir \
    conectaeduca/bacula-director:15.0.3 \
    -t \
    -u bacula \
    -g bacula \
    -c /etc/bacula-runtime/bacula-dir.conf

echo \
    "OK: configuração Director + workloads aceita."


section "8. RECRIANDO DAEMONS COM AS IMAGENS ENDURECIDAS"

docker compose \
    -f "$COMPOSE" \
    up -d \
    --force-recreate \
    storage \
    filedaemon-lab \
    director

wait_running \
    conectaeduca-bacula-storage

wait_running \
    conectaeduca-bacula-filedaemon-lab

wait_running \
    conectaeduca-bacula-director

wait_running \
    conectaeduca-bacula-catalog

docker ps \
    --filter name=conectaeduca-bacula \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'


section "9. PREPARANDO STAGING E CANARIOS DE EXCLUSAO"

docker run --rm \
    -v "$SOURCE_VOLUME:/data" \
    --entrypoint sh \
    "$DEBIAN_IMAGE" \
    -ec '
        rm -rf /data/workloads

        install \
          -d \
          -o 100 \
          -g 101 \
          -m 0750 \
          /data/workloads/mariadb \
          /data/workloads/.runtime \
          /data/workloads/secrets \
          /data/workloads/openbao/custodia \
          /data/workloads/smtp/private \
          /data/workloads/ferret/inbox \
          /data/workloads/ferret/raw \
          /data/workloads/wazuh/indexer

        for f in \
          /data/workloads/.runtime/secret.env \
          /data/workloads/secrets/root-token.txt \
          /data/workloads/openbao/custodia/unseal-share-1.txt \
          /data/workloads/smtp/private/smtp-google.env \
          /data/workloads/ferret/inbox/raw.bin \
          /data/workloads/ferret/raw/report.json \
          /data/workloads/wazuh/indexer/raw-index.bin
        do

            printf "%s\n" \
              "CANARY-DO-NOT-BACKUP" \
              > "$f"

            chown \
              100:101 \
              "$f"

            chmod \
              0640 \
              "$f"

        done

        echo \
          "OK: canários sintéticos criados; nenhum contém segredo real."
    '

docker run --rm \
    -v "$RESTORE_VOLUME:/restore" \
    --entrypoint sh \
    "$DEBIAN_IMAGE" \
    -ec '
        rm -rf /restore/*
    '



section "9A. SUPERFICIE DE AUTENTICACAO MARIADB - SEM SEGREDOS"

echo "--- variáveis disponíveis: somente nomes ---"

docker inspect \
    "$MARIADB_CONTAINER" \
    --format '{{range .Config.Env}}{{println .}}{{end}}' \
    | sed 's/=.*$//' \
    | grep -E '^(MARIADB|MYSQL)' \
    | sort \
    || true

echo
echo "--- destinos de mounts: sem conteúdo ---"

docker inspect \
    "$MARIADB_CONTAINER" \
    --format '{{range .Mounts}}{{println .Destination}}{{end}}' \
    | sort \
    || true

echo
echo "OK: nenhum valor de credencial foi exibido."


section "10. BANCO MARIADB SINTETICO"

docker ps \
    --format '{{.Names}}' \
    | grep -Fx "$MARIADB_CONTAINER" \
    >/dev/null \
    || fail \
        "container MariaDB esperado não está em execução: $MARIADB_CONTAINER"

mariadb_root <<'SQL'
DROP DATABASE IF EXISTS conectaeduca_bacula_lab;

CREATE DATABASE conectaeduca_bacula_lab
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE conectaeduca_bacula_lab;

CREATE TABLE evidencia_backup (
    id INT PRIMARY KEY,
    marcador VARCHAR(32) NOT NULL,
    valor INT NOT NULL
) ENGINE=InnoDB;

INSERT INTO evidencia_backup
    (id, marcador, valor)
VALUES
    (1, 'alpha', 100),
    (2, 'beta', 200),
    (3, 'gamma', 300);
SQL

MARIADB_ANTES="$(
    printf '%s\n' \
      'SELECT CONCAT(COUNT(*),"|",SUM(valor),"|",GROUP_CONCAT(marcador ORDER BY id SEPARATOR ",")) FROM conectaeduca_bacula_lab.evidencia_backup;' \
      | mariadb_root \
      | tail -n 1
)"

echo \
    "mariadb_antes=$MARIADB_ANTES"

[[ "$MARIADB_ANTES" == "3|600|alpha,beta,gamma" ]] \
    || fail \
        "conteúdo sintético inicial inesperado"


section "11. DUMP CONSISTENTE DIRETO PARA O STAGING"

mariadb_dump_lab \
    | docker run --rm -i \
        -v "$SOURCE_VOLUME:/data" \
        --entrypoint sh \
        "$DEBIAN_IMAGE" \
        -ec '
            umask 027

            cat \
              > /data/workloads/mariadb/conectaeduca_bacula_lab.sql

            chown \
              100:101 \
              /data/workloads/mariadb/conectaeduca_bacula_lab.sql

            chmod \
              0640 \
              /data/workloads/mariadb/conectaeduca_bacula_lab.sql
        '

DUMP_HASH="$(
    docker run --rm \
        -v "$SOURCE_VOLUME:/data:ro" \
        --entrypoint sh \
        "$DEBIAN_IMAGE" \
        -ec '
            sha256sum \
              /data/workloads/mariadb/conectaeduca_bacula_lab.sql \
              | awk "{print \$1}"
        '
)"

DUMP_BYTES="$(
    docker run --rm \
        -v "$SOURCE_VOLUME:/data:ro" \
        --entrypoint stat \
        "$DEBIAN_IMAGE" \
        -c '%s' \
        /data/workloads/mariadb/conectaeduca_bacula_lab.sql
)"

echo "dump_bytes=$DUMP_BYTES"
echo "dump_sha256=$DUMP_HASH"

[[ "$DUMP_BYTES" -gt 0 ]] \
    || fail \
        "dump MariaDB vazio"


section "12. POOL E VOLUME"

MEDIA_EXISTE="$(
    docker exec \
        conectaeduca-bacula-catalog \
        sh -c '
            psql \
              -U "$POSTGRES_USER" \
              -d "$POSTGRES_DB" \
              -Atc "
                SELECT count(*)
                FROM Media
                WHERE VolumeName = '\''LabVol001'\'';
              "
        '
)"

if [[ "$MEDIA_EXISTE" == "0" ]]; then

    printf '%s\n' \
        'label storage=ConectaEducaStorage pool=LabPool volume=LabVol001' \
        'quit' \
        | bconsole

fi

echo \
    "volume_LabVol001=presente"


section "13. BACKUP DOS ARTEFATOS"

printf '%s\n' \
    'run job=ConectaEducaArtifactsBackup level=Full yes' \
    'wait' \
    'quit' \
    | bconsole

BACKUP_ROW="$(
    docker exec \
        conectaeduca-bacula-catalog \
        sh -c '
            psql \
              -U "$POSTGRES_USER" \
              -d "$POSTGRES_DB" \
              -Atc "
                SELECT
                  JobId || '\''|'\'' ||
                  JobStatus || '\''|'\'' ||
                  JobFiles || '\''|'\'' ||
                  JobBytes
                FROM Job
                WHERE Name = '\''ConectaEducaArtifactsBackup'\''
                ORDER BY JobId DESC
                LIMIT 1;
              "
        '
)"

echo \
    "backup_workloads=$BACKUP_ROW"

IFS='|' read -r \
    BACKUP_JOBID \
    BACKUP_STATUS \
    BACKUP_FILES \
    BACKUP_BYTES \
    <<< "$BACKUP_ROW"

[[ -n "$BACKUP_JOBID" ]] \
    || fail \
        "JobId do backup de workloads ausente"

[[ "$BACKUP_STATUS" == "T" ]] \
    || fail \
        "backup de workloads falhou: $BACKUP_STATUS"

[[ "$BACKUP_FILES" -ge 1 ]] \
    || fail \
        "backup de workloads não registrou arquivos"

[[ "$BACKUP_BYTES" -gt 0 ]] \
    || fail \
        "backup de workloads não registrou bytes"


section "14. PROVA DAS EXCLUSOES"

FILE_LIST="$(
    printf '%s\n' \
        "list files jobid=$BACKUP_JOBID" \
        'quit' \
        | bconsole \
        2>&1
)"

echo "$FILE_LIST"

grep -q \
    'conectaeduca_bacula_lab.sql' \
    <<<"$FILE_LIST" \
    || fail \
        "dump permitido não apareceu no backup"

for forbidden in \
    secret.env \
    root-token.txt \
    unseal-share-1.txt \
    smtp-google.env \
    raw.bin \
    report.json \
    raw-index.bin
do

    if grep -Fq \
        "$forbidden" \
        <<<"$FILE_LIST"
    then
        fail \
            "arquivo excluído apareceu no backup: $forbidden"
    fi

    echo \
        "OK exclusão=$forbidden"

done


section "15. PROVA DE PERDA DO BANCO E DO DUMP DE ORIGEM"

printf '%s\n' \
    'DROP DATABASE conectaeduca_bacula_lab;' \
    | mariadb_root

docker run --rm \
    -v "$SOURCE_VOLUME:/data" \
    --entrypoint sh \
    "$DEBIAN_IMAGE" \
    -ec '
        rm -f \
          /data/workloads/mariadb/conectaeduca_bacula_lab.sql

        test ! -e \
          /data/workloads/mariadb/conectaeduca_bacula_lab.sql
    '

DB_EXISTE="$(
    printf '%s\n' \
      'SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME="conectaeduca_bacula_lab";' \
      | mariadb_root \
      | tail -n 1
)"

echo \
    "database_pos_perda=$DB_EXISTE"

[[ "$DB_EXISTE" == "0" ]] \
    || fail \
        "banco sintético não foi removido"

echo \
    "OK: origem lógica removida antes do restore."


section "16. RESTORE BACULA"

RESTORE_OUTPUT="$(
    printf '%s\n' \
        "restore jobid=${BACKUP_JOBID} client=conectaeduca-lab-fd fileset=ConectaEducaArtifactsSet storage=ConectaEducaStorage pool=LabPool restoreclient=conectaeduca-lab-fd restorejob=ConectaEducaArtifactsRestore where=/restore select all done yes" \
        'wait' \
        'messages' \
        'quit' \
        | bconsole \
        2>&1
)"

echo "$RESTORE_OUTPUT"

if grep -Eq \
    'Select item:|Select FileSet resource|OK to run\?' \
    <<<"$RESTORE_OUTPUT"
then
    echo "$RESTORE_OUTPUT"
    fail \
        "restore caiu inesperadamente em modo interativo"
fi

RESTORE_ROW="$(
    docker exec \
        conectaeduca-bacula-catalog \
        sh -c '
            psql \
              -U "$POSTGRES_USER" \
              -d "$POSTGRES_DB" \
              -Atc "
                SELECT
                  JobId || '\''|'\'' ||
                  JobStatus || '\''|'\'' ||
                  JobFiles || '\''|'\'' ||
                  JobBytes
                FROM Job
                WHERE Name = '\''ConectaEducaArtifactsRestore'\''
                ORDER BY JobId DESC
                LIMIT 1;
              "
        '
)"

echo \
    "restore_workloads=$RESTORE_ROW"

IFS='|' read -r \
    RESTORE_JOBID \
    RESTORE_STATUS \
    RESTORE_FILES \
    RESTORE_BYTES \
    <<< "$RESTORE_ROW"

[[ -n "$RESTORE_JOBID" ]] \
    || fail \
        "JobId de restore ausente"

[[ "$RESTORE_STATUS" == "T" ]] \
    || fail \
        "restore falhou: $RESTORE_STATUS"


section "17. HASH E RESTAURACAO LOGICA MARIADB"

RESTORED_PATH="$(
    docker run --rm \
        -v "$RESTORE_VOLUME:/restore:ro" \
        --entrypoint sh \
        "$DEBIAN_IMAGE" \
        -ec '
            find /restore \
              -type f \
              -name conectaeduca_bacula_lab.sql \
              -print \
              -quit
        '
)"

[[ -n "$RESTORED_PATH" ]] \
    || fail \
        "dump restaurado não encontrado"

echo \
    "dump_restaurado=$RESTORED_PATH"

RESTORED_HASH="$(
    docker run --rm \
        -v "$RESTORE_VOLUME:/restore:ro" \
        --entrypoint sh \
        "$DEBIAN_IMAGE" \
        -ec '
            f="$(
                find /restore \
                  -type f \
                  -name conectaeduca_bacula_lab.sql \
                  -print \
                  -quit
            )"

            test -n "$f"

            sha256sum "$f" \
              | awk "{print \$1}"
        '
)"

echo \
    "dump_sha256_original=$DUMP_HASH"

echo \
    "dump_sha256_restaurado=$RESTORED_HASH"

[[ "$DUMP_HASH" == "$RESTORED_HASH" ]] \
    || fail \
        "hash do dump restaurado diverge"

docker run --rm \
    -v "$RESTORE_VOLUME:/restore:ro" \
    --entrypoint sh \
    "$DEBIAN_IMAGE" \
    -ec '
        f="$(
            find /restore \
              -type f \
              -name conectaeduca_bacula_lab.sql \
              -print \
              -quit
        )"

        test -n "$f"

        cat "$f"
    ' \
    | mariadb_root

MARIADB_DEPOIS="$(
    printf '%s\n' \
      'SELECT CONCAT(COUNT(*),"|",SUM(valor),"|",GROUP_CONCAT(marcador ORDER BY id SEPARATOR ",")) FROM conectaeduca_bacula_lab.evidencia_backup;' \
      | mariadb_root \
      | tail -n 1
)"

echo \
    "mariadb_depois=$MARIADB_DEPOIS"

[[ "$MARIADB_DEPOIS" == "$MARIADB_ANTES" ]] \
    || fail \
        "conteúdo lógico restaurado diverge do original"

echo \
    "OK: MariaDB restaurado logicamente com conteúdo idêntico."


section "18. OPENBAO - PRONTIDAO PARA O PROXIMO TIJOLO"

OPENBAO_STATUS="$(
    docker exec \
        conectaeduca-openbao \
        sh -ec \
          'BAO_ADDR=http://127.0.0.1:8200 bao status -format=json' \
        2>/dev/null \
        || true
)"

if [[ -n "$OPENBAO_STATUS" ]]; then

    printf '%s' \
        "$OPENBAO_STATUS" \
        | python3 -c '
import json
import sys

x = json.load(sys.stdin)

for key in (
    "initialized",
    "sealed",
    "version",
    "storage_type",
):
    if key in x:
        print(
            f"openbao_{key}={x[key]}"
        )
'

else

    echo \
        "openbao_status=indisponivel"

fi

echo \
    "INFO: snapshot Raft não executado neste tijolo."

echo \
    "INFO: será criado acesso dedicado somente-read a sys/storage/raft/snapshot; root token não fará parte da rotina."


section "19. LIMPEZA DA BANCADA SINTETICA"

printf '%s\n' \
    'DROP DATABASE IF EXISTS conectaeduca_bacula_lab;' \
    | mariadb_root

docker run --rm \
    -v "$SOURCE_VOLUME:/data" \
    -v "$RESTORE_VOLUME:/restore" \
    --entrypoint sh \
    "$DEBIAN_IMAGE" \
    -ec '
        rm -rf \
          /data/workloads \
          /restore/*
    '

echo \
    "OK: banco e staging sintéticos removidos após a prova."


section "20. AUDITORIA DE GIT E SEGREDOS RUNTIME"

for path in \
    deploy/interna/bacula/.runtime/core.env \
    deploy/interna/bacula/.runtime/director-db.env \
    deploy/interna/bacula/.runtime/config/bacula-dir.conf \
    deploy/interna/bacula/.runtime/config/bacula-fd.conf
do

    git check-ignore -q \
        "$path" \
        || fail \
            "runtime não ignorado: $path"

    echo \
        "OK ignored=$path"

done

if git ls-files \
    | grep -E \
      '(^|/)(\.runtime|unseal-share-[0-9]+\.txt|smtp-google\.env|root-token\.txt)(/|$)' \
    >/dev/null
then

    fail \
        "Git contém caminho que parece material sensível de runtime"

fi

git diff --check

git status --short


section "21. ESTADO FINAL"

printf '%s\n' \
    'status director' \
    'status client=conectaeduca-lab-fd' \
    'status storage=ConectaEducaStorage' \
    'list jobs' \
    'quit' \
    | bconsole


section "RESULTADO"

echo \
    "MARIADB_DUMP_SINGLE_TRANSACTION=SIM"

echo \
    "BACULA_WORKLOAD_BACKUP_JOBID=$BACKUP_JOBID"

echo \
    "BACULA_WORKLOAD_RESTORE_JOBID=$RESTORE_JOBID"

echo \
    "DUMP_SHA256_MATCH=SIM"

echo \
    "MARIADB_LOGICAL_RESTORE_MATCH=SIM"

echo \
    "EXCLUSOES_SENSIVEIS=APROVADAS"

echo \
    "CHECKPOINT_RESULTADO=SUCESSO"

echo \
    "ARQUIVO_SAIDA=$OUT"
