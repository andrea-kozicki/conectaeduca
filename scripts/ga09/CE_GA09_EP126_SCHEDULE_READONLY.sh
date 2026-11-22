#!/usr/bin/env bash
# CE GA-09: observacao do Bacula; nao cria schedules, nao executa jobs ou restores.
set -u
umask 077
STAMP="$(date +%Y%m%dT%H%M%S)"
OUT="${HOME}/ConectaEduca_Fase2_Evidencias/EP126/GA09_SCHEDULE_${STAMP}"
mkdir -p "$OUT" || exit 1
REPORT="$OUT/resumo.txt"
{
 echo "CE GA09 EP126 — READ ONLY — $(date -Is)"
 echo "Host: $(hostname)"
 echo "=== Estado de containers ==="
 docker ps --format '{{.Names}} | {{.Status}}' 2>&1 | grep -Ei 'bacula|bacularis|pgbouncer|catalog' || true
 echo "=== Diretor identificado ==="
 DIRECTOR="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E '^conectaeduca-bacula-director$' | head -1)"
 if [ -z "$DIRECTOR" ]; then
   echo "Diretor nao localizado; sem leitura de configuracao."
 else
   echo "Diretor=$DIRECTOR"
   echo "=== Presenca de Schedule na configuracao runtime (sem exibir segredos) ==="
   docker exec "$DIRECTOR" sh -c 'if test -r /etc/bacula-runtime/bacula-dir.conf; then awk '"'"'/^[[:space:]]*Schedule[[:space:]]*\{/ {n++} END {print "SCHEDULE_BLOCKS=" n+0}'"'"' /etc/bacula-runtime/bacula-dir.conf; else echo "CONFIG_NAO_LEGIVEL"; fi' 2>&1 || true
   echo "=== Referencias Run/Schedule (contagem apenas) ==="
   docker exec "$DIRECTOR" sh -c 'if test -r /etc/bacula-runtime/bacula-dir.conf; then awk '"'"'/^[[:space:]]*Schedule[[:space:]]*=/ {n++} END {print "SCHEDULE_REFERENCES=" n+0}'"'"' /etc/bacula-runtime/bacula-dir.conf; fi' 2>&1 || true
 fi
 echo "=== Politica vigente ==="
 echo "BAC-05: backup manual aceito em 25/09; nao criar Schedule sem decisao formal e janela operacional."
 echo "=== Limites ==="
 echo "Contagens no arquivo principal nao excluem includes nem comprovam jobs recentes."
} > "$REPORT" 2>&1
sha256sum "$REPORT" > "$OUT/SHA256SUMS.txt"
echo "RELATORIO=$REPORT"
echo "HASHES=$OUT/SHA256SUMS.txt"
