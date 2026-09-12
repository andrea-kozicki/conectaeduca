#!/usr/bin/env bash
set -euo pipefail

URL="${FERRET_HEALTH_URL:-http://127.0.0.1:18082/health}"
EXPECTED_VERSION="${FERRET_EXPECTED_VERSION:-2.4.3}"
CURL_BIN="${CURL_BIN:-$(command -v curl || true)}"

[[ -n "$CURL_BIN" ]] || {
  echo "ERRO: curl ausente." >&2
  exit 1
}

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

HTTP="$("$CURL_BIN" -sS --max-time 5 -o "$TMP" -w '%{http_code}' "$URL")"
[[ "$HTTP" == "200" ]] || {
  echo "ERRO: Ferret /health HTTP=$HTTP" >&2
  exit 1
}

python3 - "$TMP" "$EXPECTED_VERSION" <<'PY'
import json,sys
path,expected=sys.argv[1],sys.argv[2]
d=json.load(open(path,encoding="utf-8"))
if d.get("status")!="healthy":
    raise SystemExit("status != healthy")
if d.get("service")!="ferret-scan-web":
    raise SystemExit("service inesperado")
if str(d.get("version",""))!=expected:
    raise SystemExit("version inesperada")
PY

echo "PASS: Ferret /health healthy version=$EXPECTED_VERSION"
