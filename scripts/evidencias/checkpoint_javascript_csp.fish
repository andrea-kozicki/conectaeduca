#!/usr/bin/env fish
set -g OK_COUNT 0
set -g WARN_COUNT 0
set -g FAIL_COUNT 0

function ok
    set -g OK_COUNT (math $OK_COUNT + 1)
    printf 'OK          %s\n' "$argv"
end

function warn
    set -g WARN_COUNT (math $WARN_COUNT + 1)
    printf 'ADVERTENCIA %s\n' "$argv"
end

function fail
    set -g FAIL_COUNT (math $FAIL_COUNT + 1)
    printf 'FALHA       %s\n' "$argv"
end

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0
    echo 'FALHA       nao foi possivel localizar a raiz Git'
    exit 1
end
cd "$ROOT"

echo '======================================================================'
echo ' CONECTAEDUCA - CHECKPOINT JAVASCRIPT / CSP'
echo ' Superficie ativa do navegador, DOM, CSRF, navegacao e politica CSP'
echo '======================================================================'

set JS_FILES (git ls-files 'public/assets/js/*.js')
if test (count $JS_FILES) -gt 0
    ok "JavaScripts rastreados: "(count $JS_FILES)
else
    fail 'nenhum JavaScript rastreado em public/assets/js'
end

if type -q node
    set syntax_bad
    for file in $JS_FILES
        node --check "$file" >/dev/null 2>&1
        or set -a syntax_bad "$file"
    end
    if test (count $syntax_bad) -eq 0
        ok 'todos os JavaScripts passam em node --check'
    else
        fail 'ha JavaScript com erro de sintaxe'
        printf '            %s\n' $syntax_bad
    end
else
    warn 'Node.js ausente; validacao node --check nao executada'
end

set dangerous (git grep -n -E '(innerHTML|outerHTML|insertAdjacentHTML|document\.write|eval[[:space:]]*\(|new[[:space:]]+Function)' -- 'public/assets/js/*.js' 2>/dev/null)
if test (count $dangerous) -eq 0
    ok 'nenhum sink DOM/eval de alto risco detectado nos JS ativos'
else
    fail 'sink DOM/eval de alto risco detectado'
    printf '            %s\n' $dangerous
end

set storage (git grep -n -E '\b(localStorage|sessionStorage|indexedDB|document\.cookie)\b' -- 'public/assets/js/*.js' 2>/dev/null)
if test (count $storage) -eq 0
    ok 'nenhum armazenamento persistente/sensivel no navegador detectado'
else
    warn 'uso de armazenamento/cookie via JavaScript requer revisao'
    printf '            %s\n' $storage
end

set inline_handlers (git grep -n -E 'on(click|submit|load|error|change|input|focus|blur|mouseover)[[:space:]]*=' -- 'src/View/**/*.php' 'public/*.php' 2>/dev/null)
if test (count $inline_handlers) -eq 0
    ok 'nenhum event handler JavaScript inline nas views ativas'
else
    fail 'event handler inline incompativel com CSP detectado'
    printf '            %s\n' $inline_handlers
end

set inline_scripts (git grep -n -P '<script(?![^>]*\bsrc=)[^>]*>' -- 'src/View/**/*.php' 'public/*.php' 2>/dev/null)
if test (count $inline_scripts) -eq 0
    ok 'nenhum bloco script inline nas views ativas'
else
    fail 'bloco script inline detectado'
    printf '            %s\n' $inline_scripts
end

set external_scripts (git grep -n -E '<script[^>]+src="(https?:)?//' -- 'src/View/**/*.php' 'public/*.php' 2>/dev/null)
if test (count $external_scripts) -eq 0
    ok 'nenhum JavaScript externo/terceiro carregado pelas views ativas'
else
    warn 'JavaScript externo detectado; revisar origem e integridade'
    printf '            %s\n' $external_scripts
end

set js_urls (git grep -n -i 'javascript:' -- 'src/View/**/*.php' 'public/*.php' 'public/assets/js/*.js' 2>/dev/null)
if test (count $js_urls) -eq 0
    ok 'nenhuma URL javascript: detectada'
else
    fail 'URL javascript: detectada'
    printf '            %s\n' $js_urls
end

if grep -Fq "script-src 'self'" src/Security/SecurityHeaders.php \
    && grep -Fq "script-src-attr 'none'" src/Security/SecurityHeaders.php \
    && grep -Fq "object-src 'none'" src/Security/SecurityHeaders.php \
    && not grep -E "script-src[^;]*(unsafe-inline|unsafe-eval)" src/Security/SecurityHeaders.php >/dev/null
    ok "CSP mantem script-src 'self', bloqueia handlers inline e objetos"
else
    fail 'CSP JavaScript nao atende ao baseline esperado'
end

if grep -Fq 'data-confirm=' src/View/inscricao/minhas-inscricoes.php \
    && grep -Fq 'data-confirm=' src/View/empresa/oportunidades.php \
    && grep -Fq 'window.confirm' public/assets/js/encrypted-form.js
    ok 'confirmacoes destrutivas foram externalizadas e cobertas pelo JS comum'
else
    fail 'confirmacoes destrutivas nao estao no padrao externo esperado'
end

if grep -Fq 'url.origin !== window.location.origin' public/assets/js/encrypted-form.js
    ok 'encrypted-form recusa action de origem externa antes do fetch'
else
    fail 'encrypted-form nao valida a origem do destino'
end

if grep -Fq 'url.origin !== window.location.origin' public/assets/js/csrf.js
    ok 'secureFetch recusa origem externa antes de anexar CSRF'
else
    fail 'secureFetch nao restringe destino a mesma origem'
end

if grep -Fq "hash: 'SHA-1'" public/assets/js/crypto-utils.js
    warn 'RSA-OAEP ainda usa SHA-1 por compatibilidade; migracao versionada para SHA-256 pendente'
else
    ok 'crypto-utils nao referencia SHA-1 no RSA-OAEP'
end

if grep -Eq '\bconsole\.(log|debug|info|warn|error)\b' public/assets/js/*.js
    warn 'ha console.* nos JS ativos; confirmar que mensagens nao carregam dados sensiveis em producao'
else
    ok 'nenhum console.* nos JS ativos'
end

if git diff --check >/dev/null
    ok 'git diff --check'
else
    fail 'git diff --check encontrou problema'
end

echo
echo '======================================================================'
echo ' RESULTADO'
echo '======================================================================'
echo "Aprovacoes:    $OK_COUNT"
echo "Advertencias:  $WARN_COUNT"
echo "Falhas:        $FAIL_COUNT"

if test $FAIL_COUNT -gt 0
    echo 'CHECKPOINT JAVASCRIPT / CSP: REPROVADO.'
    exit 1
end

if test $WARN_COUNT -gt 0
    echo 'CHECKPOINT JAVASCRIPT / CSP: APROVADO COM ADVERTENCIAS.'
    exit 0
end

echo 'CHECKPOINT JAVASCRIPT / CSP: APROVADO.'
exit 0
