#!/usr/bin/env fish

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositório ConectaEduca." >&2
    exit 1
end
cd "$ROOT"

set -g OK_COUNT 0
set -g FAIL_COUNT 0

function ok
    echo "OK          $argv"
    set -g OK_COUNT (math $OK_COUNT + 1)
end

function fail
    echo "FALHA       $argv"
    set -g FAIL_COUNT (math $FAIL_COUNT + 1)
end

echo "======================================================================"
echo " CONECTAEDUCA - CHECKPOINT SAST / HIGIENE PRE-DLP"
echo " Secret fixtures + Semgrep/Snyk hardening + Git hygiene"
echo "======================================================================"

if python3 scripts/evidencias/verificar_segredos_estaticos.py
    ok "verificador estático específico do projeto"
else
    fail "verificador estático específico do projeto"
end

if python3 -m py_compile scripts/bootstrap/provisionar_openbao_smtp.py
    ok "bootstrap OpenBao passa em py_compile"
else
    fail "bootstrap OpenBao falhou no py_compile"
end

for php_file in \
    scripts/evidencias/checkpoint_password_reset_http.php \
    scripts/evidencias/checkpoint_password_reset_e2e.php \
    scripts/evidencias/checkpoint_password_reset_mariadb.php \
    scripts/evidencias/checkpoint_crypto_hybrid_v2.php \
    tests/Unit/Service/MailServiceTest.php

    if php -l "$php_file" >/dev/null
        ok "php -l: $php_file"
    else
        fail "php -l: $php_file"
    end
end

if git diff --check
    ok "git diff --check"
else
    fail "git diff --check"
end

echo
echo "======================================================================"
echo " RESULTADO"
echo "======================================================================"
echo "Aprovacoes: $OK_COUNT"
echo "Falhas:     $FAIL_COUNT"

if test $FAIL_COUNT -eq 0
    echo "CHECKPOINT SAST / HIGIENE PRE-DLP: APROVADO."
    exit 0
end

echo "CHECKPOINT SAST / HIGIENE PRE-DLP: REPROVADO."
exit 1
