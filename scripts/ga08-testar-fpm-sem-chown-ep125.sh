#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125/GA08"; DIARIO="$HOME/ConectaEduca_Fase2_Evidencias/EP125/diario.md"
mkdir -p "$BASE"; LOG="$BASE/GA08_FPM_SOCKET_SEM_CHOWN_$(date +%Y%m%dT%H%M%S).txt"
SUF="$(date +%s)-$$"; VOL="ga08-nochown-$SUF"; PHP="ga08-nochown-php-$SUF"; TMP=""; STATUS="FALHOU"
finish(){ rc=$?; trap - EXIT; docker rm -f "$PHP" >/dev/null 2>&1 || :; docker volume rm "$VOL" >/dev/null 2>&1 || :; [[ -z "$TMP" ]] || rm -rf -- "$TMP"; if [[ -w "$DIARIO" ]]; then printf '\n## GA-08 — FPM sem chown — %s\nStatus: %s\nEvidência: %s\nProdução: intacta\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || :; fi; echo "STATUS=$STATUS"; echo "EVIDENCIA=$LOG"; exit "$rc"; }
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 FPM SOCKET SEM CHOWN ==="
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/../deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf"
[[ -r "$CONF" && -w "$DIARIO" ]] || { echo "ERRO=CONFIG_OU_DIARIO"; exit 2; }
TMP="$(mktemp -d /tmp/ga08-nochown.XXXXXXXX)"; chmod 0755 "$TMP"
sed -E '/^[[:space:]]*listen\.(owner|group)[[:space:]]*=/d' "$CONF" > "$TMP/fpm.conf"; chmod 0644 "$TMP/fpm.conf"
echo "CONFIG_TESTADA=SEM_LISTEN_OWNER_GROUP"
IMG="$(docker inspect conectaeduca-dmz-php-1 --format '{{.Image}}')"
docker volume create "$VOL" >/dev/null
docker run --rm --network none --user 0:0 --read-only --cap-drop ALL --cap-add CHOWN --cap-add FOWNER --security-opt no-new-privileges:true --mount "type=volume,src=$VOL,dst=/run/conectaeduca-fpm" --entrypoint sh "$IMG" -c 'chown 82:101 /run/conectaeduca-fpm && chmod 2770 /run/conectaeduca-fpm'
docker run -d --name "$PHP" --network none --user 82:82 --read-only --cap-drop ALL --security-opt no-new-privileges:true --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m,uid=82,gid=82,mode=1770 --mount "type=volume,src=$VOL,dst=/run/conectaeduca-fpm" --mount "type=bind,src=$TMP/fpm.conf,dst=/usr/local/etc/php-fpm.d/zz-conectaeduca.conf,readonly" --entrypoint php-fpm "$IMG" -F >/dev/null
sleep 2
echo "=== ESTADO ==="
docker inspect "$PHP" --format 'RUNNING={{.State.Running}} EXIT_CODE={{.State.ExitCode}} ERROR={{.State.Error}}'
echo "=== LOG PHP-FPM ==="; docker logs "$PHP" 2>&1 | tail -20
if [[ "$(docker inspect "$PHP" --format '{{.State.Running}}')" == true ]] && docker exec "$PHP" test -S /run/conectaeduca-fpm/php-fpm.sock; then
 docker exec "$PHP" stat -c 'SOCKET_UID=%u SOCKET_GID=%g SOCKET_MODO=%a' /run/conectaeduca-fpm/php-fpm.sock
 docker exec "$PHP" stat -c 'DIR_UID=%u DIR_GID=%g DIR_MODO=%a' /run/conectaeduca-fpm
 STATUS="SOCKET_CRIADO_SEM_CHOWN"
else STATUS="FALHA_SOCKET"; fi
echo "PRODUCAO=NAO_ALTERADA"
