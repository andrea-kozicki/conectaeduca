#!/usr/bin/env bash
# GA08 — inspecionar dependências Nginx->PHP e mounts sem imprimir segredos.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125/GA08"
DIARIO="$HOME/ConectaEduca_Fase2_Evidencias/EP125/diario.md"
mkdir -p "$BASE"
LOG="$BASE/GA08_DEPENDENCIAS_NGINX_PHP_$(date +%Y%m%dT%H%M%S).txt"
STATUS="FALHOU"
finish() {
 rc=$?
 trap - EXIT
 printf '\n## GA-08 — Dependências Nginx/PHP — %s\nStatus: %s\nEvidência: %s\nImplantação: não executada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true
 echo "STATUS=$STATUS"
 echo "EVIDENCIA=$LOG"
 exit "$rc"
}
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 — DEPENDENCIAS NGINX PHP ==="
echo "DATA=$(date -Is)"
echo "MODO=LEITURA_APENAS"
[[ -w "$DIARIO" ]] || { echo "DIARIO_INDISPONIVEL"; exit 2; }
echo "=== FASTCGI NGINX (somente diretivas relevantes) ==="
docker exec conectaeduca-dmz-nginx-1 nginx -T 2>/dev/null |
  grep -E '^[[:space:]]*(fastcgi_pass|proxy_pass|listen|upstream|server[[:space:]]+unix:)' |
  sed -E 's/(proxy_pass[[:space:]]+https?:\/\/)[^;]+/\1[DESTINO_OCULTADO]/' |
  head -60 || true
echo "=== PHP-FPM LISTEN (sem variáveis de ambiente) ==="
docker exec conectaeduca-dmz-php-1 sh -c '
  for d in /usr/local/etc/php-fpm.d /etc/php/8.3/fpm/pool.d /etc/php/8.4/fpm/pool.d; do
    [ -d "$d" ] || continue
    grep -hE "^[[:space:]]*listen[[:space:]]*=" "$d"/*.conf 2>/dev/null || true
  done
' | head -20
echo "=== MOUNTS (apenas destino e tipo; sem fontes ou conteúdos) ==="
for svc in conectaeduca-dmz-nginx-1 conectaeduca-dmz-php-1; do
  echo "CONTAINER=$svc"
  docker inspect "$svc" --format '{{range .Mounts}}{{println .Type .Destination}}{{end}}'
done
echo "=== NOTA ==="
echo "UMA_REDE_BRIDGE_COMPARTILHADA_NAO_APLICA_ACL_DIRECIONAL"
echo "CORRECAO_CANDIDATA_ANTERIOR=NAO_IMPLANTAR_COMO_REMEDIACAO_COMPLETA"
STATUS="CONCLUIDO"
echo "IMPLANTACAO=NAO_EXECUTADA"
