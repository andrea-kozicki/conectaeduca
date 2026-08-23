#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POLICY="$ROOT/.semgrep/conectaeduca.yml"
SEMGREP_BIN="${SEMGREP_BIN:-semgrep}"
EXPECTED_VERSION="1.173.0"
TMP_DIR="$(mktemp -d -t conectaeduca-semgrep-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

ok() {
    printf 'OK          %s\n' "$*"
}

fail() {
    printf 'FALHA       %s\n' "$*" >&2
    exit 1
}

command -v "$SEMGREP_BIN" >/dev/null 2>&1 \
    || fail "Semgrep não encontrado: $SEMGREP_BIN"

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
