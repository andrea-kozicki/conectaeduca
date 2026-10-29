#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT=/opt/conectaeduca
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"
OUT="$BASE/GA08"; DIARIO="$BASE/diario.md"
mkdir -p "$OUT"
LOG="$OUT/GA08_PREPARACAO_$(date +%Y%m%dT%H%M%S).txt"
STATUS=PENDENTE
finish(){ rc=$?; trap - EXIT; [[ $rc -eq 0 ]] && STATUS=PREPARADO || STATUS=BLOQUEADO; printf '\n## GA-08 — Preparação controlada — %s\nStatus: %s\nEvidência: %s\nProdução: não alterada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO"; echo "STATUS=$STATUS"; exit "$rc"; }
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 PREPARACAO SOMENTE LEITURA ==="
test -d "$ROOT/.git"
test -w "$DIARIO"
for p in deploy/dmz/compose.ga08-socket.candidate.yml deploy/dmz/ga08/app-http.socket.candidate.conf deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf; do
  test -r "$ROOT/$p" || { echo "BLOQUEIO=ARQUIVO_AUSENTE:$p"; exit 2; }
  sha256sum "$ROOT/$p"
done
for c in conectaeduca-dmz-php-1 conectaeduca-dmz-nginx-1 conectaeduca-dmz-waf-1; do
  docker inspect "$c" --format 'CONTAINER={{.Name}} STATUS={{.State.Status}} HEALTH={{if .State.Health}}{{.State.Health.Status}}{{else}}SEM_HEALTHCHECK{{end}}'
done
echo "COMPOSE_STATIC=PENDENTE"
echo "ROLLBACK_TESTADO=NAO"
echo "APLICACAO=NAO_EXECUTADA"
