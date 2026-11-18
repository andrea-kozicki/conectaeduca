#!/usr/bin/env bash
# ConectaEduca GA-06 / PA-07 — source-only UI V4/V5 regression gate.
# NO Docker, Podman, Git write, VM access or deployment.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UPSTREAM_COMMIT="a5156d1950df19276e6cfd8335603d73187a3841"
UPSTREAM_APP_BLOB="68192bc16891887240089e08634b5d41bf2588c1"
SOURCE_URL="https://raw.githubusercontent.com/awslabs/ferret-scan/$UPSTREAM_COMMIT/internal/web/assets/app.js"
for binary in curl git node awk grep mktemp; do
  command -v "$binary" >/dev/null 2>&1 || { echo "MISSING_TOOL=$binary" >&2; exit 2; }
done
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/internal/web/assets"
APP="$WORK/internal/web/assets/app.js"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  --max-time 40 --retry 2 "$SOURCE_URL" -o "$APP"
ACTUAL="$(git hash-object "$APP")"
if [ "$ACTUAL" != "$UPSTREAM_APP_BLOB" ]; then
  echo "FAIL_CLOSED=UPSTREAM_BLOB_MISMATCH expected=$UPSTREAM_APP_BLOB observed=$ACTUAL" >&2
  exit 1
fi
echo "UPSTREAM_PIN=PASS $UPSTREAM_COMMIT"

# V4 is a complete patch against upstream 2.4.3. V5 is only a delta on V4.
(
  cd "$WORK"
  git apply --check "$ROOT/deploy/interna/ferret/patches/ferret_pa07_v4.patch"
  git apply "$ROOT/deploy/interna/ferret/patches/ferret_pa07_v4.patch"
)
node --check "$APP"
grep -q '^function filterResults(filter) {' "$APP" || { echo "MISSING_FRAGMENT_BOUNDARY=filterResults" >&2; exit 1; }
FRAGMENT="$WORK/ferret-ui-test-fragment.js"
awk '/^function filterResults\(filter\) \{/ {exit} {print}' "$APP" > "$FRAGMENT"
node --check "$FRAGMENT"
echo "V4_PATCH_AND_SYNTAX=PASS"
FERRET_APP_JS="$FRAGMENT" node --test "$ROOT/tests/js/ferret-pa07-v4.test.cjs"

(
  cd "$WORK"
  git apply --check "$ROOT/deploy/interna/ferret/patches/ferret_pa07_v5_on_v4.patch"
  git apply "$ROOT/deploy/interna/ferret/patches/ferret_pa07_v5_on_v4.patch"
)
node --check "$APP"
grep -q '^function exportResults() {' "$APP" || { echo "MISSING_FRAGMENT_BOUNDARY=exportResults" >&2; exit 1; }
grep -q '^function showHelp() {' "$APP" || { echo "MISSING_FRAGMENT_BOUNDARY=showHelp" >&2; exit 1; }
awk '/^function filterResults\(filter\) \{/ {exit} {print}' "$APP" > "$FRAGMENT"
awk '/^function exportResults\(\) \{/ {flag=1}
  flag && /^function showHelp\(\) \{/ {exit}
  flag {print}' "$APP" >> "$FRAGMENT"
node --check "$FRAGMENT"
echo "V5_PATCH_AND_SYNTAX=PASS"
FERRET_APP_JS="$FRAGMENT" node --test "$ROOT/tests/js/ferret-pa07-v5.test.cjs"
echo "GA06_UI_SOURCE_GATE=PASS"
