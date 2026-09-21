#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEFAULT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
ROOT="${PROJECT_ROOT:-$DEFAULT_ROOT}"

[[ -d "$ROOT/deploy/interna/ferret" ]] || {
  echo "ERRO: raiz ConectaEduca inválida: $ROOT" >&2
  exit 1
}

cd "$ROOT"

RUNTIME="$ROOT/deploy/interna/ferret/.runtime"
SANITIZER="$ROOT/scripts/dlp/sanitizar_ferret.py"

ROOT_REAL="$(cd -- "$ROOT" && pwd -P)"
GIT_TOP=""
GIT_TOP_REAL=""
if command -v git >/dev/null 2>&1; then
  GIT_TOP="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$GIT_TOP" ]]; then
    GIT_TOP_REAL="$(cd -- "$GIT_TOP" && pwd -P)" || GIT_TOP_REAL=""
  fi
fi

if [[ -n "$GIT_TOP_REAL" && "$GIT_TOP_REAL" == "$ROOT_REAL" ]]; then
  git -C "$ROOT" check-ignore -q "deploy/interna/ferret/.runtime/prova-ignore" 2>/dev/null || {
    echo "ERRO: runtime Ferret não coberto pelo .gitignore." >&2
    exit 1
  }
else
  META="$ROOT/RELEASE-METADATA.txt"
  [[ -f "$META" ]] || {
    echo "ERRO: execução fora de Git exige RELEASE-METADATA.txt." >&2
    exit 1
  }
  grep -Fxq 'runtime_secrets_included=no' "$META" || {
    echo "ERRO: metadata não comprova exclusão de runtime secrets." >&2
    exit 1
  }
fi

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
