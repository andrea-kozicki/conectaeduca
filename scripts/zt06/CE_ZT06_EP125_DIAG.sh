#!/usr/bin/env bash
# ZT-06 EP125: somente leitura, sem sudo ou alteracoes de rede.
set -u
CONTAINER="conectaeduca-dmz-01"
OUT="$HOME/ConectaEduca_Fase2_Evidencias/EP125/ZT06_$(date +%Y%m%dT%H%M%S)"
mkdir -p "$OUT" || exit 1
chmod 700 "$OUT"
echo "UTC=$(date -u +%FT%TZ)" | tee "$OUT/resumo.txt"
docker inspect "$CONTAINER" --format 'Status={{.State.Status}} Health={{.State.Health.Status}} Restarts={{.RestartCount}}' | tee -a "$OUT/resumo.txt"
echo "=== Erros pubnub-lib nos ultimos 15 minutos ===" | tee -a "$OUT/resumo.txt"
docker logs --since 15m --timestamps "$CONTAINER" 2>&1 | grep 'TLS/SSL I/O operation failed with error code' | sed -E 's/^(\\S+).*error code: ([0-9]+).*$/\\1 codigo=\\2/' | tee -a "$OUT/resumo.txt"
sha256sum "$OUT/resumo.txt" > "$OUT/SHA256SUMS.txt"
echo "Resumo em: $OUT/resumo.txt"
echo "Revise antes de compartilhar."
