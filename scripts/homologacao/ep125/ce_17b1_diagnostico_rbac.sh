#!/usr/bin/env bash
# EP125 17B1 — diagnostico direcionado do grep RBAC/CSRF, sem segredos ou conteudo de arquivos.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"
mkdir -p "$BASE/HOMOLOG"
OUT="$BASE/HOMOLOG/EP125_HOMOLOG_ETAPA17B1_$(date +%Y%m%dT%H%M%S).txt"
PHP="${PHP_CONTAINER:-conectaeduca-dmz-php-1}"
{
 echo "ETAPA=17B1"; echo "DATA=$(date --iso-8601=seconds)"; echo "HOST=$(hostname)"
 echo "CONTAINER=$PHP"
 docker inspect "$PHP" --format 'STATUS={{.State.Status}} HEALTH={{if .State.Health}}{{.State.Health.Status}}{{else}}NA{{end}}'
 docker exec -i "$PHP" sh -s <<'INNER'
set -eu
APP=/var/www/conectaeduca
echo "UID_GID=$(id -u):$(id -g)"
echo "GREP=$(command -v grep || echo AUSENTE)"
echo "FIND=$(command -v find || echo AUSENTE)"
for p in "$APP/public" "$APP/src"; do
 [ -d "$p" ] || { echo "DIRETORIO_AUSENTE=$p"; continue; }
 echo "DIRETORIO=$p"
 find "$p" -type f \( -name '*.php' -o -name '*.js' \) 2>/dev/null | awk 'END {print "ARQUIVOS_PHP_JS=" NR}'
done
printf 'role\n' | grep -i -F 'role' >/dev/null && echo "GREP_TESTE_SIMPLES=PASS" || echo "GREP_TESTE_SIMPLES=FAIL"
printf 'role\n' | grep -i -F -l 'role' >/dev/null && echo "GREP_TESTE_L=PASS" || echo "GREP_TESTE_L=FAIL"
for termo in role admin candidato empresa csrf POST; do
 echo "TERMO=$termo"
 # Testa busca real sem imprimir conteudo, caminhos, tokens ou segredos.
 # grep -r (recursivo) e -l (somente nomes, redirecionados para contagem).
 for modo in original simplificado; do
  if [ "$modo" = original ]; then
   total=$(grep -RIl -i -F --include='*.php' --include='*.js' --exclude-dir=vendor --exclude-dir=node_modules --exclude-dir=storage -- "$termo" "$APP/public" "$APP/src" 2>/dev/null | wc -l)
  else
   total=$(find "$APP/public" "$APP/src" -type f \( -name '*.php' -o -name '*.js' \) -exec grep -i -l -F -- "$termo" {} + 2>/dev/null | wc -l)
  fi
  echo "MODO=$modo ARQUIVOS=$total"
 done
done
echo "LEITURA_CODIGO_APENAS=SIM"
INNER
 echo "ALTERACOES_NA_APLICACAO=NAO"
} > "$OUT" 2>&1 || { rc=$?; cat "$OUT"; exit "$rc"; }
cat "$OUT"
sha256sum "$OUT"
