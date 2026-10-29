#!/usr/bin/env bash
# GA08 — repetir ensaio em diretório efêmero, sem mudar arquivos de evidência.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125/GA08"
DIARIO="$HOME/ConectaEduca_Fase2_Evidencias/EP125/diario.md"
mkdir -p "$BASE"
LOG="$BASE/GA08_SOCKET_ENSAIO_V2_$(date +%Y%m%dT%H%M%S).txt"
STATUS="FALHOU"
TMP=""
finish(){
 local rc=$?
 trap - EXIT
 [[ -z "$TMP" ]] || rm -rf -- "$TMP"
 if [[ -w "$DIARIO" ]]; then printf '\n## GA-08 — Ensaio socket v2 — %s\nStatus: %s\nEvidência: %s\nProdução: não alterada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true; fi
 echo "STATUS=$STATUS"; echo "EVIDENCIA=$LOG"; exit "$rc"
}
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 — ENSAIO SOCKET V2 ==="
echo "DATA=$(date -Is)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/../deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf"
[[ -r "$CONF" && -w "$DIARIO" ]] || { echo "ERRO=CONFIG_OU_DIARIO_INDISPONIVEL"; exit 2; }
TMP="$(mktemp -d /tmp/ga08-socket-v2.XXXXXXXX)"
chmod 0755 "$TMP"
install -m 0644 "$CONF" "$TMP/fpm.conf"
IMG="$(docker inspect conectaeduca-dmz-php-1 --format '{{.Image}}')"
echo "MODO=CONTAINER_EFEMERO_SEM_REDE"
echo "CONFIG_MONTADA=ARQUIVO_TEMPORARIO_0644"
set +e
OUTPUT="$(timeout 12s docker run --rm --network none --user 82:82 --read-only --cap-drop ALL --security-opt no-new-privileges:true --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m,uid=82,gid=82,mode=1770 --tmpfs /run/conectaeduca-fpm:rw,nosuid,nodev,noexec,size=4m,uid=82,gid=101,mode=2770 --mount "type=bind,src=$TMP/fpm.conf,dst=/usr/local/etc/php-fpm.d/zz-conectaeduca.conf,readonly" --entrypoint sh "$IMG" -c 'php-fpm -t && php-fpm -F' 2>&1)"
RC=$?
set -e
echo "EXIT_CODE=$RC"
printf '%s\n' "$OUTPUT" | tail -30
if [[ "$RC" == 124 ]]; then
 echo "RESULTADO=PROCESSO_PERMANECEU_ATIVO_ATE_TIMEOUT"
 STATUS="PARCIAL_APROVADO"
elif [[ "$RC" == 0 ]]; then
 echo "RESULTADO=SAIDA_ZERO_SEM_COMPROVACAO_DE_SOCKET"
 STATUS="INCONCLUSIVO"
else
 echo "RESULTADO=FALHA_A_INVESTIGAR"
 STATUS="FALHOU"
fi
echo "LIMITACAO=NAO_TESTA_NGINX_NEM_CONEXAO_AO_SOCKET"
echo "PRODUCAO=NAO_ALTERADA"
