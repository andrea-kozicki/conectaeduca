#!/usr/bin/env fish

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositório ConectaEduca." >&2
    exit 1
end
cd "$ROOT"

set ENV_FILE "$ROOT/deploy/lab/stack-local/.runtime/stack-local.env"
set PROJECT conectaeduca-dmz-local
set RULE_HOST "$ROOT/deploy/dmz/waf/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf"
set RULE_CONTAINER /etc/modsecurity.d/owasp-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf

set DMZ_FILES \
    -f deploy/dmz/compose.yml \
    -f deploy/dmz/compose.database.yml \
    -f deploy/dmz/compose.app-secrets.yml \
    -f deploy/dmz/compose.waf.yml \
    -f deploy/dmz/compose.waf-tls.yml \
    -f deploy/dmz/compose.waf-policy.yml \
    -f deploy/dmz/compose.host.yml \
    -f deploy/dmz/compose.smtp.yml \
    -f deploy/lab/stack-local/compose.dmz-local.yml

function dmz
    docker compose -p "$PROJECT" --env-file "$ENV_FILE" $DMZ_FILES $argv
end

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
echo " CONECTAEDUCA - CHECKPOINT WAF / ENVELOPE CRIPTOGRAFICO"
echo " Excecao minima CRS 942120 + PL2 preservado"
echo "======================================================================"

if not test -f "$ENV_FILE"
    echo "FALHA       runtime do stack ausente"
    exit 1
end

if test -f "$RULE_HOST"
    ok "arquivo local de tuning existe"
else
    fail "arquivo local de tuning ausente"
end

if grep -q 'id:1001001' "$RULE_HOST" \
    && grep -q '942120;ARGS:json.encrypted_key' "$RULE_HOST" \
    && grep -q '942120;ARGS:json.iv' "$RULE_HOST" \
    && grep -q '942120;ARGS:json.tag' "$RULE_HOST" \
    && grep -q '942120;ARGS:json.ciphertext' "$RULE_HOST"
    ok "exclusao limita-se a regra 942120 e campos criptograficos"
else
    fail "escopo esperado da exclusao nao foi encontrado"
end

if grep -Eq 'SecRuleEngine[[:space:]]+Off|ctl:ruleEngine=Off|ruleRemoveByTag|ruleRemoveById=942' "$RULE_HOST"
    fail "tuning contém bypass amplo inesperado"
else
    ok "nenhum desligamento amplo do WAF foi configurado"
end

dmz config >/tmp/conectaeduca-waf-envelope-compose.yml
if test $status -eq 0
    ok "Compose completo continua valido"
else
    fail "Compose completo reprovou"
end

set WAF_ID (dmz ps -q waf)
if test -n "$WAF_ID"
    ok "container WAF localizado"
else
    fail "container WAF não está em execução"
end

if test -n "$WAF_ID"
    set MOUNT_SOURCE (docker inspect "$WAF_ID" \
        --format '{{range .Mounts}}{{if eq .Destination "/etc/modsecurity.d/owasp-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf"}}{{.Source}}{{end}}{{end}}' \
        2>/dev/null)

    if test -n "$MOUNT_SOURCE"
        ok "arquivo de tuning está montado no caminho oficial do CRS"
    else
        fail "arquivo de tuning não está montado no WAF atual"
    end

    if docker exec "$WAF_ID" grep -q 'id:1001001' "$RULE_CONTAINER" 2>/dev/null
        ok "regra local está carregável dentro do container"
    else
        fail "regra local não foi encontrada dentro do container"
    end
end

echo
echo "=== PROVA 1: ENVELOPE BASE64 NAO DEVE SER BLOQUEADO COMO SQLi ==="

set ENVELOPE '{"version":2,"algorithm":"AES-256-GCM + RSA-OAEP-SHA256","encrypted_key":"AA==","iv":"AAAAAAAAAAAAAAAA","tag":"AAAAAAAAAAAAAAAAAAAAAA==","ciphertext":"AA=="}'

set HEADERS (mktemp /tmp/conectaeduca-waf-envelope-headers.XXXXXX)
set BODY (mktemp /tmp/conectaeduca-waf-envelope-body.XXXXXX)
chmod 600 "$HEADERS" "$BODY"

set ENVELOPE_CODE (curl -ksS \
    --max-time 12 \
    --resolve conectaeduca.local:18444:127.0.0.1 \
    -D "$HEADERS" \
    -o "$BODY" \
    -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    --data-binary "$ENVELOPE" \
    https://conectaeduca.local:18444/api/processa_cadastro_usuario.php \
    2>/dev/null)

set ENVELOPE_CT (awk 'BEGIN{IGNORECASE=1} /^content-type:/{gsub("\r",""); print $2; exit}' "$HEADERS")

rm -f "$HEADERS" "$BODY"

# O envelope é criptograficamente inválido de propósito. O PHP deve responder 400.
# O que estamos provando é que o WAF deixou de responder 403 antes do backend.
if test "$ENVELOPE_CODE" = 400
    ok "envelope Base64 atravessa o WAF e chega ao backend (HTTP 400 esperado do PHP)"
else if test "$ENVELOPE_CODE" = 403
    fail "envelope Base64 ainda foi bloqueado pelo WAF (HTTP 403)"
else
    fail "resposta inesperada para envelope sintético: HTTP $ENVELOPE_CODE"
end

if string match -q 'application/json*' -- "$ENVELOPE_CT"
    ok "resposta do envelope veio do backend JSON, nao da pagina HTML 403 do WAF"
else
    fail "Content-Type inesperado no envelope sintético: $ENVELOPE_CT"
end

echo
echo "=== PROVA 2: WAF CONTINUA BLOQUEANDO TRAFEGO HOSTIL ==="

set SQLI_CODE (curl -ksS \
    --max-time 12 \
    --resolve conectaeduca.local:18444:127.0.0.1 \
    -G \
    --data-urlencode 'waf_probe=1==1' \
    -o /dev/null \
    -w '%{http_code}' \
    https://conectaeduca.local:18444/ \
    2>/dev/null)

if test "$SQLI_CODE" = 403
    ok "SQLi/operator probe fora do envelope continua bloqueado"
else
    fail "SQLi/operator probe retornou HTTP $SQLI_CODE"
end

set XSS_CODE (curl -ksS \
    --max-time 12 \
    --resolve conectaeduca.local:18444:127.0.0.1 \
    -G \
    --data-urlencode 'waf_probe=<script>alert(1)</script>' \
    -o /dev/null \
    -w '%{http_code}' \
    https://conectaeduca.local:18444/ \
    2>/dev/null)

if test "$XSS_CODE" = 403
    ok "XSS fora do envelope continua bloqueado"
else
    fail "XSS probe retornou HTTP $XSS_CODE"
end

echo
echo "=== PROVA 3: HEALTHCHECK NAO GERA HOST NUMERICO ==="

sleep 6

if test -n "$WAF_ID"
    if docker logs --since 8s "$WAF_ID" 2>&1 \
        | grep -q '"ruleId":"920350"'
        fail "healthcheck ainda aciona CRS 920350 por Host numerico"
    else
        ok "healthcheck usa hostname e nao aciona CRS 920350"
    end
end

echo
echo "=== HIGIENE ==="

if git diff --check
    ok "git diff --check"
else
    fail "git diff --check reprovou"
end

echo
echo "======================================================================"
echo " RESULTADO"
echo "======================================================================"
echo "Aprovacoes: $OK_COUNT"
echo "Falhas:     $FAIL_COUNT"

if test $FAIL_COUNT -eq 0
    echo "CHECKPOINT WAF / ENVELOPE CRIPTOGRAFICO: APROVADO."
    exit 0
end

echo "CHECKPOINT WAF / ENVELOPE CRIPTOGRAFICO: REPROVADO."
exit 1
