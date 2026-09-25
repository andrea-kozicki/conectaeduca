#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POLICY="$ROOT/.semgrep/conectaeduca.yml"
SEMGREP_BIN="${SEMGREP_BIN:-semgrep}"
EXPECTED_VERSION="1.173.0"
AUDIT_REL="scripts/observabilidade/sanitizar_openbao_audit.py"
AUDIT_FILE="$ROOT/$AUDIT_REL"
TMP_DIR="$(mktemp -d -t conectaeduca-semgrep-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

ok() {
    printf 'OK          %s\n' "$*"
}

fail() {
    printf 'FALHA       %s\n' "$*" >&2
    exit 1
}

command -v git >/dev/null 2>&1 \
    || fail "git não encontrado"

GIT_TOP="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" \
    || fail "checkout Git não identificado a partir de $ROOT"
ROOT_REAL="$(cd "$ROOT" && pwd -P)"
GIT_TOP_REAL="$(cd "$GIT_TOP" && pwd -P)"
[[ "$ROOT_REAL" == "$GIT_TOP_REAL" ]] \
    || fail "script não está ancorado no root canônico do checkout"

[[ -f "$AUDIT_FILE" ]] \
    || fail "sanitizador OpenBao ausente: $AUDIT_REL"

SCAN_BRANCH="$(git -C "$ROOT" branch --show-current)"
[[ -n "$SCAN_BRANCH" ]] || SCAN_BRANCH="<detached>"
SCAN_HEAD="$(git -C "$ROOT" rev-parse HEAD)"
AUDIT_HEAD_BLOB="$(git -C "$ROOT" rev-parse "HEAD:$AUDIT_REL")" \
    || fail "arquivo $AUDIT_REL não existe no HEAD"
AUDIT_WORKING_BLOB="$(git -C "$ROOT" hash-object "$AUDIT_FILE")"
AUDIT_STATUS="$(git -C "$ROOT" status --porcelain=v1 -- "$AUDIT_REL")"
WORKTREE_STATUS="$(git -C "$ROOT" status --porcelain=v1 --untracked-files=all)"

[[ -z "$WORKTREE_STATUS" ]] \
    || fail "checkout possui alterações locais/untracked; scan abortado para preservar proveniência do HEAD"
[[ -z "$AUDIT_STATUS" ]] \
    || fail "$AUDIT_REL possui alteração local; scan abortado para evitar evidência ambígua"
[[ "$AUDIT_WORKING_BLOB" == "$AUDIT_HEAD_BLOB" ]] \
    || fail "$AUDIT_REL no worktree difere do blob registrado no HEAD"

ORIGIN_MAIN="$(git -C "$ROOT" rev-parse --verify refs/remotes/origin/main 2>/dev/null || true)"
SCAN_VS_ORIGIN_MAIN="unavailable"
if [[ -n "$ORIGIN_MAIN" ]]; then
    SCAN_VS_ORIGIN_MAIN="$(git -C "$ROOT" rev-list --left-right --count "$SCAN_HEAD...$ORIGIN_MAIN")"
    if [[ "$SCAN_BRANCH" == "main" && "$SCAN_HEAD" != "$ORIGIN_MAIN" ]]; then
        fail "branch main local difere de origin/main; atualize/reconcilie antes do scan canônico"
    fi
fi

printf 'SEMGREP_SCAN_ROOT=%s\n' "$ROOT_REAL"
printf 'SEMGREP_SCAN_BRANCH=%s\n' "$SCAN_BRANCH"
printf 'SEMGREP_SCAN_HEAD=%s\n' "$SCAN_HEAD"
printf 'SEMGREP_ORIGIN_MAIN=%s\n' "${ORIGIN_MAIN:-unavailable}"
printf 'SEMGREP_HEAD_VS_ORIGIN_MAIN=%s\n' "$SCAN_VS_ORIGIN_MAIN"
printf 'SEMGREP_AUDIT_REL=%s\n' "$AUDIT_REL"
printf 'SEMGREP_AUDIT_HEAD_BLOB=%s\n' "$AUDIT_HEAD_BLOB"
printf 'SEMGREP_AUDIT_WORKING_BLOB=%s\n' "$AUDIT_WORKING_BLOB"
printf 'SEMGREP_AUDIT_WORKTREE_DIRTY=NO\n'
printf 'SEMGREP_WORKTREE_CLEAN=YES\n'

command -v "$SEMGREP_BIN" >/dev/null 2>&1 \
    || fail "Semgrep não encontrado: $SEMGREP_BIN"

command -v python3 >/dev/null 2>&1 \
    || fail "python3 não encontrado"

python3 - <<'PY'
import sys

minimum = (3, 10)
if sys.version_info < minimum:
    print(
        "FALHA       Python incompatível: "
        f"{sys.version_info.major}.{sys.version_info.minor}; "
        "mínimo suportado=3.10",
        file=sys.stderr,
    )
    raise SystemExit(1)

print(
    "OK          Python runtime suportado: "
    f"{sys.version_info.major}.{sys.version_info.minor} (mínimo=3.10)"
)
PY

[[ -f "$POLICY" ]] \
    || fail "política Semgrep ausente: $POLICY"

VERSION="$("$SEMGREP_BIN" --version | head -n1 | tr -d '\r')"
[[ "$VERSION" == "$EXPECTED_VERSION" ]] \
    || fail "versão Semgrep inesperada: $VERSION (esperada: $EXPECTED_VERSION)"

ok "Semgrep $VERSION"

"$SEMGREP_BIN" --validate --config "$POLICY" >/dev/null
ok "política local válida"

PROJECT_JSON="$TMP_DIR/projeto.json"

set +e
"$SEMGREP_BIN" scan \
    --config "$POLICY" \
    --metrics=off \
    --error \
    --json \
    --output "$PROJECT_JSON" \
    "$ROOT"
PROJECT_RC=$?
set -e

[[ "$PROJECT_RC" -eq 0 ]] \
    || fail "projeto real apresentou achado bloqueante ou erro (rc=$PROJECT_RC)"

python3 - "$PROJECT_JSON" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
results = data.get("results", [])
errors = data.get("errors", [])

if errors:
    print(
        f"FALHA       Semgrep reportou {len(errors)} erro(s) no projeto",
        file=sys.stderr,
    )
    raise SystemExit(1)

if results:
    print(
        f"FALHA       Semgrep reportou {len(results)} achado(s) no projeto",
        file=sys.stderr,
    )
    raise SystemExit(1)

print("OK          projeto real sem achados bloqueantes")
PY

cat > "$TMP_DIR/inseguro.py" <<'PY'
import subprocess

user_input = input()
subprocess.run(user_input, shell=True)
eval(user_input)
PY

cat > "$TMP_DIR/inseguro.php" <<'PHP'
<?php
$userInput = $_GET['cmd'] ?? '';
eval($userInput);
try {
    throw new RuntimeException('detalhe interno');
} catch (Throwable $e) {
    echo $e->getMessage();
}
PHP

FIXTURE_JSON="$TMP_DIR/fixtures.json"

set +e
"$SEMGREP_BIN" scan \
    --config "$POLICY" \
    --metrics=off \
    --error \
    --json \
    --output "$FIXTURE_JSON" \
    "$TMP_DIR/inseguro.py" "$TMP_DIR/inseguro.php"
FIXTURE_RC=$?
set -e

[[ "$FIXTURE_RC" -eq 1 ]] \
    || fail "fixtures vulneráveis não produziram rc=1 (rc=$FIXTURE_RC)"

python3 - "$FIXTURE_JSON" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
results = data.get("results", [])
errors = data.get("errors", [])

if errors:
    print(
        f"FALHA       Semgrep reportou {len(errors)} erro(s) nas fixtures",
        file=sys.stderr,
    )
    raise SystemExit(1)

expected_suffixes = {
    "conectaeduca.php.eval",
    "conectaeduca.php.raw-exception-output",
    "conectaeduca.python.eval-exec",
    "conectaeduca.python.subprocess-shell-true",
}

found = set()
for result in results:
    check_id = result.get("check_id", "")
    for suffix in expected_suffixes:
        if check_id.endswith(suffix):
            found.add(suffix)

if len(results) != 4 or found != expected_suffixes:
    print(
        "FALHA       fixtures esperavam 4 achados/4 regras; "
        f"achados={len(results)} regras={sorted(found)}",
        file=sys.stderr,
    )
    raise SystemExit(1)

print("OK          controle positivo: 4 vulnerabilidades artificiais detectadas")
PY

printf '\nCHECKPOINT_SEMGREP_SAST=APROVADO\n'
printf 'PROJETO_REAL_FINDINGS=0\n'
printf 'FIXTURES_POSITIVAS_FINDINGS=4\n'
printf 'SEMGREP_VERSION=%s\n' "$VERSION"
printf 'PYTHON_RUNTIME_MIN=3.10\n'
printf 'SCAN_PROVENANCE=PASS\n'
printf 'SCAN_HEAD=%s\n' "$SCAN_HEAD"
printf 'SCAN_BRANCH=%s\n' "$SCAN_BRANCH"
printf 'AUDIT_HEAD_BLOB=%s\n' "$AUDIT_HEAD_BLOB"
