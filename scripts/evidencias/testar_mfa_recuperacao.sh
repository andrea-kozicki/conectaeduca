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
LOGIN_PATH="${CE_LOGIN_PATH:-/login.php}"
MFA_PATH="${CE_MFA_PATH:-/mfa.php}"
MFA_CONFIG_PATH="${CE_MFA_CONFIG_PATH:-/mfa-configurar.php}"
MFA_RECOVERY_PATH="${CE_MFA_RECOVERY_PATH:-/mfa-recuperacao.php}"
MFA_RECOVERY_CODES_PATH="${CE_MFA_RECOVERY_CODES_PATH:-/mfa-codigos-recuperacao.php}"
DASHBOARD_PATH="${CE_DASHBOARD_PATH:-/dashboard.php}"
LOGOUT_PATH="${CE_LOGOUT_PATH:-/logout.php}"
CURL_INSECURE="${CE_CURL_INSECURE:-1}"

RECOVERY_EMAIL="${CE_TEST_RECOVERY_EMAIL:-}"
RECOVERY_SENHA="${CE_TEST_RECOVERY_SENHA:-}"
OUTRO_EMAIL="${CE_TEST_USUARIO_EMAIL:-}"

FIXTURE_HELPER="$ROOT/scripts/evidencias/lib/mfa_recovery_fixture.php"
AUDIT_LOG="$ROOT/storage/logs/audit.log"

# Valores exclusivamente laboratoriais. Não são credenciais reais.
CODIGO_ANTIGO_A='A1B2-C3D4-E5F6-A7B8-C9D0'
CODIGO_ANTIGO_B='1111-2222-3333-4444-5555'
CODIGO_OUTRO_USUARIO='AAAA-1111-BBBB-2222-CCCC'
CODIGO_INVALIDO='DEAD-BEEF-CAFE-FEED-0000'

FALHAS=0
TEMP_DIR="$(mktemp -d)"
FIXTURE_JSON="$TEMP_DIR/fixture.json"
NOVOS_CODIGOS="$TEMP_DIR/novos-codigos.txt"

CURL=(curl -sS)
if [[ "$CURL_INSECURE" == "1" ]]; then
    CURL+=(-k)
fi

OUTRO_USUARIO_ID=''
CODIGO_OUTRO_ID=''

cleanup() {
    if [[ -n "$OUTRO_USUARIO_ID" && -n "$CODIGO_OUTRO_ID" ]]; then
        printf '%s\n%s\n' "$OUTRO_USUARIO_ID" "$CODIGO_OUTRO_ID" |
            php "$FIXTURE_HELPER" cleanup >/dev/null 2>&1 || true
    fi

    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

resultado_codigo() {
    local descricao="$1" esperado="$2" obtido="$3"

    if [[ "$esperado" == "$obtido" ]]; then
        printf '%-58s esperado=%-3s obtido=%-3s  OK\n' \
            "$descricao" "$esperado" "$obtido"
    else
        printf '%-58s esperado=%-3s obtido=%-3s  FALHA\n' \
            "$descricao" "$esperado" "$obtido"
        FALHAS=$((FALHAS + 1))
    fi
}

resultado_location() {
    local descricao="$1" esperado="$2" obtido="$3"

    if [[ "$esperado" == "$obtido" ]]; then
        printf '%-58s esperado=%-32s  OK\n' "$descricao" "$esperado"
    else
        printf '%-58s esperado=%-32s obtido=%s  FALHA\n' \
            "$descricao" "$esperado" "${obtido:-<vazio>}"
        FALHAS=$((FALHAS + 1))
    fi
}

resultado_booleano() {
    local descricao="$1" sucesso="$2"

    if [[ "$sucesso" == "1" ]]; then
        printf '%-58s OK\n' "$descricao"
    else
        printf '%-58s FALHA\n' "$descricao"
        FALHAS=$((FALHAS + 1))
    fi
}

location_resposta() {
    local arquivo="$1" location

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

header_valor() {
    local arquivo="$1" nome="$2"

    awk -v alvo="$nome" '
        BEGIN { IGNORECASE=1 }
        index(tolower($0), tolower(alvo) ":") == 1 {
            sub(/^[^:]+:[[:space:]]*/, "")
            sub(/\r$/, "")
            print
            exit
        }
    ' "$arquivo" 2>/dev/null || true
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
        self.found = None

    def handle_starttag(self, tag, attrs):
        if tag.lower() != "input" or self.found:
            return
        data = dict(attrs)
        name = data.get("name", "")
        value = data.get("value", "")
        if "csrf" in name.lower() and value:
            self.found = (name, value)

parser = Parser()
parser.feed(Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore"))
if not parser.found:
    raise SystemExit(1)
sys.stdout.write(parser.found[0] + "\t" + parser.found[1])
PY
}

extrair_segredo_mfa() {
    local arquivo="$1"

    python3 - "$arquivo" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import sys

class Parser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_code = False
        self.parts = []
        self.codes = []

    def handle_starttag(self, tag, attrs):
        if tag.lower() == "code":
            self.in_code = True
            self.parts = []

    def handle_data(self, data):
        if self.in_code:
            self.parts.append(data)

    def handle_endtag(self, tag):
        if tag.lower() == "code" and self.in_code:
            value = "".join(self.parts).strip()
            if value:
                self.codes.append(value)
            self.in_code = False
            self.parts = []

parser = Parser()
parser.feed(Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore"))
for value in parser.codes:
    compact = "".join(value.split())
    if len(compact) >= 16:
        sys.stdout.write(compact)
        raise SystemExit(0)
raise SystemExit(1)
PY
}

extrair_codigos_recuperacao() {
    local arquivo="$1"

    python3 - "$arquivo" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore")
codes = []
for code in re.findall(r"\b[A-F0-9]{4}(?:-[A-F0-9]{4}){4}\b", text):
    if code not in codes:
        codes.append(code)
for code in codes:
    print(code)
PY
}

gerar_totp() {
    local segredo="$1"
    printf '%s' "$segredo" |
        php -r '
require "vendor/autoload.php";
$secret = trim(stream_get_contents(STDIN));
if ($secret === "") { exit(2); }
$g = new \PragmaRX\Google2FA\Google2FA();
echo $g->getCurrentOtp($secret);
'
}

aguardar_janela_segura() {
    local pos=$(( $(date +%s) % 30 ))
    if (( pos >= 25 )); then
        sleep $((31 - pos))
    fi
}

aguardar_proximo_passo() {
    local pos=$(( $(date +%s) % 30 ))
    sleep $((31 - pos))
}

abrir_pagina() {
    local cookies="$1" caminho="$2" html="$3" headers="$4"
    "${CURL[@]}" \
        -c "$cookies" -b "$cookies" \
        -D "$headers" -o "$html" \
        -w '%{http_code}' \
        "$BASE_URL$caminho"
}

post_form() {
    local cookies="$1" caminho="$2" resposta="$3" headers="$4" dados="$5"
    printf '%s' "$dados" |
        "${CURL[@]}" \
            -c "$cookies" -b "$cookies" \
            -D "$headers" -o "$resposta" \
            -w '%{http_code}' \
            -H 'Content-Type: application/x-www-form-urlencoded' \
            --data-binary @- \
            "$BASE_URL$caminho"
}

form_login() {
    local email="$1" senha="$2" csrf_nome="$3" csrf_valor="$4"
    printf '%s\n%s\n%s\n%s\n' "$email" "$senha" "$csrf_nome" "$csrf_valor" |
        python3 -c '
import sys, urllib.parse
email=sys.stdin.readline().rstrip("\n")
password=sys.stdin.readline().rstrip("\n")
name=sys.stdin.readline().rstrip("\n")
token=sys.stdin.readline().rstrip("\n")
sys.stdout.write(urllib.parse.urlencode({"email":email,"senha":password,name:token}))
'
}

form_campo_csrf() {
    local campo="$1" valor="$2" csrf_nome="$3" csrf_valor="$4"
    printf '%s\n%s\n%s\n%s\n' "$campo" "$valor" "$csrf_nome" "$csrf_valor" |
        python3 -c '
import sys, urllib.parse
field=sys.stdin.readline().rstrip("\n")
value=sys.stdin.readline().rstrip("\n")
name=sys.stdin.readline().rstrip("\n")
token=sys.stdin.readline().rstrip("\n")
sys.stdout.write(urllib.parse.urlencode({field:value,name:token}))
'
}

preparar_login_http() {
    local prefixo="$1" cookies="$2"
    local html="$TEMP_DIR/${prefixo}-login.html"
    local headers="$TEMP_DIR/${prefixo}-login.headers"
    local http dados

    http="$(abrir_pagina "$cookies" "$LOGIN_PATH" "$html" "$headers")"
    [[ "$http" == "200" ]] || return 1
    dados="$(extrair_csrf "$html")" || return 1
    printf '%s\n' "$dados"
}

fazer_login_senha() {
    local prefixo="$1" cookies="$2"
    local dados csrf_nome csrf_valor form http

    dados="$(preparar_login_http "$prefixo" "$cookies")" || return 1
    csrf_nome="${dados%%$'\t'*}"
    csrf_valor="${dados#*$'\t'}"
    form="$(form_login "$RECOVERY_EMAIL" "$RECOVERY_SENHA" "$csrf_nome" "$csrf_valor")"
    http="$(post_form "$cookies" "$LOGIN_PATH" \
        "$TEMP_DIR/${prefixo}-post.html" \
        "$TEMP_DIR/${prefixo}-post.headers" "$form")"
    printf '%s\n' "$http"
}

if [[ -z "$RECOVERY_EMAIL" || -z "$RECOVERY_SENHA" || -z "$OUTRO_EMAIL" ]]; then
    echo "ERRO: defina CE_TEST_RECOVERY_EMAIL, CE_TEST_RECOVERY_SENHA e mantenha CE_TEST_USUARIO_EMAIL no .env.test.local."
    exit 2
fi

if [[ ! -f "$FIXTURE_HELPER" || ! -f vendor/autoload.php ]]; then
    echo "ERRO: helper da fixture ou vendor/autoload.php não encontrado."
    exit 2
fi

# Prepara fixture sem expor senha ou segredo no terminal.
printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$RECOVERY_EMAIL" "$RECOVERY_SENHA" "$OUTRO_EMAIL" \
    "$CODIGO_ANTIGO_A" "$CODIGO_ANTIGO_B" "$CODIGO_OUTRO_USUARIO" |
    php "$FIXTURE_HELPER" prepare > "$FIXTURE_JSON"

OUTRO_USUARIO_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["outro_usuario_id"])' "$FIXTURE_JSON")"
CODIGO_OUTRO_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["codigo_outro_id"])' "$FIXTURE_JSON")"
SEGREDO_ANTIGO="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["segredo_antigo"])' "$FIXTURE_JSON")"

if [[ -z "$SEGREDO_ANTIGO" ]]; then
    echo "ERRO: fixture não forneceu segredo TOTP antigo."
    exit 2
fi

echo
echo "======================================================================"
echo " ConectaEduca - Teste HTTP de recuperação e rotação do MFA"
echo "======================================================================"
echo

# Sem pré-autenticação, recovery deve voltar ao login.
sem_sessao_cookies="$TEMP_DIR/sem-sessao.cookies"
http="$(abrir_pagina "$sem_sessao_cookies" "$MFA_RECOVERY_PATH" \
    "$TEMP_DIR/sem-sessao.html" "$TEMP_DIR/sem-sessao.headers")"
resultado_codigo "Recovery sem pré-autenticação" "302" "$http"
resultado_location "Recovery sem pré-auth redireciona ao login" "$LOGIN_PATH" \
    "$(location_resposta "$TEMP_DIR/sem-sessao.headers")"

cookies="$TEMP_DIR/recovery.cookies"
http="$(fazer_login_senha "recovery" "$cookies")"
resultado_codigo "Senha correta da fixture de recovery" "302" "$http"
resultado_location "Senha direciona ao desafio MFA" "$MFA_PATH" \
    "$(location_resposta "$TEMP_DIR/recovery-post.headers")"

# Dashboard continua indisponível antes do segundo fator.
http="$(abrir_pagina "$cookies" "$DASHBOARD_PATH" \
    "$TEMP_DIR/dashboard-pre.html" "$TEMP_DIR/dashboard-pre.headers")"
resultado_codigo "Dashboard antes da recuperação MFA" "401" "$http"

# Abre página de recuperação.
recovery_html="$TEMP_DIR/recovery-form.html"
recovery_headers="$TEMP_DIR/recovery-form.headers"
http="$(abrir_pagina "$cookies" "$MFA_RECOVERY_PATH" "$recovery_html" "$recovery_headers")"
resultado_codigo "GET formulário de recuperação MFA" "200" "$http"
recovery_csrf="$(extrair_csrf "$recovery_html")"
recovery_csrf_nome="${recovery_csrf%%$'\t'*}"
recovery_csrf_valor="${recovery_csrf#*$'\t'}"

# CSRF ausente.
dados_sem_csrf="$(python3 -c 'import urllib.parse; print(urllib.parse.urlencode({"codigo_recuperacao":"DEAD-BEEF-CAFE-FEED-0000"}), end="")')"
http="$(post_form "$cookies" "$MFA_RECOVERY_PATH" \
    "$TEMP_DIR/recovery-sem-csrf.html" "$TEMP_DIR/recovery-sem-csrf.headers" "$dados_sem_csrf")"
resultado_codigo "Recovery code sem CSRF" "419" "$http"

# Código inválido.
form="$(form_campo_csrf codigo_recuperacao "$CODIGO_INVALIDO" "$recovery_csrf_nome" "$recovery_csrf_valor")"
http="$(post_form "$cookies" "$MFA_RECOVERY_PATH" \
    "$TEMP_DIR/recovery-invalido.html" "$TEMP_DIR/recovery-invalido.headers" "$form")"
resultado_codigo "Recovery code inválido" "401" "$http"

# Código que existe, mas pertence a outro usuário.
form="$(form_campo_csrf codigo_recuperacao "$CODIGO_OUTRO_USUARIO" "$recovery_csrf_nome" "$recovery_csrf_valor")"
http="$(post_form "$cookies" "$MFA_RECOVERY_PATH" \
    "$TEMP_DIR/recovery-outro.html" "$TEMP_DIR/recovery-outro.headers" "$form")"
resultado_codigo "Recovery code de outro usuário" "401" "$http"

# Código válido da fixture.
form="$(form_campo_csrf codigo_recuperacao "$CODIGO_ANTIGO_A" "$recovery_csrf_nome" "$recovery_csrf_valor")"
http="$(post_form "$cookies" "$MFA_RECOVERY_PATH" \
    "$TEMP_DIR/recovery-valido.html" "$TEMP_DIR/recovery-valido.headers" "$form")"
resultado_codigo "Recovery code válido" "302" "$http"
resultado_location "Recovery obriga novo cadastro MFA" "$MFA_CONFIG_PATH" \
    "$(location_resposta "$TEMP_DIR/recovery-valido.headers")"

http="$(abrir_pagina "$cookies" "$DASHBOARD_PATH" \
    "$TEMP_DIR/dashboard-pos-recovery-code.html" "$TEMP_DIR/dashboard-pos-recovery-code.headers")"
resultado_codigo "Dashboard ainda negado após recovery code" "401" "$http"

# Obtém novo segredo e CSRF da reconfiguração.
config_html="$TEMP_DIR/config.html"
config_headers="$TEMP_DIR/config.headers"
http="$(abrir_pagina "$cookies" "$MFA_CONFIG_PATH" "$config_html" "$config_headers")"
resultado_codigo "GET reconfiguração do MFA" "200" "$http"
novo_segredo="$(extrair_segredo_mfa "$config_html")"
config_csrf="$(extrair_csrf "$config_html")"
config_csrf_nome="${config_csrf%%$'\t'*}"
config_csrf_valor="${config_csrf#*$'\t'}"

if [[ -n "$novo_segredo" && "$novo_segredo" != "$SEGREDO_ANTIGO" ]]; then
    resultado_booleano "Segredo TOTP foi rotacionado" 1
else
    resultado_booleano "Segredo TOTP foi rotacionado" 0
fi

# Mesmo conhecendo o TOTP antigo, ele já não serve durante a recuperação.
aguardar_janela_segura
old_totp="$(gerar_totp "$SEGREDO_ANTIGO")"
form="$(form_campo_csrf codigo "$old_totp" "$config_csrf_nome" "$config_csrf_valor")"
http="$(post_form "$cookies" "$MFA_PATH" \
    "$TEMP_DIR/totp-antigo-pendente.html" "$TEMP_DIR/totp-antigo-pendente.headers" "$form")"
resultado_codigo "TOTP antigo inválido após recovery code" "401" "$http"

# Confirma o novo autenticador.
new_totp="$(gerar_totp "$novo_segredo")"
form="$(form_campo_csrf codigo "$new_totp" "$config_csrf_nome" "$config_csrf_valor")"
http="$(post_form "$cookies" "$MFA_CONFIG_PATH" \
    "$TEMP_DIR/config-confirm.html" "$TEMP_DIR/config-confirm.headers" "$form")"
resultado_codigo "Novo TOTP ativa MFA reconfigurado" "302" "$http"
resultado_location "Novo MFA direciona aos novos recovery codes" "$MFA_RECOVERY_CODES_PATH" \
    "$(location_resposta "$TEMP_DIR/config-confirm.headers")"

# Apresentação dos dez novos códigos.
codes_html="$TEMP_DIR/codes.html"
codes_headers="$TEMP_DIR/codes.headers"
http="$(abrir_pagina "$cookies" "$MFA_RECOVERY_CODES_PATH" "$codes_html" "$codes_headers")"
resultado_codigo "GET novos códigos de recuperação" "200" "$http"
extrair_codigos_recuperacao "$codes_html" > "$NOVOS_CODIGOS"
quantidade_novos="$(wc -l < "$NOVOS_CODIGOS" | tr -d ' ')"
[[ "$quantidade_novos" == "10" ]] && resultado_booleano "Foram apresentados dez novos recovery codes" 1 \
    || resultado_booleano "Foram apresentados dez novos recovery codes" 0

cache_control="$(header_valor "$codes_headers" 'Cache-Control')"
if [[ "$cache_control" == *no-store* ]]; then
    resultado_booleano "Página dos recovery codes usa Cache-Control no-store" 1
else
    resultado_booleano "Página dos recovery codes usa Cache-Control no-store" 0
fi

codes_csrf="$(extrair_csrf "$codes_html")"
codes_csrf_nome="${codes_csrf%%$'\t'*}"
codes_csrf_valor="${codes_csrf#*$'\t'}"
form="$(form_campo_csrf confirmado 1 "$codes_csrf_nome" "$codes_csrf_valor")"
http="$(post_form "$cookies" "$MFA_RECOVERY_CODES_PATH" \
    "$TEMP_DIR/codes-confirm.html" "$TEMP_DIR/codes-confirm.headers" "$form")"
resultado_codigo "Confirma salvamento dos novos recovery codes" "302" "$http"
resultado_location "Recuperação concluída redireciona ao dashboard" "$DASHBOARD_PATH" \
    "$(location_resposta "$TEMP_DIR/codes-confirm.headers")"

http="$(abrir_pagina "$cookies" "$DASHBOARD_PATH" \
    "$TEMP_DIR/dashboard-final.html" "$TEMP_DIR/dashboard-final.headers")"
resultado_codigo "Dashboard após recuperação completa" "200" "$http"

# Novo login: segredo antigo rejeitado e novo segredo aceito.
abrir_pagina "$cookies" "$LOGOUT_PATH" "$TEMP_DIR/logout.html" "$TEMP_DIR/logout.headers" >/dev/null
cookies2="$TEMP_DIR/recovery2.cookies"
http="$(fazer_login_senha "recovery2" "$cookies2")"
resultado_codigo "Novo login após rotação" "302" "$http"

mfa2_html="$TEMP_DIR/mfa2.html"
mfa2_headers="$TEMP_DIR/mfa2.headers"
http="$(abrir_pagina "$cookies2" "$MFA_PATH" "$mfa2_html" "$mfa2_headers")"
resultado_codigo "GET MFA após rotação" "200" "$http"
mfa2_csrf="$(extrair_csrf "$mfa2_html")"
mfa2_csrf_nome="${mfa2_csrf%%$'\t'*}"
mfa2_csrf_valor="${mfa2_csrf#*$'\t'}"

old_totp="$(gerar_totp "$SEGREDO_ANTIGO")"
form="$(form_campo_csrf codigo "$old_totp" "$mfa2_csrf_nome" "$mfa2_csrf_valor")"
http="$(post_form "$cookies2" "$MFA_PATH" \
    "$TEMP_DIR/mfa2-old.html" "$TEMP_DIR/mfa2-old.headers" "$form")"
resultado_codigo "TOTP antigo permanece inválido após rotação" "401" "$http"

aguardar_proximo_passo
new_totp="$(gerar_totp "$novo_segredo")"
form="$(form_campo_csrf codigo "$new_totp" "$mfa2_csrf_nome" "$mfa2_csrf_valor")"
http="$(post_form "$cookies2" "$MFA_PATH" \
    "$TEMP_DIR/mfa2-new.html" "$TEMP_DIR/mfa2-new.headers" "$form")"
resultado_codigo "TOTP novo autentica após rotação" "302" "$http"
resultado_location "TOTP novo redireciona ao dashboard" "$DASHBOARD_PATH" \
    "$(location_resposta "$TEMP_DIR/mfa2-new.headers")"

abrir_pagina "$cookies2" "$LOGOUT_PATH" "$TEMP_DIR/logout2.html" "$TEMP_DIR/logout2.headers" >/dev/null

# Novo login para provar que todo o conjunto antigo de recovery foi invalidado.
cookies3="$TEMP_DIR/recovery3.cookies"
http="$(fazer_login_senha "recovery3" "$cookies3")"
resultado_codigo "Login para testar códigos antigos" "302" "$http"
recovery3_html="$TEMP_DIR/recovery3.html"
recovery3_headers="$TEMP_DIR/recovery3.headers"
http="$(abrir_pagina "$cookies3" "$MFA_RECOVERY_PATH" "$recovery3_html" "$recovery3_headers")"
resultado_codigo "GET recovery após rotação" "200" "$http"
recovery3_csrf="$(extrair_csrf "$recovery3_html")"
recovery3_csrf_nome="${recovery3_csrf%%$'\t'*}"
recovery3_csrf_valor="${recovery3_csrf#*$'\t'}"

form="$(form_campo_csrf codigo_recuperacao "$CODIGO_ANTIGO_A" "$recovery3_csrf_nome" "$recovery3_csrf_valor")"
http="$(post_form "$cookies3" "$MFA_RECOVERY_PATH" \
    "$TEMP_DIR/old-used.html" "$TEMP_DIR/old-used.headers" "$form")"
resultado_codigo "Recovery code antigo usado continua inválido" "401" "$http"

form="$(form_campo_csrf codigo_recuperacao "$CODIGO_ANTIGO_B" "$recovery3_csrf_nome" "$recovery3_csrf_valor")"
http="$(post_form "$cookies3" "$MFA_RECOVERY_PATH" \
    "$TEMP_DIR/old-unused.html" "$TEMP_DIR/old-unused.headers" "$form")"
resultado_codigo "Recovery code antigo nunca usado também é inválido" "401" "$http"

http="$(abrir_pagina "$cookies3" "$DASHBOARD_PATH" \
    "$TEMP_DIR/dashboard-old-recovery.html" "$TEMP_DIR/dashboard-old-recovery.headers")"
resultado_codigo "Dashboard segue negado após códigos antigos" "401" "$http"
abrir_pagina "$cookies3" "$LOGOUT_PATH" "$TEMP_DIR/logout3.html" "$TEMP_DIR/logout3.headers" >/dev/null

# Estado final persistido.
printf '%s\n' "$RECOVERY_EMAIL" | php "$FIXTURE_HELPER" state > "$TEMP_DIR/state.json"
if python3 - "$TEMP_DIR/state.json" <<'PY'
import json, sys
s=json.load(open(sys.argv[1]))
ok=(int(s["mfa_ativo"])==1 and int(s["qr_confirmado"])==1 and
    int(s["ativo"])==1 and int(s["possui_passo_totp"])==1 and
    int(s["total_codigos"])==10 and int(s["codigos_disponiveis"])==10 and
    int(s["codigos_usados"])==0)
raise SystemExit(0 if ok else 1)
PY
then
    resultado_booleano "Estado final MFA + 10 novos recovery codes íntegro" 1
else
    resultado_booleano "Estado final MFA + 10 novos recovery codes íntegro" 0
fi

# Nenhum código conhecido ou recém-gerado pode aparecer na auditoria.
if [[ -f "$AUDIT_LOG" ]]; then
    if grep -Fq -e "$CODIGO_ANTIGO_A" -e "$CODIGO_ANTIGO_B" -e "$CODIGO_OUTRO_USUARIO" "$AUDIT_LOG"; then
        resultado_booleano "Audit log não contém recovery codes de teste" 0
    elif python3 - "$AUDIT_LOG" "$NOVOS_CODIGOS" <<'PY'
from pathlib import Path
import sys
log=Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore")
codes=[x.strip() for x in Path(sys.argv[2]).read_text().splitlines() if x.strip()]
raise SystemExit(1 if any(code in log for code in codes) else 0)
PY
    then
        resultado_booleano "Audit log não contém recovery codes de teste" 1
    else
        resultado_booleano "Audit log não contém recovery codes de teste" 0
    fi
fi

echo
echo "======================================================================"
if [[ "$FALHAS" -eq 0 ]]; then
    echo "RESULTADO: recuperação e rotação do MFA passaram em todos os testes."
    echo "Falhas: 0"
    echo "======================================================================"
    exit 0
fi

echo "RESULTADO: foram encontradas falhas na recuperação do MFA."
echo "Falhas: $FALHAS"
echo "======================================================================"
exit 1
