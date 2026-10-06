#!/usr/bin/env bash
# FREEZE-02 / EP126 - proveniencia final read-only + gate remoto antes da tag.
# Nao altera runtime. O unico efeito local e atualizar refs remotas via git fetch.

EXPECTED="c37bdce07a9ae71ceb1a1e0c8e0e1e2b51e112ce"
REPO="/opt/conectaeduca"
OUT="$HOME/Downloads"
[ -d "$OUT" ] || OUT="$HOME"
STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
REPORT="$OUT/conectaeduca-freeze02-ep126-provenance-$STAMP.txt"
FAIL=0

HOST="$(hostname)"
HEAD="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)"
BRANCH="$(git -C "$REPO" branch --show-current 2>/dev/null)"
DIRTY="$(git -C "$REPO" status --short 2>/dev/null)"

echo "=== FREEZE-02 / EP126 PROVENIENCIA FINAL ==="
echo "HOST=$HOST"
echo "HEAD=$HEAD"
echo "BRANCH=$BRANCH"

[ "$HOST" = "ep126-pucpr" ] || { echo "HOST_MATCH=FAIL"; FAIL=1; }
[ "$HEAD" = "$EXPECTED" ] || { echo "HEAD_MATCH=FAIL"; FAIL=1; }
[ "$BRANCH" = "main" ] || { echo "BRANCH_MAIN=FAIL"; FAIL=1; }
[ -z "$DIRTY" ] || { echo "WORKTREE_CLEAN=FAIL"; printf '%s\n' "$DIRTY"; FAIL=1; }

git -C "$REPO" fetch origin main
FETCH_RC=$?
echo "FETCH_ORIGIN_MAIN_RC=$FETCH_RC"
[ "$FETCH_RC" -eq 0 ] || FAIL=1

ORIGIN_MAIN="$(git -C "$REPO" rev-parse origin/main 2>/dev/null)"
echo "ORIGIN_MAIN=$ORIGIN_MAIN"
[ "$ORIGIN_MAIN" = "$EXPECTED" ] || { echo "ORIGIN_MAIN_MATCH=FAIL"; FAIL=1; }

CRITICAL=(
  conectaeduca-wazuh-wazuh.manager-1
  conectaeduca-wazuh-wazuh.indexer-1
  conectaeduca-wazuh-wazuh.dashboard-1
  conectaeduca-openbao
  conectaeduca-bacula-director
  conectaeduca-bacula-storage
  conectaeduca-bacula-catalog
  conectaeduca-bacula-pgbouncer
  conectaeduca-mariadb-mariadb-1
)

for NAME in "${CRITICAL[@]}"; do
  if docker ps --format '{{.Names}}' | grep -Fxq "$NAME"; then
    STATE="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$NAME" 2>/dev/null)"
    IMGREF="$(docker inspect -f '{{.Config.Image}}' "$NAME" 2>/dev/null)"
    IMGID="$(docker inspect -f '{{.Image}}' "$NAME" 2>/dev/null)"
    echo "CONTAINER=$NAME|STATE=$STATE|IMAGE_REF=$IMGREF|IMAGE_ID=$IMGID"
    case "$STATE" in healthy|running) ;; *) FAIL=1 ;; esac
  else
    echo "CONTAINER=$NAME|STATE=ABSENT"
    FAIL=1
  fi
done

echo "=== RUNNING EP126 CONTAINER IMAGE PROVENANCE ==="
while IFS= read -r NAME; do
  [ -n "$NAME" ] || continue
  IMGREF="$(docker inspect -f '{{.Config.Image}}' "$NAME" 2>/dev/null)"
  IMGID="$(docker inspect -f '{{.Image}}' "$NAME" 2>/dev/null)"
  REVD="$(docker image inspect "$IMGID" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' 2>/dev/null)"
  SOURCE="$(docker image inspect "$IMGID" --format '{{index .Config.Labels "org.opencontainers.image.source"}}' 2>/dev/null)"
  POLICY="$(docker image inspect "$IMGID" --format '{{index .Config.Labels "io.conectaeduca.build-policy"}}' 2>/dev/null)"
  DIGESTS="$(docker image inspect "$IMGID" --format '{{join .RepoDigests ","}}' 2>/dev/null)"
  [ -n "$REVD" ] || REVD="NO_REVISION_LABEL"
  [ -n "$SOURCE" ] || SOURCE="NO_SOURCE_LABEL"
  [ -n "$POLICY" ] || POLICY="NO_BUILD_POLICY_LABEL"
  [ -n "$DIGESTS" ] || DIGESTS="LOCAL_OR_UNPINNED_NO_REPODIGEST"
  echo "IMAGE_PROVENANCE=$NAME|REF=$IMGREF|ID=$IMGID|SOURCE=$SOURCE|REV=$REVD|POLICY=$POLICY|REPODIGESTS=$DIGESTS"
  if [ "$SOURCE" = "https://github.com/andrea-kozicki/conectaeduca" ] && [ "$REVD" != "$EXPECTED" ]; then
    echo "PROJECT_IMAGE_REVISION_MISMATCH=$NAME|REV=$REVD"
    FAIL=1
  fi
done < <(docker ps --format '{{.Names}}' | LC_ALL=C sort)

TWINGATE_RUNNING="$(docker ps --format '{{.Names}}' | grep -i twingate || true)"
if [ -z "$TWINGATE_RUNNING" ]; then
  echo "TWINGATE_RUNNING=NO"
else
  echo "TWINGATE_RUNNING=YES"
  printf '%s\n' "$TWINGATE_RUNNING"
  FAIL=1
fi

ENVF="$REPO/deploy/interna/bacula/.conectaeduca-storage-path.env"
if [ -f "$ENVF" ]; then
  echo "BACULA_STORAGE_ENV_PRESENT=YES"
else
  echo "BACULA_STORAGE_ENV_PRESENT=NO"
  FAIL=1
fi

MOUNT="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/backup"}}TYPE={{.Type}} SOURCE={{.Source}} DEST={{.Destination}} RW={{.RW}}{{end}}{{end}}' conectaeduca-bacula-storage 2>/dev/null)"
echo "BACULA_LIVE_BACKUP_MOUNT=$MOUNT"
[ "$MOUNT" = "TYPE=bind SOURCE=/srv/conectaeduca-backup/bacula/volumes DEST=/backup RW=true" ] || FAIL=1

DIRTY_AFTER="$(git -C "$REPO" status --short 2>/dev/null)"
[ -z "$DIRTY_AFTER" ] || FAIL=1

{
  echo "=== CONECTAEDUCA FREEZE-02 / EP126 PROVENIENCIA ==="
  echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "HOST=$HOST"
  echo "HEAD=$HEAD"
  echo "ORIGIN_MAIN=$ORIGIN_MAIN"
  echo "FETCH_ORIGIN_MAIN_RC=$FETCH_RC"
  echo "TWINGATE_RUNNING=$([ -z "$TWINGATE_RUNNING" ] && echo NO || echo YES)"
  echo "BACULA_STORAGE_ENV_PRESENT=$([ -f "$ENVF" ] && echo YES || echo NO)"
  echo "BACULA_LIVE_BACKUP_MOUNT=$MOUNT"
  while IFS= read -r NAME; do
    [ -n "$NAME" ] || continue
    IMGREF="$(docker inspect -f '{{.Config.Image}}' "$NAME" 2>/dev/null)"
    IMGID="$(docker inspect -f '{{.Image}}' "$NAME" 2>/dev/null)"
    REVD="$(docker image inspect "$IMGID" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' 2>/dev/null)"
    SOURCE="$(docker image inspect "$IMGID" --format '{{index .Config.Labels "org.opencontainers.image.source"}}' 2>/dev/null)"
    DIGESTS="$(docker image inspect "$IMGID" --format '{{join .RepoDigests ","}}' 2>/dev/null)"
    [ -n "$REVD" ] || REVD="NO_REVISION_LABEL"
    [ -n "$SOURCE" ] || SOURCE="NO_SOURCE_LABEL"
    [ -n "$DIGESTS" ] || DIGESTS="LOCAL_OR_UNPINNED_NO_REPODIGEST"
    echo "IMAGE=$NAME|REF=$IMGREF|ID=$IMGID|SOURCE=$SOURCE|REV=$REVD|REPODIGESTS=$DIGESTS"
  done < <(docker ps --format '{{.Names}}' | LC_ALL=C sort)
  echo "WORKTREE_CLEAN_AFTER=$([ -z "$DIRTY_AFTER" ] && echo PASS || echo FAIL)"
  if [ "$FAIL" -eq 0 ]; then
    echo "FREEZE02_EP126_PROVENANCE=PASS"
    echo "READY_FOR_TAG=YES"
  else
    echo "FREEZE02_EP126_PROVENANCE=FAIL"
    echo "READY_FOR_TAG=NO"
  fi
  echo "SECRET_VALUES_RECORDED=NO"
} > "$REPORT"

sha256sum "$REPORT" > "$REPORT.sha256"
echo "REPORT=$REPORT"
echo "REPORT_SHA256=$(awk '{print $1}' "$REPORT.sha256")"

[ "$FAIL" -eq 0 ]
