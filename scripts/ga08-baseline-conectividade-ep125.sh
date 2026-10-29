#!/usr/bin/env bash
# GA08 — baseline de conectividade anterior à mudança; sem modificar contêineres.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125/GA08"
DIARIO="$HOME/ConectaEduca_Fase2_Evidencias/EP125/diario.md"
STAMP="$(date +%Y%m%dT%H%M%S)"
LOG="$BASE/GA08_BASELINE_CONECTIVIDADE_$STAMP.txt"
mkdir -p "$BASE"
STATUS="FALHOU"
finalizar() {
  rc=$?
  trap - EXIT
  printf '\n## GA-08 — Baseline de conectividade — %s\nStatus: %s\nEvidência: %s\nAlterações no runtime: nenhuma\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true
  echo "STATUS=$STATUS"
  echo "EVIDENCIA=$LOG"
  echo "DIARIO=$DIARIO"
  exit "$rc"
}
trap finalizar EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 — BASELINE DE CONECTIVIDADE ==="
echo "DATA=$(date -Is)"
[[ -f "$DIARIO" && -w "$DIARIO" ]] || { echo "ERRO=DIARIO_INDISPONIVEL"; exit 2; }
for svc in conectaeduca-dmz-waf-1 conectaeduca-dmz-nginx-1 conectaeduca-dmz-php-1; do
  echo "CONTAINER=$svc"
  docker inspect "$svc" --format 'RUNNING={{.State.Running}} HEALTH={{if .State.Health}}{{.State.Health.Status}}{{else}}NAO_DEFINIDO{{end}}' || exit 2
done
echo "=== TESTE HTTP LOCAL VIA WAF ==="
if curl -kfsS --connect-timeout 3 --max-time 8 --output /dev/null --write-out 'WAF_HTTPS_HTTP_CODE=%{http_code}\n' --resolve conectaeduca.local:443:192.168.6.34 https://conectaeduca.local/healthz; then
  echo "WAF_HTTPS=OK"
else
  echo "WAF_HTTPS=FALHOU"
fi
echo "=== TESTE HTTP LOCAL DIRETO AO NGINX ==="
# Origem host EP125, não prova alcance de outro contêiner nem simula insider.
if curl -fsS --connect-timeout 2 --max-time 5 --output /dev/null --write-out 'NGINX_HOST_HTTP_CODE=%{http_code}\n' http://192.168.6.34:8088/healthz; then
  echo "NGINX_HOST_8088=ACESSIVEL"
else
  echo "NGINX_HOST_8088=NAO_ACESSIVEL"
fi
echo "=== SAIDA TCP PHP -> DB (SEM CREDENCIAIS) ==="
# O host/porta são obtidos apenas dentro do contêiner; nunca impressos.
if docker exec conectaeduca-dmz-php-1 sh -c '
  php -r '\''$h=getenv("DB_HOST"); $p=(int)(getenv("DB_PORT")?:3306); if(!$h){fwrite(STDERR,"DB_HOST_AUSENTE\n");exit(2);} $s=@fsockopen($h,$p,$e,$m,3); if($s){fclose($s);echo "DB_TCP=OK\n";} else {echo "DB_TCP=FALHOU\n";exit(1);}'\''
'; then
  echo "DB_CONNECTIVITY=OK"
else
  echo "DB_CONNECTIVITY=FALHOU_OU_NAO_TESTAVEL"
fi
echo "=== PORTAS PUBLICADAS ==="
for svc in conectaeduca-dmz-waf-1 conectaeduca-dmz-nginx-1 conectaeduca-dmz-php-1; do
  docker inspect "$svc" --format '{{.Name}} PUBLICACOES={{len .HostConfig.PortBindings}}'
done
STATUS="CONCLUIDO_BASELINE"
echo "OBSERVACAO=Teste direto de rede Docker e bypass exigem etapa específica controlada"
echo "IMPLANTACAO=NAO_EXECUTADA"
