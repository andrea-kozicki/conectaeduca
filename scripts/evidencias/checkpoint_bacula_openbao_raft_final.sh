#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/srv/www/htdocs/conectaeduca"
COMPOSE="$ROOT/deploy/interna/bacula/compose.yml"
OPENBAO_API="http://127.0.0.1:18200/v1"
OPENBAO_CONTAINER="conectaeduca-openbao"
POLICY="$ROOT/deploy/interna/openbao/policies/bacula-snapshot.hcl"

RUNTIME_DIR="$ROOT/deploy/interna/openbao/.runtime/bacula-snapshot"
ROLE_FILE="$RUNTIME_DIR/role-id"
SECRET_FILE="$RUNTIME_DIR/secret-id"

SOURCE_VOLUME="conectaeduca-bacula_fd-lab-source"
RESTORE_VOLUME="conectaeduca-bacula_fd-lab-restore"
DEBIAN_IMAGE="debian:trixie-slim@sha256:3a39a0592364683e6bab97937b72cad5a8fa6dcbbee90edb3bb48c7f8e94f258"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HOME/Downloads/conectaeduca-checkpoint-bacula-openbao-raft-final-$STAMP.txt"
SNAP_HOST="/dev/shm/conectaeduca-openbao-raft-final-$STAMP.snap"

cd "$ROOT"
exec > >(tee "$OUT") 2>&1

section() {
    printf '\n================================================================\n%s\n================================================================\n' "$1"
}

fail() {
    echo "FALHA: $*" >&2
    exit 1
}

bconsole() {
    timeout 180s docker compose \
        -f "$COMPOSE" \
        --profile tools \
        run --rm -T bconsole
}

cleanup() {
    set +e
    rm -f "$SNAP_HOST" >/dev/null 2>&1 || true

    docker run --rm \
        -v "$SOURCE_VOLUME:/data" \
        -v "$RESTORE_VOLUME:/restore" \
        --entrypoint sh \
        "$DEBIAN_IMAGE" \
        -ec '
          rm -rf \
            /data/workloads/openbao/raft \
            /data/workloads/openbao/custodia \
            /restore/*
        ' >/dev/null 2>&1 || true
}
trap cleanup EXIT

section "1. BASELINE"

echo "data=$(date --iso-8601=seconds)"
echo "branch=$(git branch --show-current)"
echo "head=$(git rev-parse HEAD)"

git diff --check

STATUS_JSON="$(
    docker exec \
        -e BAO_ADDR=http://127.0.0.1:8200 \
        "$OPENBAO_CONTAINER" \
        bao status -format=json
)"

python3 - "$STATUS_JSON" <<'PY'
import json,sys
x=json.loads(sys.argv[1])
print(
    "OPENBAO=initialized=%s|sealed=%s|version=%s|storage_type=%s"
    % (
        x.get("initialized"),
        x.get("sealed"),
        x.get("version"),
        x.get("storage_type"),
    )
)
if not (
    x.get("initialized") is True
    and x.get("sealed") is False
    and x.get("storage_type") == "raft"
):
    raise SystemExit(1)
PY

echo "OPENBAO_BASELINE=APROVADO"

section "2. APPROLE DE MINIMO PRIVILEGIO"

[[ -s "$POLICY" ]] || fail "policy ausente"
[[ -s "$ROLE_FILE" ]] || fail "RoleID ausente"
[[ -s "$SECRET_FILE" ]] || fail "SecretID ausente"

[[ "$(stat -c '%a' "$ROLE_FILE")" == "600" ]] \
    || fail "RoleID não está 0600"

[[ "$(stat -c '%a' "$SECRET_FILE")" == "600" ]] \
    || fail "SecretID não está 0600"

git check-ignore -q "$ROLE_FILE" || fail "RoleID não ignorado"
git check-ignore -q "$SECRET_FILE" || fail "SecretID não ignorado"

echo "APPROLE_RUNTIME=APROVADO|content=OCULTO"

section "3. SNAPSHOT RAFT VIA APPROLE"

python3 - \
    "$OPENBAO_API" \
    "$ROLE_FILE" \
    "$SECRET_FILE" \
    "$SNAP_HOST" <<'PY'
import hashlib,json,pathlib,sys,urllib.error,urllib.request

base=sys.argv[1].rstrip("/")
role=pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").strip()
secret=pathlib.Path(sys.argv[3]).read_text(encoding="utf-8").strip()
out=pathlib.Path(sys.argv[4])

def req(method,path,payload=None,token=None,raw=False):
    data=None if payload is None else json.dumps(payload).encode()
    headers={"Content-Type":"application/json"}
    if token:
        headers["X-Vault-Token"]=token
    q=urllib.request.Request(
        base+path,
        data=data,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(q,timeout=30) as r:
            body=r.read()
            return r.status, body if raw else (
                json.loads(body) if body else {}
            )
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{method} {path}: HTTP {e.code}")

_,login=req(
    "POST",
    "/auth/approle/login",
    {"role_id":role,"secret_id":secret},
)

token=(login.get("auth") or {}).get("client_token")
policies=(login.get("auth") or {}).get("policies") or []

if not token or "bacula-snapshot" not in policies or "default" in policies:
    raise RuntimeError("policies AppRole inesperadas")

code,blob=req(
    "GET",
    "/sys/storage/raft/snapshot",
    token=token,
    raw=True,
)

if code != 200 or len(blob) < 128:
    raise RuntimeError("snapshot inválido")

out.write_bytes(blob)
out.chmod(0o600)

print(f"SNAPSHOT_BYTES={len(blob)}")
print(f"SNAPSHOT_SHA256={hashlib.sha256(blob).hexdigest()}")
print("APPROLE_TOKEN_CONTENT=OCULTO")
PY

SNAP_HASH="$(sha256sum "$SNAP_HOST" | awk '{print $1}')"
SNAP_BYTES="$(stat -c '%s' "$SNAP_HOST")"

[[ "$SNAP_BYTES" -gt 0 ]] || fail "snapshot vazio"

echo "OPENBAO_RAFT_SNAPSHOT=APROVADO"

section "4. PREPARAR STAGING BACULA"

docker run --rm \
    -v "$SOURCE_VOLUME:/data" \
    -v "$RESTORE_VOLUME:/restore" \
    --entrypoint sh \
    "$DEBIAN_IMAGE" \
    -ec '
      rm -rf /data/workloads/openbao /restore/*
      install -d -o 100 -g 101 -m 0750 \
        /data/workloads/openbao/raft \
        /data/workloads/openbao/custodia
      printf "%s\n" "CANARY-UNSEAL-SHARE-NAO-BACKUP" \
        > /data/workloads/openbao/custodia/unseal-share-canary.txt
      chown 100:101 \
        /data/workloads/openbao/custodia/unseal-share-canary.txt
      chmod 0640 \
        /data/workloads/openbao/custodia/unseal-share-canary.txt
    '

cat "$SNAP_HOST" \
    | docker run \
        --rm \
        -i \
        -v "$SOURCE_VOLUME:/data" \
        --entrypoint sh \
        "$DEBIAN_IMAGE" \
        -ec '
          umask 027
          cat > /data/workloads/openbao/raft/openbao-raft.snap
          chown 100:101 /data/workloads/openbao/raft/openbao-raft.snap
          chmod 0640 /data/workloads/openbao/raft/openbao-raft.snap
        '

rm -f "$SNAP_HOST"

STAGED_HASH="$(
    docker run \
        --rm \
        -v "$SOURCE_VOLUME:/data:ro" \
        --entrypoint sh \
        "$DEBIAN_IMAGE" \
        -ec '
          sha256sum /data/workloads/openbao/raft/openbao-raft.snap \
            | awk "{print \$1}"
        '
)"

[[ "$STAGED_HASH" == "$SNAP_HASH" ]] \
    || fail "hash mudou no staging"

echo "STAGING_SHA256_MATCH=SIM"

section "5. BACULA OPERACIONAL"

fish scripts/bootstrap/preparar_bacula_core.fish
python3 scripts/bootstrap/materializar_bacula_core.py
python3 scripts/bootstrap/materializar_bacula_workloads_lab.py

docker compose \
    -f "$COMPOSE" \
    up -d \
    catalog \
    storage \
    filedaemon-lab \
    director

docker compose \
    -f "$COMPOSE" \
    restart director

sleep 4

for c in \
    conectaeduca-bacula-catalog \
    conectaeduca-bacula-storage \
    conectaeduca-bacula-filedaemon-lab \
    conectaeduca-bacula-director
do
    state="$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || true)"
    [[ "$state" == "running" ]] || fail "$c não está running"
    echo "BACULA=$c|state=running"
done

echo "BACULA_RUNTIME=APROVADO"

section "6. BACKUP SNAPSHOT"

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

echo "BACKUP_ROW=$BACKUP_ROW"

IFS='|' read -r \
    BACKUP_JOBID \
    BACKUP_STATUS \
    BACKUP_FILES \
    BACKUP_BYTES \
    <<< "$BACKUP_ROW"

[[ -n "$BACKUP_JOBID" ]] || fail "backup JobId ausente"
[[ "$BACKUP_STATUS" == "T" ]] || fail "backup status=$BACKUP_STATUS"
[[ "$BACKUP_FILES" -ge 1 ]] || fail "backup sem arquivos"
[[ "$BACKUP_BYTES" -gt 0 ]] || fail "backup sem bytes"

FILE_LIST="$(
    printf '%s\n' \
        "list files jobid=$BACKUP_JOBID" \
        'quit' \
        | bconsole \
        2>&1
)"

grep -Fq \
    '/data/workloads/openbao/raft/openbao-raft.snap' \
    <<< "$FILE_LIST" \
    || fail "snapshot não entrou no backup"

if grep -Fq \
    'unseal-share-canary.txt' \
    <<< "$FILE_LIST"
then
    fail "custódia entrou indevidamente no backup"
fi

echo "BACULA_BACKUP_OPENBAO=APROVADO"
echo "OPENBAO_CUSTODIA_EXCLUIDA=SIM"

section "7. PROVA DE PERDA"

docker run --rm \
    -v "$SOURCE_VOLUME:/data" \
    --entrypoint sh \
    "$DEBIAN_IMAGE" \
    -ec '
      rm -rf /data/workloads/openbao/raft
      test ! -e /data/workloads/openbao/raft/openbao-raft.snap
    '

echo "SNAPSHOT_ORIGINAL_REMOVIDO=SIM"

section "8. RESTORE BACULA"

RESTORE_OUTPUT="$(
    printf '%s\n' \
      "restore jobid=${BACKUP_JOBID} client=conectaeduca-lab-fd fileset=ConectaEducaArtifactsSet storage=ConectaEducaStorage pool=LabPool restoreclient=conectaeduca-lab-fd restorejob=ConectaEducaArtifactsRestore where=/restore select all done yes" \
      'wait' \
      'messages' \
      'quit' \
      | bconsole \
      2>&1
)"

if grep -Eq \
    'Select item:|Select FileSet resource|OK to run\?' \
    <<< "$RESTORE_OUTPUT"
then
    echo "$RESTORE_OUTPUT"
    fail "restore caiu em modo interativo"
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

echo "RESTORE_ROW=$RESTORE_ROW"

IFS='|' read -r \
    RESTORE_JOBID \
    RESTORE_STATUS \
    RESTORE_FILES \
    RESTORE_BYTES \
    <<< "$RESTORE_ROW"

[[ -n "$RESTORE_JOBID" ]] || fail "restore JobId ausente"
[[ "$RESTORE_STATUS" == "T" ]] || fail "restore status=$RESTORE_STATUS"

RESTORED_PATH="$(
    docker run \
        --rm \
        -v "$RESTORE_VOLUME:/restore:ro" \
        --entrypoint sh \
        "$DEBIAN_IMAGE" \
        -ec '
          find /restore \
            -type f \
            -name openbao-raft.snap \
            -print \
            -quit
        '
)"

[[ -n "$RESTORED_PATH" ]] || fail "snapshot restaurado não encontrado"

RESTORED_HASH="$(
    docker run \
        --rm \
        -v "$RESTORE_VOLUME:/restore:ro" \
        --entrypoint sh \
        "$DEBIAN_IMAGE" \
        -ec '
          f="$(find /restore -type f -name openbao-raft.snap -print -quit)"
          test -n "$f"
          sha256sum "$f" | awk "{print \$1}"
        '
)"

[[ "$SNAP_HASH" == "$RESTORED_HASH" ]] \
    || fail "SHA-256 restaurado diverge"

echo "SNAPSHOT_SHA256_ORIGINAL=$SNAP_HASH"
echo "SNAPSHOT_SHA256_RESTAURADO=$RESTORED_HASH"
echo "SNAPSHOT_SHA256_MATCH=SIM"
echo "BACULA_RESTORE_OPENBAO=APROVADO"

section "9. ESTADO FINAL"

STATUS_JSON="$(
    docker exec \
        -e BAO_ADDR=http://127.0.0.1:8200 \
        "$OPENBAO_CONTAINER" \
        bao status -format=json
)"

python3 - "$STATUS_JSON" <<'PY'
import json,sys
x=json.loads(sys.argv[1])
print(
    "OPENBAO_FINAL=initialized=%s|sealed=%s|version=%s|storage_type=%s"
    % (
        x.get("initialized"),
        x.get("sealed"),
        x.get("version"),
        x.get("storage_type"),
    )
)
if not (
    x.get("initialized") is True
    and x.get("sealed") is False
    and x.get("storage_type") == "raft"
):
    raise SystemExit(1)
PY

git check-ignore -q "$ROLE_FILE"
git check-ignore -q "$SECRET_FILE"
git diff --check

echo "CHECKPOINT_RESULTADO=SUCESSO"
echo "OPENBAO_APPROLE_MIN_PRIVILEGIO=SIM"
echo "OPENBAO_ROOT_TOKEN_ROTINA=NAO"
echo "OPENBAO_RAFT_SNAPSHOT=SIM"
echo "BACULA_OPENBAO_BACKUP_JOBID=$BACKUP_JOBID"
echo "BACULA_OPENBAO_RESTORE_JOBID=$RESTORE_JOBID"
echo "SNAPSHOT_SHA256_MATCH=SIM"
echo "OPENBAO_CUSTODIA_EXCLUIDA=SIM"
echo "ARQUIVO_SAIDA=$OUT"
