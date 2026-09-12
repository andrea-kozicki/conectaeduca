#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERRO: execute dentro do repositório ConectaEduca." >&2
  exit 1
}
cd "$ROOT"

FERRET_UID=1000
COMPOSE="$ROOT/deploy/interna/ferret/compose.yml"
CONFIG="$ROOT/deploy/interna/ferret/config/ferret.yaml"
RUNTIME="$ROOT/deploy/interna/ferret/.runtime"
STATE="$RUNTIME/state"
INBOX="$RUNTIME/inbox"
RAW_DIR="$RUNTIME/reports/raw"
EVENTS_DIR="$RUNTIME/events"
EVENTS_FILE="${FERRET_EVENTS_FILE:-$EVENTS_DIR/dlp.jsonl}"
LEDGER_FILE="${FERRET_LEDGER_FILE:-$STATE/processed.sha256}"
SUPPRESSIONS="$STATE/suppressions.yaml"
SANITIZER="$ROOT/scripts/dlp/sanitizar_ferret.py"
PREP="$ROOT/scripts/bootstrap/preparar_ferret.sh"

as_ferret() {
  sudo -u "#${FERRET_UID}" -- "$@"
}

usage() {
  echo "Uso: $0 [--todos | --arquivo NOME] [--force]"
}

MODE="all"
ONLY_FILE=""
FORCE=0

while (($#)); do
  case "$1" in
    --todos)
      MODE="all"
      shift
      ;;
    --arquivo)
      [[ $# -ge 2 ]] || { echo "ERRO: --arquivo exige nome." >&2; exit 2; }
      MODE="one"
      ONLY_FILE="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERRO: argumento desconhecido: $1" >&2
      exit 2
      ;;
  esac
done

for required in "$COMPOSE" "$CONFIG" "$SANITIZER" "$PREP"; do
  [[ -f "$required" ]] || { echo "ERRO: arquivo ausente: $required" >&2; exit 1; }
done

# SUPPRESSIONS fica sob runtime 1000:1000/0700.
# O usuário host não deve atravessar esse diretório; valide no boundary correto.
as_ferret test -f "$SUPPRESSIONS" || {
  echo "ERRO: suppression file ausente ou inacessível ao UID1000: $SUPPRESSIONS" >&2
  exit 1
}

bash "$PREP" >/dev/null

IMAGE="$(docker compose -f "$COMPOSE" config --images | head -n1)"
[[ -n "$IMAGE" ]] || { echo "ERRO: imagem Ferret não resolvida." >&2; exit 1; }

process_one() {
  local file_path="$1"
  local basename_file file_hash stamp short_hash raw_basename raw_path
  local raw_tmp err_tmp scan_rc cname

  as_ferret test -f "$file_path" || {
    echo "AVISO: não é arquivo regular: $(basename "$file_path")" >&2
    return 0
  }

  basename_file="$(basename "$file_path")"
  file_hash="$(as_ferret sha256sum "$file_path" | awk '{print $1}')"
  [[ "$file_hash" =~ ^[0-9a-f]{64}$ ]] || {
    echo "ERRO: SHA-256 inválido." >&2
    return 1
  }

  if [[ "$FORCE" -ne 1 ]] && as_ferret test -f "$LEDGER_FILE"; then
    if as_ferret grep -Fxq "$file_hash" "$LEDGER_FILE" 2>/dev/null; then
      echo "INFO: artefato já processado; ignorado (file_id=${file_hash:0:12}...)."
      return 0
    fi
  fi

  stamp="$(date '+%Y%m%d-%H%M%S')"
  short_hash="${file_hash:0:16}"
  raw_basename="${stamp}-${short_hash}.json"
  raw_path="$RAW_DIR/$raw_basename"
  cname="conectaeduca-ferret-scan-${stamp}-${short_hash:0:8}"

  raw_tmp="$(mktemp)"
  err_tmp="$(mktemp)"
  chmod 0600 "$raw_tmp" "$err_tmp"

  cleanup_one() {
    rm -f "$raw_tmp" "$err_tmp" 2>/dev/null || true
  }

  echo "INFO: processando artefato file_id=${short_hash}..."

  set +e
  docker run \
    --rm \
    --name "$cname" \
    --network none \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --pids-limit 128 \
    --user 1000:1000 \
    --tmpfs /tmp:rw,nosuid,nodev,noexec,size=256m,uid=1000,gid=1000,mode=1770 \
    -v "$file_path:/scan/input:ro" \
    -v "$CONFIG:/etc/ferret/ferret.yaml:ro" \
    -v "$SUPPRESSIONS:/var/lib/ferret/suppressions.yaml:ro" \
    --entrypoint /ferret-scan \
    "$IMAGE" \
    --file /scan/input \
    --config /etc/ferret/ferret.yaml \
    --profile conectaeduca-deep \
    --format json \
    --no-color \
    --suppression-file /var/lib/ferret/suppressions.yaml \
    >"$raw_tmp" 2>"$err_tmp"
  scan_rc=$?
  set -e

  if [[ "$scan_rc" -ne 0 ]]; then
    echo "ERRO: Ferret falhou (rc=$scan_rc)." >&2
    tail -n 8 "$err_tmp" >&2 || true
    cleanup_one
    return 1
  fi

  python3 - "$raw_tmp" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
ok=isinstance(d,dict) and isinstance(d.get("results"),list) and isinstance(d.get("stats"),dict)
raise SystemExit(0 if ok else 1)
PY
  if [[ "$?" -ne 0 ]]; then
    echo "ERRO: stdout do Ferret não é JSON válido." >&2
    cleanup_one
    return 1
  fi

  sudo install -o 1000 -g 1000 -m 0600 "$raw_tmp" "$raw_path"

  raw_size="$(as_ferret stat -c '%s' "$raw_path" 2>/dev/null || echo 0)"
  if [[ ! "$raw_size" =~ ^[0-9]+$ ]] || (( raw_size <= 0 )); then
    echo "ERRO: raw instalado está vazio/inacessível." >&2
    cleanup_one
    return 1
  fi

  as_ferret python3 "$SANITIZER" \
    --input "$raw_path" \
    --output "$EVENTS_FILE" \
    --file-id "$file_hash"

  as_ferret chmod 0600 "$EVENTS_FILE"

  if ! as_ferret test -f "$LEDGER_FILE"; then
    as_ferret touch "$LEDGER_FILE"
    as_ferret chmod 0600 "$LEDGER_FILE"
  fi

  if ! as_ferret grep -Fxq "$file_hash" "$LEDGER_FILE" 2>/dev/null; then
    printf '%s\n' "$file_hash" | sudo -u "#${FERRET_UID}" -- tee -a "$LEDGER_FILE" >/dev/null
  fi

  cleanup_one
  echo "OK: file_id=${short_hash}... processado; raw local e evento sanitizado disponíveis."
}

failures=0
candidates=()

if [[ "$MODE" == "one" ]]; then
  requested_base="$(basename -- "$ONLY_FILE")"
  [[ "$requested_base" == "$ONLY_FILE" && "$ONLY_FILE" != "." && "$ONLY_FILE" != ".." ]] || {
    echo "ERRO: --arquivo aceita somente nome direto da inbox." >&2
    exit 2
  }
  candidate="$INBOX/$ONLY_FILE"
  as_ferret test -f "$candidate" || {
    echo "ERRO: arquivo não localizado na inbox: $ONLY_FILE" >&2
    exit 1
  }
  candidates+=("$candidate")
else
  while IFS= read -r -d '' candidate; do
    candidates+=("$candidate")
  done < <(as_ferret find "$INBOX" -maxdepth 1 -type f -print0 2>/dev/null)
fi

if [[ "${#candidates[@]}" -eq 0 ]]; then
  echo "INFO: inbox sem arquivos regulares."
  exit 0
fi

for candidate in "${candidates[@]}"; do
  process_one "$candidate" || failures=$((failures+1))
done

[[ "$failures" -eq 0 ]] || {
  echo "ERRO: $failures artefato(s) falharam." >&2
  exit 1
}
