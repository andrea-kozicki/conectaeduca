#!/usr/bin/env bash
# CE EP126: acrescenta registro auditavel ao diario local. Executar APOS preflights.
set -euo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP126"
DIARY="$BASE/diario.md"
MARK="CE-EP126-20261031-ZT06-GA09"
if [ ! -f "$DIARY" ]; then echo "ERRO: diario nao encontrado: $DIARY" >&2; exit 2; fi
if grep -Fq "$MARK" "$DIARY"; then echo "Registro ja existe; nenhuma alteracao."; exit 0; fi
ZT="$(find "$BASE" -maxdepth 2 -type f -path '*/ZT06_PREFLIGHT_*/resumo.txt' -print 2>/dev/null | sort | tail -1)"
GA="$(find "$BASE" -maxdepth 2 -type f -path '*/GA09_SCHEDULE_*/resumo.txt' -print 2>/dev/null | sort | tail -1)"
if [ -z "$ZT" ] || [ -z "$GA" ]; then echo "ERRO: rode os dois preflights antes de atualizar o diario." >&2; exit 3; fi
BACKUP="$DIARY.bak.$(date +%Y%m%dT%H%M%S)"
cp -p -- "$DIARY" "$BACKUP"
{
 printf '\n## %s — Diagnosticos read-only EP126 (%s)\n' "$MARK" "$(date -Is)"
 printf '%s\n' '- Guacamole: sessao observada 10.96.43.36 -> 192.168.6.50:3390/TCP, associada a LAN49 na tabela de estados do pfSense.'
 printf '%s\n' '- Segmentacao LAN33/LAN49: suporte consultado; regra historica causadora do bloqueio ainda nao identificada. Nenhuma mudanca de firewall nesta coleta.'
 printf '%s\n' '- Bacula: contêineres em execucao na coleta anterior; schedules e execucoes automaticas nao inferidos do estado healthy. Politica BAC-05 de backups manuais permanece ate decisao formal.'
 printf '%s\n' '- Twingate EP126: preflight executado, Connector nao instalado por estes scripts; topologia e autorizacao pendentes.'
 printf 'Evidencia ZT06: %s\n' "$ZT"
 printf 'SHA256 ZT06: %s\n' "$(sha256sum "$ZT" | awk '{print $1}')"
 printf 'Evidencia GA09: %s\n' "$GA"
 printf 'SHA256 GA09: %s\n' "$(sha256sum "$GA" | awk '{print $1}')"
 printf '%s\n' '- Os resultados tecnicos detalhados estao nos relatórios acima; revisar antes de concluir aptidao para deploy.'
} >> "$DIARY"
sha256sum "$DIARY" > "$BASE/diario.sha256"
echo "DIARIO_ATUALIZADO=$DIARY"
echo "BACKUP=$BACKUP"
echo "HASH=$BASE/diario.sha256"
