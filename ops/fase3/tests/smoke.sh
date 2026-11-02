#!/usr/bin/env bash
# Smoke estatico local. Executar fora das VMs e sem acesso Docker.
set -euo pipefail

BASE="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
for file in \
  "$BASE/lib/ce-common.sh" \
  "$BASE/ep125/ce-ep125.sh" \
  "$BASE/ep126/ce-ep126.sh" \
  "$BASE/opensuse/ce-client.sh" \
  "$BASE/bootstrap.sh"
do
  bash -n "$file"
  echo "BASH_N_OK=$file"
done

bash "$BASE/ep125/ce-ep125.sh" help >/dev/null
bash "$BASE/ep126/ce-ep126.sh" help >/dev/null
echo "HELP_OK=AMBAS"

# O dispatcher deve rejeitar chamadas de escrita antes de verificar o hostname.
for op in apply deploy restart rollback merge
do
  if bash "$BASE/ep125/ce-ep125.sh" "$op" waf >/dev/null 2>&1; then
    echo "FALHA_SEGURANCA=OP_PERMITIDA:$op"
    exit 1
  fi
  if bash "$BASE/ep126/ce-ep126.sh" "$op" bacula >/dev/null 2>&1; then
    echo "FALHA_SEGURANCA=OP_PERMITIDA:$op"
    exit 1
  fi
done

# E cada launcher precisa recusar o computador errado.
if [[ "$(hostname -s)" != ep125-pucpr ]]; then
  if bash "$BASE/ep125/ce-ep125.sh" check waf >/dev/null 2>&1; then
    echo "FALHA_SEGURANCA=GUARDA_HOST_EP125"
    exit 1
  fi
fi
if [[ "$(hostname -s)" != ep126-pucpr-br ]]; then
  if bash "$BASE/ep126/ce-ep126.sh" check wazuh >/dev/null 2>&1; then
    echo "FALHA_SEGURANCA=GUARDA_HOST_EP126"
    exit 1
  fi
fi

# Bootstrap deve rejeitar hosts errados sem sequer baixar arquivos.
if [[ "$(hostname -s)" != ep125-pucpr ]]; then
  if bash "$BASE/bootstrap.sh" ep125 >/dev/null 2>&1; then
    echo "FALHA_SEGURANCA=BOOTSTRAP_EP125_HOST"
    exit 1
  fi
fi
if [[ "$(hostname -s)" != ep126-pucpr-br ]]; then
  if bash "$BASE/bootstrap.sh" ep126 >/dev/null 2>&1; then
    echo "FALHA_SEGURANCA=BOOTSTRAP_EP126_HOST"
    exit 1
  fi
fi

echo "RESULTADO=SMOKE_READONLY_PASS"
