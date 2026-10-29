#!/usr/bin/env bash
# GA-08 — validar candidato do repositório sem implantar nem exigir segredos.
set -Eeuo pipefail
umask 077
ROOT="$(git rev-parse --show-toplevel)"
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125/GA08"
DIARIO="$HOME/ConectaEduca_Fase2_Evidencias/EP125/diario.md"
mkdir -p "$BASE"
LOG="$BASE/GA08_SOCKET_STATIC_$(date +%Y%m%dT%H%M%S).txt"
STATUS="FALHOU"
finish(){ rc=$?; trap - EXIT; printf '\n## GA-08 — Candidato socket (validação estática) — %s\nStatus: %s\nEvidência: %s\nImplantação: não executada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true; echo "STATUS=$STATUS"; echo "EVIDENCIA=$LOG"; exit "$rc"; }
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 — SOCKET STATIC ==="
echo "DATA=$(date -Is)"
[[ -w "$DIARIO" ]] || { echo "DIARIO_INDISPONIVEL"; exit 2; }
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
echo "OBSERVACAO=Compose efetivo, permissões de bind mount, rede de saída e rollback ainda pendentes"
echo "NAO_EXECUTAR_COMPOSE_UP=SIM"
STATUS="VALIDADO_ESTATICAMENTE"
