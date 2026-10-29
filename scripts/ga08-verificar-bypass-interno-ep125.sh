#!/usr/bin/env bash
# GA-08 — comprovar caminho interno PHP -> Nginx, sem ataques nem mudanças.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125/GA08"
DIARIO="$HOME/ConectaEduca_Fase2_Evidencias/EP125/diario.md"
mkdir -p "$BASE"
LOG="$BASE/GA08_CAMINHO_INTERNO_$(date +%Y%m%dT%H%M%S).txt"
STATUS="INCONCLUSIVO"
finish() {
  local rc=$?
  trap - EXIT
  { printf '\n## GA-08 — Caminho interno PHP-Nginx — %s\n' "$(date -Is)"; printf 'Status: %s\nEvidência: %s\nImplantação: não executada\n' "$STATUS" "$LOG"; } >> "$DIARIO" || true
  printf 'STATUS=%s\nEVIDENCIA=%s\n' "$STATUS" "$LOG"
  exit "$rc"
}
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 — CAMINHO INTERNO ==="
echo "DATA=$(date -Is)"
echo "MODO=LEITURA_APENAS"
[[ -w "$DIARIO" ]] || { echo "ERRO=DIARIO_INDISPONIVEL"; exit 2; }
echo "=== REDES COMPARTILHADAS ATUAIS ==="
for svc in conectaeduca-dmz-waf-1 conectaeduca-dmz-nginx-1 conectaeduca-dmz-php-1; do
  docker inspect "$svc" --format '{{.Name}} REDES={{range $name,$v := .NetworkSettings.Networks}}{{$name}} {{end}}'
done
echo "=== TESTE TCP/HTTP PHP -> NGINX INTERNO ==="
# PHP já está instalado no contêiner; não precisa instalar ferramentas.
# Usa GET /healthz (sem autenticação, sem payload) e limita leitura à linha de status.
if docker exec conectaeduca-dmz-php-1 php -r '
$h="nginx";$p=8080;
$s=@fsockopen($h,$p,$errno,$errstr,3);
if(!$s){echo "CAMINHO_INTERNO=SEM_CONEXAO\n";exit(1);}
stream_set_timeout($s,4);
fwrite($s,"GET /healthz HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n");
$line=fgets($s,256);fclose($s);
echo "CAMINHO_INTERNO=TCP_ACESSIVEL\n";
if($line && preg_match("/^HTTP\\/[^ ]+ ([0-9]{3})/",$line,$m)){echo "HTTP_STATUS=".$m[1]."\n";}else{echo "HTTP_STATUS=NAO_DETERMINADO\n";}
'; then
  STATUS="BYPASS_POTENCIAL_CONFIRMADO"
  echo "CONCLUSAO=PHP_ACESSA_NGINX_SEM_PASSAR_PELO_WAF"
else
  STATUS="CAMINHO_NAO_COMPROVADO"
  echo "CONCLUSAO=ACESSO_INTERNO_NAO_COMPROVADO_NESTE_TESTE"
fi
echo "ALTERACOES_RUNTIME=NENHUMA"
