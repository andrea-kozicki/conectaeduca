#!/usr/bin/env bash
# EP125 17B3 — triagem de rotas e guardas para planejar RBAC negativo.
# Somente leitura; sem HTTP, credenciais, conteúdo do código ou reinícios.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"
mkdir -p "$BASE/HOMOLOG"
OUT="$BASE/HOMOLOG/EP125_HOMOLOG_ETAPA17B3_$(date +%Y%m%dT%H%M%S).txt"
PHP="${PHP_CONTAINER:-conectaeduca-dmz-php-1}"
{
 echo "ETAPA=17B3 DATA=$(date --iso-8601=seconds) HOST=$(hostname)"
 docker inspect "$PHP" --format 'CONTAINER={{.Name}} STATUS={{.State.Status}} HEALTH={{if .State.Health}}{{.State.Health.Status}}{{else}}NA{{end}}'
 docker exec -i "$PHP" sh -s <<'INNER'
set -eu
APP=/var/www/conectaeduca
for dir in public src; do
 p="$APP/$dir"
 [ -d "$p" ] || { echo "ESCOPO_AUSENTE=$dir"; continue; }
 echo "ESCOPO=$dir"
 find "$p" -type f \( -name '*.php' -o -name '*.js' \) 2>/dev/null | awk 'END{print "ARQUIVOS=" NR}'
 for term in 'REQUEST_METHOD' 'POST' 'GET' 'csrf' 'csrf_token' 'role' 'authorize' 'permission' '403' 'forbidden'; do
  n=$(find "$p" -type f \( -name '*.php' -o -name '*.js' \) -exec grep -i -l -F -- "$term" {} + 2>/dev/null | wc -l)
  echo "INDICADOR=$term ARQUIVOS=$n"
 done
 # Lista apenas basenames de PHP sob public para planejamento, sem conteúdo.
 if [ "$dir" = public ]; then
  echo "ARQUIVOS_PUBLIC_PHP_BASENAME_INICIO"
  find "$p" -type f -name '*.php' -exec basename {} \; 2>/dev/null | LC_ALL=C sort -u | head -80
  echo "ARQUIVOS_PUBLIC_PHP_BASENAME_FIM"
 fi
done
echo "INSPECAO_ESTATICA=SIM"
INNER
 echo "REQUISICOES_HTTP=NAO ALTERACOES_APLICACAO=NAO RESTARTS=NAO"
} > "$OUT" 2>&1 || { rc=$?; cat "$OUT"; exit "$rc"; }
cat "$OUT"
sha256sum "$OUT"
