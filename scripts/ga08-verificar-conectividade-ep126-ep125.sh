#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"; OUT="$BASE/GA08"; DIARIO="$BASE/diario.md"
mkdir -p "$OUT"
LOG="$OUT/GA08_EP126_CONECTIVIDADE_$(date +%Y%m%dT%H%M%S).txt"
STATUS=INCONCLUSIVO
finish(){ rc=$?; trap - EXIT; printf '\n## GA-08 — Conectividade PHP-EP126 — %s\nStatus: %s\nEvidência: %s\nProdução: não alterada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true; echo "STATUS=$STATUS"; exit "$rc"; }
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 EP126 — TESTE TCP SEM CREDENCIAIS ==="
C=conectaeduca-dmz-php-1
docker inspect "$C" --format 'PHP_STATUS={{.State.Status}} HEALTH={{if .State.Health}}{{.State.Health.Status}}{{else}}SEM_HEALTHCHECK{{end}}'
# Rede TCP para o destino historicamente documentado; nao realiza autenticacao SQL.
if docker exec "$C" php -r '$h="192.168.6.50";$p=3306;$s=@fsockopen($h,$p,$errno,$errstr,3);if($s){fclose($s);echo "EP126_TCP3306=OK\n";exit(0);}echo "EP126_TCP3306=FALHOU\n";exit(2);'; then
 STATUS=TCP_EP126_OK
else
 STATUS=TCP_EP126_FALHOU
fi
echo "AUTENTICACAO_SQL=NAO_TESTADA"
echo "SEGREDOS=NAO_LIDOS"
echo "PRODUCAO=NAO_ALTERADA"
