#!/usr/bin/env bash
# GA08: diagnóstico pontual de inicialização FPM com volume efêmero.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125/GA08"
DIARIO="$HOME/ConectaEduca_Fase2_Evidencias/EP125/diario.md"
mkdir -p "$BASE"
LOG="$BASE/GA08_FPM_VOLUME_DIAGNOSTICO_$(date +%Y%m%dT%H%M%S).txt"
SUFFIX="$(date +%s)-$$"; VOL="ga08-diag-$SUFFIX"; PHP="ga08-diag-php-$SUFFIX"; TMP=""; STATUS="FALHOU"
finish(){
 local rc=$?; trap - EXIT
 docker rm -f "$PHP" >/dev/null 2>&1 || true
 docker volume rm "$VOL" >/dev/null 2>&1 || true
 [[ -z "$TMP" ]] || rm -rf -- "$TMP"
 if [[ -w "$DIARIO" ]]; then printf '\n## GA-08 — Diagnóstico PHP-FPM volume — %s\nStatus: %s\nEvidência: %s\nProdução: intacta\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true; fi
 echo "STATUS=$STATUS"; echo "EVIDENCIA=$LOG"; exit "$rc"
}
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 — DIAGNOSTICO FPM EM VOLUME EFEMERO ==="
echo "DATA=$(date -Is)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/../deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf"
[[ -r "$CONF" && -w "$DIARIO" ]] || { echo "ERRO=CONFIG_OU_DIARIO"; exit 2; }
TMP="$(mktemp -d /tmp/ga08-fpm-diag.XXXXXXXX)"
chmod 0755 "$TMP"
install -m 0644 "$CONF" "$TMP/fpm.conf"
IMG="$(docker inspect conectaeduca-dmz-php-1 --format '{{.Image}}')"
docker volume create "$VOL" >/dev/null
docker run --rm --network none --user 0:0 --read-only --cap-drop ALL --cap-add CHOWN --cap-add FOWNER --security-opt no-new-privileges:true --mount "type=volume,src=$VOL,dst=/run/conectaeduca-fpm" --entrypoint sh "$IMG" -c 'chown 82:101 /run/conectaeduca-fpm && chmod 2770 /run/conectaeduca-fpm'
echo "VOLUME_PREPARADO=SIM"
docker run -d --name "$PHP" --network none --user 82:82 --read-only --cap-drop ALL --security-opt no-new-privileges:true --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m,uid=82,gid=82,mode=1770 --mount "type=volume,src=$VOL,dst=/run/conectaeduca-fpm" --mount "type=bind,src=$TMP/fpm.conf,dst=/usr/local/etc/php-fpm.d/zz-conectaeduca.conf,readonly" --entrypoint php-fpm "$IMG" -F >/dev/null
sleep 2
docker inspect "$PHP" --format 'CONTAINER_RUNNING={{.State.Running}} EXIT_CODE={{.State.ExitCode}} ERROR={{.State.Error}}'
echo "=== LOG PHP-FPM (30 LINHAS) ==="
docker logs "$PHP" 2>&1 | tail -30
if [[ "$(docker inspect "$PHP" --format '{{.State.Running}}')" == "true" ]]; then
 docker exec "$PHP" stat -c 'DIR_UID=%u DIR_GID=%g DIR_MODO=%a' /run/conectaeduca-fpm
 if docker exec "$PHP" test -S /run/conectaeduca-fpm/php-fpm.sock; then
  docker exec "$PHP" stat -c 'SOCKET_UID=%u SOCKET_GID=%g SOCKET_MODO=%a' /run/conectaeduca-fpm/php-fpm.sock
  STATUS="SOCKET_CRIADO_COM_VOLUME"
 else STATUS="PHP_ATIVO_SEM_SOCKET"; fi
else STATUS="PHP_ENCERROU"; fi
echo "PRODUCAO=NAO_ALTERADA"
