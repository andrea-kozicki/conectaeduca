#!/usr/bin/env bash
set -euo pipefail

BIND_ADDRESS="${FERRET_BIND_ADDRESS:-127.0.0.1}"
WEB_PORT="${FERRET_WEB_PORT:-18082}"

case "$BIND_ADDRESS" in
  0.0.0.0) PROBE_HOST="127.0.0.1" ;;
  ::|[::]) PROBE_HOST="[::1]" ;;
  *:*)
    case "$BIND_ADDRESS" in
      [*]) PROBE_HOST="$BIND_ADDRESS" ;;
      *) PROBE_HOST="[$BIND_ADDRESS]" ;;
    esac
    ;;
  *) PROBE_HOST="$BIND_ADDRESS" ;;
esac

URL="${FERRET_HEALTH_URL:-http://${PROBE_HOST}:${WEB_PORT}/health}"
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
