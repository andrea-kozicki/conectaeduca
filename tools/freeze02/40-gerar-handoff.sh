#!/usr/bin/env bash
# FREEZE-02 - gerar e verificar handoff canonico no host atual.
# EP125 -> dmz | EP126 -> interna
# Nao altera main e usa o SHA congelado explicitamente.

EXPECTED_HEAD="c37bdce07a9ae71ceb1a1e0c8e0e1e2b51e112ce"
REPO="/opt/conectaeduca"
OUT="$HOME/Downloads"
[ -d "$OUT" ] || OUT="$HOME"
STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
FAIL=0

HOST="$(hostname)"
case "$HOST" in
  ep125-pucpr) TARGET="dmz" ;;
  ep126-pucpr) TARGET="interna" ;;
  *) TARGET="unsupported"; FAIL=1 ;;
esac

HEAD="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)"
BRANCH="$(git -C "$REPO" branch --show-current 2>/dev/null)"
DIRTY="$(git -C "$REPO" status --short 2>/dev/null)"

echo "HOST=$HOST"
echo "TARGET=$TARGET"
echo "HEAD=$HEAD"
echo "BRANCH=$BRANCH"

[ "$HEAD" = "$EXPECTED_HEAD" ] || { echo "HEAD_MATCH=FAIL"; FAIL=1; }
[ "$BRANCH" = "main" ] || { echo "BRANCH_MAIN=FAIL"; FAIL=1; }
[ -z "$DIRTY" ] || { echo "WORKTREE_CLEAN=FAIL"; printf '%s\n' "$DIRTY"; FAIL=1; }

GEN_LOG="$OUT/conectaeduca-freeze02-handoff-$TARGET-$STAMP.log"
REPORT="$OUT/conectaeduca-freeze02-handoff-$TARGET-$STAMP.txt"
GEN_RC=99
VERIFY_RC=99
BUNDLE=""

if [ "$FAIL" -eq 0 ]; then
  (
    cd "$REPO" || return 1
    scripts/release/gerar_handoff.sh "$TARGET" "$OUT" "$EXPECTED_HEAD"
  ) > "$GEN_LOG" 2>&1
  GEN_RC=$?
  cat "$GEN_LOG"
  echo "HANDOFF_GENERATE_RC=$GEN_RC"
  [ "$GEN_RC" -eq 0 ] || FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  BUNDLE="$(tail -n 1 "$GEN_LOG" 2>/dev/null)"
  if [ -f "$BUNDLE" ]; then
    (
      cd "$REPO" || return 1
      scripts/release/verificar_handoff.sh "$BUNDLE" "$TARGET"
    )
    VERIFY_RC=$?
    echo "HANDOFF_VERIFY_RC=$VERIFY_RC"
    [ "$VERIFY_RC" -eq 0 ] || FAIL=1
  else
    echo "HANDOFF_BUNDLE_RESOLUTION=FAIL"
    FAIL=1
  fi
fi

{
  echo "=== CONECTAEDUCA FREEZE-02 / HANDOFF ==="
  echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "HOST=$HOST"
  echo "TARGET=$TARGET"
  echo "HEAD=$HEAD"
  echo "HANDOFF_GENERATE_RC=$GEN_RC"
  echo "HANDOFF_VERIFY_RC=$VERIFY_RC"
  if [ -f "$BUNDLE" ]; then
    echo "BUNDLE=$BUNDLE"
    echo "BUNDLE_SHA256=$(sha256sum "$BUNDLE" | awk '{print $1}')"
  fi
  if [ "$FAIL" -eq 0 ]; then
    echo "FREEZE02_HANDOFF=PASS"
  else
    echo "FREEZE02_HANDOFF=FAIL"
  fi
  echo "SECRET_VALUES_RECORDED=NO"
} > "$REPORT"

sha256sum "$REPORT" > "$REPORT.sha256"
echo "REPORT=$REPORT"
echo "REPORT_SHA256=$(awk '{print $1}' "$REPORT.sha256")"

[ "$FAIL" -eq 0 ]
