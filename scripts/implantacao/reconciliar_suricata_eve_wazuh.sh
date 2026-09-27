#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

VERSION="1.0.0"
ACTION="${1:-check}"
CFG="${CONECTAEDUCA_SURICATA_CONFIG:-/etc/suricata/suricata.yaml}"
BACKUP_DIR="${CONECTAEDUCA_SURICATA_BACKUP_DIR:-/var/backups/conectaeduca/suricata}"
EXPECTED_HOSTS_REGEX="${CONECTAEDUCA_SURICATA_HOSTS_REGEX:-^(ep125-pucpr|conectaeduca-dmz)$}"
STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
HOST="$(hostname -s 2>/dev/null || hostname)"
OUT="${CONECTAEDUCA_EVIDENCE_DIR:-$HOME}/conectaeduca-suricata-eve-wazuh-${ACTION}-${HOST}-${STAMP}.txt"

PASS=0
WARN=0
FAIL=0
MUTATION_STARTED=0
ROLLBACK_USED=0
RESTART_USED=0
BACKUP=""
WORK=""

log() {
  printf '%s\n' "$*"
  if [[ "$ACTION" != "self-test" && "$ACTION" != "--self-test" ]]; then
    printf '%s\n' "$*" >>"$OUT"
  fi
}
pass() { PASS=$((PASS+1)); log "[PASS] $*"; }
warn() { WARN=$((WARN+1)); log "[WARN] $*"; }
fail() { FAIL=$((FAIL+1)); log "[FAIL] $*"; }

sha256_file() { sha256sum "$1" | awk '{print $1}'; }

usage() {
  cat <<'EOF'
Uso:
  reconciliar_suricata_eve_wazuh.sh check
  reconciliar_suricata_eve_wazuh.sh apply
  reconciliar_suricata_eve_wazuh.sh --self-test

check:
  somente leitura; valida que o eve-log NÃO exporta event_type=stats,
  que alert permanece e que o logger global de stats continua configurado.

apply:
  requer confirmação literal APPLY; cria backup, remove somente o item
  direto "- stats:" de outputs -> eve-log -> types, executa suricata -T,
  aplica atomicamente, reinicia apenas Suricata, valida e faz rollback
  automático se qualquer gate falhar.

Variáveis opcionais:
  CONECTAEDUCA_SURICATA_CONFIG
  CONECTAEDUCA_SURICATA_BACKUP_DIR
  CONECTAEDUCA_SURICATA_HOSTS_REGEX
  CONECTAEDUCA_EVIDENCE_DIR
EOF
}

render_candidate() {
  local src="$1"
  local dst="$2"
  local meta="$3"

  python3 - "$src" "$dst" "$meta" <<'PY'
from pathlib import Path
import json
import re
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
meta_path = Path(sys.argv[3])
lines = src.read_text(encoding="utf-8").splitlines(keepends=True)

def raw(i):
    return lines[i].rstrip("\n")

def indentation(s):
    return len(s) - len(s.lstrip(" "))

def ignored(s):
    return (not s.strip()) or s.lstrip().startswith("#")

outputs = [
    i for i, line in enumerate(lines)
    if indentation(line) == 0
    and re.match(r"^outputs:\s*(?:#.*)?$", raw(i))
]
if len(outputs) != 1:
    raise SystemExit(f"STRUCTURAL_FAIL top-level outputs={len(outputs)}")
o = outputs[0]

outputs_end = len(lines)
for i in range(o + 1, len(lines)):
    if ignored(lines[i]):
        continue
    if indentation(lines[i]) == 0:
        outputs_end = i
        break

list_items = [
    (i, indentation(lines[i]))
    for i in range(o + 1, outputs_end)
    if not ignored(lines[i]) and re.match(r"^\s*-\s+\S", raw(i))
]
if not list_items:
    raise SystemExit("STRUCTURAL_FAIL no list items under outputs")

direct_item_indent = min(ind for _, ind in list_items)
direct_items = [i for i, ind in list_items if ind == direct_item_indent]

eve = [
    i for i in direct_items
    if re.match(r"^\s*-\s+eve-log:\s*(?:#.*)?$", raw(i))
]
if len(eve) != 1:
    raise SystemExit(f"STRUCTURAL_FAIL direct eve-log={len(eve)}")
e = eve[0]

eve_end = outputs_end
for i in direct_items:
    if i > e:
        eve_end = i
        break

types_candidates = [
    (i, indentation(lines[i]))
    for i in range(e + 1, eve_end)
    if not ignored(lines[i])
    and re.match(r"^\s*types:\s*(?:#.*)?$", raw(i))
]
if not types_candidates:
    raise SystemExit("STRUCTURAL_FAIL no types under eve-log")

direct_types_indent = min(ind for _, ind in types_candidates)
direct_types = [i for i, ind in types_candidates if ind == direct_types_indent]
if len(direct_types) != 1:
    raise SystemExit(
        "STRUCTURAL_FAIL direct eve types="
        + ",".join(str(i + 1) for i in direct_types)
    )
t = direct_types[0]

types_end = eve_end
for i in range(t + 1, eve_end):
    if ignored(lines[i]):
        continue
    if indentation(lines[i]) <= direct_types_indent:
        types_end = i
        break

entries = [
    (i, indentation(lines[i]))
    for i in range(t + 1, types_end)
    if not ignored(lines[i]) and re.match(r"^\s*-\s+\S", raw(i))
]
if not entries:
    raise SystemExit("STRUCTURAL_FAIL no entries under eve-log.types")

direct_entry_indent = min(ind for _, ind in entries)
direct_entries = [i for i, ind in entries if ind == direct_entry_indent]

def entry_name(i):
    m = re.match(r"^\s*-\s+([A-Za-z0-9_-]+)\s*(?::.*)?$", raw(i))
    return m.group(1) if m else None

named = [(i, entry_name(i)) for i in direct_entries]
alerts = [i for i, name in named if name == "alert"]
stats = [i for i, name in named if name == "stats"]

if len(alerts) != 1:
    raise SystemExit(f"STRUCTURAL_FAIL direct alert={len(alerts)}")
if len(stats) > 1:
    raise SystemExit(f"STRUCTURAL_FAIL direct stats={len(stats)}")

result = {
    "outputs_line": o + 1,
    "eve_log_line": e + 1,
    "direct_types_line": t + 1,
    "types_candidates": [
        {"line": i + 1, "indent": ind}
        for i, ind in types_candidates
    ],
    "direct_entries": [
        {"line": i + 1, "name": name}
        for i, name in named
    ],
    "stats_present": bool(stats),
    "alert_present": any(name == "alert" for _, name in named),
}

if not stats:
    dst.write_text("".join(lines), encoding="utf-8")
    result["changed"] = False
    result["removed_lines"] = 0
    meta_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(0)

s = stats[0]
send = types_end
for i, _name in named:
    if i > s:
        send = i
        break

candidate = lines[:s] + lines[send:]
dst.write_text("".join(candidate), encoding="utf-8")

result["changed"] = True
result["stats_start_line"] = s + 1
result["stats_end_line"] = send
result["removed_lines"] = send - s
meta_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
PY
}

candidate_checks() {
  local original="$1"
  local candidate="$2"
  local meta="$3"

  python3 - "$original" "$candidate" "$meta" <<'PY'
from pathlib import Path
import difflib
import json
import re
import sys

original = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
candidate = Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
meta = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))

if not meta.get("alert_present"):
    raise SystemExit("CANDIDATE_FAIL alert not present before edit")

changed = bool(meta.get("changed"))
diff = list(difflib.unified_diff(original, candidate, n=0))
removed = [x[1:] for x in diff if x.startswith("-") and not x.startswith("---")]
added = [x[1:] for x in diff if x.startswith("+") and not x.startswith("+++")]

if not changed:
    if removed or added:
        raise SystemExit("CANDIDATE_FAIL idempotent candidate unexpectedly differs")
else:
    if added:
        raise SystemExit(f"CANDIDATE_FAIL added lines={added}")
    if not removed:
        raise SystemExit("CANDIDATE_FAIL no removed lines")
    if not re.match(r"^\s*-\s+stats\s*:", removed[0]):
        raise SystemExit("CANDIDATE_FAIL first removed line is not direct EVE stats")
    if len(removed) != int(meta.get("removed_lines", -1)):
        raise SystemExit("CANDIDATE_FAIL removal count mismatch")

top_stats = sum(bool(re.match(r"^  - stats:\s*(?:#.*)?$", x)) for x in candidate)
if top_stats < 1:
    raise SystemExit("CANDIDATE_FAIL global stats logger missing")

global_interval = sum(
    bool(re.match(r"^  interval:\s*8(?:\s|$)", x))
    for x in candidate
)
if global_interval < 1:
    raise SystemExit("CANDIDATE_FAIL global stats interval 8 missing")

tmp = "\n".join(candidate)
if not re.search(r"(?m)^\s*-\s+alert\s*:", tmp):
    raise SystemExit("CANDIDATE_FAIL alert item missing after edit")

print(f"CANDIDATE_CHANGED={'YES' if changed else 'NO'}")
print(f"DIFF_REMOVED_LINES={len(removed)}")
print(f"DIFF_ADDED_LINES={len(added)}")
print(f"OUTPUTS_LEVEL_STATS_LOGGER_COUNT={top_stats}")
print(f"GLOBAL_INTERVAL_8_COUNT={global_interval}")
print("CANDIDATE_SCOPE_CHECK=PASS")
PY
}

self_test() {
  local td src dst meta
  td="$(mktemp -d)"
  trap 'rm -rf "$td"' RETURN

  src="$td/source.yaml"
  dst="$td/candidate.yaml"
  meta="$td/meta.json"

  cat >"$src" <<'YAML'
stats:
  enabled: yes
  interval: 8

outputs:
  - fast:
      enabled: no
  - eve-log:
      enabled: yes
      types:
        - alert:
            tagged-packets: yes
            nested:
              types:
                - fake
        - dns:
            version: 2
        - stats:
            totals: yes
            threads: no
            deltas: no
        - flow
  - stats:
      enabled: yes
      filename: stats.log
YAML

  render_candidate "$src" "$dst" "$meta"
  candidate_checks "$src" "$dst" "$meta"

  grep -Eq '^[[:space:]]*-[[:space:]]+alert:' "$dst"     || { echo "SELF_TEST=FAIL alert_missing"; return 1; }
  if grep -Eq '^[[:space:]]{8}-[[:space:]]+stats:' "$dst"; then
    echo "SELF_TEST=FAIL eve_stats_remained"
    return 1
  fi
  grep -Eq '^  - stats:' "$dst"     || { echo "SELF_TEST=FAIL global_stats_missing"; return 1; }

  cp "$dst" "$td/reconciled.yaml"
  render_candidate "$td/reconciled.yaml" "$td/second.yaml" "$td/second.json"
  cmp -s "$td/reconciled.yaml" "$td/second.yaml"     || { echo "SELF_TEST=FAIL not_idempotent"; return 1; }

  echo "SELF_TEST_SURICATA_EVE_WAZUH=PASS"
}

if [[ "$ACTION" == "--self-test" || "$ACTION" == "self-test" ]]; then
  self_test
  exit $?
fi

case "$ACTION" in
  check|apply) ;;
  -h|--help|help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

mkdir -p "$(dirname "$OUT")"
: >"$OUT"
chmod 0600 "$OUT"

finish() {
  local rc=$?
  local final digest

  if [[ "$rc" -ne 0 && "$FAIL" -eq 0 ]]; then
    FAIL=$((FAIL+1))
  fi

  if (( FAIL > 0 )); then
    final="FAIL"
  elif (( WARN > 0 )); then
    final="WARN"
  else
    final="PASS"
  fi

  log ""
  log "=== SUMMARY ==="
  log "PASS=$PASS"
  log "WARN=$WARN"
  log "FAIL=$FAIL"
  log "MUTATION_STARTED=$MUTATION_STARTED"
  log "RESTART_USED=$RESTART_USED"
  log "ROLLBACK_USED=$ROLLBACK_USED"
  log "FINAL=$final"
  log "EVIDENCE_FILE=$OUT"

  digest="$(sha256_file "$OUT")"
  printf 'SHA256=%s\n' "$digest"
  if [[ -n "${WORK:-}" && -d "$WORK" ]]; then
    rm -rf -- "$WORK"
  fi
  exit "$rc"
}
trap finish EXIT

log "=== CONECTAEDUCA — SURICATA EVE -> WAZUH RECONCILER ==="
log "VERSION=$VERSION"
log "ACTION=$ACTION"
log "HOST=$HOST"
log "CONFIG=$CFG"
log "ROOT_SHELL_USED=0"
log "GLOBAL_SURICATA_STATS_TARGET=UNCHANGED"
log "WAZUH_DECODER_ORDER_SIZE_TARGET=UNCHANGED"

[[ "$HOST" =~ $EXPECTED_HOSTS_REGEX ]] || {
  fail "Host não autorizado para esta reconciliação: $HOST"
  exit 1
}
pass "Host DMZ autorizado."

for cmd in python3 sha256sum systemctl suricata sudo stat diff cmp install grep cp tail seq; do
  command -v "$cmd" >/dev/null 2>&1 || {
    fail "Comando ausente: $cmd"
    exit 1
  }
done
pass "Dependências locais disponíveis."

systemctl is-active --quiet suricata.service || {
  fail "suricata.service não está ativo."
  exit 1
}
pass "Suricata ativo."

systemctl is-active --quiet wazuh-agent.service || {
  fail "wazuh-agent.service não está ativo."
  exit 1
}
pass "Wazuh Agent ativo."

sudo -v
pass "sudo autenticado para comandos pontuais."

sudo -n test -f "$CFG" || {
  fail "Configuração ausente ou sudo não autenticado: $CFG"
  exit 1
}
sudo -n test ! -L "$CFG" || {
  fail "Configuração não pode ser symlink: $CFG"
  exit 1
}
pass "Arquivo de configuração localizado e não é symlink."

WORK="$(mktemp -d "$HOME/.conectaeduca-suricata-eve-wazuh-${STAMP}.XXXXXX")"
ORIGINAL="$WORK/original.yaml"
CANDIDATE="$WORK/candidate.yaml"
META="$WORK/meta.json"
sudo -n cat "$CFG" >"$ORIGINAL"
ORIGINAL_SHA="$(sha256_file "$ORIGINAL")"
LIVE_SHA="$(sudo -n sha256sum "$CFG" | awk '{print $1}')"
[[ "$ORIGINAL_SHA" == "$LIVE_SHA" ]] || {
  fail "Cópia offline divergiu do arquivo live."
  exit 1
}
pass "Snapshot offline bit-identical."

set +e
render_candidate "$ORIGINAL" "$CANDIDATE" "$META"
render_rc=$?
set -e
if (( render_rc != 0 )); then
  fail "Parser estrutural recusou a configuração."
  exit "$render_rc"
fi

candidate_checks "$ORIGINAL" "$CANDIDATE" "$META" >>"$OUT"
pass "Escopo estrutural do candidato validado."

CHANGED="$(
  python3 - "$META" <<'PY'
import json,sys
print("1" if json.load(open(sys.argv[1],encoding="utf-8")).get("changed") else "0")
PY
)"

if [[ "$CHANGED" == "0" ]]; then
  pass "EVE stats já está ausente; estado idempotente."
  sudo -n suricata -T -c "$CFG" >>"$OUT" 2>&1
  pass "Configuração live válida."
  log "SURICATA_EVE_STATS_RECONCILED=1"
  log "NEXT_GATE=VALIDATE_ANALYSISD_NO_FIELD_LIMIT_ERRORS"
  exit 0
fi

if [[ "$ACTION" == "check" ]]; then
  warn "EVE stats ainda está presente; APPLY necessário."
  log "SURICATA_EVE_STATS_RECONCILED=0"
  log "NEXT_GATE=RUN_APPLY"
  exit 10
fi

log ""
log "=== CANDIDATE DIFF ==="
diff -u "$ORIGINAL" "$CANDIDATE" | tee -a "$OUT" || true

sudo -n suricata -T -c "$CANDIDATE" >>"$OUT" 2>&1 || {
  fail "suricata -T rejeitou o candidato."
  exit 1
}
pass "Candidato aprovado pelo suricata -T."

printf 'Digite APPLY para remover somente EVE event_type=stats e reiniciar Suricata: '
read -r confirm
if [[ "$confirm" != "APPLY" ]]; then
  warn "APPLY cancelado pelo operador."
  exit 11
fi

NOW_SHA="$(sudo -n sha256sum "$CFG" | awk '{print $1}')"
[[ "$NOW_SHA" == "$LIVE_SHA" ]] || {
  fail "Configuração mudou durante o preflight; abortando."
  exit 1
}
pass "Configuração permaneceu estável antes da mutação."

sudo -n install -d -m 0750 "$BACKUP_DIR"
BACKUP="$BACKUP_DIR/suricata.yaml.pre-eve-wazuh-${STAMP}.bak"
sudo -n cp -a -- "$CFG" "$BACKUP"
BACKUP_SHA="$(sudo -n sha256sum "$BACKUP" | awk '{print $1}')"
[[ "$BACKUP_SHA" == "$LIVE_SHA" ]] || {
  fail "Backup não é bit-identical."
  exit 1
}
pass "Backup bit-identical criado: $BACKUP"

rollback() {
  ROLLBACK_USED=1
  warn "Rollback automático iniciado."
  sudo -n cp -a -- "$BACKUP" "$CFG" || return 1
  sudo -n suricata -T -c "$CFG" >/dev/null 2>&1 || return 1
  sudo -n systemctl restart suricata.service || return 1
  sleep 3
  systemctl is-active --quiet suricata.service || return 1
  return 0
}

MUTATION_STARTED=1
UID_CFG="$(sudo -n stat -c '%u' "$CFG")"
GID_CFG="$(sudo -n stat -c '%g' "$CFG")"
MODE_CFG="$(sudo -n stat -c '%a' "$CFG")"
STAGE="/etc/suricata/.suricata.yaml.conectaeduca-${STAMP}.new"

set +e
(
  # A transação roda em subshell com fail-fast explicitamente reativado.
  # O caller mantém errexit suspenso apenas para capturar apply_rc e executar
  # o rollback controlado abaixo.
  set -Eeuo pipefail

  sudo -n install -o "$UID_CFG" -g "$GID_CFG" -m "$MODE_CFG" "$CANDIDATE" "$STAGE"
  sudo -n mv -f -- "$STAGE" "$CFG"
  [[ "$(sudo -n sha256sum "$CFG" | awk '{print $1}')" == "$(sha256_file "$CANDIDATE")" ]]
  sudo -n suricata -T -c "$CFG"

  sudo -n systemctl restart suricata.service
  : >"$WORK/restart.used"

  new_pid=""
  for _ in $(seq 1 30); do
    if systemctl is-active --quiet suricata.service; then
      new_pid="$(systemctl show -p MainPID --value suricata.service)"
      [[ -n "$new_pid" && "$new_pid" != "0" ]] && break
    fi
    sleep 1
  done
  [[ -n "$new_pid" && "$new_pid" != "0" ]]

  sleep 4
  boundary_epoch="$(date +%s)"
  boundary_utc="$(date -u --iso-8601=seconds)"
  log "VALIDATION_BOUNDARY_UTC=$boundary_utc"
  sleep 28

  # Se tail falhar ou eve.json não for legível, errexit encerra a transação
  # antes do Python e força o caminho de rollback.
  sudo -n tail -n 6000 /var/log/suricata/eve.json >"$WORK/eve-post.jsonl"

  python3 - "$WORK/eve-post.jsonl" "$boundary_epoch" <<'PY'
import json
import sys
from datetime import datetime, timezone

path = sys.argv[1]
boundary = float(sys.argv[2])
events = stats = parse_errors = 0
counts = {}

for line in open(path, encoding="utf-8", errors="replace"):
    try:
        rec = json.loads(line)
    except Exception:
        parse_errors += 1
        continue
    raw = str(rec.get("timestamp", "")).replace("Z", "+00:00")
    try:
        value = datetime.fromisoformat(raw)
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        epoch = value.timestamp()
    except Exception:
        continue
    if epoch < boundary:
        continue
    events += 1
    kind = str(rec.get("event_type", "<missing>"))
    counts[kind] = counts.get(kind, 0) + 1
    if kind == "stats":
        stats += 1

print(f"POST_BOUNDARY_PARSE_ERRORS={parse_errors}")
print(f"POST_BOUNDARY_EVENTS={events}")
print(f"POST_BOUNDARY_STATS_EVENTS={stats}")
for kind in sorted(counts):
    print(f"POST_BOUNDARY_EVENT_TYPE={kind}|COUNT={counts[kind]}")

if stats:
    raise SystemExit(31)
PY
)
apply_rc=$?
set -e

if [[ -f "$WORK/restart.used" ]]; then
  RESTART_USED=1
fi

if (( apply_rc != 0 )); then
  fail "Validação pós-apply falhou; restaurando baseline."
  if rollback; then
    pass "Rollback automático concluído."
  else
    fail "Rollback automático falhou; intervenção manual necessária."
  fi
  exit 1
fi

pass "EVE stats removido e não reapareceu após boundary pós-restart."
pass "Suricata permaneceu ativo após a alteração."
pass "Wazuh Agent não foi reiniciado pelo reconciliador."

log "SURICATA_EVE_STATS_RECONCILED=1"
log "GLOBAL_SURICATA_STATS_CONFIG_CHANGED=0"
log "WAZUH_DECODER_ORDER_SIZE_CHANGED=0"
log "NEXT_GATE=VALIDATE_ANALYSISD_NO_FIELD_LIMIT_ERRORS"
