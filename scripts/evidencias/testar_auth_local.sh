#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

umask 077

ENV_TESTE="${CE_TEST_ENV_FILE:-$ROOT/.env.test.local}"

if [[ -f "$ENV_TESTE" ]]; then
    set -a
    # Arquivo local e deliberadamente não versionado.
    # shellcheck disable=SC1090
    source "$ENV_TESTE"
    set +a
fi

BASE_URL="${CE_BASE_URL:-https://conectaeduca.local}"

LOGIN_PATH="${CE_LOGIN_PATH:-/login.php}"
DASHBOARD_PATH="${CE_DASHBOARD_PATH:-/dashboard.php}"
EMPRESA_PATH="${CE_EMPRESA_PATH:-/empresa/oportunidades.php}"
ADMIN_PATH="${CE_ADMIN_PATH:-/admin/auditoria.php}"
LOGOUT_PATH="${CE_LOGOUT_PATH:-/logout.php}"

SESSION_COOKIE="${CE_SESSION_COOKIE:-CONECTAEDUCASESSID}"
CURL_INSECURE="${CE_CURL_INSECURE:-1}"

FALHAS=0
TEMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TEMP_DIR"' EXIT

CURL=(
    curl
    -sS
)

if [[ "$CURL_INSECURE" == "1" ]]; then
    CURL+=(-k)
fi

# ----------------------------------------------------------------------
# Validação do ambiente
# ----------------------------------------------------------------------

obrigatorias=(
    CE_TEST_USUARIO_EMAIL
    CE_TEST_USUARIO_SENHA
    CE_TEST_EMPRESA_EMAIL
    CE_TEST_EMPRESA_SENHA
    CE_TEST_ADMIN_EMAIL
    CE_TEST_ADMIN_SENHA
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
    echo "Preencha .env.test.local antes de executar os testes."
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
        printf '%-42s esperado=%-3s obtido=%-3s  OK\n' \
            "$descricao" "$esperado" "$obtido"
    else
        printf '%-42s esperado=%-3s obtido=%-3s  FALHA\n' \
            "$descricao" "$esperado" "$obtido"

        FALHAS=$((FALHAS + 1))
    fi
}

resultado_booleano() {
    local descricao="$1"
    local sucesso="$2"

    if [[ "$sucesso" == "1" ]]; then
        printf '%-42s OK\n' "$descricao"
    else
        printf '%-42s FALHA\n' "$descricao"
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

print(
    parser.encontrado[0]
    + "\t"
    + parser.encontrado[1]
)
PY
}

gerar_form_login() {
    local email="$1"
    local senha="$2"
    local csrf_nome="$3"
    local csrf_valor="$4"

    # A senha é fornecida ao Python via STDIN.
    # Ela não aparece como argumento de processo.
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

abrir_login() {
    local cookies="$1"
    local html="$2"

    "${CURL[@]}" \
        -c "$cookies" \
        -b "$cookies" \
        -o "$html" \
        -w '%{http_code}' \
        "$BASE_URL$LOGIN_PATH"
}

post_login() {
    local cookies="$1"
    local resposta="$2"
    local email="$3"
    local senha="$4"
    local csrf_nome="$5"
    local csrf_valor="$6"

    gerar_form_login \
        "$email" \
        "$senha" \
        "$csrf_nome" \
        "$csrf_valor" |
    "${CURL[@]}" \
        -c "$cookies" \
        -b "$cookies" \
        -o "$resposta" \
        -w '%{http_code}' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data-binary @- \
        "$BASE_URL$LOGIN_PATH"
}

get_autenticado() {
    local cookies="$1"
    local caminho="$2"
    local resposta="$3"

    "${CURL[@]}" \
        -c "$cookies" \
        -b "$cookies" \
        -o "$resposta" \
        -w '%{http_code}' \
        "$BASE_URL$caminho"
}

preparar_login() {
    local prefixo="$1"
    local cookies="$TEMP_DIR/${prefixo}.cookies"
    local html="$TEMP_DIR/${prefixo}-login.html"

    local codigo
    codigo="$(abrir_login "$cookies" "$html")"

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

# ----------------------------------------------------------------------
# Cabeçalho
# ----------------------------------------------------------------------

echo
echo "=============================================================="
echo " ConectaEduca - Testes reproduzíveis de autenticação local"
echo "=============================================================="
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
html_publico="$TEMP_DIR/publico.html"

codigo="$(
    abrir_login \
        "$cookies_publico" \
        "$html_publico"
)"

resultado_codigo \
    "GET /login.php" \
    "200" \
    "$codigo"

codigo="$(
    "${CURL[@]}" \
        -o "$TEMP_DIR/dashboard-sem-sessao.html" \
        -w '%{http_code}' \
        "$BASE_URL$DASHBOARD_PATH"
)"

resultado_codigo \
    "Dashboard sem sessão" \
    "401" \
    "$codigo"

codigo="$(
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
    "$codigo"

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

codigo="$(
    post_login \
        "$cookies" \
        "$TEMP_DIR/senha-incorreta.html" \
        "$CE_TEST_USUARIO_EMAIL" \
        "$senha_invalida" \
        "$csrf_nome" \
        "$csrf_valor"
)"

resultado_codigo \
    "Login com senha incorreta" \
    "401" \
    "$codigo"

echo

# ----------------------------------------------------------------------
# Usuário comum
# ----------------------------------------------------------------------

echo "--- USUÁRIO COMUM ---"

dados="$(preparar_login "usuario")"

cookies="${dados%%$'\t'*}"
resto="${dados#*$'\t'}"
csrf_nome="${resto%%$'\t'*}"
csrf_valor="${resto#*$'\t'}"

sessao_antes="$(cookie_sessao "$cookies")"

codigo="$(
    post_login \
        "$cookies" \
        "$TEMP_DIR/usuario-login.html" \
        "$CE_TEST_USUARIO_EMAIL" \
        "$CE_TEST_USUARIO_SENHA" \
        "$csrf_nome" \
        "$csrf_valor"
)"

resultado_codigo \
    "Login usuário" \
    "302" \
    "$codigo"

sessao_depois="$(cookie_sessao "$cookies")"

if [[ -n "$sessao_antes" \
      && -n "$sessao_depois" \
      && "$sessao_antes" != "$sessao_depois" ]]; then
    resultado_booleano \
        "Regeneração do ID de sessão" \
        1
else
    resultado_booleano \
        "Regeneração do ID de sessão" \
        0
fi

codigo="$(
    get_autenticado \
        "$cookies" \
        "$DASHBOARD_PATH" \
        "$TEMP_DIR/usuario-dashboard.html"
)"

resultado_codigo "Dashboard usuário" "200" "$codigo"

codigo="$(
    get_autenticado \
        "$cookies" \
        "$EMPRESA_PATH" \
        "$TEMP_DIR/usuario-empresa.html"
)"

resultado_codigo \
    "Área empresa como usuário" \
    "403" \
    "$codigo"

codigo="$(
    get_autenticado \
        "$cookies" \
        "$ADMIN_PATH" \
        "$TEMP_DIR/usuario-admin.html"
)"

resultado_codigo \
    "Auditoria admin como usuário" \
    "403" \
    "$codigo"

codigo="$(
    get_autenticado \
        "$cookies" \
        "$LOGOUT_PATH" \
        "$TEMP_DIR/usuario-logout.html"
)"

resultado_codigo "Logout usuário" "302" "$codigo"

codigo="$(
    get_autenticado \
        "$cookies" \
        "$DASHBOARD_PATH" \
        "$TEMP_DIR/usuario-pos-logout.html"
)"

resultado_codigo \
    "Dashboard após logout" \
    "401" \
    "$codigo"

echo

# ----------------------------------------------------------------------
# Empresa
# ----------------------------------------------------------------------

echo "--- EMPRESA ---"

dados="$(preparar_login "empresa")"

cookies="${dados%%$'\t'*}"
resto="${dados#*$'\t'}"
csrf_nome="${resto%%$'\t'*}"
csrf_valor="${resto#*$'\t'}"

codigo="$(
    post_login \
        "$cookies" \
        "$TEMP_DIR/empresa-login.html" \
        "$CE_TEST_EMPRESA_EMAIL" \
        "$CE_TEST_EMPRESA_SENHA" \
        "$csrf_nome" \
        "$csrf_valor"
)"

resultado_codigo "Login empresa" "302" "$codigo"

codigo="$(
    get_autenticado \
        "$cookies" \
        "$DASHBOARD_PATH" \
        "$TEMP_DIR/empresa-dashboard.html"
)"

resultado_codigo "Dashboard empresa" "200" "$codigo"

codigo="$(
    get_autenticado \
        "$cookies" \
        "$EMPRESA_PATH" \
        "$TEMP_DIR/empresa-area.html"
)"

resultado_codigo "Área empresa" "200" "$codigo"

codigo="$(
    get_autenticado \
        "$cookies" \
        "$ADMIN_PATH" \
        "$TEMP_DIR/empresa-admin.html"
)"

resultado_codigo \
    "Auditoria admin como empresa" \
    "403" \
    "$codigo"

codigo="$(
    get_autenticado \
        "$cookies" \
        "$LOGOUT_PATH" \
        "$TEMP_DIR/empresa-logout.html"
)"

resultado_codigo "Logout empresa" "302" "$codigo"

echo

# ----------------------------------------------------------------------
# Administrador
# ----------------------------------------------------------------------

echo "--- ADMINISTRADOR ---"

dados="$(preparar_login "admin")"

cookies="${dados%%$'\t'*}"
resto="${dados#*$'\t'}"
csrf_nome="${resto%%$'\t'*}"
csrf_valor="${resto#*$'\t'}"

codigo="$(
    post_login \
        "$cookies" \
        "$TEMP_DIR/admin-login.html" \
        "$CE_TEST_ADMIN_EMAIL" \
        "$CE_TEST_ADMIN_SENHA" \
        "$csrf_nome" \
        "$csrf_valor"
)"

resultado_codigo "Login administrador" "302" "$codigo"

codigo="$(
    get_autenticado \
        "$cookies" \
        "$DASHBOARD_PATH" \
        "$TEMP_DIR/admin-dashboard.html"
)"

resultado_codigo "Dashboard admin" "200" "$codigo"

codigo="$(
    get_autenticado \
        "$cookies" \
        "$EMPRESA_PATH" \
        "$TEMP_DIR/admin-empresa.html"
)"

resultado_codigo \
    "Área empresa como admin" \
    "200" \
    "$codigo"

codigo="$(
    get_autenticado \
        "$cookies" \
        "$ADMIN_PATH" \
        "$TEMP_DIR/admin-auditoria.html"
)"

resultado_codigo \
    "Auditoria como admin" \
    "200" \
    "$codigo"

codigo="$(
    get_autenticado \
        "$cookies" \
        "$LOGOUT_PATH" \
        "$TEMP_DIR/admin-logout.html"
)"

resultado_codigo "Logout admin" "302" "$codigo"

# ----------------------------------------------------------------------
# Resultado
# ----------------------------------------------------------------------

echo
echo "=============================================================="

if [[ "$FALHAS" -eq 0 ]]; then
    echo "RESULTADO: todos os testes de autenticação passaram."
    echo "Falhas: 0"
    echo "=============================================================="
    exit 0
fi

echo "RESULTADO: foram encontradas falhas."
echo "Falhas: $FALHAS"
echo "=============================================================="

exit 1
