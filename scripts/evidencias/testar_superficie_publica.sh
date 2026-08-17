#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

umask 077

ENV_TESTE="${CE_TEST_ENV_FILE:-$ROOT/.env.test.local}"
if [[ -f "$ENV_TESTE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_TESTE"
fi

BASE_URL="${CE_BASE_URL:-https://conectaeduca.local}"
CURL_INSECURE="${CE_CURL_INSECURE:-1}"

CURL=(curl -sS -o /dev/null)
if [[ "$CURL_INSECURE" == "1" ]]; then
    CURL+=(-k)
fi

FALHAS=0

codigo_http() {
    local metodo="$1"
    local caminho="$2"

    "${CURL[@]}" \
        -X "$metodo" \
        -w '%{http_code}' \
        "$BASE_URL$caminho"
}

esperar_codigo() {
    local descricao="$1"
    local metodo="$2"
    local caminho="$3"
    local esperado="$4"
    local obtido

    obtido="$(codigo_http "$metodo" "$caminho")"

    if [[ "$obtido" == "$esperado" ]]; then
        printf '%-58s esperado=%-3s obtido=%-3s  OK\n' \
            "$descricao" "$esperado" "$obtido"
    else
        printf '%-58s esperado=%-3s obtido=%-3s  FALHA\n' \
            "$descricao" "$esperado" "$obtido"
        FALHAS=$((FALHAS + 1))
    fi
}

esperar_bloqueado() {
    local descricao="$1"
    local caminho="$2"
    local obtido

    obtido="$(codigo_http GET "$caminho")"

    if [[ "$obtido" == "403" || "$obtido" == "404" ]]; then
        printf '%-58s esperado=403/404 obtido=%-3s  OK\n' \
            "$descricao" "$obtido"
    else
        printf '%-58s esperado=403/404 obtido=%-3s  FALHA\n' \
            "$descricao" "$obtido"
        FALHAS=$((FALHAS + 1))
    fi
}

printf '\n======================================================================\n'
printf ' ConectaEduca - Validação da superfície pública HTTP\n'
printf '======================================================================\n\n'
printf 'URL: %s\n\n' "$BASE_URL"

printf '%s\n' '--- RECURSOS PÚBLICOS ---'
esperar_codigo 'Login público' GET '/login.php' 200
esperar_codigo 'CSS público' GET '/assets/css/style.css' 200
esperar_codigo 'JavaScript público' GET '/assets/js/crypto-utils.js' 200
esperar_codigo 'Endpoint da chave pública' GET '/api/public_key.php' 200

printf '\n%s\n' '--- RESTRIÇÃO DE MÉTODOS DA API ---'
esperar_codigo 'POST proibido em public_key.php' POST '/api/public_key.php' 403
esperar_codigo 'GET proibido em processa_cadastro_usuario.php' GET '/api/processa_cadastro_usuario.php' 403
esperar_codigo 'POST proibido em relatorios.php' POST '/api/relatorios.php' 403

printf '\n%s\n' '--- DIRETÓRIOS SEM LISTAGEM ---'
esperar_codigo 'Listagem de /assets/ bloqueada' GET '/assets/' 403
esperar_codigo 'Listagem de /api/ bloqueada' GET '/api/' 403

printf '\n%s\n' '--- ARQUIVOS INTERNOS FORA DA SUPERFÍCIE WEB ---'
esperar_bloqueado '.env não acessível' '/.env'
esperar_bloqueado '.env.test.local não acessível' '/.env.test.local'
esperar_bloqueado 'composer.json não acessível' '/composer.json'
esperar_bloqueado 'composer.lock não acessível' '/composer.lock'
esperar_bloqueado 'Makefile não acessível' '/Makefile'
esperar_bloqueado 'Schema SQL não acessível' '/sql/conectaeduca.sql'
esperar_bloqueado 'Código src/ não acessível' '/src/Config/Database.php'
esperar_bloqueado 'Bootstrap privado não acessível' '/bootstrap/app.php'
esperar_bloqueado 'Chave privada não acessível' '/storage/keys/private.pem'
esperar_bloqueado 'Vendor não acessível' '/vendor/autoload.php'
esperar_bloqueado 'Bootstrap antigo da API não existe' '/api/bootstrap.php'

printf '\n======================================================================\n'
if [[ "$FALHAS" -eq 0 ]]; then
    printf 'RESULTADO: superfície pública validada; arquivos internos permanecem inacessíveis.\n'
    printf 'Falhas: 0\n'
else
    printf 'RESULTADO: foram encontradas falhas na superfície pública.\n'
    printf 'Falhas: %d\n' "$FALHAS"
fi
printf '======================================================================\n\n'

exit "$FALHAS"
