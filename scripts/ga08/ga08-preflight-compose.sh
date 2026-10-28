#!/usr/bin/env bash
# GA-08: preflight somente leitura. Nao imprime variaveis, segredos nem compose resolvido.
set -Eeuo pipefail
umask 077

ROOT="/opt/conectaeduca/deploy/dmz"
BASE="${HOME}/ConectaEduca_Fase2_Evidencias/EP125/GA08"
DIARIO="${HOME}/ConectaEduca_Fase2_Evidencias/EP125/diario.md"
STAMP="$(date +%Y%m%dT%H%M%S)"
LOG="${BASE}/GA08_PREFLIGHT_GITHUB_${STAMP}.txt"
CANDIDATE="${BASE}/compose.ga08-segmentacao.candidate.yml"
mkdir -p "$BASE"

status="FALHOU"
finish() {
  local rc=$?
  if [[ $rc -eq 0 ]]; then status="OK"; fi
  printf 'PREFLIGHT=%s\nIMPLANTACAO=NAO_EXECUTADA\nEVIDENCIA=%s\n' "$status" "$LOG" | tee -a "$LOG"
  if [[ -f "$DIARIO" && -w "$DIARIO" ]]; then
    printf '\n## GA-08 — Preflight GitHub — %s\nStatus: %s\nEvidencia: %s\nImplantacao: nao executada\n' "$(date -Is)" "$status" "$LOG" >> "$DIARIO"
  else
    printf 'AVISO=DIARIO_INDISPONIVEL\n' | tee -a "$LOG"
  fi
}
trap finish EXIT

{
  echo "=== GA-08 PREFLIGHT GITHUB ==="
  echo "DATA=$(date -Is)"
  docker compose version
  [[ -r "$CANDIDATE" ]] || { echo "ERRO=CANDIDATO_AUSENTE"; exit 2; }
  [[ -d "$ROOT" ]] || { echo "ERRO=RAIZ_COMPOSE_AUSENTE"; exit 2; }
  cd "$ROOT"

  mapfile -t files < <(docker inspect conectaeduca-dmz-nginx-1 --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' | tr ',' '\n')
  (( ${#files[@]} > 0 )) || { echo "ERRO=LISTA_COMPOSE_VAZIA"; exit 2; }
  args=()
  for f in "${files[@]}"; do
    [[ -r "$f" ]] || { echo "ERRO=ARQUIVO_COMPOSE_INACESSIVEL:$(basename "$f")"; exit 2; }
    args+=(-f "$f")
    echo "COMPOSE=$(basename "$f")"
  done

  # Apenas nomes de arquivos e presenca de variaveis, nunca valores.
  for d in "$ROOT" /opt/conectaeduca /opt/conectaeduca/deploy; do
    [[ -f "$d/.env" ]] && echo "ENV_FILE_PRESENTE=$d/.env"
  done
  for key in CONECTAEDUCA_DB_HOST CONECTAEDUCA_DB_PASSWORD_FILE CONECTAEDUCA_APP_URL CONECTAEDUCA_WAF_BIND_ADDRESS; do
    if [[ -n "${!key:-}" ]]; then echo "VAR_${key}=SESSAO"; else echo "VAR_${key}=NAO_EXPORTADA"; fi
  done

  # Docker Compose carrega .env do diretorio de trabalho se existente.
  # Sem .env ou variaveis, reportar erro sem mascarar falha.
  echo "ETAPA=VALIDAR_COMPOSE"
  docker compose "${args[@]}" -f "$CANDIDATE" config --quiet
  echo "COMPOSE=VALIDO"

  echo "ETAPA=VERIFICAR_TOPOLOGIA"
  docker compose "${args[@]}" -f "$CANDIDATE" config --format json |
    python3 -c '
import json,sys
cfg=json.load(sys.stdin)
expected={"waf":{"waf_backend"},"nginx":{"waf_backend","app_backend"},"php":{"app_backend"}}
for name,want in expected.items():
    svc=cfg["services"][name]
    actual=set(svc.get("networks") or {})
    ports=svc.get("ports") or []
    print(f"{name.upper()}_REDES={','.join(sorted(actual))}")
    print(f"{name.upper()}_PORTAS_PUBLICADAS={len(ports)}")
    if actual != want: raise SystemExit(f"ERRO=REDES_{name}")
    if name != "waf" and ports: raise SystemExit(f"ERRO=PORTAS_{name}")
    if name == "waf" and not {80,443}.issubset({int(p["published"]) for p in ports if p.get("published")}):
        raise SystemExit("ERRO=PORTAS_WAF")
print("TOPOLOGIA_CANDIDATA=OK")
'
} > "$LOG" 2>&1 || { cat "$LOG"; exit 1; }
cat "$LOG"
