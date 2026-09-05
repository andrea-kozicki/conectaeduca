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

command -v gitleaks >/dev/null 2>&1 || die "gitleaks não encontrado no PATH."
command -v openssl >/dev/null 2>&1 || die "openssl não encontrado."
[[ -f "${CONFIG}" ]] || die ".gitleaks.toml ausente."

VERSION="$(gitleaks version)"
[[ "${VERSION}" == *"${EXPECTED_VERSION}"* ]] \
  || die "versão Gitleaks inesperada: ${VERSION}"

echo "GITLEAKS_VERSION=${VERSION}"

gitleaks git \
  --no-banner \
  --no-color \
  --redact=100 \
  --config "${CONFIG}" \
  "${ROOT}"

echo "GITLEAKS_GIT_CURRENT_REF=APROVADO"

TRACKED_TREE="${TMP}/tracked-tree"
mkdir -p "${TRACKED_TREE}"

(
  cd "${ROOT}"
  git ls-files -z \
    | tar --null -T - -cf -
) | tar -C "${TRACKED_TREE}" -xf -

gitleaks dir \
  --no-banner \
  --no-color \
  --redact=100 \
  --config "${CONFIG}" \
  "${TRACKED_TREE}"

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
