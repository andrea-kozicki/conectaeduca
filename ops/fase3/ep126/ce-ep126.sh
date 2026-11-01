#!/usr/bin/env bash
# EP126 Intranet — executar APENAS em ep126-pucpr-br (bash; nao abrir sessao root persistente).
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
CE_VM="EP126"
CE_EXPECTED_HOST="ep126-pucpr-br"
CE_REPO_ROOT="/opt/conectaeduca"
source "$SCRIPT_DIR/../lib/ce-common.sh"
ce_main "${1:-help}" "${2:-}"
