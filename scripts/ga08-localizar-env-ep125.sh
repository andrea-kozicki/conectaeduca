#!/usr/bin/env bash
# GA-08: localizar origem das variáveis sem imprimir valores nem alterar serviços.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125/GA08"
DIARIO="$HOME/ConectaEduca_Fase2_Evidencias/EP125/diario.md"
STAMP="$(date +%Y%m%dT%H%M%S)"
LOG="$BASE/GA08_ORIGEM_ENV_$STAMP.txt"
mkdir -p "$BASE"
STATUS="BLOQUEADO"
finish() {
  local rc=$?
  trap - EXIT
  {
    echo
    echo "## GA-08 — Origem das variáveis — $(date -Is)"
    echo "Status: $STATUS"
    echo "Evidência: $LOG"
    echo "Implantação: não executada"
  } >> "$DIARIO" || true
  echo "STATUS=$STATUS"
  echo "EVIDENCIA=$LOG"
  echo "DIARIO=$DIARIO"
  exit "$rc"
}
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 — ORIGEM DAS VARIAVEIS ==="
echo "DATA=$(date -Is)"
echo "MODO=LEITURA_APENAS"
[[ -f "$DIARIO" && -w "$DIARIO" ]] || { echo "DIARIO_INDISPONIVEL"; exit 2; }

# Exibe apenas existência e permissões resumidas; não lê valores de arquivos.
for dir in /opt/conectaeduca /opt/conectaeduca/deploy/dmz /etc/conectaeduca; do
  [[ -d "$dir" ]] || continue
  echo "DIRETORIO=$dir"
  for name in .env .env.production env.production deploy.env stack.env; do
    path="$dir/$name"
    if [[ -e "$path" ]]; then
      [[ -r "$path" ]] && readflag=SIM || readflag=NAO
      echo "ENV_CANDIDATO=$path LEGIVEL=$readflag"
    fi
  done
done

# Consultar somente nomes das variáveis presentes no ambiente do contêiner;
# não imprimir o conteúdo e não inspecionar secrets.
for svc in conectaeduca-dmz-php-1 conectaeduca-dmz-waf-1; do
  echo "CONTAINER=$svc"
  if docker inspect "$svc" >/dev/null 2>&1; then
    docker inspect "$svc" --format '{{range .Config.Env}}{{println .}}{{end}}' |
    awk -F= '/^CONECTAEDUCA_[A-Za-z0-9_]*=/ {print $1"=PRESENTE_NO_CONTAINER"}' |
    sort -u
  else
    echo "CONTAINER_INACESSIVEL"
  fi
done

# Somente nomes de arquivos que referenciam os nomes de variáveis; não mostrar linhas.
for dir in /opt/conectaeduca/deploy /opt/conectaeduca/scripts; do
  [[ -d "$dir" ]] || continue
  grep -rlE --include='*.sh' --include='*.service' --include='*.md' --include='*.yml' --include='*.yaml' --include='*.env.example' \
    'CONECTAEDUCA_DB_PASSWORD_FILE|CONECTAEDUCA_WAF_BIND_ADDRESS' "$dir" 2>/dev/null |
    head -30 | while IFS= read -r path; do echo "REFERENCIA=$(basename "$path")"; done
done
STATUS="OK"
echo "PROXIMO_PASSO=IDENTIFICAR_ORIGEM_AUTORIZADA_SEM_EXIBIR_SEGREDOS"
