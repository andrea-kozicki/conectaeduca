#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

umask 077

ENV_TESTE="${CE_TEST_ENV_FILE:-$ROOT/.env.test.local}"

if [[ -f "$ENV_TESTE" ]]; then
    # Arquivo local e deliberadamente não versionado.
    # As variáveis não são exportadas para processos-filhos.
    # shellcheck disable=SC1090
    source "$ENV_TESTE"
fi

BASE_URL="${CE_BASE_URL:-https://conectaeduca.local}"

LOGIN_PATH="${CE_LOGIN_PATH:-/login.php}"
MFA_PATH="${CE_MFA_PATH:-/mfa.php}"
MFA_CONFIG_PATH="${CE_MFA_CONFIG_PATH:-/mfa-configurar.php}"
DASHBOARD_PATH="${CE_DASHBOARD_PATH:-/dashboard.php}"
EMPRESA_PATH="${CE_EMPRESA_PATH:-/empresa/oportunidades.php}"
ADMIN_PATH="${CE_ADMIN_PATH:-/admin/auditoria.php}"
LOGOUT_PATH="${CE_LOGOUT_PATH:-/logout.php}"

SESSION_COOKIE="${CE_SESSION_COOKIE:-CONECTAEDUCASESSID}"
CURL_INSECURE="${CE_CURL_INSECURE:-1}"

FALHAS=0
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

CURL=(curl -sS)

if [[ "$CURL_INSECURE" == "1" ]]; then
    CURL+=(-k)
fi

# ----------------------------------------------------------------------
# Validação do ambiente
# ----------------------------------------------------------------------

obrigatorias=(
    CE_TEST_USUARIO_EMAIL
    CE_TEST_USUARIO_SENHA
    CE_TEST_USUARIO_TOTP_SECRET
    CE_TEST_EMPRESA_EMAIL
    CE_TEST_EMPRESA_SENHA
    CE_TEST_EMPRESA_TOTP_SECRET
    CE_TEST_ADMIN_EMAIL
    CE_TEST_ADMIN_SENHA
    CE_TEST_ADMIN_TOTP_SECRET
)

faltando=0

for variavel in "${obrigatorias[@]}"; do
    if [[ -z "${!variavel:-}" ]]; then
        echo "ERRO: variável obrigatória ausente: $variavel"
        faltando=1
    fi
done

if [[ "$faltando" -ne 0 ]]; then
    echo
    echo "Preencha .env.test.local antes de executar os testes MFA."
    echo "As contas de laboratório também devem estar com o MFA já configurado."
    exit 2
fi

if [[ ! -f vendor/autoload.php ]]; then
    echo "ERRO: vendor/autoload.php não encontrado. Execute composer install."
    exit 2
fi

# ----------------------------------------------------------------------
# Funções auxiliares
# ----------------------------------------------------------------------

resultado_codigo() {
    local descricao="$1"
    local esperado="$2"
    local obtido="$3"

    if [[ "$esperado" == "$obtido" ]]; then
        printf '%-48s esperado=%-3s obtido=%-3s  OK\n' \
            "$descricao" "$esperado" "$obtido"
    else
        printf '%-48s esperado=%-3s obtido=%-3s  FALHA\n' \
            "$descricao" "$esperado" "$obtido"
        FALHAS=$((FALHAS + 1))
    fi
}

resultado_location() {
    local descricao="$1"
    local esperado="$2"
    local obtido="$3"

    if [[ "$esperado" == "$obtido" ]]; then
        printf '%-48s esperado=%-24s  OK\n' \
            "$descricao" "$esperado"
    else
        printf '%-48s esperado=%-24s obtido=%s  FALHA\n' \
            "$descricao" "$esperado" "${obtido:-<vazio>}"
        FALHAS=$((FALHAS + 1))
    fi
}

resultado_booleano() {
    local descricao="$1"
    local sucesso="$2"

    if [[ "$sucesso" == "1" ]]; then
        printf '%-48s OK\n' "$descricao"
    else
        printf '%-48s FALHA\n' "$descricao"
        FALHAS=$((FALHAS + 1))
    fi
}

cookie_sessao() {
    local arquivo="$1"

    awk -F '\t' \
        -v nome="$SESSION_COOKIE" \
        '$6 == nome {valor=$7} END {print valor}' \
        "$arquivo" 2>/dev/null || true
}

location_resposta() {
    local arquivo="$1"
    local location

    location="$({
        awk 'BEGIN { IGNORECASE=1 }
             /^Location:/ {
                 sub(/^[^:]+:[[:space:]]*/, "")
                 sub(/\r$/, "")
                 print
                 exit
             }' "$arquivo"
    } || true)"

    if [[ "$location" == "$BASE_URL"* ]]; then
        location="${location#"$BASE_URL"}"
    fi

    printf '%s' "$location"
}

extrair_csrf() {
    local arquivo="$1"

    python3 - "$arquivo" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import sys

class Parser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.encontrado = None

    def handle_starttag(self, tag, attrs):
        if tag.lower() != "input" or self.encontrado:
            return

        dados = dict(attrs)
        nome = dados.get("name", "")
        valor = dados.get("value", "")

        if "csrf" in nome.lower() and valor:
            self.encontrado = (nome, valor)

arquivo = Path(sys.argv[1])
parser = Parser()
parser.feed(arquivo.read_text(encoding="utf-8", errors="ignore"))

if not parser.encontrado:
    raise SystemExit(1)

sys.stdout.write(parser.encontrado[0] + "\t" + parser.encontrado[1])
PY
}

gerar_form_login() {
    local email="$1"
    local senha="$2"
    local csrf_nome="$3"
    local csrf_valor="$4"

    printf '%s\n%s\n%s\n%s\n' \
        "$email" \
        "$senha" \
        "$csrf_nome" \
        "$csrf_valor" |
    python3 -c '
import sys
import urllib.parse

email = sys.stdin.readline().rstrip("\n")
senha = sys.stdin.readline().rstrip("\n")
csrf_nome = sys.stdin.readline().rstrip("\n")
csrf_valor = sys.stdin.readline().rstrip("\n")

sys.stdout.write(
    urllib.parse.urlencode({
        "email": email,
        "senha": senha,
        csrf_nome: csrf_valor,
    })
)
'
}

gerar_form_codigo() {
    local codigo="$1"
    local csrf_nome="$2"
    local csrf_valor="$3"

    printf '%s\n%s\n%s\n' \
        "$codigo" \
        "$csrf_nome" \
        "$csrf_valor" |
    python3 -c '
import sys
import urllib.parse

codigo = sys.stdin.readline().rstrip("\n")
csrf_nome = sys.stdin.readline().rstrip("\n")
csrf_valor = sys.stdin.readline().rstrip("\n")

sys.stdout.write(
    urllib.parse.urlencode({
        "codigo": codigo,
        csrf_nome: csrf_valor,
    })
)
'
}

gerar_totp() {
    local segredo="$1"

    printf '%s' "$segredo" |
    php -r '
require "vendor/autoload.php";

$segredo = trim(stream_get_contents(STDIN));

if ($segredo === "") {
    fwrite(STDERR, "Segredo TOTP vazio.\n");
    exit(2);
}

$google2fa = new \PragmaRX\Google2FA\Google2FA();
echo $google2fa->getCurrentOtp($segredo);
'
}

aguardar_janela_totp_segura() {
    local segundo_no_passo
    segundo_no_passo=$(( $(date +%s) % 30 ))

    # Evita gerar um TOTP nos últimos segundos da janela de 30 s,
    # reduzindo flutuações do teste em fronteiras de tempo.
    if (( segundo_no_passo >= 25 )); then
        sleep $((31 - segundo_no_passo))
    fi
}

gerar_codigo_invalido() {
    local codigo_valido="$1"

    python3 - "$codigo_valido" <<'PY'
import sys

codigo = sys.argv[1]

if len(codigo) != 6 or not codigo.isdigit():
    raise SystemExit("Código TOTP gerado é inválido.")

valor = (int(codigo) + 1) % 1_000_000
print(f"{valor:06d}", end="")
PY
}

abrir_pagina() {
    local cookies="$1"
    local caminho="$2"
    local html="$3"
    local headers="$4"

    "${CURL[@]}" \
        -c "$cookies" \
        -b "$cookies" \
        -D "$headers" \
        -o "$html" \
        -w '%{http_code}' \
        "$BASE_URL$caminho"
}

post_login() {
    local cookies="$1"
    local resposta="$2"
    local headers="$3"
    local email="$4"
    local senha="$5"
    local csrf_nome="$6"
    local csrf_valor="$7"

    gerar_form_login \
        "$email" \
        "$senha" \
        "$csrf_nome" \
        "$csrf_valor" |
    "${CURL[@]}" \
        -c "$cookies" \
        -b "$cookies" \
        -D "$headers" \
        -o "$resposta" \
        -w '%{http_code}' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data-binary @- \
        "$BASE_URL$LOGIN_PATH"
}

post_mfa() {
    local cookies="$1"
    local resposta="$2"
    local headers="$3"
    local codigo="$4"
    local csrf_nome="$5"
    local csrf_valor="$6"

    gerar_form_codigo \
        "$codigo" \
        "$csrf_nome" \
        "$csrf_valor" |
    "${CURL[@]}" \
        -c "$cookies" \
        -b "$cookies" \
        -D "$headers" \
        -o "$resposta" \
        -w '%{http_code}' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data-binary @- \
        "$BASE_URL$MFA_PATH"
}

preparar_login() {
    local prefixo="$1"
    local cookies="$TEMP_DIR/${prefixo}.cookies"
    local html="$TEMP_DIR/${prefixo}-login.html"
    local headers="$TEMP_DIR/${prefixo}-login.headers"

    local codigo
    codigo="$(abrir_pagina "$cookies" "$LOGIN_PATH" "$html" "$headers")"

    if [[ "$codigo" != "200" ]]; then
        echo "ERRO: não foi possível abrir a tela de login ($codigo)." >&2
        return 1
    fi

    local dados
    if ! dados="$(extrair_csrf "$html")"; then
        echo "ERRO: token CSRF não encontrado na tela de login." >&2
        return 1
    fi

    printf '%s\t%s\t%s\n' \
        "$cookies" \
        "${dados%%$'\t'*}" \
        "${dados#*$'\t'}"
}

testar_papel() {
    local prefixo="$1"
    local rotulo="$2"
    local email="$3"
    local senha="$4"
    local segredo="$5"
    local empresa_esperado="$6"
    local admin_esperado="$7"
    local testar_replay="${8:-0}"

    echo "--- $rotulo ---"

    local dados cookies resto csrf_nome csrf_valor
    dados="$(preparar_login "$prefixo")"

    cookies="${dados%%$'\t'*}"
    resto="${dados#*$'\t'}"
    csrf_nome="${resto%%$'\t'*}"
    csrf_valor="${resto#*$'\t'}"

    local sessao_anonima sessao_pre_mfa sessao_autenticada
    sessao_anonima="$(cookie_sessao "$cookies")"

    local login_headers="$TEMP_DIR/${prefixo}-post-login.headers"
    local login_html="$TEMP_DIR/${prefixo}-post-login.html"
    local codigo_http location

    codigo_http="$(
        post_login \
            "$cookies" \
            "$login_html" \
            "$login_headers" \
            "$email" \
            "$senha" \
            "$csrf_nome" \
            "$csrf_valor"
    )"

    resultado_codigo \
        "Senha correta ($rotulo)" \
        "302" \
        "$codigo_http"

    location="$(location_resposta "$login_headers")"
    resultado_location \
        "Redirecionamento para MFA ($rotulo)" \
        "$MFA_PATH" \
        "$location"

    if [[ "$codigo_http" != "302" || "$location" != "$MFA_PATH" ]]; then
        if [[ "$location" == "$MFA_CONFIG_PATH" ]]; then
            echo "ERRO: MFA ainda não configurado para $rotulo." >&2
        fi
        echo
        return
    fi

    sessao_pre_mfa="$(cookie_sessao "$cookies")"

    if [[ -n "$sessao_anonima" \
          && -n "$sessao_pre_mfa" \
          && "$sessao_anonima" != "$sessao_pre_mfa" ]]; then
        resultado_booleano \
            "Sessão regenerada após senha ($rotulo)" \
            1
    else
        resultado_booleano \
            "Sessão regenerada após senha ($rotulo)" \
            0
    fi

    codigo_http="$(
        abrir_pagina \
            "$cookies" \
            "$DASHBOARD_PATH" \
            "$TEMP_DIR/${prefixo}-dashboard-pre-mfa.html" \
            "$TEMP_DIR/${prefixo}-dashboard-pre-mfa.headers"
    )"

    resultado_codigo \
        "Dashboard antes do MFA ($rotulo)" \
        "401" \
        "$codigo_http"

    local mfa_html="$TEMP_DIR/${prefixo}-mfa.html"
    local mfa_headers="$TEMP_DIR/${prefixo}-mfa.headers"

    codigo_http="$(
        abrir_pagina \
            "$cookies" \
            "$MFA_PATH" \
            "$mfa_html" \
            "$mfa_headers"
    )"

    resultado_codigo \
        "GET desafio MFA ($rotulo)" \
        "200" \
        "$codigo_http"

    local dados_mfa csrf_mfa_nome csrf_mfa_valor

    if ! dados_mfa="$(extrair_csrf "$mfa_html")"; then
        echo "ERRO: token CSRF não encontrado em $MFA_PATH para $rotulo." >&2
        FALHAS=$((FALHAS + 1))
        echo
        return
    fi

    csrf_mfa_nome="${dados_mfa%%$'\t'*}"
    csrf_mfa_valor="${dados_mfa#*$'\t'}"

    local codigo_valido codigo_invalido

    aguardar_janela_totp_segura
    codigo_valido="$(gerar_totp "$segredo")"
    codigo_invalido="$(gerar_codigo_invalido "$codigo_valido")"

    codigo_http="$(
        post_mfa \
            "$cookies" \
            "$TEMP_DIR/${prefixo}-mfa-invalido.html" \
            "$TEMP_DIR/${prefixo}-mfa-invalido.headers" \
            "$codigo_invalido" \
            "$csrf_mfa_nome" \
            "$csrf_mfa_valor"
    )"

    resultado_codigo \
        "TOTP inválido ($rotulo)" \
        "401" \
        "$codigo_http"

    # Recalcula o TOTP imediatamente antes do POST válido, caso a
    # janela temporal tenha mudado durante o teste inválido.
    codigo_valido="$(gerar_totp "$segredo")"

    codigo_http="$(
        post_mfa \
            "$cookies" \
            "$TEMP_DIR/${prefixo}-mfa-valido.html" \
            "$TEMP_DIR/${prefixo}-mfa-valido.headers" \
            "$codigo_valido" \
            "$csrf_mfa_nome" \
            "$csrf_mfa_valor"
    )"

    resultado_codigo \
        "TOTP válido ($rotulo)" \
        "302" \
        "$codigo_http"

    location="$(location_resposta "$TEMP_DIR/${prefixo}-mfa-valido.headers")"
    resultado_location \
        "Redirecionamento pós-MFA ($rotulo)" \
        "$DASHBOARD_PATH" \
        "$location"

    sessao_autenticada="$(cookie_sessao "$cookies")"

    if [[ -n "$sessao_pre_mfa" \
          && -n "$sessao_autenticada" \
          && "$sessao_pre_mfa" != "$sessao_autenticada" ]]; then
        resultado_booleano \
            "Sessão regenerada após MFA ($rotulo)" \
            1
    else
        resultado_booleano \
            "Sessão regenerada após MFA ($rotulo)" \
            0
    fi

    codigo_http="$(
        abrir_pagina \
            "$cookies" \
            "$DASHBOARD_PATH" \
            "$TEMP_DIR/${prefixo}-dashboard.html" \
            "$TEMP_DIR/${prefixo}-dashboard.headers"
    )"

    resultado_codigo \
        "Dashboard após MFA ($rotulo)" \
        "200" \
        "$codigo_http"

    codigo_http="$(
        abrir_pagina \
            "$cookies" \
            "$EMPRESA_PATH" \
            "$TEMP_DIR/${prefixo}-empresa.html" \
            "$TEMP_DIR/${prefixo}-empresa.headers"
    )"

    resultado_codigo \
        "Área empresa ($rotulo)" \
        "$empresa_esperado" \
        "$codigo_http"

    codigo_http="$(
        abrir_pagina \
            "$cookies" \
            "$ADMIN_PATH" \
            "$TEMP_DIR/${prefixo}-admin.html" \
            "$TEMP_DIR/${prefixo}-admin.headers"
    )"

    resultado_codigo \
        "Auditoria admin ($rotulo)" \
        "$admin_esperado" \
        "$codigo_http"

    codigo_http="$(
        abrir_pagina \
            "$cookies" \
            "$LOGOUT_PATH" \
            "$TEMP_DIR/${prefixo}-logout.html" \
            "$TEMP_DIR/${prefixo}-logout.headers"
    )"

    resultado_codigo \
        "Logout ($rotulo)" \
        "302" \
        "$codigo_http"

    codigo_http="$(
        abrir_pagina \
            "$cookies" \
            "$DASHBOARD_PATH" \
            "$TEMP_DIR/${prefixo}-pos-logout.html" \
            "$TEMP_DIR/${prefixo}-pos-logout.headers"
    )"

    resultado_codigo \
        "Dashboard após logout ($rotulo)" \
        "401" \
        "$codigo_http"

    if [[ "$testar_replay" == "1" ]]; then
        local replay_dados replay_cookies replay_resto
        local replay_csrf_nome replay_csrf_valor

        replay_dados="$(preparar_login "${prefixo}-replay")"
        replay_cookies="${replay_dados%%$'\t'*}"
        replay_resto="${replay_dados#*$'\t'}"
        replay_csrf_nome="${replay_resto%%$'\t'*}"
        replay_csrf_valor="${replay_resto#*$'\t'}"

        codigo_http="$(
            post_login \
                "$replay_cookies" \
                "$TEMP_DIR/${prefixo}-replay-login.html" \
                "$TEMP_DIR/${prefixo}-replay-login.headers" \
                "$email" \
                "$senha" \
                "$replay_csrf_nome" \
                "$replay_csrf_valor"
        )"

        resultado_codigo \
            "Nova pré-auth para replay ($rotulo)" \
            "302" \
            "$codigo_http"

        local replay_mfa_html="$TEMP_DIR/${prefixo}-replay-mfa.html"

        codigo_http="$(
            abrir_pagina \
                "$replay_cookies" \
                "$MFA_PATH" \
                "$replay_mfa_html" \
                "$TEMP_DIR/${prefixo}-replay-mfa.headers"
        )"

        resultado_codigo \
            "GET MFA para replay ($rotulo)" \
            "200" \
            "$codigo_http"

        local replay_dados_mfa replay_mfa_nome replay_mfa_valor
        replay_dados_mfa="$(extrair_csrf "$replay_mfa_html")"
        replay_mfa_nome="${replay_dados_mfa%%$'\t'*}"
        replay_mfa_valor="${replay_dados_mfa#*$'\t'}"

        codigo_http="$(
            post_mfa \
                "$replay_cookies" \
                "$TEMP_DIR/${prefixo}-replay-resposta.html" \
                "$TEMP_DIR/${prefixo}-replay-resposta.headers" \
                "$codigo_valido" \
                "$replay_mfa_nome" \
                "$replay_mfa_valor"
        )"

        resultado_codigo \
            "Replay do TOTP já usado ($rotulo)" \
            "401" \
            "$codigo_http"

        # Destrói a pré-autenticação deixada pelo teste de replay.
        abrir_pagina \
            "$replay_cookies" \
            "$LOGOUT_PATH" \
            "$TEMP_DIR/${prefixo}-replay-logout.html" \
            "$TEMP_DIR/${prefixo}-replay-logout.headers" \
            >/dev/null
    fi

    echo
}

# ----------------------------------------------------------------------
# Cabeçalho
# ----------------------------------------------------------------------

echo
echo "=================================================================="
echo " ConectaEduca - Testes de autenticação local com MFA obrigatório"
echo "=================================================================="
echo

echo "Branch: $(git branch --show-current)"
echo "Commit: $(git rev-parse HEAD)"
echo "URL:    $BASE_URL"
echo

# ----------------------------------------------------------------------
# Testes públicos
# ----------------------------------------------------------------------

echo "--- TESTES PÚBLICOS ---"

cookies_publico="$TEMP_DIR/publico.cookies"

codigo_http="$(
    abrir_pagina \
        "$cookies_publico" \
        "$LOGIN_PATH" \
        "$TEMP_DIR/publico-login.html" \
        "$TEMP_DIR/publico-login.headers"
)"

resultado_codigo \
    "GET /login.php" \
    "200" \
    "$codigo_http"

codigo_http="$(
    "${CURL[@]}" \
        -o "$TEMP_DIR/dashboard-sem-sessao.html" \
        -w '%{http_code}' \
        "$BASE_URL$DASHBOARD_PATH"
)"

resultado_codigo \
    "Dashboard sem sessão" \
    "401" \
    "$codigo_http"

codigo_http="$(
    printf 'email=teste%%40invalid.local&senha=teste' |
    "${CURL[@]}" \
        -o "$TEMP_DIR/sem-csrf.html" \
        -w '%{http_code}' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data-binary @- \
        "$BASE_URL$LOGIN_PATH"
)"

resultado_codigo \
    "POST login sem CSRF" \
    "419" \
    "$codigo_http"

echo

# ----------------------------------------------------------------------
# Credenciais inválidas
# ----------------------------------------------------------------------

echo "--- CREDENCIAIS INVÁLIDAS ---"

dados="$(preparar_login "senha-incorreta")"
cookies="${dados%%$'\t'*}"
resto="${dados#*$'\t'}"
csrf_nome="${resto%%$'\t'*}"
csrf_valor="${resto#*$'\t'}"

senha_invalida="__CONECTAEDUCA_SENHA_INVALIDA_${RANDOM}_${RANDOM}__"

codigo_http="$(
    post_login \
        "$cookies" \
        "$TEMP_DIR/senha-incorreta.html" \
        "$TEMP_DIR/senha-incorreta.headers" \
        "$CE_TEST_USUARIO_EMAIL" \
        "$senha_invalida" \
        "$csrf_nome" \
        "$csrf_valor"
)"

resultado_codigo \
    "Login com senha incorreta" \
    "401" \
    "$codigo_http"

echo

# ----------------------------------------------------------------------
# Papéis + MFA
# ----------------------------------------------------------------------

testar_papel \
    "usuario" \
    "USUÁRIO COMUM" \
    "$CE_TEST_USUARIO_EMAIL" \
    "$CE_TEST_USUARIO_SENHA" \
    "$CE_TEST_USUARIO_TOTP_SECRET" \
    "403" \
    "403" \
    "1"

testar_papel \
    "empresa" \
    "EMPRESA" \
    "$CE_TEST_EMPRESA_EMAIL" \
    "$CE_TEST_EMPRESA_SENHA" \
    "$CE_TEST_EMPRESA_TOTP_SECRET" \
    "200" \
    "403" \
    "0"

testar_papel \
    "admin" \
    "ADMINISTRADOR" \
    "$CE_TEST_ADMIN_EMAIL" \
    "$CE_TEST_ADMIN_SENHA" \
    "$CE_TEST_ADMIN_TOTP_SECRET" \
    "200" \
    "200" \
    "0"

# ----------------------------------------------------------------------
# Resultado
# ----------------------------------------------------------------------

echo "=================================================================="

if [[ "$FALHAS" -eq 0 ]]; then
    echo "RESULTADO: todos os testes de autenticação com MFA passaram."
    echo "Falhas: 0"
    echo "=================================================================="
    exit 0
fi

echo "RESULTADO: foram encontradas falhas."
echo "Falhas: $FALHAS"
echo "=================================================================="

exit 1
