#!/usr/bin/env bash
# GA-08: validar topologia SEM interpolar variáveis, sem carregar segredos.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125/GA08"
DIARIO="$HOME/ConectaEduca_Fase2_Evidencias/EP125/diario.md"
STAMP="$(date +%Y%m%dT%H%M%S)"
LOG="$BASE/GA08_TOPOLOGIA_SEM_ENV_$STAMP.txt"
CANDIDATO="$BASE/compose.ga08-segmentacao.candidate.yml"
mkdir -p "$BASE"
STATUS="FALHOU"
on_exit() {
  local rc=$?
  trap - EXIT
  { printf '\n## GA-08 — Topologia sem interpolação — %s\n' "$(date -Is)"; printf 'Status: %s\nEvidência: %s\nImplantação: NÃO EXECUTADA\n' "$STATUS" "$LOG"; } >> "$DIARIO" || true
  echo "STATUS=$STATUS"
  echo "EVIDENCIA=$LOG"
  exit "$rc"
}
trap on_exit EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA-08 — TOPOLOGIA SEM ENV ==="
echo "DATA=$(date -Is)"
echo "MODO=LEITURA_APENAS"
[[ -r "$CANDIDATO" && -w "$DIARIO" ]] || { echo "ERRO=ARQUIVO_CANDIDATO_OU_DIARIO_INDISPONIVEL"; exit 2; }
cd /opt/conectaeduca/deploy/dmz
raw="$(docker inspect conectaeduca-dmz-nginx-1 --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}')"
IFS=',' read -r -a files <<< "$raw"
args=()
for f in "${files[@]}"; do
  [[ -r "$f" ]] || { echo "ERRO=COMPOSE_INACESSIVEL"; exit 2; }
  args+=(-f "$f")
done
echo "ARQUIVOS_BASE=${#files[@]}"
# Compose --no-interpolate permite inspecionar a estrutura sem resolver variáveis obrigatórias.
# Nunca imprimir configuração completa: ela pode incluir caminhos internos.
TMP="$(mktemp "$BASE/.ga08-json.XXXXXX")"
ERR="$(mktemp "$BASE/.ga08-error.XXXXXX")"
trap 'rm -f "$TMP" "$ERR"; on_exit' EXIT
if ! docker compose "${args[@]}" -f "$CANDIDATO" config --no-interpolate --format json > "$TMP" 2>"$ERR"; then
  echo "CONFIG_SEM_INTERPOLACAO=FALHOU"
  echo "ERRO_COMPOSE=OCULTADO_POR_PRECAUCAO"
  exit 2
fi
python3 - "$TMP" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf8") as f: c=json.load(f)
expected={"waf":{"waf_backend"},"nginx":{"waf_backend","app_backend"},"php":{"app_backend"}}
for name,nets in expected.items():
    service=c["services"][name]
    actual=set(service.get("networks",{}))
    ports=service.get("ports",[])
    print(f"{name.upper()}_REDES={','.join(sorted(actual))}")
    print(f"{name.upper()}_PORTAS_PUBLICADAS={len(ports)}")
    if actual!=nets: sys.exit(f"REDES_INVALIDAS_{name}")
    if name!="waf" and ports: sys.exit(f"PORTAS_INDEVIDAS_{name}")
    if name=="waf" and len(ports)<2: sys.exit("PORTAS_WAF_INCOMPLETAS")
print("TOPOLOGIA_SEM_INTERPOLACAO=OK")
PY
STATUS="VALIDADO_PARCIAL"
echo "VARIAVEIS_RUNTIME=NAO_VALIDADAS"
echo "IMPLANTACAO=NAO_EXECUTADA"
