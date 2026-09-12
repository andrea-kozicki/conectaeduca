#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERRO: execute dentro do repositório ConectaEduca." >&2
  exit 1
}
cd "$ROOT"

RUNTIME="$ROOT/deploy/interna/ferret/.runtime"
SANITIZER="$ROOT/scripts/dlp/sanitizar_ferret.py"

git check-ignore -q "deploy/interna/ferret/.runtime/prova-ignore" 2>/dev/null || {
  echo "ERRO: runtime Ferret não coberto pelo .gitignore." >&2
  exit 1
}

[[ -f "$SANITIZER" ]] || {
  echo "ERRO: sanitizador ausente." >&2
  exit 1
}

chmod 0755 "$SANITIZER"

sudo install -d -o 1000 -g 1000 -m 0700 \
  "$RUNTIME" \
  "$RUNTIME/state" \
  "$RUNTIME/inbox" \
  "$RUNTIME/reports" \
  "$RUNTIME/reports/raw" \
  "$RUNTIME/events"

for dir in \
  "$RUNTIME" \
  "$RUNTIME/state" \
  "$RUNTIME/inbox" \
  "$RUNTIME/reports" \
  "$RUNTIME/reports/raw" \
  "$RUNTIME/events"
do
  meta="$(sudo stat -c '%u:%g %a' "$dir")"
  [[ "$meta" == "1000:1000 700" ]] || {
    echo "ERRO: metadata inesperada em $dir: $meta" >&2
    exit 1
  }
done

echo "OK: runtime Ferret 1000:1000/0700; sanitizador 0755."
