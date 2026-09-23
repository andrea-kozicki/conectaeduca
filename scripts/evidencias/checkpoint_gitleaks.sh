#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_VERSION="8.30.1"
ROOT="$(git rev-parse --show-toplevel)"
CONFIG="${ROOT}/.gitleaks.toml"
TMP="$(mktemp -d -t conectaeduca-gitleaks-gate-XXXXXX)"

cleanup() {
  rm -rf "${TMP}"
}
trap cleanup EXIT

die() {
  echo "FAIL: $*" >&2
  exit 1
}

print_safe_findings() {
  local scope="$1"
  local report="$2"

  python3 - "${scope}" "${report}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

scope = sys.argv[1]
report = Path(sys.argv[2])

if not report.is_file() or report.stat().st_size == 0:
    print(f"GITLEAKS_DIAGNOSTIC|scope={scope}|report=empty")
    raise SystemExit(0)

try:
    data = json.loads(report.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"GITLEAKS_DIAGNOSTIC|scope={scope}|report=parse_error|type={type(exc).__name__}")
    raise SystemExit(0)

if not isinstance(data, list):
    print(f"GITLEAKS_DIAGNOSTIC|scope={scope}|report=unexpected_shape")
    raise SystemExit(0)

print(f"GITLEAKS_FINDING_COUNT|scope={scope}|count={len(data)}")

def clean(value: object) -> str:
    text = "" if value is None else str(value)
    return (
        text.replace("\r", " ")
        .replace("\n", " ")
        .replace("|", "%7C")
    )

for item in data:
    if not isinstance(item, dict):
        continue

    # Deliberadamente NÃO imprimir Secret, Match, Entropy nem Fingerprint.
    rule = clean(item.get("RuleID"))
    file = clean(item.get("File"))
    line = clean(item.get("StartLine"))
    commit = clean(item.get("Commit"))

    print(
        "GITLEAKS_FINDING"
        f"|scope={scope}"
        f"|rule={rule}"
        f"|file={file}"
        f"|line={line}"
        f"|commit={commit}"
    )
PY
}

command -v gitleaks >/dev/null 2>&1 || die "gitleaks não encontrado no PATH."
command -v openssl >/dev/null 2>&1 || die "openssl não encontrado."
command -v python3 >/dev/null 2>&1 || die "python3 não encontrado."
[[ -f "${CONFIG}" ]] || die ".gitleaks.toml ausente."

VERSION="$(gitleaks version)"
[[ "${VERSION}" == *"${EXPECTED_VERSION}"* ]] \
  || die "versão Gitleaks inesperada: ${VERSION}"

echo "GITLEAKS_VERSION=${VERSION}"

GIT_REPORT="${TMP}/git-report.json"
set +e
gitleaks git \
  --no-banner \
  --no-color \
  --redact=100 \
  --report-format json \
  --report-path "${GIT_REPORT}" \
  --config "${CONFIG}" \
  "${ROOT}"
RC_GIT=$?
set -e

if [[ "${RC_GIT}" -ne 0 ]]; then
  print_safe_findings "git" "${GIT_REPORT}"
  die "Gitleaks encontrou achados no histórico/ref atual."
fi

echo "GITLEAKS_GIT_CURRENT_REF=APROVADO"

TRACKED_TREE="${TMP}/tracked-tree"
mkdir -p "${TRACKED_TREE}"

(
  cd "${ROOT}"
  git ls-files -z \
    | tar --null -T - -cf -
) | tar -C "${TRACKED_TREE}" -xf -

DIR_REPORT="${TMP}/dir-report.json"
set +e
gitleaks dir \
  --no-banner \
  --no-color \
  --redact=100 \
  --report-format json \
  --report-path "${DIR_REPORT}" \
  --config "${CONFIG}" \
  "${TRACKED_TREE}"
RC_DIR=$?
set -e

if [[ "${RC_DIR}" -ne 0 ]]; then
  print_safe_findings "tracked-tree" "${DIR_REPORT}"
  die "Gitleaks encontrou achados na árvore versionada atual."
fi

echo "GITLEAKS_DIR_TRACKED_TREE=APROVADO"

mkdir -p "${TMP}/negative"
openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:2048 \
  -out "${TMP}/negative/ephemeral-private-key.pem" \
  >/dev/null 2>&1
chmod 0600 "${TMP}/negative/ephemeral-private-key.pem"

set +e
gitleaks dir \
  --no-banner \
  --no-color \
  --redact=100 \
  --config "${CONFIG}" \
  "${TMP}/negative" \
  >/dev/null 2>&1
RC_NEG=$?
set -e

[[ "${RC_NEG}" -eq 1 ]] \
  || die "controle negativo falhou; private key efêmera não foi bloqueada."

echo "GITLEAKS_NEGATIVE_CONTROL=APROVADO"
echo "GITLEAKS_GATE=APROVADO"
