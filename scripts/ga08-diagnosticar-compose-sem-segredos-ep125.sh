#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT=/opt/conectaeduca
BRANCH=origin/docs/fase3-arquitetura-zero-trust-20261021
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"
OUT="$BASE/GA08"; DIARIO="$BASE/diario.md"
mkdir -p "$OUT"
LOG="$OUT/GA08_COMPOSE_DIAGNOSTICO_$(date +%Y%m%dT%H%M%S).txt"
TMP=$(mktemp -d)
STATUS=DIAGNOSTICO_INCONCLUSIVO
finish(){ rc=$?; trap - EXIT; rm -rf "$TMP"; printf '\n## GA-08 — Diagnóstico Compose — %s\nStatus: %s\nEvidência: %s\nProdução: não alterada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true; echo "STATUS=$STATUS"; exit "$rc"; }
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 DIAGNOSTICO COMPOSE SEM SEGREDOS ==="
echo "DATA=$(date -Is)"
files=(compose.yml compose.database.yml compose.app-secrets.yml compose.waf.yml compose.waf-tls.yml compose.waf-policy.yml compose.host.yml compose.vm.yml compose.database-tls.yml compose.audit-persistent.yml)
args=()
for f in "${files[@]}"; do
 if [[ -r "$ROOT/deploy/dmz/$f" ]]; then args+=(-f "$ROOT/deploy/dmz/$f"); else echo "FALTA_BASE=$f"; fi
done
for p in deploy/dmz/compose.ga08-socket.candidate.yml deploy/dmz/ga08/app-http.socket.candidate.conf deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf; do
 git -C "$ROOT" show "$BRANCH:$p" > "$TMP/$(basename "$p")" || { echo "FALTA_CANDIDATO=$p"; STATUS=FALTA_CANDIDATO; exit 2; }
done
export CONECTAEDUCA_GA08_SOCKET_DIR="$TMP/socket"
export CONECTAEDUCA_GA08_NGINX_CONF="$TMP/app-http.socket.candidate.conf"
export CONECTAEDUCA_GA08_FPM_CONF="$TMP/zz-conectaeduca.socket.candidate.conf"
args+=(-f "$TMP/compose.ga08-socket.candidate.yml")
# Capturar stderr somente em arquivo temporário privado e classificar sem imprimir valores.
set +e
docker compose --project-directory "$ROOT/deploy/dmz" "${args[@]}" config --quiet >"$TMP/stdout" 2>"$TMP/stderr"
rc=$?
set -e
echo "COMPOSE_EXIT=$rc"
if [[ $rc -eq 0 ]]; then STATUS=COMPOSE_OK; echo "COMPOSE_CONFIG=PASS"; exit 0; fi
python3 - "$TMP/stderr" <<'PY'
import re,sys
s=open(sys.argv[1],encoding="utf-8",errors="replace").read()
patterns=[
 ("VARIAVEL_OBRIGATORIA",r"required variable|variable is not set|is required|must be set"),
 ("ARQUIVO_COMPOSE_AUSENTE",r"no such file or directory|cannot find|not found"),
 ("ERRO_YAML",r"yaml:|mapping values are not allowed|did not find expected"),
 ("OVERRIDE_INCOMPATIVEL",r"override|!override|unrecognized tag"),
 ("SERVICO_INVALIDO",r"services\.|additional properties|invalid type|validation failed"),
 ("AMBIENTE_DOTENV",r"env file|\.env"),
 ("PERMISSAO",r"permission denied"),
]
matched=[name for name,pat in patterns if re.search(pat,s,re.I)]
print("CLASSES_ERRO="+(",".join(matched) if matched else "DESCONHECIDA"))
print("LINHAS_ERRO="+str(len(s.splitlines())))
print("ERRO_BRUTO=NAO_EXIBIDO")
PY
STATUS=COMPOSE_INVALIDO_CLASSIFICADO
