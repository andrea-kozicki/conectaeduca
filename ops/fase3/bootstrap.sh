#!/usr/bin/env bash
# Instala kit em HOME: somente download, hashes e sintaxe.
# Nao modifica /opt/conectaeduca, Docker, Git de trabalho ou servicos.
set -euo pipefail
set +x
umask 077

TARGET=""
if (( $# > 0 )); then TARGET="$1"; fi
case "$TARGET" in
  ep125) EXPECTED_HOST="ep125-pucpr"; ENTRY="ep125/ce-ep125.sh";;
  ep126) EXPECTED_HOST="ep126-pucpr-br"; ENTRY="ep126/ce-ep126.sh";;
  opensuse) EXPECTED_HOST="opensuse-andrea"; ENTRY="opensuse/ce-client.sh";;
  *) echo "USO: bash bootstrap.sh ep125|ep126|opensuse" >&2; exit 2;;
esac
[[ "$(hostname -s)" == "$EXPECTED_HOST" ]] || {
  echo "ERRO=HOST_INCORRETO" >&2
  exit 3
}
command -v curl >/dev/null || { echo "ERRO=CURL_AUSENTE"; exit 4; }
command -v git >/dev/null || { echo "ERRO=GIT_AUSENTE"; exit 4; }

PIN="4a07ab30e35afa33cb2a098de53eb06e4647909b"
BASE_URL="https://raw.githubusercontent.com/andrea-kozicki/conectaeduca/$PIN/ops/fase3"
PIN_SHORT="$(printf '%.8s' "$PIN")"
DEST="$HOME/ConectaEduca_Fase3_Kit-$PIN_SHORT"
if [[ -e "$DEST" ]]; then
  echo "KIT_JA_EXISTENTE=$DEST"
  echo "SEM_SOBRESCRITA=SIM"
  exit 0
fi

STAGING="$(mktemp -d "$HOME/.ce-f3-kit.XXXXXXXX")"
trap 'rm -rf -- "$STAGING"' EXIT

while read -r FILE EXPECTED_SHA; do
  [[ -n "$FILE" ]] || continue
  mkdir -p -- "$STAGING/$(dirname "$FILE")"
  curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
    --connect-timeout 8 --max-time 35 \
    "$BASE_URL/$FILE" -o "$STAGING/$FILE"
  ACTUAL_SHA="$(git hash-object "$STAGING/$FILE")"
  if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
    echo "ERRO=HASH_DIVERGENTE arquivo=$FILE" >&2
    exit 5
  fi
  echo "VERIFICADO=$FILE"
done <<'MANIFEST'
lib/ce-common.sh 42bfa0b9ff59b85b73d36a53b210cf49c4b0368e
ep125/ce-ep125.sh 0aed3603288a1b91a8ca5234c4fb28b1af50e973
ep125/QUEUE.md 44e3850c2c9ef3ae0721ccdd0090faf63e53e220
ep126/ce-ep126.sh 4d23f905ee8c027ea544936143bbc8d3edb469ef
ep126/QUEUE.md 3f080b2588ca16553c93b369983208bbfedd22be
README.md 4dc72b3503a2bfb7b0241ff01cc51b40c0ad8861
opensuse/ce-client.sh 78a26052e457145597bb5f405c7d8a7dff005b77
tests/smoke.sh 9feaea4600407ccb8138c613d9cac69fb3099032
MANIFEST

bash "$STAGING/tests/smoke.sh"
mv -T -- "$STAGING" "$DEST"
trap - EXIT
echo "KIT_INSTALADO=$DEST"
echo "SCRIPT_PRINCIPAL=$DEST/$ENTRY"
echo "VM_ALTERADA=NAO"
