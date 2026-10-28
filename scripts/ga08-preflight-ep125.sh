#!/usr/bin/env bash
# GA-08 — preflight seguro, sem alterar runtime. Executar na EP125.
set -Eeuo pipefail
umask 077

BASE="${HOME}/ConectaEduca_Fase2_Evidencias/EP125/GA08"
DIARIO="${HOME}/ConectaEduca_Fase2_Evidencias/EP125/diario.md"
STAMP="$(date +%Y%m%dT%H%M%S)"
LOG="${BASE}/GA08_PREFLIGHT_GITHUB_${STAMP}.txt"
CANDIDATO="${BASE}/compose.ga08-segmentacao.candidate.yml"
mkdir -p "$BASE"
STATUS="BLOQUEADO"
motivo="Não iniciado"
registrar() {
  local rc=$?
  trap - EXIT
  if [[ "$STATUS" != "OK" && "$rc" -eq 0 ]]; then rc=2; fi
  {
    printf '\n## GA-08 — Preflight versionado — %s\n' "$(date -Is)"
    printf 'Status: %s\nMotivo: %s\nEvidência: %s\nImplantação: NÃO EXECUTADA\n' "$STATUS" "$motivo" "$LOG"
  } >> "$DIARIO" || printf 'AVISO: não foi possível atualizar o diário\n' >&2
  printf '\nSTATUS=%s\nEVIDENCIA=%s\nDIARIO=%s\n' "$STATUS" "$LOG" "$DIARIO"
  exit "$rc"
}
trap registrar EXIT

[[ -f "$DIARIO" && -w "$DIARIO" ]] || { echo "ERRO: diário não disponível: $DIARIO" >&2; exit 3; }
exec > >(tee "$LOG") 2>&1
echo "=== GA-08 — PREFLIGHT VERSIONADO ==="
echo "DATA=$(date -Is)"
echo "EXECUCAO=LEITURA_APENAS"
echo "COMPOSE=$(docker compose version --short)"
[[ -r "$CANDIDATO" ]] || { motivo="Overlay candidato ausente"; echo "$motivo"; exit 2; }
[[ -d /opt/conectaeduca/deploy/dmz ]] || { motivo="Diretório de deploy ausente"; echo "$motivo"; exit 2; }
cd /opt/conectaeduca/deploy/dmz

# Respeitar exatamente os arquivos/ordem registrados no contêiner existente.
FILES_RAW="$(docker inspect conectaeduca-dmz-nginx-1 --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}')"
[[ -n "$FILES_RAW" && "$FILES_RAW" != "<no value>" ]] || { motivo="Labels Compose indisponíveis"; echo "$motivo"; exit 2; }
IFS=',' read -r -a FILES <<< "$FILES_RAW"
ARGS=()
for file in "${FILES[@]}"; do
  [[ -r "$file" ]] || { motivo="Arquivo Compose inacessível: $(basename "$file")"; echo "$motivo"; exit 2; }
  ARGS+=(-f "$file")
  printf 'COMPOSE_FILE=%s\n' "$(basename "$file")"
done

# Nunca carregar um arquivo .env desconhecido automaticamente. Mostrar somente caminhos.
if [[ -n "${GA08_ENV_FILE:-}" ]]; then
  [[ -r "$GA08_ENV_FILE" ]] || { motivo="GA08_ENV_FILE não legível"; echo "$motivo"; exit 2; }
  ENV_ARGS=(--env-file "$GA08_ENV_FILE")
  echo "ENV_FILE=FORNECIDO_PELO_OPERADOR"
else
  ENV_ARGS=()
  echo "ENV_FILE=NAO_INFORMADO"
  for candidate in /opt/conectaeduca/deploy/dmz/.env /opt/conectaeduca/.env; do
    [[ -f "$candidate" ]] && printf 'ENV_CANDIDATO=%s\n' "$candidate"
  done
fi

for var in CONECTAEDUCA_DB_HOST CONECTAEDUCA_DB_PASSWORD_FILE CONECTAEDUCA_APP_URL CONECTAEDUCA_WAF_BIND_ADDRESS; do
  [[ -n "${!var:-}" ]] && echo "$var=DEFINIDA" || echo "$var=AUSENTE_NO_SHELL"
done

# Capturar erros de interpolação sem divulgar conteúdo de configuração resolvida.
ERR="$(mktemp "$BASE/.ga08-err.XXXXXX")"
trap 'rm -f "$ERR"; registrar' EXIT
if ! docker compose "${ENV_ARGS[@]}" "${ARGS[@]}" -f "$CANDIDATO" config --quiet 2>"$ERR"; then
  motivo="Compose não validou; variáveis de implantação ou overlays pendentes"
  echo "CONFIG_VALIDACAO=FALHOU"
  # Não imprimir stderr bruto, que pode conter valores sensíveis.
  echo "DETALHES=omitidos_por_seguranca"
  exit 2
fi
echo "CONFIG_VALIDACAO=OK"

# JSON processado somente por pipe; Python imprime apenas contagem de portas e nomes de redes.
if ! docker compose "${ENV_ARGS[@]}" "${ARGS[@]}" -f "$CANDIDATO" config --format json 2>"$ERR" |
python3 -c '
import json,sys
try: cfg=json.load(sys.stdin)
except Exception: sys.exit("CONFIG_JSON_INVALIDO")
wanted={"waf":{"waf_backend"},"nginx":{"waf_backend","app_backend"},"php":{"app_backend"}}
for name,expected in wanted.items():
    svc=cfg["services"][name]
    nets=set(svc.get("networks",{}))
    ports=svc.get("ports",[])
    print(f"{name.upper()}_REDES={sorted(nets)}")
    print(f"{name.upper()}_PORTAS_PUBLICADAS={len(ports)}")
    if nets != expected: sys.exit(f"REDES_INVALIDAS_{name}")
    if name in ("nginx","php") and ports: sys.exit(f"PORTAS_INDEVIDAS_{name}")
    if name=="waf":
        published={str(p.get("published")) for p in ports}
        if not {"80","443"}.issubset(published): sys.exit("WAF_SEM_80_443")
print("TOPOLOGIA=OK")
'; then
  motivo="Topologia candidata não validada"
  exit 2
fi

STATUS="OK"
motivo="Sintaxe e topologia validadas; ainda requer checagem de conectividade e rollback antes de implantar"
echo "IMPLANTACAO=NAO_EXECUTADA"
