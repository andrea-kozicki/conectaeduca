#!/usr/bin/env bash
# GA08: teste efêmero de acesso ao socket via grupo suplementar 82.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125/GA08"
DIARIO="$HOME/ConectaEduca_Fase2_Evidencias/EP125/diario.md"
mkdir -p "$BASE"
LOG="$BASE/GA08_SOCKET_GRUPO82_$(date +%Y%m%dT%H%M%S).txt"
TAG="$(date +%s)-$$"; VOL="ga08-group82-$TAG"; PHP="ga08-fpm-group82-$TAG"; TMP=""; STATUS="FALHOU"
finish(){ rc=$?; trap - EXIT; docker rm -f "$PHP" >/dev/null 2>&1 || :; docker volume rm "$VOL" >/dev/null 2>&1 || :; [[ -z "$TMP" ]] || rm -rf "$TMP"; if [[ -w "$DIARIO" ]]; then printf '\n## GA08 socket grupo82 — %s\nStatus: %s\nEvidência: %s\nProdução: intacta\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || :; fi; echo "STATUS=$STATUS"; echo "EVIDENCIA=$LOG"; exit "$rc"; }
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 — SOCKET GRUPO SUPLEMENTAR 82 ==="
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/../deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf"
[[ -r "$CONF" && -w "$DIARIO" ]] || { echo "ERRO=CONFIG_OU_DIARIO"; exit 2; }
TMP="$(mktemp -d /tmp/ga08-group82.XXXXXXXX)"; chmod 0755 "$TMP"
sed -E '/^[[:space:]]*listen\.(owner|group)[[:space:]]*=/d' "$CONF" > "$TMP/fpm.conf"; chmod 0644 "$TMP/fpm.conf"
PIMG="$(docker inspect conectaeduca-dmz-php-1 --format '{{.Image}}')"
NIMG="$(docker inspect conectaeduca-dmz-nginx-1 --format '{{.Image}}')"
docker volume create "$VOL" >/dev/null
docker run --rm --network none --user 0:0 --read-only --cap-drop ALL --cap-add CHOWN --cap-add FOWNER --security-opt no-new-privileges:true --mount "type=volume,src=$VOL,dst=/run/conectaeduca-fpm" --entrypoint sh "$PIMG" -c 'chown 82:82 /run/conectaeduca-fpm && chmod 0770 /run/conectaeduca-fpm'
docker run -d --name "$PHP" --network none --user 82:82 --read-only --cap-drop ALL --security-opt no-new-privileges:true --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m,uid=82,gid=82,mode=1770 --mount "type=volume,src=$VOL,dst=/run/conectaeduca-fpm" --mount "type=bind,src=$TMP/fpm.conf,dst=/usr/local/etc/php-fpm.d/zz-conectaeduca.conf,readonly" --entrypoint php-fpm "$PIMG" -F >/dev/null
sleep 2
if [[ "$(docker inspect "$PHP" --format '{{.State.Running}}')" != true ]]; then docker logs "$PHP" 2>&1 | tail -20; exit 3; fi
docker exec "$PHP" stat -c 'SOCKET_UID=%u SOCKET_GID=%g SOCKET_MODO=%a' /run/conectaeduca-fpm/php-fpm.sock
docker exec "$PHP" stat -c 'DIR_UID=%u DIR_GID=%g DIR_MODO=%a' /run/conectaeduca-fpm
echo "=== NGINX UID101 GID101 + GROUP82, SEM REDE ==="
# Acesso real a socket Unix via PHP CLI (stream_socket_client), sem rede IP.
docker run --rm --network none --user 101:101 --group-add 82 --read-only --cap-drop ALL --security-opt no-new-privileges:true --mount "type=volume,src=$VOL,dst=/run/conectaeduca-fpm,readonly" --entrypoint sh "$PIMG" -c 'id; php -r '\''$s=@stream_socket_client("unix:///run/conectaeduca-fpm/php-fpm.sock",$errno,$errstr,3); if (!$s) {fwrite(STDERR,"SOCKET_CONNECT_FAIL ".$errno." ".$errstr.PHP_EOL);exit(7);} echo "SOCKET_CONNECT_OK".PHP_EOL;fclose($s);'\'''
echo "PRODUCAO=NAO_ALTERADA"
STATUS="CONEXAO_UNIX_UID101_GRUPO82_OK"
