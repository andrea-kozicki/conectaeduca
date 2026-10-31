#!/usr/bin/env bash
# ConectaEduca — EP125: preflight read-only por padrao; deploy so com --deploy.
# Rodar em processo filho: bash scripts/twingate/ce_twingate_dmz_preflight_deploy.sh
set -Eeuo pipefail
umask 077
ACTION="${1:---preflight}"
case "$ACTION" in --preflight|--deploy) ;; *) echo "Uso: bash $0 [--preflight|--deploy]" >&2; exit 2;; esac
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="$ROOT/deploy/twingate/dmz"
COMPOSE="$DIR/compose.yml"
ENV="$DIR/connector.env"
LOGDIR="${HOME}/ConectaEduca_Fase2_Evidencias/EP125/TWINGATE"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/CE_TWINGATE_DMZ_${ACTION#--}_$(date +%Y%m%dT%H%M%S).txt"
exec > >(tee "$LOG") 2>&1
echo "===== TWINGATE DMZ / ${ACTION} ====="
date --iso-8601=seconds; hostname
echo "LOG=$LOG"
command -v docker >/dev/null || { echo "ERRO: docker indisponivel"; exit 3; }
docker info >/dev/null 2>&1 || { echo "ERRO: docker sem acesso; nenhuma alteracao"; exit 3; }
docker compose version
echo "MEMORIA:"; free -h | head -2
echo "DISCO:"; df -h / | tail -1
echo "SERVICOS DMZ (somente status):"
docker ps --format '{{.Names}} {{.Status}} {{.Ports}}' | grep -E 'dmz|nginx|waf|php|twingate' || true
echo "TCP 443 no host 192.168.6.34:"
if timeout 4 bash -c 'exec 3<>/dev/tcp/192.168.6.34/443' 2>/dev/null; then
 echo "TCP443_CONECTA=SIM (nao comprova TLS/WAF nem acesso de dentro do container)"
else
 echo "TCP443_CONECTA=NAO (nao instalar ate revisar caminho de rede)"
fi
echo "Conector existente:"
docker ps -a --filter 'name=^/conectaeduca-dmz-01$' --format '{{.Names}} {{.Status}}' || true
if [[ "$ACTION" == "--preflight" ]]; then
 echo "MODO=READ_ONLY; ALTERACOES=NAO"
 echo "Proxima etapa: revisar log, rota a partir de bridge Docker e autorizacao de mudanca."
 exit 0
fi
echo "===== VALIDACOES ANTES DE DEPLOY ====="
[[ -f "$COMPOSE" ]] || { echo "ERRO: compose nao encontrado"; exit 4; }
[[ -f "$ENV" ]] || { echo "ERRO: criar $ENV a partir do exemplo, sem enviar tokens"; exit 4; }
perm="$(stat -c '%a' "$ENV")"
[[ "$perm" == 600 || "$perm" == 400 ]] || { echo "ERRO: chmod 600 $ENV (atual: $perm)"; exit 4; }
for key in TWINGATE_NETWORK TWINGATE_ACCESS_TOKEN TWINGATE_REFRESH_TOKEN; do
 grep -Eq "^$key=[^[:space:]]+" "$ENV" || { echo "ERRO: campo $key ausente"; exit 4; }
done
if grep -Eq 'SUBSTITUIR_|^TWINGATE_.*=.*(EXAMPLE|PLACEHOLDER)' "$ENV"; then
 echo "ERRO: placeholders presentes"; exit 4
fi
docker compose -f "$COMPOSE" config --quiet >/dev/null
echo "ATENCAO: esta operacao criara/iniciara um container isolado; nao altera compose da aplicacao."
read -r -p "Digite INSTALAR para confirmar: " confirm
[[ "$confirm" == "INSTALAR" ]] || { echo "CANCELADO"; exit 0; }
docker compose -f "$COMPOSE" up -d --no-build
echo "ESTADO (sem exibir variaveis/tokens):"
docker ps --filter 'name=^/conectaeduca-dmz-01$' --format '{{.Names}} {{.Status}}'
echo "NAO use docker inspect nem cole logs sem revisar segredos."
echo "ROLLBACK: docker compose -f '$COMPOSE' down (nao altera containers da aplicacao)."
