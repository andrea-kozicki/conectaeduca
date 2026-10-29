#!/usr/bin/env bash
# GA-08 — validação estática do candidato; funciona em checkout ou git archive.
set -Eeuo pipefail
umask 077
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125/GA08"
DIARIO="$HOME/ConectaEduca_Fase2_Evidencias/EP125/diario.md"
mkdir -p "$BASE"
LOG="$BASE/GA08_SOCKET_STATIC_$(date +%Y%m%dT%H%M%S).txt"
STATUS="FALHOU"
finish(){
  local rc=$?
  trap - EXIT
  if [[ -f "$DIARIO" && -w "$DIARIO" ]]; then
    printf '\n## GA-08 — Candidato socket (validação estática) — %s\nStatus: %s\nEvidência: %s\nImplantação: não executada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO"
  else
    echo "AVISO=DIARIO_NAO_ATUALIZADO"
  fi
  echo "STATUS=$STATUS"
  echo "EVIDENCIA=$LOG"
  echo "DIARIO=$DIARIO"
  exit "$rc"
}
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 — SOCKET STATIC ==="
echo "DATA=$(date -Is)"
echo "MODO=LEITURA_APENAS"
C="$ROOT/deploy/dmz/compose.ga08-socket.candidate.yml"
N="$ROOT/deploy/dmz/ga08/app-http.socket.candidate.conf"
P="$ROOT/deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf"
for f in "$C" "$N" "$P"; do [[ -r "$f" ]] || { echo "ARQUIVO_AUSENTE=$(basename "$f")"; exit 2; }; done
echo "ARQUIVOS_CANDIDATOS=3"
python3 - "$C" "$N" "$P" <<'PY'
import pathlib,sys,re
c,n,p=(pathlib.Path(x).read_text() for x in sys.argv[1:])
assert 'php_egress' in c and 'waf_backend' in c
assert 'app_backend' not in c
assert 'fastcgi_pass php:9000' not in n
assert len(re.findall(r'fastcgi_pass unix:/run/conectaeduca-fpm/php-fpm.sock;',n))>=5
assert 'listen = /run/conectaeduca-fpm/php-fpm.sock' in p
assert 'listen.mode = 0660' in p
print('CONTRATO_ESTATICO=OK')
PY
echo "PENDENTE=COMPOSE_EFETIVO_PERMISSOES_REDE_EGRESS_ROLLBACK"
echo "NAO_EXECUTAR_COMPOSE_UP=SIM"
STATUS="VALIDADO_ESTATICAMENTE"
