#!/usr/bin/env bash
# EP125 — 17B2: mapeamento estatico de controles RBAC/CSRF.
# Somente leitura; nao imprime codigo, caminhos, cookies ou credenciais.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"
mkdir -p "$BASE/HOMOLOG"
OUT="$BASE/HOMOLOG/EP125_HOMOLOG_ETAPA17B2_$(date +%Y%m%dT%H%M%S).txt"
PHP="${PHP_CONTAINER:-conectaeduca-dmz-php-1}"
{
 echo "ETAPA=17B2 DATA=$(date --iso-8601=seconds)"
 docker inspect "$PHP" --format 'CONTAINER={{.Name}} STATUS={{.State.Status}} HEALTH={{if .State.Health}}{{.State.Health.Status}}{{else}}NA{{end}}'
 docker exec -i "$PHP" sh -s <<'INNER'
set -eu
APP=/var/www/conectaeduca
echo "UID_GID=$(id -u):$(id -g)"
for dir in public src; do
  p="$APP/$dir"
  [ -d "$p" ] || continue
  echo "ESCOPO=$dir"
  for term in 'csrf' 'csrf_token' 'hash_equals' 'session_start' 'role' 'permission' 'authorize' 'admin' 'empresa' 'candidato' 'REQUEST_METHOD' 'POST' '403' 'forbidden'; do
    n=$(find "$p" -type f \( -name '*.php' -o -name '*.js' \) -exec grep -i -l -F -- "$term" {} + 2>/dev/null | wc -l)
    echo "INDICADOR=$term ARQUIVOS=$n"
  done
done
echo "MAPEAMENTO_ESTATICO=CONCLUIDO"
INNER
 echo "ALTERACOES_APLICACAO=NAO RESTARTS=NAO"
} > "$OUT" 2>&1 || { rc=$?; cat "$OUT"; exit "$rc"; }
cat "$OUT"
sha256sum "$OUT"
