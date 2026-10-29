#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT=/opt/conectaeduca
BRANCH=origin/docs/fase3-arquitetura-zero-trust-20261021
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"
OUT="$BASE/GA08"; DIARIO="$BASE/diario.md"
mkdir -p "$OUT"
LOG="$OUT/GA08_PREPARACAO_$(date +%Y%m%dT%H%M%S).txt"
STATUS=PENDENTE
finish(){ rc=$?; trap - EXIT; if [[ $rc -eq 0 ]]; then STATUS=PREPARADO; else STATUS=BLOQUEADO; fi; printf '\n## GA-08 — Preparação controlada — %s\nStatus: %s\nEvidência: %s\nProdução: não alterada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true; echo "STATUS=$STATUS"; exit "$rc"; }
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 PREPARACAO SOMENTE LEITURA ==="
test -d "$ROOT/.git"
test -w "$DIARIO"
git -C "$ROOT" rev-parse --verify "$BRANCH^{commit}" >/dev/null || { echo "BLOQUEIO=BRANCH_NAO_DISPONIVEL"; exit 2; }
echo "FONTE=$BRANCH"
echo "COMMIT=$(git -C "$ROOT" rev-parse "$BRANCH")"
for p in deploy/dmz/compose.ga08-socket.candidate.yml deploy/dmz/ga08/app-http.socket.candidate.conf deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf; do
  git -C "$ROOT" cat-file -e "$BRANCH:$p" || { echo "BLOQUEIO=ARQUIVO_AUSENTE_NA_BRANCH:$p"; exit 2; }
  hash=$(git -C "$ROOT" show "$BRANCH:$p" | sha256sum | cut -d' ' -f1)
  echo "CANDIDATO=$p SHA256=$hash"
done
for c in conectaeduca-dmz-php-1 conectaeduca-dmz-nginx-1 conectaeduca-dmz-waf-1; do
  docker inspect "$c" --format 'CONTAINER={{.Name}} STATUS={{.State.Status}} HEALTH={{if .State.Health}}{{.State.Health.Status}}{{else}}SEM_HEALTHCHECK{{end}}'
done
echo "COMPOSE_STATIC=PENDENTE"
echo "ROLLBACK_TESTADO=NAO"
echo "APLICACAO=NAO_EXECUTADA"
