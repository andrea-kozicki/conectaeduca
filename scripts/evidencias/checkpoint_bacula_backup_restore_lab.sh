#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/srv/www/htdocs/conectaeduca"
COMPOSE="$ROOT/deploy/interna/bacula/compose.yml"
DOCKERFILE="$ROOT/deploy/interna/bacula/images/Dockerfile"

DEBIAN_IMAGE="debian:trixie-slim@sha256:3a39a0592364683e6bab97937b72cad5a8fa6dcbbee90edb3bb48c7f8e94f258"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HOME/Downloads/conectaeduca-checkpoint-bacula-backup-restore-$STAMP.txt"
QUARENTENA="/var/tmp/conectaeduca-acidentais-$STAMP"

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


diagnostico_falha() {
    rc=$?

    trap - ERR
    set +e

    section "DIAGNOSTICO AUTOMATICO APOS FALHA"

    docker ps -a \
        --filter name=conectaeduca-bacula \
        --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

    echo
    echo "--- LOG DIRECTOR ---"
    docker logs --tail 120 conectaeduca-bacula-director 2>&1 || true

    echo
    echo "--- LOG STORAGE ---"
    docker logs --tail 120 conectaeduca-bacula-storage 2>&1 || true

    echo
    echo "--- LOG FILE DAEMON LAB ---"
    docker logs --tail 120 conectaeduca-bacula-filedaemon-lab 2>&1 || true

    echo
    echo "--- LOG CATALOG ---"
    docker logs --tail 80 conectaeduca-bacula-catalog 2>&1 || true

    echo
    echo "--- ULTIMOS JOBS ---"

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
                LIMIT 10;
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


wait_running() {
    local container="$1"

    for i in $(seq 1 30); do
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


bconsole() {
    timeout 60s docker compose \
        -f "$COMPOSE" \
        --profile tools \
        run --rm -T bconsole
}


cd "$ROOT"


section "1. INFORMACOES"

echo "data=$(date --iso-8601=seconds)"
echo "host=$(hostname)"
echo "branch=$(git branch --show-current)"
echo "saida=$OUT"


section "2. QUARENTENA DOS ARQUIVOS ACIDENTAIS"

mkdir -p "$QUARENTENA"

encontrou=0

for f in 'e \' 'tatus --short'; do
    if [[ -e "$f" ]]; then
        encontrou=1

        echo
        echo "arquivo=$f"
        stat -c 'bytes=%s modo=%a owner=%U:%G' -- "$f"
        sha256sum -- "$f"

        mv -- "$f" "$QUARENTENA/"

        echo "OK: movido para quarentena."
    fi
done

if [[ "$encontrou" -eq 0 ]]; then
    echo "OK: nenhum arquivo acidental presente."
else
    echo
    echo "quarentena=$QUARENTENA"

    if [[ -f "$QUARENTENA/e \\" && \
          -f "$QUARENTENA/tatus --short" ]]; then

        if cmp -s \
            "$QUARENTENA/e \\" \
            "$QUARENTENA/tatus --short"
        then
            echo "INFO: os dois arquivos acidentais são byte-a-byte idênticos."
        else
            echo "INFO: os arquivos acidentais possuem conteúdos diferentes."
        fi
    fi
fi


section "3. ADICIONANDO IMAGEM DO FILE DAEMON DE LABORATORIO"

python3 - <<'PY'
from pathlib import Path

p = Path("deploy/interna/bacula/images/Dockerfile")
s = p.read_text(encoding="utf-8")

if "FROM base AS filedaemon" not in s:
    s += r'''

FROM base AS filedaemon

ARG BACULA_VERSION

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bacula-fd="${BACULA_VERSION}" \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

CMD ["bacula-fd", "-f", "-c", "/etc/bacula/bacula-fd.conf"]
'''

    p.write_text(s, encoding="utf-8")

    print("OK: target filedaemon acrescentado ao Dockerfile.")
else:
    print("OK: target filedaemon já existe.")
PY


section "4. CONFIGURACAO DO LAB NO MATERIALIZADOR"

python3 - <<'PY'
from pathlib import Path

p = Path("scripts/bootstrap/materializar_bacula_core.py")
s = p.read_text(encoding="utf-8")

if "Name = conectaeduca-lab-fd" not in s:

    old = '''Client {{
  Name = conectaeduca-bootstrap-fd
  Address = 127.0.0.1
  FDPort = 9102
  Catalog = ConectaEducaCatalog
  Password = "{bootstrap_fd_password}"
  Enabled = no
}}

FileSet {{
  Name = "BootstrapEmpty"

  Include {{
    Options {{
      Signature = SHA256
    }}

    File = /tmp
  }}
}}

Pool {{
  Name = BootstrapPool
  Pool Type = Backup
  Storage = ConectaEducaStorage
  Recycle = yes
  AutoPrune = yes
  Volume Retention = 1 day
}}

Job {{
  Name = "CoreConnectivity"
  Type = Admin
  Client = conectaeduca-bootstrap-fd
  FileSet = "BootstrapEmpty"
  Pool = BootstrapPool
  Storage = ConectaEducaStorage
  Messages = Standard
  Enabled = no
}}
'''

    new = '''Client {{
  Name = conectaeduca-lab-fd
  Address = filedaemon-lab
  FDPort = 9102
  Catalog = ConectaEducaCatalog
  Password = "{bootstrap_fd_password}"
  File Retention = 7 days
  Job Retention = 7 days
  AutoPrune = yes
}}

FileSet {{
  Name = "LabSyntheticSet"

  Include {{
    Options {{
      Signature = SHA256
    }}

    File = /data/synthetic.bin
  }}
}}

Pool {{
  Name = LabPool
  Pool Type = Backup
  Storage = ConectaEducaStorage
  Recycle = yes
  AutoPrune = yes
  Volume Retention = 1 day
  Maximum Volumes = 2
}}

Job {{
  Name = "LabSyntheticBackup"
  Type = Backup
  Level = Full
  Client = conectaeduca-lab-fd
  FileSet = "LabSyntheticSet"
  Pool = LabPool
  Storage = ConectaEducaStorage
  Messages = Standard
}}

Job {{
  Name = "LabSyntheticRestore"
  Type = Restore
  Client = conectaeduca-lab-fd
  FileSet = "LabSyntheticSet"
  Pool = LabPool
  Storage = ConectaEducaStorage
  Messages = Standard
  Where = /restore
  Replace = always
}}
'''

    if old not in s:
        raise SystemExit(
            "ERRO: bloco placeholder esperado não encontrado."
        )

    s = s.replace(old, new, 1)

else:
    print("OK: recursos de laboratório já existem.")


if 'atomic_secret(CONFIG / "bacula-fd.conf"' not in s:

    marker = '''atomic_secret(CONFIG / "bacula-dir.conf", director_conf)
'''

    if marker not in s:
        raise SystemExit(
            "ERRO: ponto de inserção do bacula-fd.conf não encontrado."
        )

    fd = (
        'fd_conf = f"""FileDaemon {{\n'
        '  Name = conectaeduca-lab-fd\n'
        '  FDport = 9102\n'
        '  WorkingDirectory = "/var/lib/bacula"\n'
        '  Pid Directory = "/run/bacula"\n'
        '  Maximum Concurrent Jobs = 5\n'
        '  FDAddress = 0.0.0.0\n'
        '}}\n'
        '\n'
        'Director {{\n'
        '  Name = conectaeduca-dir\n'
        '  Password = "{bootstrap_fd_password}"\n'
        '}}\n'
        '\n'
        'Messages {{\n'
        '  Name = Standard\n'
        '  stdout = all, !skipped, !saved\n'
        '}}\n'
        '"""\n\n'
        'atomic_secret(CONFIG / "bacula-fd.conf", fd_conf)\n'
    )

    s = s.replace(marker, fd + "\n" + marker, 1)


p.write_text(s, encoding="utf-8")

print("OK: materializador preparado para backup/restore sintético.")
PY


section "5. SERVICO FILE DAEMON LAB NO COMPOSE"

python3 - <<'PY'
from pathlib import Path

p = Path("deploy/interna/bacula/compose.yml")
s = p.read_text(encoding="utf-8")

if "\n  filedaemon-lab:\n" not in s:

    marker = "\n\nnetworks:\n"

    if marker not in s:
        raise SystemExit("ERRO: seção networks não encontrada.")

    service = r'''

  filedaemon-lab:
    image: conectaeduca/bacula-filedaemon:15.0.3
    container_name: conectaeduca-bacula-filedaemon-lab

    volumes:
      - ./.runtime/config/bacula-fd.conf:/etc/bacula-runtime/bacula-fd.conf:ro
      - fd-lab-source:/data:ro
      - fd-lab-restore:/restore

    networks:
      - bacula-backend

    expose:
      - "9102"

    entrypoint:
      - /bin/sh
      - -ec

    command:
      - |
        install -d -o bacula -g bacula -m 2775 /run/bacula
        install -d -o bacula -g bacula -m 0700 /var/lib/bacula

        chown bacula:bacula /restore
        chmod 0750 /restore

        exec bacula-fd \
          -f \
          -u bacula \
          -g bacula \
          -c /etc/bacula-runtime/bacula-fd.conf

    restart: unless-stopped

    security_opt:
      - no-new-privileges:true
'''

    s = s.replace(marker, service + marker, 1)

if "  fd-lab-source:" not in s:
    marker = "  storage-data:\n"

    if marker not in s:
        raise SystemExit("ERRO: volume storage-data não encontrado.")

    s = s.replace(
        marker,
        marker + "  fd-lab-source:\n  fd-lab-restore:\n",
        1,
    )

p.write_text(s, encoding="utf-8")

print("OK: filedaemon-lab acrescentado ao Compose.")
print("OK: volumes sintéticos de source/restore declarados.")
PY


section "6. VALIDACOES ESTATICAS"

fish scripts/bootstrap/preparar_bacula_core.fish

python3 -m py_compile \
    scripts/bootstrap/materializar_bacula_core.py

python3 scripts/bootstrap/materializar_bacula_core.py

test -s deploy/interna/bacula/.runtime/config/bacula-fd.conf

stat -c '%a %U:%G %n' \
    deploy/interna/bacula/.runtime/config/bacula-fd.conf

git check-ignore -v \
    deploy/interna/bacula/.runtime/config/bacula-fd.conf

docker compose \
    -f "$COMPOSE" \
    --profile tools \
    config >/dev/null

git diff --check

echo "OK: validações estáticas concluídas."


section "7. BUILD FILE DAEMON"

docker build \
    --platform linux/amd64 \
    --target filedaemon \
    -t conectaeduca/bacula-filedaemon:15.0.3 \
    -f "$DOCKERFILE" \
    "$ROOT"

docker run --rm \
    --entrypoint sh \
    conectaeduca/bacula-filedaemon:15.0.3 \
    -c '
        echo "bacula-fd=$(command -v bacula-fd)"
        bacula-fd -? 2>&1 | head -n 5

        dpkg-query -W \
          -f="\${Package}=\${Version}\n" \
          bacula-fd
    '


section "8. TESTES DE CONFIGURACAO"

docker run --rm \
    --user 0:0 \
    --tmpfs /run/bacula \
    --tmpfs /var/lib/bacula \
    --mount \
      type=bind,src="$ROOT/deploy/interna/bacula/.runtime/config/bacula-fd.conf",dst=/etc/bacula-runtime/bacula-fd.conf,readonly \
    --entrypoint bacula-fd \
    conectaeduca/bacula-filedaemon:15.0.3 \
    -t \
    -u bacula \
    -g bacula \
    -c /etc/bacula-runtime/bacula-fd.conf

echo "OK: bacula-fd.conf aceito."

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

echo "OK: configuração ampliada do Director aceita."


section "9. SUBINDO NUCLEO + FILE DAEMON"

docker compose \
    -f "$COMPOSE" \
    up -d catalog storage filedaemon-lab director

docker compose \
    -f "$COMPOSE" \
    restart director

wait_running conectaeduca-bacula-catalog
wait_running conectaeduca-bacula-storage
wait_running conectaeduca-bacula-filedaemon-lab
wait_running conectaeduca-bacula-director


section "10. ESTADO E PRIVILEGIOS"

docker ps \
    --filter name=conectaeduca-bacula \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

echo
echo "--- FILE DAEMON PID 1 ---"

docker exec conectaeduca-bacula-filedaemon-lab \
    sh -c '
        grep -E "^(Name|Uid|Gid):" /proc/1/status
    '

echo
echo "--- SUPERFICIE ---"

for c in \
    conectaeduca-bacula-catalog \
    conectaeduca-bacula-storage \
    conectaeduca-bacula-director \
    conectaeduca-bacula-filedaemon-lab
do
    portas="$(docker port "$c" 2>/dev/null || true)"

    if [[ -n "$portas" ]]; then
        echo "$portas"
        fail "$c possui porta publicada no host"
    fi

    echo "OK: $c sem porta publicada no host."
done


section "11. DIRECTOR -> FILE DAEMON"

FD_STATUS="$(
    printf '%s\n' \
        'status client=conectaeduca-lab-fd' \
        'quit' \
        | bconsole 2>&1
)"

echo "$FD_STATUS"

grep -Eq     'conectaeduca-lab-fd Version|Daemon started|Connecting to Client'     <<<"$FD_STATUS" \
    || fail "bconsole não comprovou comunicação com o File Daemon"


section "12. PREPARANDO ARQUIVO SINTETICO"

docker run --rm \
    -v conectaeduca-bacula_fd-lab-source:/data \
    --entrypoint sh \
    "$DEBIAN_IMAGE" \
    -ec '
        rm -rf /data/*

        dd \
          if=/dev/urandom \
          of=/data/synthetic.bin \
          bs=1024 \
          count=128 \
          status=none

        chmod 0644 /data/synthetic.bin

        stat \
          -c "source_bytes=%s source_mode=%a" \
          /data/synthetic.bin
    '

docker run --rm \
    -v conectaeduca-bacula_fd-lab-restore:/restore \
    --entrypoint sh \
    "$DEBIAN_IMAGE" \
    -ec '
        rm -rf /restore/*
    '

HASH_ORIGINAL="$(
    docker run --rm \
        -v conectaeduca-bacula_fd-lab-source:/data:ro \
        --entrypoint sh \
        "$DEBIAN_IMAGE" \
        -ec '
            sha256sum /data/synthetic.bin | awk "{print \$1}"
        '
)"

echo "sha256_original=$HASH_ORIGINAL"


section "13. POOL E VOLUME BACULA"

POOL_EXISTE="$(
    docker exec conectaeduca-bacula-catalog \
        sh -c '
            psql \
              -U "$POSTGRES_USER" \
              -d "$POSTGRES_DB" \
              -Atc "
                SELECT count(*)
                FROM Pool
                WHERE Name = '\''LabPool'\'';
              "
        '
)"

echo "pool_lab_existente=$POOL_EXISTE"

if [[ "$POOL_EXISTE" == "0" ]]; then
    printf '%s\n' \
        'create pool=LabPool' \
        'quit' \
        | bconsole
fi

MEDIA_EXISTE="$(
    docker exec conectaeduca-bacula-catalog \
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

echo "volume_lab_existente=$MEDIA_EXISTE"

if [[ "$MEDIA_EXISTE" == "0" ]]; then

    printf '%s\n' \
        'label storage=ConectaEducaStorage pool=LabPool volume=LabVol001' \
        'quit' \
        | bconsole
fi


section "14. PRIMEIRO BACKUP REAL"

printf '%s\n' \
    'run job=LabSyntheticBackup level=Full yes' \
    'wait' \
    'quit' \
    | bconsole

BACKUP_ROW="$(
    docker exec conectaeduca-bacula-catalog \
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
                WHERE Name = '\''LabSyntheticBackup'\''
                ORDER BY JobId DESC
                LIMIT 1;
              "
        '
)"

echo "backup=$BACKUP_ROW"

IFS='|' read -r \
    BACKUP_JOBID \
    BACKUP_STATUS \
    BACKUP_FILES \
    BACKUP_BYTES \
    <<< "$BACKUP_ROW"

[[ -n "$BACKUP_JOBID" ]] \
    || fail "JobId do backup não encontrado"

[[ "$BACKUP_STATUS" == "T" ]] \
    || fail "backup terminou com status $BACKUP_STATUS"

[[ "$BACKUP_FILES" -ge 1 ]] \
    || fail "backup não registrou arquivos"

[[ "$BACKUP_BYTES" -gt 0 ]] \
    || fail "backup não registrou bytes"

echo "OK: backup real concluído."
echo "backup_jobid=$BACKUP_JOBID"


section "15. PROVA DE PERDA DO ORIGINAL"

docker run --rm \
    -v conectaeduca-bacula_fd-lab-source:/data \
    --entrypoint sh \
    "$DEBIAN_IMAGE" \
    -ec '
        rm -f /data/synthetic.bin

        test ! -e /data/synthetic.bin
    '

echo "OK: arquivo original removido do source."


section "16. RESTORE"

RESTORE_OUTPUT="$(
    printf '%s\n' \
        "restore jobid=${BACKUP_JOBID} client=conectaeduca-lab-fd fileset=LabSyntheticSet storage=ConectaEducaStorage pool=LabPool restoreclient=conectaeduca-lab-fd restorejob=LabSyntheticRestore where=/restore select all done yes" \
        'wait' \
        'messages' \
        'quit' \
        | bconsole 2>&1
)"

if grep -q 'Select item:' <<<"$RESTORE_OUTPUT"; then
    echo "$RESTORE_OUTPUT"
    fail "restore caiu inesperadamente em modo interativo"
fi

echo "$RESTORE_OUTPUT"

RESTORE_ROW="$(
    docker exec conectaeduca-bacula-catalog \
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
                WHERE Name = '\''LabSyntheticRestore'\''
                ORDER BY JobId DESC
                LIMIT 1;
              "
        '
)"

echo "restore=$RESTORE_ROW"

IFS='|' read -r \
    RESTORE_JOBID \
    RESTORE_STATUS \
    RESTORE_FILES \
    RESTORE_BYTES \
    <<< "$RESTORE_ROW"

[[ -n "$RESTORE_JOBID" ]] \
    || fail "JobId do restore não encontrado"

[[ "$RESTORE_STATUS" == "T" ]] \
    || fail "restore terminou com status $RESTORE_STATUS"


section "17. PROVA SHA-256 DO RESTORE"

RESTORED_PATH="$(
    docker run --rm \
        -v conectaeduca-bacula_fd-lab-restore:/restore:ro \
        --entrypoint sh \
        "$DEBIAN_IMAGE" \
        -ec '
            find /restore \
              -type f \
              -name synthetic.bin \
              -print \
              -quit
        '
)"

[[ -n "$RESTORED_PATH" ]] \
    || fail "synthetic.bin não apareceu no volume de restore"

echo "arquivo_restaurado=$RESTORED_PATH"

HASH_RESTAURADO="$(
    docker run --rm \
        -v conectaeduca-bacula_fd-lab-restore:/restore:ro \
        --entrypoint sh \
        "$DEBIAN_IMAGE" \
        -ec '
            f="$(
                find /restore \
                  -type f \
                  -name synthetic.bin \
                  -print \
                  -quit
            )"

            test -n "$f"

            sha256sum "$f" | awk "{print \$1}"
        '
)"

echo "sha256_original=$HASH_ORIGINAL"
echo "sha256_restaurado=$HASH_RESTAURADO"

[[ "$HASH_ORIGINAL" == "$HASH_RESTAURADO" ]] \
    || fail "SHA-256 do arquivo restaurado diverge do original"

echo "OK: SHA-256 restaurado é idêntico ao original."


section "18. ESTADO FINAL BACULA"

printf '%s\n' \
    'status director' \
    'status client=conectaeduca-lab-fd' \
    'status storage=ConectaEducaStorage' \
    'list jobs' \
    'quit' \
    | bconsole

echo
echo "--- VOLUMES ---"

docker volume ls \
    --format '{{.Name}}' \
    | grep '^conectaeduca-bacula_' \
    | sort

echo
echo "--- CONTAINERS ---"

docker ps \
    --filter name=conectaeduca-bacula \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'


section "19. GIT"

git status --short
git diff --check


section "RESULTADO"

echo "BACULA_BACKUP_JOBID=$BACKUP_JOBID"
echo "BACULA_RESTORE_JOBID=$RESTORE_JOBID"
echo "SHA256_MATCH=SIM"
echo "CHECKPOINT_RESULTADO=SUCESSO"
echo "ARQUIVO_SAIDA=$OUT"
