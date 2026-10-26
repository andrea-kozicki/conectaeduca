#!/usr/bin/env bash
# PA-03+PA-07: demonstra compatibilidade CI de PRs #206/#210 num worktree local.
# Nao toca main/remoto, VMs, Docker, Wazuh Manager nem recursos institucionais.
set -euo pipefail
export GIT_TERMINAL_PROMPT=0
umask 077
PR206_SHA='02f3a4d536a3a36eb06caef234b33a7d0c5aedee'
PR210_SHA='3455353cd7a9c3da602e19c90c3c0a6f608f68ec'
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
git diff --quiet && git diff --cached --quiet || { echo 'PA03_PA07=FAIL dirty_checkout' >&2; exit 2; }
TMP="$(mktemp -d)"
WT="$TMP/worktree"
cleanup() {
  if [[ -d "$WT" ]]; then git worktree remove --force "$WT" >/dev/null 2>&1 || true; fi
  rm -rf -- "$TMP"
}
trap cleanup EXIT HUP INT TERM

git fetch --no-tags origin main \
  '+refs/pull/206/head:refs/remotes/origin/compat-pr206' \
  '+refs/pull/210/head:refs/remotes/origin/compat-pr210' >/dev/null
[[ "$(git rev-parse refs/remotes/origin/compat-pr206)" == "$PR206_SHA" ]] || {
  echo 'PA03_PA07=FAIL sha_drift_pr206'; exit 3;
}
[[ "$(git rev-parse refs/remotes/origin/compat-pr210)" == "$PR210_SHA" ]] || {
  echo 'PA03_PA07=FAIL sha_drift_pr210'; exit 3;
}
BASE="$(git rev-parse refs/remotes/origin/main)"
git worktree add --detach "$WT" "$BASE" >/dev/null
export GIT_AUTHOR_NAME="ConectaEduca Offline CI"
export GIT_AUTHOR_EMAIL="offline@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
for sha in "$PR206_SHA" "$PR210_SHA"; do
  if ! git -C "$WT" -c commit.gpgsign=false merge --no-ff --no-edit "$sha"; then
    echo 'PA03_PA07=FAIL conflict' >&2
    git -C "$WT" diff --name-only --diff-filter=U >&2 || true
    exit 4
  fi
done
cd "$WT"
echo "PA03_PA07_BASE_SHA=$BASE"
echo "PA03_PA07_PR206_SHA=$PR206_SHA"
echo "PA03_PA07_PR210_SHA=$PR210_SHA"
echo 'PA03_PA07_MERGE_TEMP=PASS'
python3 - <<'PY'
from pathlib import Path
p = Path(".github/workflows/repository-static-integrity.yml")
content = p.read_text(encoding="utf-8")
for required in (
    "python3 scripts/evidencias/validar_regras_dlp_confidence.py",
    "test_dlp_wazuh_contract_pr206.py",
    "python3 scripts/evidencias/checkpoint_compose_security_invariants.py --self-test",
    "test_pa03_compose_inline_lists.py",
    "python3 scripts/evidencias/checkpoint_compose_security_invariants.py",
):
    if required not in content:
        raise SystemExit(f"PA03_PA07=FAIL missing_integrity_gate={required}")
print("PA03_PA07_BOTH_INTEGRITY_GATES=PASS")
PY
python3 scripts/evidencias/validar_regras_dlp_confidence.py
python3 scripts/evidencias/checkpoint_compose_security_invariants.py --self-test
python3 scripts/evidencias/checkpoint_compose_security_invariants.py
python3 - <<'PY'
import unittest
suite = unittest.TestSuite()
for pattern in ("test_dlp_wazuh_contract_pr206.py", "test_pa03_compose_inline_lists.py"):
    suite.addTests(unittest.TestLoader().discover("tests/python", pattern))
count = suite.countTestCases()
print(f"PA03_PA07_OFFLINE_TESTS={count}", flush=True)
if count != 27:
    raise SystemExit("PA03_PA07=FAIL expected_27_tests")
result = unittest.TextTestRunner(verbosity=2).run(suite)
if not result.wasSuccessful():
    raise SystemExit("PA03_PA07=FAIL unit_tests")
print("PA03_PA07=PASS offline integration 27/27")
PY
