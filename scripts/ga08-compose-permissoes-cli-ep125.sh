#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"; OUT="$BASE/GA08"; DIARIO="$BASE/diario.md"
mkdir -p "$OUT"; LOG="$OUT/GA08_COMPOSE_PERMISSOES_CLI_$(date +%Y%m%dT%H%M%S).txt"
STATUS=INCONCLUSIVO
finish(){ rc=$?; trap - EXIT; printf '\n## GA-08 — Docker Compose permissões de execução — %s\nStatus: %s\nEvidência: %s\nProdução: não alterada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true; echo "STATUS=$STATUS"; exit "$rc"; }
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 COMPOSE — DIAGNOSTICO DE PERMISSOES DE PROCESSO ==="
python3 - <<'PY'
import os,subprocess
print('EUID='+str(os.geteuid()))
for name,cmd in [
 ('PYTHON_DOCKER_VERSION',['docker','compose','version']),
 ('PYTHON_DOCKER_INFO',['docker','info','--format','{{.ServerVersion}}']),
 ('PYTHON_COMPOSE_MINIMAL',['docker','compose','-f','/dev/null','config','--quiet'])
]:
 try:
  p=subprocess.run(cmd,capture_output=True,timeout=12)
  print(name+'_EXIT='+str(p.returncode))
  err=p.stderr.decode('utf-8','replace').strip().lower()
  if 'permission denied' in err: label='PERMISSAO_NEGADA'
  elif 'unknown flag' in err: label='FLAG_INVALIDA'
  elif 'unknown command' in err: label='COMANDO_INVALIDO'
  elif 'no configuration' in err or 'empty compose' in err: label='CONFIG_VAZIA'
  elif 'docker' in err and 'not found' in err: label='EXECUTAVEL_NAO_ENCONTRADO'
  elif 'error' in err: label='ERRO_GENERICO'
  elif err: label='OUTRA_MENSAGEM'
  else: label='SEM_STDERR'
  print(name+'_CLASSE='+label)
 except (OSError,subprocess.TimeoutExpired) as e:
  print(name+'_EXCECAO='+type(e).__name__)
print('PRODUCAO=NAO_ALTERADA')
PY
STATUS=DIAGNOSTICO_PERMISSOES_CONCLUIDO
