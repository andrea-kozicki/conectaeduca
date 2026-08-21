#!/usr/bin/env fish

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositório ConectaEduca." >&2
    exit 1
end
cd "$ROOT"

set ENV_FILE "$ROOT/deploy/lab/stack-local/.runtime/stack-local.env"
set DB_PROJECT conectaeduca-mariadb-local
set DMZ_PROJECT conectaeduca-dmz-local

if not test -f "$ENV_FILE"
    echo "FALHA runtime do stack ausente"
    exit 1
end

set DB_FILES \
    -f deploy/interna/mariadb/compose.yml \
    -f deploy/interna/mariadb/compose.host.yml \
    -f deploy/lab/stack-local/compose.db-local.yml

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

function db
    docker compose -p "$DB_PROJECT" --env-file "$ENV_FILE" $DB_FILES $argv
end

function dmz
    docker compose -p "$DMZ_PROJECT" --env-file "$ENV_FILE" $DMZ_FILES $argv
end

echo "======================================================================"
echo " CONECTAEDUCA - CHECKPOINT STACK LOCAL PERSISTENTE"
echo " DB externo + WAF/TLS + app secrets + SMTP/OpenBao"
echo "======================================================================"

set FAIL 0
function ok
    echo "OK          $argv"
end
function fail
    echo "FALHA       $argv"
    set -g FAIL (math $FAIL + 1)
end

for svc in mariadb
    set cid (db ps -q $svc)
    set health (docker inspect "$cid" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}ausente{{end}}' 2>/dev/null)
    if test "$health" = healthy
        ok "$svc healthy"
    else
        fail "$svc health=$health"
    end
end

for svc in php nginx waf
    set cid (dmz ps -q $svc)
    set health (docker inspect "$cid" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}ausente{{end}}' 2>/dev/null)
    if test "$health" = healthy
        ok "$svc healthy"
    else
        fail "$svc health=$health"
    end
end

set pdo (dmz exec -T php php -r '
require "/var/www/conectaeduca/vendor/autoload.php";
$pdo=\ConectaEduca\Config\Database::connect();
echo $pdo->query("SELECT DATABASE()")->fetchColumn();
' 2>/dev/null)

if test "$pdo" = conectaeduca
    ok "PDO conecta no MariaDB externo ao projeto Docker"
else
    fail "PDO não confirmou banco conectaeduca"
end

set login_code (curl -ksS \
    --resolve conectaeduca.local:18444:127.0.0.1 \
    -o /dev/null -w '%{http_code}' \
    https://conectaeduca.local:18444/login.php 2>/dev/null)

if test "$login_code" = 200
    ok "login HTTPS via WAF responde 200"
else
    fail "login HTTPS=$login_code"
end

set reset_code (curl -ksS \
    --resolve conectaeduca.local:18444:127.0.0.1 \
    -o /dev/null -w '%{http_code}' \
    https://conectaeduca.local:18444/esqueci-senha.php 2>/dev/null)

if test "$reset_code" = 200
    ok "recuperação de senha via WAF responde 200"
else
    fail "recuperação de senha HTTPS=$reset_code"
end

set key_code (curl -ksS \
    --resolve conectaeduca.local:18444:127.0.0.1 \
    -o /dev/null -w '%{http_code}' \
    https://conectaeduca.local:18444/api/public_key.php 2>/dev/null)

if test "$key_code" = 200
    ok "chave pública da criptografia híbrida acessível"
else
    fail "public_key HTTP=$key_code"
end

set xss_code (curl -ksS \
    --resolve conectaeduca.local:18444:127.0.0.1 \
    -G --data-urlencode 'q=<script>alert(1)</script>' \
    -o /dev/null -w '%{http_code}' \
    https://conectaeduca.local:18444/ 2>/dev/null)

if test "$xss_code" = 403
    ok "WAF PL2 bloqueia vetor XSS"
else
    fail "WAF XSS HTTP=$xss_code"
end

set PHP_ID (dmz ps -q php)
set NGINX_ID (dmz ps -q nginx)
set WAF_ID (dmz ps -q waf)

set PHP_PUBLISH (docker port "$PHP_ID" 9000/tcp 2>/dev/null)
if test -n "$PHP_PUBLISH"
    fail "container PHP publicou 9000 no host: $PHP_PUBLISH"
else
    ok "container PHP-FPM não publica 9000 no host"
end

set NGINX_PUBLISH (docker port "$NGINX_ID" 8080/tcp 2>/dev/null)
if test -n "$NGINX_PUBLISH"
    fail "container Nginx publicou 8080 no host: $NGINX_PUBLISH"
else
    ok "container Nginx não publica 8080 no host"
end

set WAF_HTTP_PUBLISH (docker port "$WAF_ID" 8080/tcp 2>/dev/null)
set WAF_HTTPS_PUBLISH (docker port "$WAF_ID" 8443/tcp 2>/dev/null)

if test "$WAF_HTTP_PUBLISH" = "127.0.0.1:18081"
    ok "WAF HTTP publicado apenas em 127.0.0.1:18081"
else
    fail "binding HTTP do WAF inesperado: $WAF_HTTP_PUBLISH"
end

if test "$WAF_HTTPS_PUBLISH" = "127.0.0.1:18444"
    ok "WAF HTTPS publicado apenas em 127.0.0.1:18444"
else
    fail "binding HTTPS do WAF inesperado: $WAF_HTTPS_PUBLISH"
end

echo
echo "Falhas: $FAIL"
if test $FAIL -eq 0
    echo "CHECKPOINT STACK LOCAL: APROVADO."
    exit 0
end

echo "CHECKPOINT STACK LOCAL: REPROVADO."
exit 1
