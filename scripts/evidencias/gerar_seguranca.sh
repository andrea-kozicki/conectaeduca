#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# Evidências podem conter informações do ambiente local.
umask 077

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${EVIDENCIAS_DIR:-$ROOT/docs/evidencias/seguranca/$TIMESTAMP}"
SUMMARY="$OUT/resumo.txt"

mkdir -p "$OUT"
: > "$SUMMARY"

BRANCH="$(git branch --show-current)"
COMMIT="$(git rev-parse HEAD)"

registrar() {
    local nome="$1"
    local codigo="$2"

    printf '%-32s exit=%s\n' "$nome" "$codigo" | tee -a "$SUMMARY"
}

executar() {
    local nome="$1"
    shift

    local arquivo="$OUT/${nome}.txt"

    {
        printf 'Data: %s\n' "$(date --iso-8601=seconds)"
        printf 'Branch: %s\n' "$BRANCH"
        printf 'Commit: %s\n' "$COMMIT"
        printf '\n'
    } > "$arquivo"

    set +e
    "$@" >> "$arquivo" 2>&1
    local codigo=$?
    set -e

    printf '\nexit_code=%s\n' "$codigo" >> "$arquivo"
    registrar "$nome" "$codigo"
}

echo "ConectaEduca - validação de segurança" >> "$SUMMARY"
echo "Branch: $BRANCH" >> "$SUMMARY"
echo "Commit: $COMMIT" >> "$SUMMARY"
echo "Data: $(date --iso-8601=seconds)" >> "$SUMMARY"
echo >> "$SUMMARY"

# ----------------------------------------------------------------------
# Contexto do ambiente
# ----------------------------------------------------------------------

{
    echo "=== CONTEXTO ==="
    echo "Branch: $BRANCH"
    echo "Commit: $COMMIT"
    echo "Data: $(date --iso-8601=seconds)"
    echo

    echo "PHP:"
    php -v | head -n 1
    echo

    echo "Composer:"
    composer --version
    echo

    echo "Git status:"
    git status --short
} > "$OUT/contexto.txt"

registrar "contexto" 0

# ----------------------------------------------------------------------
# PHP lint - somente arquivos rastreados pelo Git
# ----------------------------------------------------------------------

executar \
    "php-lint" \
    bash -lc \
    'git ls-files -z "*.php" | xargs -0 -r -n1 php -l'

# ----------------------------------------------------------------------
# PHPUnit
# ----------------------------------------------------------------------

if [[ -x vendor/bin/phpunit ]]; then
    executar "phpunit" vendor/bin/phpunit
else
    echo "vendor/bin/phpunit não encontrado." > "$OUT/phpunit.txt"
    registrar "phpunit" 127
fi

# ----------------------------------------------------------------------
# Composer Audit
# ----------------------------------------------------------------------

executar "composer-audit" composer audit

# ----------------------------------------------------------------------
# Verificação de resíduos ativos do Cognito/AWS
#
# As migrations 001/002 são deliberadamente preservadas como histórico.
# ----------------------------------------------------------------------

COGNITO_FILE="$OUT/referencias-cognito-ativas.txt"

set +e
git grep -ni -E \
    'cognito|amazon cognito|cognito_sub|COGNITO_|aws/aws-sdk-php|AWS_' \
    -- \
    ':!sql/migrations/**' \
    ':!estrutura_arquivos_repositorio.txt' \
    ':!scripts/evidencias/gerar_seguranca.sh' \
  ':!scripts/evidencias/README.md' \
    > "$COGNITO_FILE" 2>&1
COGNITO_RC=$?
set -e

if [[ "$COGNITO_RC" -eq 1 ]]; then
    echo "OK: nenhuma referência ativa ao Cognito/AWS encontrada." \
        > "$COGNITO_FILE"
    registrar "referencias-cognito-ativas" 0
elif [[ "$COGNITO_RC" -eq 0 ]]; then
    {
        echo
        echo "ATENÇÃO: foram encontradas referências ativas."
    } >> "$COGNITO_FILE"
    registrar "referencias-cognito-ativas" 1
else
    registrar "referencias-cognito-ativas" "$COGNITO_RC"
fi

# ----------------------------------------------------------------------
# GitHub Actions - procurar actions ainda referenciadas por tags mutáveis
# ----------------------------------------------------------------------

ACTIONS_FILE="$OUT/github-actions-pinning.txt"

set +e
git grep -nE \
    'uses:[[:space:]]+[^[:space:]]+@(v[0-9]+([.][0-9]+)*|main|master|latest)' \
    -- .github/workflows \
    > "$ACTIONS_FILE" 2>&1
ACTIONS_RC=$?
set -e

if [[ "$ACTIONS_RC" -eq 1 ]]; then
    echo "OK: nenhuma GitHub Action com tag mutável detectada." \
        > "$ACTIONS_FILE"
    registrar "github-actions-pinning" 0
elif [[ "$ACTIONS_RC" -eq 0 ]]; then
    {
        echo
        echo "ATENÇÃO: existem GitHub Actions sem pin por SHA."
    } >> "$ACTIONS_FILE"
    registrar "github-actions-pinning" 1
else
    registrar "github-actions-pinning" "$ACTIONS_RC"
fi

# ----------------------------------------------------------------------
# Autenticação local, CSRF, RBAC e sessão
# ----------------------------------------------------------------------

if [[ -f .env.test.local ]]; then
    if git check-ignore -q .env.test.local; then
        echo "OK: .env.test.local está protegido pelo .gitignore." \
            > "$OUT/auth-local-env.txt"

        registrar "auth-local-env" 0
    else
        echo "ERRO: .env.test.local existe, mas não está ignorado pelo Git." \
            > "$OUT/auth-local-env.txt"

        registrar "auth-local-env" 1
    fi
else
    echo "AVISO: .env.test.local não encontrado." \
        > "$OUT/auth-local-env.txt"

    registrar "auth-local-env" 2
fi

if [[ -x scripts/evidencias/testar_auth_local.sh ]]; then
    executar \
        "auth-local" \
        scripts/evidencias/testar_auth_local.sh
else
    echo "Script testar_auth_local.sh não encontrado ou não executável." \
        > "$OUT/auth-local.txt"

    registrar "auth-local" 127
fi


# ----------------------------------------------------------------------
# Semgrep
# ----------------------------------------------------------------------

if command -v semgrep >/dev/null 2>&1; then
    executar "semgrep" semgrep ci
else
    echo "Semgrep não instalado." > "$OUT/semgrep.txt"
    registrar "semgrep" 127
fi

# ----------------------------------------------------------------------
# Snyk
#
# Antes de executar Snyk Code, confirma que o .env local está ignorado.
# ----------------------------------------------------------------------

SNYK_PERMITIDO=1

if [[ -f .env ]]; then
    if git check-ignore -q .env; then
        echo "OK: .env está protegido pelo .gitignore." \
            > "$OUT/snyk-protecao-env.txt"
        registrar "snyk-protecao-env" 0
    else
        echo "ERRO: .env existe, mas não está ignorado pelo Git." \
            > "$OUT/snyk-protecao-env.txt"
        registrar "snyk-protecao-env" 1
        SNYK_PERMITIDO=0
    fi
fi

if command -v snyk >/dev/null 2>&1; then
    if [[ "$SNYK_PERMITIDO" -eq 1 ]]; then
        executar \
            "snyk-open-source" \
            snyk test \
            --target-reference="$BRANCH"

        executar \
            "snyk-code" \
            snyk code test \
            --target-reference="$BRANCH"
    else
        echo "Snyk não executado por segurança: verifique o .gitignore." \
            > "$OUT/snyk.txt"
        registrar "snyk" 1
    fi
else
    echo "Snyk CLI não instalado." > "$OUT/snyk.txt"
    registrar "snyk" 127
fi

# ----------------------------------------------------------------------
# Integridade das evidências
# ----------------------------------------------------------------------

(
    cd "$OUT"
    sha256sum ./*.txt > SHA256SUMS.txt
)

echo
echo "=============================================="
echo "Evidências geradas em:"
echo "$OUT"
echo
echo "Resumo:"
cat "$SUMMARY"
echo "=============================================="
