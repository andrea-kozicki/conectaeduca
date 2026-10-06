#!/usr/bin/env bash
# FREEZE-02 / EP126 - rematerializa somente o env-file do Storage Bacula.
#
# Uso seguro no freeze:
# - valida host, SHA, branch e worktree;
# - valida o mount live exato do Storage antes de escrever;
# - grava apenas o path nao-sensivel do bind;
# - usa sudo somente no install pontual do arquivo root:root 0644;
# - nao recria containers, nao para servicos e nao altera Git tracked.

EXPECTED_HEAD="c37bdce07a9ae71ceb1a1e0c8e0e1e2b51e112ce"
REPO="/opt/conectaeduca"
BACULA_DIR="$REPO/deploy/interna/bacula"
ENVF="$BACULA_DIR/.conectaeduca-storage-path.env"
TARGET="/srv/conectaeduca-backup/bacula/volumes"
STORAGE="conectaeduca-bacula-storage"
OUT="$HOME/Downloads"
[ -d "$OUT" ] || OUT="$HOME"
STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
REPORT="$OUT/conectaeduca-freeze02-bacula-env-$STAMP.txt"
TMP="$(mktemp -t conectaeduca-bacula-env-XXXXXX)"
FAIL=0

cleanup() {
  rm -f "$TMP"
}
trap cleanup EXIT

echo "=== FREEZE-02 / EP126 BACULA ENV REMATERIALIZATION ==="

HOST="$(hostname)"
HEAD="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)"
BRANCH="$(git -C "$REPO" branch --show-current 2>/dev/null)"
DIRTY="$(git -C "$REPO" status --short 2>/dev/null)"

echo "HOST=$HOST"
echo "HEAD=$HEAD"
echo "BRANCH=$BRANCH"

[ "$HOST" = "ep126-pucpr" ] || { echo "HOST_MATCH=FAIL"; FAIL=1; }
[ "$HEAD" = "$EXPECTED_HEAD" ] || { echo "HEAD_MATCH=FAIL"; FAIL=1; }
[ "$BRANCH" = "main" ] || { echo "BRANCH_MAIN=FAIL"; FAIL=1; }
[ -z "$DIRTY" ] || { echo "WORKTREE_CLEAN_BEFORE=FAIL"; printf '%s\n' "$DIRTY"; FAIL=1; }

STATE="$(docker inspect -f '{{.State.Running}}' "$STORAGE" 2>/dev/null)"
MOUNT="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/backup"}}TYPE={{.Type}} SOURCE={{.Source}} DEST={{.Destination}} RW={{.RW}}{{end}}{{end}}' "$STORAGE" 2>/dev/null)"

echo "STORAGE_RUNNING=$STATE"
echo "BACULA_LIVE_BACKUP_MOUNT=$MOUNT"

[ "$STATE" = "true" ] || { echo "STORAGE_RUNNING_CHECK=FAIL"; FAIL=1; }

EXPECTED_MOUNT="TYPE=bind SOURCE=$TARGET DEST=/backup RW=true"
if [ "$MOUNT" = "$EXPECTED_MOUNT" ]; then
  echo "BACULA_LIVE_STORAGE_BIND=PASS"
else
  echo "BACULA_LIVE_STORAGE_BIND=FAIL"
  FAIL=1
fi

REL_ENV="deploy/interna/bacula/.conectaeduca-storage-path.env"
EXCLUDE_FILE="$REPO/.git/info/exclude"

git -C "$REPO" check-ignore -q "$REL_ENV"
IGNORED_RC=$?

if [ "$IGNORED_RC" -ne 0 ] && [ "$FAIL" -eq 0 ]; then
  if ! grep -Fxq "/$REL_ENV" "$EXCLUDE_FILE" 2>/dev/null; then
    printf '\n/%s\n' "$REL_ENV" >> "$EXCLUDE_FILE"
  fi
  git -C "$REPO" check-ignore -q "$REL_ENV"
  IGNORED_RC=$?
  if [ "$IGNORED_RC" -eq 0 ]; then
    echo "ENV_FILE_LOCAL_EXCLUDE_ADDED=YES"
  fi
fi

if [ "$IGNORED_RC" -eq 0 ]; then
  echo "ENV_FILE_GIT_IGNORED=PASS"
else
  echo "ENV_FILE_GIT_IGNORED=FAIL"
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  printf "CONECTAEDUCA_BACULA_STORAGE_PATH='%s'\n" "$TARGET" > "$TMP"
  chmod 0600 "$TMP"

  sudo install -o root -g root -m 0644 "$TMP" "$ENVF"
  INSTALL_RC=$?
  echo "ENV_INSTALL_RC=$INSTALL_RC"
  [ "$INSTALL_RC" -eq 0 ] || FAIL=1
else
  INSTALL_RC=99
fi

if [ "$FAIL" -eq 0 ]; then
  EXPECTED_LINE="CONECTAEDUCA_BACULA_STORAGE_PATH='$TARGET'"
  ACTUAL_LINE="$(cat "$ENVF" 2>/dev/null)"
  META="$(stat -c '%U:%G %a' "$ENVF" 2>/dev/null)"
  echo "ENV_META=$META"

  if [ "$ACTUAL_LINE" = "$EXPECTED_LINE" ]; then
    echo "ENV_CONTENT=PASS"
  else
    echo "ENV_CONTENT=FAIL"
    FAIL=1
  fi

  if [ "$META" = "root:root 644" ]; then
    echo "ENV_OWNER_MODE=PASS"
  else
    echo "ENV_OWNER_MODE=FAIL"
    FAIL=1
  fi
fi

DIRTY_AFTER="$(git -C "$REPO" status --short 2>/dev/null)"
if [ -z "$DIRTY_AFTER" ]; then
  echo "WORKTREE_CLEAN_AFTER=PASS"
else
  echo "WORKTREE_CLEAN_AFTER=FAIL"
  printf '%s\n' "$DIRTY_AFTER"
  FAIL=1
fi

{
  echo "=== CONECTAEDUCA FREEZE-02 / BACULA STORAGE PATH ENV ==="
  echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "HOST=$HOST"
  echo "HEAD=$HEAD"
  echo "BRANCH=$BRANCH"
  echo "STORAGE_RUNNING=$STATE"
  echo "BACULA_LIVE_BACKUP_MOUNT=$MOUNT"
  echo "ENV_FILE=$ENVF"
  echo "ENV_INSTALL_RC=$INSTALL_RC"
  echo "ENV_FILE_GIT_IGNORED=$([ "$IGNORED_RC" -eq 0 ] && echo PASS || echo FAIL)"
  echo "WORKTREE_CLEAN_AFTER=$([ -z "$DIRTY_AFTER" ] && echo PASS || echo FAIL)"
  if [ "$FAIL" -eq 0 ]; then
    echo "FREEZE02_BACULA_STORAGE_ENV=PASS"
  else
    echo "FREEZE02_BACULA_STORAGE_ENV=FAIL"
  fi
  echo "SECRET_VALUES_RECORDED=NO"
} > "$REPORT"

sha256sum "$REPORT" > "$REPORT.sha256"
echo "REPORT=$REPORT"
echo "REPORT_SHA256=$(awk '{print $1}' "$REPORT.sha256")"

[ "$FAIL" -eq 0 ]
