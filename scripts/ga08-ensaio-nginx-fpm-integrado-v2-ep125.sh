#!/usr/bin/env bash
# GA-08: ensaio isolado Nginx -> PHP-FPM por socket, sem rede e sem portas publicadas.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125/GA08"
DIARIO="$HOME/ConectaEduca_Fase2_Evidencias/EP125/diario.md"
mkdir -p "$BASE"
LOG="$BASE/GA08_NGINX_FPM_INTEGRADO_V2_$(date +%Y%m%dT%H%M%S).txt"
SUFFIX="$(date +%s)-$$"
VOL="ga08-socket-$SUFFIX"; PHP="ga08-php-$SUFFIX"; NGINX="ga08-nginx-$SUFFIX"
TMP=""; STATUS="FALHOU"
finish(){
 local rc=$?; trap - EXIT
 docker rm -f "$NGINX" "$PHP" >/dev/null 2>&1 || true
 docker volume rm "$VOL" >/dev/null 2>&1 || true
 [[ -z "$TMP" ]] || rm -rf -- "$TMP"
 if [[ -w "$DIARIO" ]]; then printf '\n## GA-08 — Ensaio integrado socket v2 — %s\nStatus: %s\nEvidência: %s\nProdução: não alterada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true; fi
 echo "STATUS=$STATUS"; echo "EVIDENCIA=$LOG"; exit "$rc"
}
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 — ENSAIO INTEGRADO V2 SEM REDE ==="
echo "DATA=$(date -Is)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/../deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf"
[[ -r "$CONF" && -w "$DIARIO" ]] || { echo "ERRO=CONFIG_OU_DIARIO"; exit 2; }
TMP="$(mktemp -d /tmp/ga08-integrado-v2.XXXXXXXX)"
chmod 0755 "$TMP"
install -m 0644 "$CONF" "$TMP/fpm.conf"
cat > "$TMP/nginx.conf" <<'EOF'
worker_processes 1;
pid /tmp/nginx.pid;
events { worker_connections 32; }
http {
 access_log off;
 error_log /dev/stderr notice;
 server {
  listen 8080;
  location = /_fpm_ping {
   include /etc/nginx/fastcgi_params;
   fastcgi_param SCRIPT_NAME /fpm-ping;
   fastcgi_param SCRIPT_FILENAME /fpm-ping;
   fastcgi_pass unix:/run/conectaeduca-fpm/php-fpm.sock;
  }
 }
}
EOF
chmod 0644 "$TMP/nginx.conf"
PIMG="$(docker inspect conectaeduca-dmz-php-1 --format '{{.Image}}')"
NIMG="$(docker inspect conectaeduca-dmz-nginx-1 --format '{{.Image}}')"
docker volume create "$VOL" >/dev/null
# Contêiner de preparação temporário: somente CAP_CHOWN e CAP_FOWNER, sem rede.
docker run --rm --network none --user 0:0 --read-only --cap-drop ALL --cap-add CHOWN --cap-add FOWNER --security-opt no-new-privileges:true --mount "type=volume,src=$VOL,dst=/run/conectaeduca-fpm" --entrypoint sh "$PIMG" -c 'chown 82:101 /run/conectaeduca-fpm && chmod 2770 /run/conectaeduca-fpm'
echo "VOLUME_PREPARADO=SIM"
docker run -d --name "$PHP" --network none --user 82:82 --read-only --cap-drop ALL --security-opt no-new-privileges:true --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m,uid=82,gid=82,mode=1770 --mount "type=volume,src=$VOL,dst=/run/conectaeduca-fpm" --mount "type=bind,src=$TMP/fpm.conf,dst=/usr/local/etc/php-fpm.d/zz-conectaeduca.conf,readonly" --entrypoint php-fpm "$PIMG" -F >/dev/null
for i in $(seq 1 30); do docker exec "$PHP" test -S /run/conectaeduca-fpm/php-fpm.sock && break; sleep 0.2; done
docker exec "$PHP" test -S /run/conectaeduca-fpm/php-fpm.sock
docker exec "$PHP" stat -c 'SOCKET_UID=%u SOCKET_GID=%g SOCKET_MODO=%a' /run/conectaeduca-fpm/php-fpm.sock
docker run -d --name "$NGINX" --network none --user 101:101 --read-only --cap-drop ALL --security-opt no-new-privileges:true --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m,uid=101,gid=101,mode=1770 --tmpfs /var/cache/nginx:rw,nosuid,nodev,noexec,size=8m,uid=101,gid=101,mode=0750 --mount "type=volume,src=$VOL,dst=/run/conectaeduca-fpm,readonly" --mount "type=bind,src=$TMP/nginx.conf,dst=/tmp/ga08-nginx.conf,readonly" --entrypoint nginx "$NIMG" -c /tmp/ga08-nginx.conf -g 'daemon off;' >/dev/null
RESP=""
for i in $(seq 1 30); do
 RESP="$(docker exec "$NGINX" wget -q -O - http://127.0.0.1:8080/_fpm_ping 2>/dev/null || true)"
 [[ "$RESP" == "pong" ]] && break
 sleep 0.2
done
echo "RESPOSTA_FPM=$RESP"
if [[ "$RESP" != "pong" ]]; then
 echo "=== LOG NGINX ==="; docker logs "$NGINX" 2>&1 | tail -20
 echo "=== LOG PHP ==="; docker logs "$PHP" 2>&1 | tail -20
 exit 3
fi
echo "NETWORK_MODE=NONE_EM_AMBOS"
echo "PORTAS_PUBLICADAS=NENHUMA"
echo "PRODUCAO=NAO_ALTERADA"
STATUS="INTEGRACAO_OK"
