#!/usr/bin/env bash
# Diagnostico NAO invasivo do Twingate Client no openSUSE pessoal.
# Nao inicia Connector, nao instala Client, nao altera DNS, sudo ou credenciais.
set -euo pipefail
set +x
umask 077

echo "CE_FASE3=TWINGATE_CLIENT_READONLY"
echo "HOST=$(hostname -s)"
if [[ "$(hostname -s)" != "opensuse-andrea" ]]; then
  echo "ERRO=EXECUTAR_SOMENTE_NO_OPENSUSE_PESSOAL" >&2
  exit 2
fi

if ! command -v twingate >/dev/null 2>&1; then
  echo "CLIENTE=NAO_INSTALADO"
  exit 0
fi

state="$(twingate status 2>&1 || true)"
echo "CLIENT_STATUS=$state"

if [[ "$state" == *not-running* ]]; then
  echo "RECURSOS=NAO_CONSULTADOS_POR_CLIENTE_PARADO"
  echo "PROXIMO_PASSO=Executar 'twingate start' SEM sudo, autenticar interativamente se solicitado, depois verificar 'twingate status' e 'twingate resources'"
  echo "CONNECTOR_DOCKER_PESSOAL=NAO_INICIADO_POR_ESTE_SCRIPT"
  exit 0
fi

echo "=== RESOURCES VISIVEIS ==="
twingate resources 2>&1 || true

echo "=== ALIAS WAZUH ==="
if getent ahostsv4 wazuh.dashboard >/dev/null 2>&1; then
  echo "ALIAS_DNS=RESOLVIDO"
else
  echo "ALIAS_DNS=NAO_RESOLVIDO"
fi

echo "ALTERACOES_REALIZADAS=NAO"
