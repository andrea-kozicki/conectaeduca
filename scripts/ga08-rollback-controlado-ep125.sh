#!/usr/bin/env bash
# GA-08: verifica precondicoes de rollback; nao executa mudancas automaticamente.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"; OUT="$BASE/GA08"
mkdir -p "$OUT"
LOG="$OUT/GA08_ROLLBACK_PREFLIGHT_$(date +%Y%m%dT%H%M%S).txt"
exec > >(tee "$LOG") 2>&1
echo "=== GA08 ROLLBACK: PREPARACAO SOMENTE LEITURA ==="
echo "DATA=$(date -Is)"
echo "ESTADO=SEM_IMPLANTACAO_GA08_AUTORIZADA"
for c in conectaeduca-dmz-php-1 conectaeduca-dmz-nginx-1 conectaeduca-dmz-waf-1; do
  docker inspect "$c" --format 'CONTAINER={{.Name}} IMAGE={{.Image}} STATUS={{.State.Status}}'
done
echo "ROLLBACK_EXECUTADO=NAO"
echo "PENDENCIA=SNAPSHOT_COMPOSE_CONFIG_ENV_E_TESTE_DE_RESTAURACAO"
printf '\n## GA-08 — Preflight rollback — %s\nStatus: somente leitura; rollback não executado\nEvidência: %s\n' "$(date -Is)" "$LOG" >> "$BASE/diario.md"
