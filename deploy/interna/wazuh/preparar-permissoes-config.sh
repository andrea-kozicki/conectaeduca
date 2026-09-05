#!/usr/bin/env bash
set -Eeuo pipefail

WAZUH_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

for dir in \
  "${WAZUH_DIR}/config/decoders" \
  "${WAZUH_DIR}/config/rules"
do
  [[ -d "${dir}" ]] || {
    echo "ERRO: diretório ausente: ${dir}" >&2
    exit 1
  }

  while IFS= read -r -d '' file; do
    chmod 0644 "${file}"
  done < <(find "${dir}" -maxdepth 1 -type f -name '*.xml' -print0)
done

FAIL=0

for dir in \
  "${WAZUH_DIR}/config/decoders" \
  "${WAZUH_DIR}/config/rules"
do
  while IFS= read -r -d '' file; do
    mode="$(stat -c '%a' "${file}")"
    if [[ "${mode}" != "644" ]]; then
      echo "ERRO: modo inesperado ${mode}: ${file}" >&2
      FAIL=1
    fi
  done < <(find "${dir}" -maxdepth 1 -type f -name '*.xml' -print0)
done

[[ "${FAIL}" -eq 0 ]] || exit 1

echo "WAZUH_CONFIG_PERMISSIONS=APROVADO"
