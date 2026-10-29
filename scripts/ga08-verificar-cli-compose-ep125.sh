#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT=/opt/conectaeduca
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"; OUT="$BASE/GA08"; DIARIO="$BASE/diario.md"
mkdir -p "$OUT"
LOG="$OUT/GA08_COMPOSE_CLI_$(date +%Y%m%dT%H%M%S).txt"
STATUS=INCONCLUSIVO
finish(){ rc=$?; trap - EXIT; printf '\n## GA-08 — Compatibilidade CLI Compose — %s\nStatus: %s\nEvidência: %s\nProdução: não alterada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true; echo "STATUS=$STATUS"; exit "$rc"; }
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 COMPOSE CLI — TESTE MINIMO SEM CONFIGURACAO REAL ==="
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; finish' EXIT
printf 'services:\n  ga08_probe:\n    image: busybox:latest\n' > "$TMP/compose.yml"
python3 - "$TMP" <<'PY'
import subprocess,sys
d=sys.argv[1]
tests=[
 ('BASE',['docker','compose','-f',d+'/compose.yml','config','--quiet']),
 ('PROJECT_DIRECTORY',['docker','compose','--project-directory',d,'-f',d+'/compose.yml','config','--quiet']),
 ('PROJECT_DIRECTORY_AFTER_F',['docker','compose','-f',d+'/compose.yml','--project-directory',d,'config','--quiet']),
]
for name,cmd in tests:
 p=subprocess.run(cmd,capture_output=True,text=True)
 print(name+'_EXIT='+str(p.returncode))
 if p.returncode:
  e=p.stderr.strip()
  if 'unknown flag' in e.lower(): category='FLAG_DESCONHECIDA'
  elif 'unknown command' in e.lower(): category='COMANDO_DESCONHECIDO'
  elif 'permission denied' in e.lower(): category='PERMISSAO'
  elif 'no configuration file' in e.lower(): category='SEM_CONFIG'
  else: category='OUTRO'
  print(name+'_ERRO='+category)
print('PRODUCAO=NAO_ALTERADA')
PY
STATUS=DIAGNOSTICO_CLI_CONCLUIDO
