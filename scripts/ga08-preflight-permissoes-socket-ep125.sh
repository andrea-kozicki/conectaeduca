#!/usr/bin/env bash
# GA08: preflight de permissões/compatibilidade de socket; não modifica runtime.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125/GA08"
DIARIO="$HOME/ConectaEduca_Fase2_Evidencias/EP125/diario.md"
mkdir -p "$BASE"
LOG="$BASE/GA08_SOCKET_PREFLIGHT_$(date +%Y%m%dT%H%M%S).txt"
STATUS="BLOQUEADO"
finish(){ local rc=$?; trap - EXIT; if [[ -w "$DIARIO" ]]; then printf '\n## GA-08 — Preflight de permissões socket — %s\nStatus: %s\nEvidência: %s\nImplantação: não executada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO"; fi; printf 'STATUS=%s\nEVIDENCIA=%s\n' "$STATUS" "$LOG"; exit "$rc"; }
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 — SOCKET PREFLIGHT ==="
echo "DATA=$(date -Is)"
echo "MODO=LEITURA_APENAS"
[[ -w "$DIARIO" ]] || { echo "ERRO=DIARIO_INDISPONIVEL"; exit 2; }
for svc in conectaeduca-dmz-nginx-1 conectaeduca-dmz-php-1; do
 echo "CONTAINER=$svc"
 docker inspect "$svc" --format 'USER={{.Config.User}} READONLY={{.HostConfig.ReadonlyRootfs}} GROUP_ADD={{json .HostConfig.GroupAdd}}'
done
echo "=== IDENTIDADES EFETIVAS ==="
docker exec conectaeduca-dmz-nginx-1 id
docker exec conectaeduca-dmz-php-1 id
echo "=== DIRETORIOS DISPONIVEIS ==="
for d in /run/conectaeduca-fpm /opt/conectaeduca/run /opt/conectaeduca/deploy/dmz/run; do
 if [[ -e "$d" ]]; then
  stat -c 'CAMINHO=%n TIPO=%F UID=%u GID=%g MODO=%a' "$d"
 else
  echo "CAMINHO=$d AUSENTE"
 fi
done
echo "=== VOLUMES EXISTENTES PARA SOCKET ==="
for svc in conectaeduca-dmz-nginx-1 conectaeduca-dmz-php-1; do
 echo "CONTAINER=$svc"
 docker inspect "$svc" --format '{{range .Mounts}}{{if eq .Destination "/run/conectaeduca-fpm"}}SOCKET_MOUNT_EXISTENTE={{.Type}}{{end}}{{end}}'
done
echo "=== ALCANCE DA REDE ATUAL ==="
docker inspect conectaeduca-dmz-php-1 --format '{{range $n,$v := .NetworkSettings.Networks}}REDE_PHP={{$n}}{{println}}{{end}}'
echo "=== CONCLUSÃO ==="
echo "NOTA=Permissões do bind mount ainda dependem de provisionamento controlado; sem testes de escrita."
STATUS="INSPECIONADO"
echo "IMPLANTACAO=NAO_EXECUTADA"
