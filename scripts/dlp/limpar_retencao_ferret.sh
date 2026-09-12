#!/usr/bin/env bash
set -euo pipefail

ROOT="/opt/conectaeduca"
RUNTIME="${FERRET_RUNTIME_ROOT:-$ROOT/deploy/interna/ferret/.runtime}"
STATE="$RUNTIME/state"
INBOX="$RUNTIME/inbox"
RAW_DIR="$RUNTIME/reports/raw"
LEDGER="$STATE/processed.sha256"
HOLD="$STATE/retention.hold"

DAYS="${FERRET_RETENTION_DAYS:-7}"
MODE="${1:---dry-run}"

case "$MODE" in
  --dry-run) APPLY=0 ;;
  --apply) APPLY=1 ;;
  *)
    echo "Uso: $0 [--dry-run|--apply]" >&2
    exit 2
    ;;
esac

[[ "$(id -u)" == "1000" ]] || {
  echo "ERRO: execute este helper no boundary UID1000." >&2
  exit 1
}

[[ "$DAYS" =~ ^[0-9]+$ ]] && (( DAYS >= 1 )) || {
  echo "ERRO: FERRET_RETENTION_DAYS deve ser inteiro >= 1." >&2
  exit 1
}

for d in "$STATE" "$INBOX" "$RAW_DIR"; do
  [[ -d "$d" ]] || {
    echo "ERRO: diretório ausente: $d" >&2
    exit 1
  }
done

if [[ -e "$HOLD" ]]; then
  echo "HOLD: retenção suspensa por $HOLD"
  exit 0
fi

AGE_MINUTES=$(( DAYS * 1440 ))

remove_or_report(){
  local kind="$1"
  local path="$2"
  if [[ "$APPLY" -eq 1 ]]; then
    rm -f -- "$path"
    echo "REMOVED[$kind]: $(basename "$path")"
  else
    echo "WOULD_REMOVE[$kind]: $(basename "$path")"
  fi
}

ledger_has_full_hash(){
  local hash="$1"
  [[ -f "$LEDGER" ]] && grep -Fxq "$hash" "$LEDGER" 2>/dev/null
}

ledger_has_short_hash(){
  local short="$1"
  [[ -f "$LEDGER" ]] && grep -Eq "^${short}[0-9a-f]{48}$" "$LEDGER" 2>/dev/null
}

raw_candidates=0
while IFS= read -r -d '' path; do
  base="$(basename "$path")"
  stem="${base%.json}"
  short="${stem##*-}"

  if [[ "$short" =~ ^[0-9a-f]{16}$ ]] && ledger_has_short_hash "$short"; then
    raw_candidates=$((raw_candidates+1))
    remove_or_report raw_processed "$path"
  else
    echo "KEEP[raw_unconfirmed]: $base"
  fi
done < <(find "$RAW_DIR" -maxdepth 1 -type f -name '*.json' -mmin "+$AGE_MINUTES" -print0 2>/dev/null)

inbox_candidates=0
while IFS= read -r -d '' path; do
  hash="$(sha256sum "$path" | awk '{print $1}')"
  if ledger_has_full_hash "$hash"; then
    inbox_candidates=$((inbox_candidates+1))
    remove_or_report inbox_processed "$path"
  else
    echo "KEEP[inbox_unprocessed]: $(basename "$path")"
  fi
done < <(find "$INBOX" -maxdepth 1 -type f -mmin "+$AGE_MINUTES" -print0 2>/dev/null)

echo "SUMMARY: mode=$MODE retention_days=$DAYS raw_processed_candidates=$raw_candidates inbox_processed_candidates=$inbox_candidates"
