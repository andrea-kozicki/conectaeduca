#!/usr/bin/env bash
# GA08: ensaio isolado de socket PHP-FPM; não toca contêineres de produção.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125/GA08"
DIARIO="$HOME/ConectaEduca_Fase2_Evidencias/EP125/diario.md"
mkdir -p "$BASE"
LOG="$BASE/GA08_SOCKET_ENSAIO_$(date +%Y%m%dT%H%M%S).txt"
STATUS="BLOQUEADO"
finish(){ rc=$?; trap - EXIT; if [[ -w "$DIARIO" ]]; then printf '\n## GA-08 — Ensaio isolado socket — %s\nStatus: %s\nEvidência: %s\nProdução: não alterada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true; fi; echo "STATUS=$STATUS"; echo "EVIDENCIA=$LOG"; exit "$rc"; }
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 — ENSAIO SOCKET ISOLADO ==="
echo "DATA=$(date -Is)"
[[ -w "$DIARIO" ]] || { echo "DIARIO_INDISPONIVEL"; exit 2; }
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONF="$ROOT/deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf"
[[ -r "$CONF" ]] || { echo "CONF_AUSENTE=$CONF"; exit 2; }
command -v docker >/dev/null
echo "IMAGEM=$(docker inspect conectaeduca-dmz-php-1 --format '{{.Config.Image}}')"
IMG="$(docker inspect conectaeduca-dmz-php-1 --format '{{.Image}}')"
echo "CONTAINER_PRODUCAO_INTACTO=SIM"
echo "MODO=DOCKER_RUN_EFEMERO_SEM_REDE"
# docker run temporário não modifica nem reinicia contêineres existentes.
set +e
OUTPUT="$(timeout 12s docker run --rm --network none --user 82:82 --read-only --cap-drop ALL --security-opt no-new-privileges:true --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m,uid=82,gid=82,mode=1770 --tmpfs /run/conectaeduca-fpm:rw,nosuid,nodev,noexec,size=4m,uid=82,gid=101,mode=2770 --mount "type=bind,src=$CONF,dst=/usr/local/etc/php-fpm.d/zz-conectaeduca.conf,readonly" --entrypoint sh "$IMG" -c 'php-fpm -t && php-fpm -F' 2>&1)"
RC=$?
set -e
echo "EXIT_CODE=$RC"
printf '%s\n' "$OUTPUT" | tail -35
if [[ $RC -eq 124 ]]; then
  echo "RESULTADO=PROCESSO_PERMANECEU_ATIVO_ATE_TIMEOUT"
  echo "LIMITACAO=NAO_COMPROVA_CONEXAO_NGINX_NEM_PERMISSOES_DE_ACESSO_AO_SOCKET"
  STATUS="PARCIAL_APROVADO"
elif [[ $RC -eq 0 ]]; then
  echo "RESULTADO=PROCESSO_ENCERROU_SEM_ERRO"
  STATUS="INCONCLUSIVO"
else
  echo "RESULTADO=FALHA_A_INVESTIGAR"
  STATUS="FALHOU"
fi
echo "PRODUCAO=NAO_ALTERADA"
