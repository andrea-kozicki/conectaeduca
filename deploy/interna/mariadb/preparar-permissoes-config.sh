#!/usr/bin/env bash
set -Eeuo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

FILES=(
  "${DIR}/conectaeduca.cnf"
  "${DIR}/tls.cnf"
  "${DIR}/require-secure-transport.cnf"
)

for file in "${FILES[@]}"; do
  [[ -f "${file}" ]] || {
    echo "ERRO: arquivo esperado ausente: ${file}" >&2
    exit 1
  }

  chmod 0644 "${file}"
done

for file in "${FILES[@]}"; do
  mode="$(stat -c '%a' "${file}")"

  if [[ "${mode}" != "644" ]]; then
    echo "ERRO: modo inesperado ${mode} em ${file}" >&2
    exit 1
  fi
done

echo "MARIADB_CONFIG_PERMISSIONS=APROVADO"
