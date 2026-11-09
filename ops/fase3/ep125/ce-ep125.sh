#!/usr/bin/env bash
# EP125 DMZ — executar APENAS em ep125-pucpr (bash; nao abrir sessao root persistente).
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
CE_VM="EP125"
CE_EXPECTED_HOST="ep125-pucpr"
CE_REPO_ROOT="/opt/conectaeduca"
source "$SCRIPT_DIR/../lib/ce-common.sh"
ce_main "${1:-help}" "${2:-}"
