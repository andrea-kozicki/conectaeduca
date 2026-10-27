#!/usr/bin/env bash
# PA-07/GA-06: compatibilidade 206+207, EXCLUSIVAMENTE EM WORKTREE TEMPORARIO.
# Nenhuma VM, docker, token, merge em main ou push. Necessita GitHub remoto.
set -euo pipefail
export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_NOSYSTEM=1
umask 077

PR206_SHA='4def9c240b550a2942143f0d962d168bd1944f11'
PR207_SHA='f1a88a0f252c01b702113f0b0c5a5678db75ac51'
REPO="$(git rev-parse --show-toplevel)"
cd "$REPO"
git diff --quiet && git diff --cached --quiet || {
  echo 'PA07_CROSS_PR=FAIL reason=dirty_source_worktree' >&2; exit 2;
}
temp="$(mktemp -d)"
WT="$temp/worktree"
cleanup() {
  if [[ -d "$WT" ]]; then git worktree remove --force "$WT" >/dev/null 2>&1 || true; fi
  rm -rf -- "$temp"
}
trap cleanup EXIT HUP INT TERM

git fetch --no-tags origin main \
  '+refs/pull/206/head:refs/remotes/origin/pa07-test-pr206' \
  '+refs/pull/207/head:refs/remotes/origin/pa07-test-pr207' >/dev/null
actual206="$(git rev-parse refs/remotes/origin/pa07-test-pr206)"
actual207="$(git rev-parse refs/remotes/origin/pa07-test-pr207)"
if [[ "$actual206" != "$PR206_SHA" || "$actual207" != "$PR207_SHA" ]]; then
  printf 'PA07_CROSS_PR=FAIL reason=sha_drift expected206=%s actual206=%s expected207=%s actual207=%s\n' \
    "$PR206_SHA" "$actual206" "$PR207_SHA" "$actual207" >&2
  exit 3
fi

BASE_SHA="$(git rev-parse refs/remotes/origin/main)"
git worktree add --detach "$WT" "$BASE_SHA" >/dev/null
export GIT_AUTHOR_NAME='GA06 Offline CI'
export GIT_AUTHOR_EMAIL='ga06-offline@example.invalid'
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
for sha in "$PR207_SHA" "$PR206_SHA"; do
  if ! git -C "$WT" -c commit.gpgsign=false merge --no-ff --no-edit "$sha"; then
    echo 'PA07_CROSS_PR=FAIL reason=git_merge_conflict' >&2
    git -C "$WT" diff --name-only --diff-filter=U >&2 || true
    exit 4
  fi
done
cd "$WT"
echo 'PA07_RUNTIME_DEPLOYED=NAO'
echo "PA07_BASE_SHA=$BASE_SHA"
echo "PA07_PR206_SHA=$PR206_SHA"
echo "PA07_PR207_SHA=$PR207_SHA"
echo 'PA07_GIT_TEMP_MERGE=PASS'

python3 scripts/evidencias/validar_regras_dlp_confidence.py
python3 scripts/evidencias/ga06_validar_politica_tar.py

python3 - <<'PY'
import unittest

patterns = [
    "test_dlp_wazuh_contract_pr206.py",
    "test_ferret_sanitizer_ga06.py",
    "test_ga06_provenance_offline.py",
    "test_ferret_processor_negative_ga06.py",
    "test_ga06_offline_tar_policy.py",
]
suite = unittest.TestSuite()
for pattern in patterns:
    suite.addTests(unittest.TestLoader().discover("tests/python", pattern))
count = suite.countTestCases()
print(f"PA07_CROSS_PR_TEST_COUNT={count}", flush=True)
if count != 55:
    raise SystemExit("PA07_CROSS_PR=FAIL reason=expected_55_tests")
outcome = unittest.TextTestRunner(verbosity=2).run(suite)
if not outcome.wasSuccessful():
    raise SystemExit("PA07_CROSS_PR=FAIL reason=unit_tests_failed")
print("PA07_CROSS_PR=PASS 55/55 offline tests; no Docker/Wazuh Manager used")
PY
