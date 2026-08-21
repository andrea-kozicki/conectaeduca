#!/usr/bin/env fish

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositório ConectaEduca." >&2
    exit 1
end
cd "$ROOT"

set RUNTIME "$ROOT/deploy/lab/stack-local/.runtime"
set ENV_FILE "$RUNTIME/stack-local.env"
set SMTP_ENV "$ROOT/deploy/dmz/.runtime/smtp-google.env"
set SMTP_SECRET /dev/shm/conectaeduca-smtp-password
set GROUP_NAME conectaeduca-stack-secret

set DB_PROJECT conectaeduca-mariadb-local
set DMZ_PROJECT conectaeduca-dmz-local

set DB_ROOT_SECRET "$RUNTIME/mariadb_root_password"
set DB_APP_SECRET "$RUNTIME/conectaeduca_db_password"
set APP_PRIVATE "$RUNTIME/conectaeduca_private_key"
set APP_PUBLIC "$RUNTIME/conectaeduca_public_key"
set WAF_TLS_KEY "$RUNTIME/waf_tls_key"
set WAF_TLS_CERT "$RUNTIME/waf_tls_cert"

set DB_VOLUME conectaeduca-mariadb-local-data

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

function wait_healthy
    set label $argv[1]
    set cid $argv[2]
    set timeout $argv[3]
    set elapsed 0

    while test $elapsed -le $timeout
        set state (docker inspect "$cid" --format '{{.State.Status}}' 2>/dev/null)
        set health (docker inspect "$cid" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}sem-healthcheck{{end}}' 2>/dev/null)

        if test "$state" = running -a "$health" = healthy
            echo "OK          $label healthy"
            return 0
        end

        if test "$state" = exited -o "$state" = dead
            echo "FALHA       $label encerrou antes de ficar healthy"
            return 1
        end

        if test (math "$elapsed % 10") -eq 0
            echo "INFO        aguardando $label: t={$elapsed}s state=$state health=$health"
        end

        sleep 2
        set elapsed (math "$elapsed + 2")
    end

    echo "FALHA       timeout esperando $label ficar healthy"
    return 1
end

function ensure_secret_group
    if not getent group "$GROUP_NAME" >/dev/null 2>&1
        echo "INFO        criando grupo de sistema dedicado: $GROUP_NAME" >&2
        sudo groupadd --system "$GROUP_NAME"
        or return 1
    end

    set line (getent group "$GROUP_NAME")
    set fields (string split ':' -- "$line")
    set gid $fields[3]
    set members $fields[4]

    if test -z "$gid"
        echo "FALHA       GID do grupo dedicado indisponível" >&2
        return 1
    end

    if test -n "$members"
        echo "FALHA       grupo $GROUP_NAME possui membros explícitos; esperado nenhum" >&2
        return 1
    end

    echo "$gid"
end

function secure_group_file
    set file $argv[1]
    set gid $argv[2]

    sudo chown (id -u):(id -g) "$file"
    or return 1

    sudo chgrp "$gid" "$file"
    or return 1

    chmod 0640 "$file"
    or return 1

    set mode (stat -c '%a' "$file")
    set actual_gid (stat -c '%g' "$file")

    if test "$mode" != 640 -o "$actual_gid" != "$gid"
        echo "FALHA       proteção inesperada em $file"
        return 1
    end
end

function create_tls_if_needed
    set source_cert /etc/apache2/ssl/conectaeduca/cert.pem
    set source_key /etc/apache2/ssl/conectaeduca/key.pem
    set reused 0

    if sudo test -f "$source_cert"; and sudo test -f "$source_key"
        set tmp_cert "$RUNTIME/.candidate-cert.pem"
        set tmp_key "$RUNTIME/.candidate-key.pem"

        sudo cp "$source_cert" "$tmp_cert"
        or return 1
        sudo cp "$source_key" "$tmp_key"
        or return 1
        sudo chown (id -u):(id -g) "$tmp_cert" "$tmp_key"

        if openssl x509 -in "$tmp_cert" -noout -ext subjectAltName 2>/dev/null \
            | grep -q 'DNS:conectaeduca.local'
            set cert_fp (openssl x509 -in "$tmp_cert" -pubkey -noout 2>/dev/null \
                | openssl pkey -pubin -outform DER 2>/dev/null \
                | sha256sum | awk '{print $1}')
            set key_fp (openssl pkey -in "$tmp_key" -pubout -outform DER 2>/dev/null \
                | sha256sum | awk '{print $1}')

            if test -n "$cert_fp" -a "$cert_fp" = "$key_fp"
                mv "$tmp_cert" "$WAF_TLS_CERT"
                mv "$tmp_key" "$WAF_TLS_KEY"
                set reused 1
                echo "OK          certificado local existente reutilizado para o WAF"
            end
        end

        rm -f "$tmp_cert" "$tmp_key"
    end

    if test $reused -eq 0
        echo "INFO        gerando certificado TLS autoassinado de laboratório"
        openssl req \
            -x509 \
            -newkey rsa:2048 \
            -sha256 \
            -nodes \
            -days 30 \
            -subj "/CN=conectaeduca.local" \
            -addext "subjectAltName=DNS:conectaeduca.local" \
            -keyout "$WAF_TLS_KEY" \
            -out "$WAF_TLS_CERT" \
            >/dev/null 2>&1
        or return 1
    end
end

function prepare_runtime
    mkdir -p "$RUNTIME"
    chmod 0700 "$RUNTIME"
    or return 1

    set volume_exists 0
    if docker volume inspect "$DB_VOLUME" >/dev/null 2>&1
        set volume_exists 1
    end

    set required \
        "$DB_ROOT_SECRET" \
        "$DB_APP_SECRET" \
        "$APP_PRIVATE" \
        "$APP_PUBLIC" \
        "$WAF_TLS_KEY" \
        "$WAF_TLS_CERT"

    set missing
    for file in $required
        if not test -f "$file"
            set -a missing "$file"
        end
    end

    if test $volume_exists -eq 1 -a (count $missing) -gt 0
        echo "FALHA       volume MariaDB persistente existe, mas secrets locais estão incompletos"
        echo "INFO        não serão geradas credenciais novas para um volume existente"
        return 1
    end

    if test $volume_exists -eq 0
        if test (count $missing) -gt 0
            echo "INFO        inicializando material persistente do laboratório"

            openssl rand -hex 32 > "$DB_ROOT_SECRET"
            or return 1
            openssl rand -hex 32 > "$DB_APP_SECRET"
            or return 1

            openssl genpkey \
                -algorithm RSA \
                -pkeyopt rsa_keygen_bits:2048 \
                -out "$APP_PRIVATE" \
                >/dev/null 2>&1
            or return 1

            openssl pkey \
                -in "$APP_PRIVATE" \
                -pubout \
                -out "$APP_PUBLIC" \
                >/dev/null 2>&1
            or return 1

            create_tls_if_needed
            or return 1
        end
    end

    for file in $required
        if not test -s "$file"
            echo "FALHA       secret/runtime ausente ou vazio: $file"
            return 1
        end
    end
end

function write_env
    set stack_gid $argv[1]
    set db_gateway $argv[2]

    if not test -f "$SMTP_ENV"
        echo "FALHA       runtime SMTP não encontrado: $SMTP_ENV"
        return 1
    end

    if not test -f "$SMTP_SECRET"
        echo "FALHA       segredo SMTP não está materializado em RAM"
        echo "INFO        o OpenBao deve materializá-lo antes de subir o stack"
        return 1
    end

    set tmp "$RUNTIME/.stack-local.env.tmp"
    rm -f "$tmp"

    grep -E \
        '^(CONECTAEDUCA_SMTP_[A-Z0-9_]+|SMTP_REAL_CHECKPOINT_TO)=' \
        "$SMTP_ENV" \
        > "$tmp"
    or true

    if grep -Eq '^MAIL_PASSWORD=' "$tmp"
        echo "FALHA       MAIL_PASSWORD direto apareceu no runtime SMTP"
        rm -f "$tmp"
        return 1
    end

    begin
        echo "CONECTAEDUCA_STACK_SECRET_GID=$stack_gid"
        echo "CONECTAEDUCA_DB_ROOT_PASSWORD_FILE=$DB_ROOT_SECRET"
        echo "CONECTAEDUCA_DB_PASSWORD_FILE=$DB_APP_SECRET"
        echo "CONECTAEDUCA_DB_HOST=host.docker.internal"
        echo "CONECTAEDUCA_DB_BIND_ADDRESS=$db_gateway"
        echo "CONECTAEDUCA_DB_PORT=13306"
        echo "CONECTAEDUCA_PRIVATE_KEY_FILE=$APP_PRIVATE"
        echo "CONECTAEDUCA_PUBLIC_KEY_FILE=$APP_PUBLIC"
        echo "CONECTAEDUCA_WAF_TLS_CERT_FILE=$WAF_TLS_CERT"
        echo "CONECTAEDUCA_WAF_TLS_KEY_FILE=$WAF_TLS_KEY"
        echo "CONECTAEDUCA_WAF_BIND_ADDRESS=127.0.0.1"
        echo "CONECTAEDUCA_HTTP_PORT=18081"
        echo "CONECTAEDUCA_HTTPS_PORT=18444"
        echo "CONECTAEDUCA_APP_URL=https://conectaeduca.local:18444"
    end >> "$tmp"

    mv "$tmp" "$ENV_FILE"
    chmod 0600 "$ENV_FILE"
    echo "OK          runtime consolidado criado sem senha inline"
end

echo
echo "======================================================================"
echo " CONECTAEDUCA - SUBIR STACK LOCAL PERSISTENTE"
echo " MariaDB + PHP-FPM + Nginx + WAF/TLS + OpenBao/SMTP"
echo "======================================================================"

for cmd in docker openssl git grep ss getent
    if not type -q $cmd
        echo "FALHA       comando ausente: $cmd"
        exit 1
    end
end

docker info >/dev/null 2>&1
or begin
    echo "FALHA       sem acesso à API Docker"
    exit 1
end

if not docker ps --format '{{.Names}}' | grep -qx conectaeduca-openbao
    echo "FALHA       OpenBao não está em execução"
    exit 1
end

echo "OK          OpenBao está em execução"

set HOST_LOCAL (getent ahostsv4 conectaeduca.local 2>/dev/null | awk 'NR==1 {print $1; exit}')
if test "$HOST_LOCAL" != "127.0.0.1"
    echo "FALHA       conectaeduca.local deve resolver para 127.0.0.1 neste laboratório; atual=$HOST_LOCAL"
    echo "INFO        corrija /etc/hosts antes de subir o WAF local"
    exit 1
end
echo "OK          conectaeduca.local resolve para 127.0.0.1"

set STACK_GID (ensure_secret_group)
if test $status -ne 0 -o -z "$STACK_GID"
    echo "FALHA       grupo dedicado do stack não pôde ser preparado"
    exit 1
end
echo "OK          grupo $GROUP_NAME sem membros explícitos (gid=$STACK_GID)"

prepare_runtime
or exit 1

for file in \
    "$DB_ROOT_SECRET" \
    "$DB_APP_SECRET" \
    "$APP_PRIVATE" \
    "$APP_PUBLIC" \
    "$WAF_TLS_KEY" \
    "$WAF_TLS_CERT"
    secure_group_file "$file" "$STACK_GID"
    or exit 1
end

echo "OK          secrets persistentes: 0640 + grupo dedicado + other deny"

# A ponte SMTP já usa um grupo separado e atualiza o runtime SMTP.
fish scripts/bootstrap/preparar_smtp_secret_container.fish
or begin
    echo "FALHA       ponte SMTP não pôde ser preparada"
    exit 1
end

set DB_GATEWAY (docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null)
if test -z "$DB_GATEWAY"
    echo "FALHA       gateway da bridge Docker não pôde ser determinado"
    exit 1
end

echo "OK          MariaDB será publicado somente no gateway Docker: $DB_GATEWAY:13306"

write_env "$STACK_GID" "$DB_GATEWAY"
or exit 1

# Derruba somente estes dois projetos; nunca remove o volume MariaDB.
dmz down --remove-orphans >/dev/null 2>&1
db down --remove-orphans >/dev/null 2>&1

for port in 13306 18081 18444
    if ss -H -ltn "( sport = :$port )" 2>/dev/null | grep -q .
        echo "FALHA       porta TCP $port já está ocupada por outro processo"
        exit 1
    end
end
echo "OK          portas do stack estão livres"

echo
echo "=== 1. VALIDANDO COMPOSES ==="
db config >/dev/null
or begin
    echo "FALHA       Compose MariaDB inválido"
    exit 1
end

dmz config >/dev/null
or begin
    echo "FALHA       Compose DMZ inválido"
    exit 1
end
echo "OK          Compose DB e DMZ válidos"

echo
echo "=== 2. BUILD DMZ ==="
dmz build php nginx
or begin
    echo "FALHA       build PHP/Nginx reprovou"
    exit 1
end
echo "OK          imagens PHP/Nginx construídas"

echo
echo "=== 3. SUBINDO MARIADB ==="
db up -d
or begin
    echo "FALHA       MariaDB não iniciou"
    exit 1
end

set DB_ID (db ps -q mariadb)
if test -z "$DB_ID"
    echo "FALHA       container MariaDB não encontrado"
    exit 1
end

wait_healthy mariadb "$DB_ID" 180
or begin
    db logs --no-color --tail=120 mariadb
    exit 1
end

echo
echo "=== 4. SUBINDO DMZ ==="
dmz up -d
or begin
    echo "FALHA       DMZ não iniciou"
    exit 1
end

set PHP_ID (dmz ps -q php)
set NGINX_ID (dmz ps -q nginx)
set WAF_ID (dmz ps -q waf)

wait_healthy php-fpm "$PHP_ID" 120
or exit 1
wait_healthy nginx "$NGINX_ID" 120
or exit 1
wait_healthy waf "$WAF_ID" 180
or begin
    dmz logs --no-color --tail=120 waf
    exit 1
end

echo
echo "=== 5. FRONTEIRA DMZ -> BANCO ==="

set RESOLVED_HOST_GATEWAY (dmz exec -T php getent hosts host.docker.internal 2>/dev/null | awk 'NR==1{print $1}')
echo "INFO        host.docker.internal=$RESOLVED_HOST_GATEWAY"

if test "$RESOLVED_HOST_GATEWAY" != "$DB_GATEWAY"
    echo "FALHA       host-gateway diverge do endereço onde MariaDB foi publicado"
    exit 1
end

set PDO_RESULT (dmz exec -T php php -r '
require "/var/www/conectaeduca/vendor/autoload.php";
$pdo=\ConectaEduca\Config\Database::connect();
$r=$pdo->query("SELECT DATABASE() db, @@character_set_connection charset")->fetch(PDO::FETCH_ASSOC);
echo $r["db"],"|",$r["charset"];
' 2>&1)

if test "$PDO_RESULT" != "conectaeduca|utf8mb4"
    echo "FALHA       PDO não autenticou no MariaDB: $PDO_RESULT"
    exit 1
end
echo "OK          PHP autentica no MariaDB pelo endpoint de host"

echo
echo "=== 6. HTTPS / WAF / CHAVES ==="

set HTTPS_CODE (curl -ksS \
    --max-time 12 \
    --resolve conectaeduca.local:18444:127.0.0.1 \
    -o /dev/null \
    -w '%{http_code}' \
    https://conectaeduca.local:18444/login.php 2>/dev/null)

if test "$HTTPS_CODE" != 200
    echo "FALHA       /login.php via WAF retornou HTTP $HTTPS_CODE"
    exit 1
end
echo "OK          login HTTP 200 via WAF/TLS"

set KEY_CODE (curl -ksS \
    --max-time 12 \
    --resolve conectaeduca.local:18444:127.0.0.1 \
    -o /dev/null \
    -w '%{http_code}' \
    https://conectaeduca.local:18444/api/public_key.php 2>/dev/null)

if test "$KEY_CODE" != 200
    echo "FALHA       API de chave pública retornou HTTP $KEY_CODE"
    exit 1
end
echo "OK          aplicação consegue ler o par criptográfico montado"

set XSS_CODE (curl -ksS \
    --max-time 12 \
    --resolve conectaeduca.local:18444:127.0.0.1 \
    -G \
    --data-urlencode 'q=<script>alert(1)</script>' \
    -o /dev/null \
    -w '%{http_code}' \
    https://conectaeduca.local:18444/ 2>/dev/null)

if test "$XSS_CODE" != 403
    echo "FALHA       WAF não bloqueou vetor XSS sintético; HTTP=$XSS_CODE"
    exit 1
end
echo "OK          WAF PL2 bloqueia vetor XSS sintético"

echo
echo "=== 7. SMTP SEM ENVIAR MENSAGEM ==="

dmz run --rm --no-deps \
    -v "$ROOT/scripts/evidencias/diagnosticar_smtp_container.php:/tmp/diagnosticar_smtp_container.php:ro" \
    php php /tmp/diagnosticar_smtp_container.php
or begin
    echo "FALHA       autenticação SMTP do container reprovou"
    exit 1
end

echo
echo "=== 8. SUPERFÍCIE PUBLICADA ==="

# Valide bindings dos containers, não listeners globais do host.
# O openSUSE pode legitimamente ter seu próprio PHP-FPM em :9000.
set PHP_PUBLISH (docker port "$PHP_ID" 9000/tcp 2>/dev/null)
if test -n "$PHP_PUBLISH"
    echo "FALHA       container PHP publicou 9000 no host: $PHP_PUBLISH"
    exit 1
end
echo "OK          container PHP-FPM não publica 9000 no host"

set NGINX_PUBLISH (docker port "$NGINX_ID" 8080/tcp 2>/dev/null)
if test -n "$NGINX_PUBLISH"
    echo "FALHA       container Nginx publicou 8080 no host: $NGINX_PUBLISH"
    exit 1
end
echo "OK          container Nginx não publica 8080 no host"

set WAF_HTTP_PUBLISH (docker port "$WAF_ID" 8080/tcp 2>/dev/null)
set WAF_HTTPS_PUBLISH (docker port "$WAF_ID" 8443/tcp 2>/dev/null)

if test "$WAF_HTTP_PUBLISH" != "127.0.0.1:18081"
    echo "FALHA       binding HTTP do WAF inesperado: $WAF_HTTP_PUBLISH"
    exit 1
end

if test "$WAF_HTTPS_PUBLISH" != "127.0.0.1:18444"
    echo "FALHA       binding HTTPS do WAF inesperado: $WAF_HTTPS_PUBLISH"
    exit 1
end

echo "OK          somente o WAF publica HTTP/HTTPS no loopback esperado"
echo "OK          WAF HTTPS disponível em 127.0.0.1:18444"
echo "OK          MariaDB disponível somente em $DB_GATEWAY:13306"

echo
echo "======================================================================"
echo " STACK LOCAL: ONLINE"
echo "======================================================================"
echo
echo "Aplicação:"
echo "  https://conectaeduca.local:18444/login.php"
echo
echo "OpenBao:"
echo "  http://127.0.0.1:18200"
echo
echo "MariaDB (simulação inter-VM):"
echo "  $DB_GATEWAY:13306"
echo
echo "PHP-FPM e Nginx:"
echo "  não publicados no host"
echo
echo "O launcher NÃO removerá os containers nem o volume."
echo "Para parar sem apagar dados:"
echo "  fish scripts/bootstrap/parar_stack_local.fish"
