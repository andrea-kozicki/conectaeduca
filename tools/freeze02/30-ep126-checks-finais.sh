#!/usr/bin/env bash
# FREEZE-02 / EP126 - checks finais somente leitura
# Nao altera runtime. Twingate deve permanecer OFF.

EXPECTED_HEAD="c37bdce07a9ae71ceb1a1e0c8e0e1e2b51e112ce"
REPO="/opt/conectaeduca"
OUT="$HOME/Downloads"
[ -d "$OUT" ] || OUT="$HOME"
STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
REPORT="$OUT/conectaeduca-freeze02-ep126-checks-$STAMP.txt"
FAIL=0

echo "=== FREEZE-02 / EP126 CHECKS FINAIS ==="

HOST="$(hostname)"
HEAD="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)"
BRANCH="$(git -C "$REPO" branch --show-current 2>/dev/null)"
DIRTY="$(git -C "$REPO" status --short 2>/dev/null)"

[ "$HOST" = "ep126-pucpr" ] || { echo "HOST_MATCH=FAIL"; FAIL=1; }
[ "$HEAD" = "$EXPECTED_HEAD" ] || { echo "HEAD_MATCH=FAIL"; FAIL=1; }
[ "$BRANCH" = "main" ] || { echo "BRANCH_MAIN=FAIL"; FAIL=1; }
[ -z "$DIRTY" ] || { echo "WORKTREE_CLEAN=FAIL"; printf '%s\n' "$DIRTY"; FAIL=1; }

for NAME in   conectaeduca-wazuh-wazuh.manager-1   conectaeduca-wazuh-wazuh.indexer-1   conectaeduca-wazuh-wazuh.dashboard-1   conectaeduca-openbao   conectaeduca-bacula-director   conectaeduca-bacula-storage   conectaeduca-bacula-catalog   conectaeduca-bacula-pgbouncer   conectaeduca-mariadb-mariadb-1
do
  if docker ps --format '{{.Names}}' | grep -Fxq "$NAME"; then
    STATE="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$NAME" 2>/dev/null)"
    echo "SERVICE=$NAME|STATE=$STATE"
    case "$STATE" in
      healthy|running) ;;
      *) FAIL=1 ;;
    esac
  else
    echo "SERVICE=$NAME|STATE=ABSENT"
    FAIL=1
  fi
done

TWINGATE_RUNNING="$(docker ps --format '{{.Names}}' | grep -i twingate || true)"
if [ -z "$TWINGATE_RUNNING" ]; then
  echo "TWINGATE_RUNNING=NO"
else
  echo "TWINGATE_RUNNING=YES"
  printf '%s\n' "$TWINGATE_RUNNING"
  FAIL=1
fi

BAO_TMP="/tmp/conectaeduca-bao-health-$$"
BAO_CODE="$(curl -sS --max-time 5 -o "$BAO_TMP" -w '%{http_code}'   http://127.0.0.1:18200/v1/sys/health 2>/dev/null)"
rm -f "$BAO_TMP"
echo "OPENBAO_HEALTH_HTTP=$BAO_CODE"
case "$BAO_CODE" in
  200|429) echo "OPENBAO_HEALTH=PASS" ;;
  *) echo "OPENBAO_HEALTH=FAIL"; FAIL=1 ;;
esac

python3 "$REPO/scripts/evidencias/pentest_no_sudo_readiness.py"
READINESS_RC=$?
echo "PENTEST_NO_SUDO_READINESS_RC=$READINESS_RC"
[ "$READINESS_RC" -eq 0 ] || FAIL=1

python3 "$REPO/scripts/evidencias/pfsense_wazuh_postreboot_readonly.py"
PFSENSE_RC=$?
echo "PFSENSE_WAZUH_READONLY_RC=$PFSENSE_RC"
[ "$PFSENSE_RC" -eq 0 ] || FAIL=1

ENVF="$REPO/deploy/interna/bacula/.conectaeduca-storage-path.env"
MOUNT="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/backup"}}TYPE={{.Type}} SOURCE={{.Source}} DEST={{.Destination}} RW={{.RW}}{{end}}{{end}}' conectaeduca-bacula-storage 2>/dev/null)"
echo "BACULA_LIVE_BACKUP_MOUNT=$MOUNT"

case "$MOUNT" in
  "TYPE=bind SOURCE=/srv/conectaeduca-backup/bacula/volumes DEST=/backup RW=true")
    echo "BACULA_LIVE_STORAGE_BIND=PASS"
    ;;
  *)
    echo "BACULA_LIVE_STORAGE_BIND=FAIL"
    FAIL=1
    ;;
esac

if [ -f "$ENVF" ]; then
  echo "BACULA_STORAGE_ENV_PRESENT=YES"
  ENVLINE="$(cat "$ENVF" 2>/dev/null)"
  if printf '%s\n' "$ENVLINE" | grep -Eq "^CONECTAEDUCA_BACULA_STORAGE_PATH=['\"]?/srv/conectaeduca-backup/bacula/volumes['\"]?$"; then
    echo "BACULA_STORAGE_ENV_MATCH=PASS"
  else
    echo "BACULA_STORAGE_ENV_MATCH=FAIL"
    FAIL=1
  fi
else
  echo "BACULA_STORAGE_ENV_PRESENT=NO"
  echo "BACULA_STORAGE_ENV_DRIFT=DOCUMENT_FOR_HANDOFF"
fi

{
  echo "=== CONECTAEDUCA FREEZE-02 / EP126 CHECKS ==="
  echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "HOST=$HOST"
  echo "HEAD=$HEAD"
  echo "OPENBAO_HEALTH_HTTP=$BAO_CODE"
  echo "TWINGATE_RUNNING=$([ -z "$TWINGATE_RUNNING" ] && echo NO || echo YES)"
  echo "PENTEST_NO_SUDO_READINESS_RC=$READINESS_RC"
  echo "PFSENSE_WAZUH_READONLY_RC=$PFSENSE_RC"
  echo "BACULA_LIVE_BACKUP_MOUNT=$MOUNT"
  echo "BACULA_STORAGE_ENV_PRESENT=$([ -f "$ENVF" ] && echo YES || echo NO)"
  if [ "$FAIL" -eq 0 ]; then
    echo "FREEZE02_EP126_FINAL_CHECKS=PASS"
  else
    echo "FREEZE02_EP126_FINAL_CHECKS=FAIL"
  fi
  echo "SECRET_VALUES_RECORDED=NO"
} > "$REPORT"

sha256sum "$REPORT" > "$REPORT.sha256"
echo "REPORT=$REPORT"
echo "REPORT_SHA256=$(awk '{print $1}' "$REPORT.sha256")"

[ "$FAIL" -eq 0 ]
