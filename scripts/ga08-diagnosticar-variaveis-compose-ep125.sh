#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT=/opt/conectaeduca
BRANCH=origin/docs/fase3-arquitetura-zero-trust-20261021
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"; OUT="$BASE/GA08"
mkdir -p "$OUT"
LOG="$OUT/GA08_COMPOSE_VARIAVEIS_$(date +%Y%m%dT%H%M%S).txt"
TMP=$(mktemp -d)
STATUS=INCONCLUSIVO
finish(){ rc=$?; trap - EXIT; rm -rf "$TMP"; printf '\n## GA-08 — Diagnóstico de variáveis Compose — %s\nStatus: %s\nEvidência: %s\nProdução: não alterada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$BASE/diario.md" || true; echo "STATUS=$STATUS"; exit "$rc"; }
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 COMPOSE: NOMES DE VARIAVEIS, SEM VALORES ==="
files=(compose.yml compose.database.yml compose.app-secrets.yml compose.waf.yml compose.waf-tls.yml compose.waf-policy.yml compose.host.yml compose.vm.yml compose.database-tls.yml compose.audit-persistent.yml)
args=()
for f in "${files[@]}"; do
 test -r "$ROOT/deploy/dmz/$f" || { echo "FALTA_BASE=$f"; STATUS=ARQUIVO_AUSENTE; exit 2; }
 args+=(-f "$ROOT/deploy/dmz/$f")
done
git -C "$ROOT" show "$BRANCH:deploy/dmz/compose.ga08-socket.candidate.yml" > "$TMP/overlay.yml"
git -C "$ROOT" show "$BRANCH:deploy/dmz/ga08/app-http.socket.candidate.conf" > "$TMP/nginx.conf"
git -C "$ROOT" show "$BRANCH:deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf" > "$TMP/fpm.conf"
export CONECTAEDUCA_GA08_SOCKET_DIR="$TMP/socket"
export CONECTAEDUCA_GA08_NGINX_CONF="$TMP/nginx.conf"
export CONECTAEDUCA_GA08_FPM_CONF="$TMP/fpm.conf"
args+=(-f "$TMP/overlay.yml")
set +e
docker compose --project-directory "$ROOT/deploy/dmz" "${args[@]}" config --quiet > "$TMP/stdout" 2> "$TMP/stderr"
rc=$?
set -e
echo "COMPOSE_EXIT=$rc"
python3 - "$TMP/stderr" <<'PY'
import re,sys
s=open(sys.argv[1],encoding='utf-8',errors='replace').read()
found=set()
for pattern in [r'(?i)(?:required variable|variable)\s+["\x27]?([A-Z][A-Z0-9_]+)',r'(?i)\$\{([A-Z][A-Z0-9_]+)',r'(?i)\b([A-Z][A-Z0-9_]+)\s+(?:is required|is not set|must be set)']:
 for v in re.findall(pattern,s):
  if re.fullmatch(r'[A-Z][A-Z0-9_]*',v): found.add(v)
print('VARIAVEIS_IDENTIFICADAS='+(','.join(sorted(found)) if found else 'NENHUMA'))
print('MENSAGEM_SANITIZADA=NAO_EXIBIDA')
print('LINHAS_ERRO='+str(len(s.splitlines())))
PY
if [[ $rc -eq 0 ]]; then STATUS=COMPOSE_OK; else STATUS=VARIAVEIS_IDENTIFICADAS_OU_INCONCLUSIVO; fi
echo "PRODUCAO=NAO_ALTERADA"
