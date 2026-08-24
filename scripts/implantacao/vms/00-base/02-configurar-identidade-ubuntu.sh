#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
VMS_DIR="$(cd -P "$SCRIPT_DIR/.." && pwd -P)"
source "$VMS_DIR/lib/comum.sh"
MODE=check; ROLE=""; SELF_TEST=0
while (($#)); do
  case "$1" in
    --role) ROLE="${2:-}"; shift 2 ;;
    --check) MODE=check; shift ;;
    --apply) MODE=apply; shift ;;
    --self-test) SELF_TEST=1; shift ;;
    -h|--help) echo "Uso: $0 --role dmz|interna [--check|--apply]"; exit 0 ;;
    *) echo "ERRO: opção desconhecida: $1" >&2; exit 64 ;;
  esac
done
if (( SELF_TEST )); then ce_valid_role dmz && ce_valid_role interna && ! ce_valid_role banco; echo "SELF_TEST_IDENTIDADE=APROVADO"; exit 0; fi
ce_valid_role "$ROLE" || { echo "ERRO: --role dmz|interna é obrigatório" >&2; exit 64; }
case "$ROLE" in dmz) EXPECTED=conectaeduca-dmz; VM_ID=CE-UBUNTU-DMZ;; interna) EXPECTED=conectaeduca-interna; VM_ID=CE-UBUNTU-INT;; esac
CURRENT="$(hostname 2>/dev/null || true)"
echo "VM_ID=$VM_ID"; echo "HOSTNAME_ESPERADO=$EXPECTED"; echo "HOSTNAME_ATUAL=${CURRENT:-INDETERMINADO}"
if [[ "$MODE" == check ]]; then [[ "$CURRENT" == "$EXPECTED" ]] && { echo "IDENTIDADE_HOST=APROVADA"; exit 0; }; echo "IDENTIDADE_HOST=PENDENTE"; exit 1; fi
[[ "$(id -u)" -eq 0 ]] || { echo "ERRO: --apply exige sudo/root" >&2; exit 1; }
command -v hostnamectl >/dev/null || { echo "ERRO: hostnamectl ausente" >&2; exit 1; }
hostnamectl set-hostname "$EXPECTED"
[[ "$(hostname)" == "$EXPECTED" ]] || { echo "ERRO: hostname não foi aplicado" >&2; exit 1; }
echo "IDENTIDADE_HOST=APLICADA"
