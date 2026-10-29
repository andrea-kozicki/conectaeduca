#!/usr/bin/env bash
# GA-08: gate deliberadamente fechado ate Compose, conectividade e rollback aprovados.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"; OUT="$BASE/GA08"
mkdir -p "$OUT"
LOG="$OUT/GA08_IMPLANTACAO_GATE_$(date +%Y%m%dT%H%M%S).txt"
exec > >(tee "$LOG") 2>&1
echo "=== GA08 IMPLANTACAO CONTROLADA: GATE FECHADO ==="
echo "DATA=$(date -Is)"
echo "MOTIVO=COMPOSE_E_ROLLBACK_AINDA_NAO_VALIDADOS"
echo "MOTIVO_2=DEPENDENCIAS_EP126_E_TESTES_DE_ISOLAMENTO_PENDENTES"
echo "APLICACAO=NAO_EXECUTADA"
echo "PRODUCAO=NAO_ALTERADA"
printf '\n## GA-08 — Gate de implantação — %s\nStatus: BLOQUEADO, sem alteração em produção\nEvidência: %s\n' "$(date -Is)" "$LOG" >> "$BASE/diario.md"
exit 3
