#!/usr/bin/env bash
# FREEZE-02 / EP125 - proveniencia final read-only + gate remoto antes da tag.
# Nao altera runtime. O unico efeito local e atualizar refs remotas via git fetch.

EXPECTED="c37bdce07a9ae71ceb1a1e0c8e0e1e2b51e112ce"
REPO="/opt/conectaeduca"
OUT="$HOME/Downloads"
[ -d "$OUT" ] || OUT="$HOME"
STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
REPORT="$OUT/conectaeduca-freeze02-ep125-provenance-$STAMP.txt"
FAIL=0

HOST="$(hostname)"
HEAD="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)"
BRANCH="$(git -C "$REPO" branch --show-current 2>/dev/null)"
DIRTY="$(git -C "$REPO" status --short 2>/dev/null)"

echo "=== FREEZE-02 / EP125 PROVENIENCIA FINAL ==="
echo "HOST=$HOST"
echo "HEAD=$HEAD"
echo "BRANCH=$BRANCH"

[ "$HOST" = "ep125-pucpr" ] || { echo "HOST_MATCH=FAIL"; FAIL=1; }
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

for IMG in conectaeduca/php-fpm:dmz conectaeduca/nginx:dmz conectaeduca/waf:dmz; do
  if docker image inspect "$IMG" >/dev/null 2>&1; then
    IID="$(docker image inspect "$IMG" --format '{{.Id}}')"
    REV="$(docker image inspect "$IMG" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')"
    POLICY="$(docker image inspect "$IMG" --format '{{index .Config.Labels "io.conectaeduca.build-policy"}}')"
    DIGESTS="$(docker image inspect "$IMG" --format '{{join .RepoDigests ","}}')"
    [ -n "$DIGESTS" ] || DIGESTS="LOCAL_BUILD_NO_REPODIGEST"
    echo "IMAGE=$IMG|ID=$IID|REV=$REV|POLICY=$POLICY|REPODIGESTS=$DIGESTS"
    if [ "$REV" = "$EXPECTED" ]; then
      echo "IMAGE_REVISION=$IMG|PASS"
    else
      echo "IMAGE_REVISION=$IMG|FAIL"
      FAIL=1
    fi
  else
    echo "IMAGE=$IMG|ABSENT"
    FAIL=1
  fi
done

echo "=== RUNNING DMZ CONTAINERS ==="
docker ps --format '{{.Names}}|IMAGE={{.Image}}|CONTAINER_ID={{.ID}}|STATUS={{.Status}}' | grep '^conectaeduca-dmz-' || true

DIRTY_AFTER="$(git -C "$REPO" status --short 2>/dev/null)"
[ -z "$DIRTY_AFTER" ] || FAIL=1

{
  echo "=== CONECTAEDUCA FREEZE-02 / EP125 PROVENIENCIA ==="
  echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "HOST=$HOST"
  echo "HEAD=$HEAD"
  echo "ORIGIN_MAIN=$ORIGIN_MAIN"
  echo "FETCH_ORIGIN_MAIN_RC=$FETCH_RC"
  for IMG in conectaeduca/php-fpm:dmz conectaeduca/nginx:dmz conectaeduca/waf:dmz; do
    if docker image inspect "$IMG" >/dev/null 2>&1; then
      IID="$(docker image inspect "$IMG" --format '{{.Id}}')"
      REV="$(docker image inspect "$IMG" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')"
      POLICY="$(docker image inspect "$IMG" --format '{{index .Config.Labels "io.conectaeduca.build-policy"}}')"
      DIGESTS="$(docker image inspect "$IMG" --format '{{join .RepoDigests ","}}')"
      [ -n "$DIGESTS" ] || DIGESTS="LOCAL_BUILD_NO_REPODIGEST"
      echo "IMAGE=$IMG|ID=$IID|REV=$REV|POLICY=$POLICY|REPODIGESTS=$DIGESTS"
    fi
  done
  echo "WORKTREE_CLEAN_AFTER=$([ -z "$DIRTY_AFTER" ] && echo PASS || echo FAIL)"
  if [ "$FAIL" -eq 0 ]; then
    echo "FREEZE02_EP125_PROVENANCE=PASS"
    echo "READY_FOR_TAG=YES"
  else
    echo "FREEZE02_EP125_PROVENANCE=FAIL"
    echo "READY_FOR_TAG=NO"
  fi
  echo "SECRET_VALUES_RECORDED=NO"
} > "$REPORT"

sha256sum "$REPORT" > "$REPORT.sha256"
echo "REPORT=$REPORT"
echo "REPORT_SHA256=$(awk '{print $1}' "$REPORT.sha256")"

[ "$FAIL" -eq 0 ]
