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

FERRET_UID=1000
FERRET_SCAN_MEMORY_LIMIT="${FERRET_SCAN_MEMORY_LIMIT:-1280m}"
FERRET_SCAN_CPU_LIMIT="${FERRET_SCAN_CPU_LIMIT:-2.00}"
COMPOSE="$ROOT/deploy/interna/ferret/compose.yml"
CONFIG="$ROOT/deploy/interna/ferret/config/ferret.yaml"
RUNTIME="$ROOT/deploy/interna/ferret/.runtime"
STATE="$RUNTIME/state"
STAGING="$STATE/incoming"
INBOX="$RUNTIME/inbox"
RAW_DIR="$RUNTIME/reports/raw"
EVENTS_DIR="$RUNTIME/events"
EVENTS_FILE="${FERRET_EVENTS_FILE:-$EVENTS_DIR/dlp.jsonl}"
LEDGER_FILE="${FERRET_LEDGER_FILE:-$STATE/processed.sha256}"
RUN_LEDGER_FILE="${FERRET_RUN_LEDGER_FILE:-$STATE/processed-runs.tsv}"
SUPPRESSIONS="$STATE/suppressions.yaml"
SANITIZER="$ROOT/scripts/dlp/sanitizar_ferret.py"
SNAPSHOTTER="$ROOT/scripts/dlp/snapshot_ferret_input.py"
PREP="$ROOT/scripts/bootstrap/preparar_ferret.sh"

as_ferret() {
  sudo -u "#${FERRET_UID}" -- "$@"
}

ACTIVE_SNAPSHOTS=()
# Os temporarios brutos tambem precisam de limpeza em EXIT/sinais.
# O tracker nao guarda conteudo; apenas caminhos privados criados por mktemp.
ACTIVE_TEMP_FILES=()

cleanup_active_temp_files() {
  local candidate
  for candidate in "${ACTIVE_TEMP_FILES[@]:-}"; do
    [[ -z "$candidate" ]] || rm -f -- "$candidate" 2>/dev/null || true
  done
}

cleanup_active_snapshots() {
  local snapshot
  for snapshot in "${ACTIVE_SNAPSHOTS[@]:-}"; do
    [[ -z "$snapshot" ]] || as_ferret rm -f -- "$snapshot" 2>/dev/null || true
  done
}

cleanup_all() {
  cleanup_active_temp_files
  cleanup_active_snapshots
}

on_signal() {
  local code="$1"
  cleanup_all
  trap - EXIT HUP INT TERM
  exit "$code"
}

trap cleanup_all EXIT
trap 'on_signal 129' HUP
trap 'on_signal 130' INT
trap 'on_signal 143' TERM

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

for required in "$COMPOSE" "$CONFIG" "$SANITIZER" "$SNAPSHOTTER" "$PREP"; do
  [[ -f "$required" ]] || { echo "ERRO: arquivo ausente: $required" >&2; exit 1; }
done

# SUPPRESSIONS fica sob runtime 1000:1000/0700.
# O usuário host não deve atravessar esse diretório; valide no boundary correto.
as_ferret test -f "$SUPPRESSIONS" || {
  echo "ERRO: suppression file ausente ou inacessível ao UID1000: $SUPPRESSIONS" >&2
  exit 1
}

bash "$PREP" >/dev/null

STALE_TEMP_MINUTES="${FERRET_STALE_TEMP_MINUTES:-1440}"
[[ "$STALE_TEMP_MINUTES" =~ ^[0-9]+$ ]] && (( STALE_TEMP_MINUTES >= 60 )) || {
  echo "ERRO: FERRET_STALE_TEMP_MINUTES deve ser inteiro >= 60." >&2
  exit 1
}

reap_stale_temp() {
  local dir="$1"
  local pattern="$2"
  local kind="$3"
  local stale

  while IFS= read -r -d '' stale; do
    as_ferret rm -f -- "$stale"
    echo "INFO: temporario Ferret obsoleto removido [$kind]: $(basename "$stale")"
  done < <(
    as_ferret find "$dir" -xdev -maxdepth 1 -type f -name "$pattern" \
      -mmin "+$STALE_TEMP_MINUTES" -print0 2>/dev/null
  )
}

# Recuperação pós-crash/reboot/SIGKILL.
# O processor ignora uploads em andamento; apenas temporários suficientemente
# antigos são removidos, evitando disputar execuções recentes/concorrentes.
reap_stale_temp "$STAGING" '.snapshot-*' snapshot
reap_stale_temp "$INBOX" '.upload-*' upload

# Optional PA-07 candidate overlay: default stays on the digest-pinned upstream image.
# This also changes the ephemeral CLI scanner, not just the Web UI.
FERRET_COMPOSE_ARGS=(-f "$COMPOSE")
if [[ -n "${FERRET_COMPOSE_OVERRIDE:-}" ]]; then
  [[ -f "$FERRET_COMPOSE_OVERRIDE" ]] || {
    echo "ERRO: override Ferret inexistente: $FERRET_COMPOSE_OVERRIDE" >&2
    exit 1
  }
  FERRET_COMPOSE_ARGS+=(-f "$FERRET_COMPOSE_OVERRIDE")
fi
IMAGE="$(docker compose "${FERRET_COMPOSE_ARGS[@]}" config --images | head -n1)"
[[ -n "$IMAGE" ]] || { echo "ERRO: imagem Ferret não resolvida." >&2; exit 1; }

# Para a candidata local opt-in, nunca permitir pull implicito e vincular
# o scanner CLI ao Docker Image ID aprovado na custodia EP126 (Docker 29).
DOCKER_PULL_ARGS=()
if [[ "$IMAGE" == "localhost/conectaeduca/ferret-scan:2.4.3-pa07-v5-candidate" ]]; then
  python3 "$ROOT/scripts/evidencias/ga06_validar_politica_tar.py" >/dev/null || exit 1
  expected_id="$(python3 - "$ROOT/deploy/interna/ferret/pa07-v5/GA06_CANDIDATE_PROVENANCE.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fp:
    manifest = json.load(fp)
print("sha256:" + manifest["ep126_docker_descriptor_sha256"])
PY
)"
  actual_id="$(docker image inspect "$IMAGE" --format '{{.Id}}' 2>/dev/null)" || {
    echo "ERRO: imagem GA-06 local ausente; pull proibido." >&2
    exit 1
  }
  [[ "$actual_id" == "$expected_id" ]] || {
    echo "ERRO: Docker Image ID GA-06 divergente da custodia; scanner bloqueado." >&2
    exit 1
  }
  DOCKER_PULL_ARGS=(--pull=never)
fi

process_one() {
  local file_path="$1"
  local basename_file file_hash stamp short_hash raw_basename raw_path
  local raw_tmp err_tmp scan_rc cname snapshot_meta snapshot_path

  basename_file="$(basename "$file_path")"
  [[ "$basename_file" != "." && "$basename_file" != ".." ]] || {
    echo "ERRO: nome inválido na inbox." >&2
    return 1
  }
  if [[ "$basename_file" == .upload-* ]]; then
    echo "INFO: submissão ainda não publicada; ignorada: $basename_file"
    return 0
  fi

  # O processo pai escolhe e registra o pathname ANTES de iniciar a cópia.
  # Assim, qualquer EXIT/HUP/INT/TERM já conhece inclusive snapshots parciais.
  snapshot_path="$STAGING/.snapshot-${BASHPID}-${RANDOM}-${RANDOM}"
  ACTIVE_SNAPSHOTS+=("$snapshot_path")

  # Faz snapshot do inode aberto via openat(O_NOFOLLOW) em staging protegido.
  # O hash é calculado sobre o mesmo snapshot que será montado no scanner.
  snapshot_meta=""
  if ! snapshot_meta="$(as_ferret python3 "$SNAPSHOTTER" \
      --inbox "$INBOX" \
      --name "$basename_file" \
      --staging "$STAGING" \
      --output "$snapshot_path")"
  then
    as_ferret rm -f -- "$snapshot_path" 2>/dev/null || true
    echo "ERRO: não foi possível fixar snapshot protegido: $basename_file" >&2
    return 1
  fi

  file_hash="$snapshot_meta"
  [[ "$file_hash" =~ ^[0-9a-f]{64}$ ]] || {
    echo "ERRO: SHA-256 inválido no snapshot protegido." >&2
    as_ferret rm -f -- "$snapshot_path" 2>/dev/null || true
    return 1
  }

  raw_tmp=""
  err_tmp=""
  cleanup_one() {
    [[ -z "$raw_tmp" ]] || rm -f "$raw_tmp" 2>/dev/null || true
    [[ -z "$err_tmp" ]] || rm -f "$err_tmp" 2>/dev/null || true
    [[ -z "${snapshot_path:-}" ]] || as_ferret rm -f -- "$snapshot_path" 2>/dev/null || true
  }

  if [[ "$FORCE" -ne 1 ]] && as_ferret test -f "$LEDGER_FILE"; then
    if as_ferret grep -Fxq "$file_hash" "$LEDGER_FILE" 2>/dev/null; then
      echo "INFO: artefato já processado; ignorado (file_id=${file_hash:0:12}...)."
      cleanup_one
      return 0
    fi
  fi

  stamp="$(date '+%Y%m%d-%H%M%S')"
  short_hash="${file_hash:0:16}"
  raw_basename="${stamp}-${short_hash}.json"
  raw_path="$RAW_DIR/$raw_basename"
  cname="conectaeduca-ferret-scan-${stamp}-${short_hash:0:8}"

  raw_tmp="$(mktemp)"
  ACTIVE_TEMP_FILES+=("$raw_tmp")
  err_tmp="$(mktemp)"
  ACTIVE_TEMP_FILES+=("$err_tmp")
  chmod 0600 "$raw_tmp" "$err_tmp"

  echo "INFO: processando artefato file_id=${short_hash}..."

  set +e
  docker run \
    "${DOCKER_PULL_ARGS[@]}" \
    --rm \
    --name "$cname" \
    --network none \
    --memory "$FERRET_SCAN_MEMORY_LIMIT" \
    --cpus "$FERRET_SCAN_CPU_LIMIT" \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --pids-limit 128 \
    --user 1000:1000 \
    --tmpfs /home/ferret/tmp:rw,nosuid,nodev,noexec,size=256m,uid=1000,gid=1000,mode=0700 \
    -v "$snapshot_path:/scan/input:ro" \
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

  # A verificacao deve permanecer em contexto condicional: nunca depender
  # da excecao implicita de errexit quando process_one e chamado via '||'.
  if ! python3 - "$raw_tmp" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as fp:
    d=json.load(fp)
ok=isinstance(d,dict) and isinstance(d.get("results"),list) and isinstance(d.get("stats"),dict)
raise SystemExit(0 if ok else 1)
PY
  then
    echo "ERRO: stdout do Ferret não é JSON válido." >&2
    cleanup_one
    return 1
  fi

  if ! sudo install -o 1000 -g 1000 -m 0600 "$raw_tmp" "$raw_path"; then
    echo "ERRO: nao foi possivel instalar relatorio bruto com acesso restrito." >&2
    cleanup_one
    return 1
  fi

  raw_size="$(as_ferret stat -c '%s' "$raw_path" 2>/dev/null || echo 0)"
  if [[ ! "$raw_size" =~ ^[0-9]+$ ]] || (( raw_size <= 0 )); then
    echo "ERRO: raw instalado está vazio/inacessível." >&2
    cleanup_one
    return 1
  fi

  if ! as_ferret python3 "$SANITIZER" \
    --input "$raw_path" \
    --output "$EVENTS_FILE" \
    --file-id "$file_hash"
  then
    echo "ERRO: sanitização do relatório Ferret falhou; ledger não será atualizado." >&2
    cleanup_one
    return 1
  fi

  if ! as_ferret chmod 0600 "$EVENTS_FILE"; then
    echo "ERRO: nao foi possivel restringir permissoes do evento sanitizado." >&2
    cleanup_one
    return 1
  fi

  if ! as_ferret test -f "$LEDGER_FILE"; then
    as_ferret touch "$LEDGER_FILE"
    as_ferret chmod 0600 "$LEDGER_FILE"
  fi

  if ! as_ferret grep -Fxq "$file_hash" "$LEDGER_FILE" 2>/dev/null; then
    printf '%s\n' "$file_hash" | sudo -u "#${FERRET_UID}" -- tee -a "$LEDGER_FILE" >/dev/null
  fi

  if ! as_ferret test -f "$RUN_LEDGER_FILE"; then
    as_ferret touch "$RUN_LEDGER_FILE"
    as_ferret chmod 0600 "$RUN_LEDGER_FILE"
  fi
  printf '%s\t%s\t%s\n' "$raw_basename" "$file_hash" "$stamp" \
    | sudo -u "#${FERRET_UID}" -- tee -a "$RUN_LEDGER_FILE" >/dev/null

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