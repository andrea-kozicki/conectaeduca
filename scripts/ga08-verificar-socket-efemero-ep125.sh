#!/usr/bin/env bash
# GA08: verificar socket no contêiner efêmero; produção intacta.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125/GA08"
DIARIO="$HOME/ConectaEduca_Fase2_Evidencias/EP125/diario.md"
mkdir -p "$BASE"
LOG="$BASE/GA08_SOCKET_PERMISSOES_$(date +%Y%m%dT%H%M%S).txt"
STATUS="FALHOU"; TMP=""
finish(){ local rc=$?; trap - EXIT; [[ -z "$TMP" ]] || rm -rf -- "$TMP"; if [[ -w "$DIARIO" ]]; then printf '\n## GA-08 — Socket permissões isoladas — %s\nStatus: %s\nEvidência: %s\nProdução: intacta\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true; fi; echo "STATUS=$STATUS"; echo "EVIDENCIA=$LOG"; exit "$rc"; }
trap finish EXIT
exec > >(tee "$LOG") 2>&1
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/../deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf"
[[ -r "$CONF" && -w "$DIARIO" ]] || { echo "ERRO=CONF_OU_DIARIO"; exit 2; }
TMP="$(mktemp -d /tmp/ga08-sockcheck.XXXXXXXX)"
chmod 0755 "$TMP"
install -m 0644 "$CONF" "$TMP/fpm.conf"
IMG="$(docker inspect conectaeduca-dmz-php-1 --format '{{.Image}}')"
echo "MODO=CONTÊINER_EFÊMERO_SEM_REDE"
set +e
docker run --rm --network none --user 82:82 --read-only --cap-drop ALL --security-opt no-new-privileges:true --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m,uid=82,gid=82,mode=1770 --tmpfs /run/conectaeduca-fpm:rw,nosuid,nodev,noexec,size=4m,uid=82,gid=101,mode=2770 --mount "type=bind,src=$TMP/fpm.conf,dst=/usr/local/etc/php-fpm.d/zz-conectaeduca.conf,readonly" --entrypoint sh "$IMG" -c '
 php-fpm -F >/tmp/fpm.log 2>&1 &
 pid=$!
 trap "kill $pid 2>/dev/null || true" EXIT
 i=0
 while [ "$i" -lt 25 ]; do
  [ -S /run/conectaeduca-fpm/php-fpm.sock ] && break
  sleep 0.2; i=$((i+1))
 done
 cat /tmp/fpm.log
 if [ ! -S /run/conectaeduca-fpm/php-fpm.sock ]; then echo SOCKET_NAO_CRIADO; exit 3; fi
 stat -c "SOCKET_UID=%u SOCKET_GID=%g SOCKET_MODO=%a" /run/conectaeduca-fpm/php-fpm.sock
 stat -c "DIR_UID=%u DIR_GID=%g DIR_MODO=%a" /run/conectaeduca-fpm
 echo SOCKET_CRIADO=SIM
 '
RC=$?
set -e
echo "EXIT_CODE=$RC"
if [[ "$RC" == 0 ]]; then STATUS="SOCKET_CRIADO"; else STATUS="FALHOU"; fi
echo "NOTA=Não comprova acesso pelo Nginx; requer ensaio entre dois contêineres."
echo "PRODUCAO=NAO_ALTERADA"
