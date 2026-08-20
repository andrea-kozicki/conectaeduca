#!/usr/bin/env fish

set -g APROVACOES 0
set -g ADVERTENCIAS 0
set -g FALHAS 0

function ok
    set -g APROVACOES (math $APROVACOES + 1)
    printf 'OK          %s\n' "$argv"
end

function info
    printf 'INFO        %s\n' "$argv"
end

function warn
    set -g ADVERTENCIAS (math $ADVERTENCIAS + 1)
    printf 'ADVERTENCIA %s\n' "$argv"
end

function fail
    set -g FALHAS (math $FALHAS + 1)
    printf 'FALHA       %s\n' "$argv"
end

printf '%s\n' '======================================================================'
printf '%s\n' ' CONECTAEDUCA - CHECKPOINT COMPOSER / SUPPLY CHAIN'
printf '%s\n' ' Dependencias, plataforma PHP, advisories, licencas e runtime'
printf '%s\n' '======================================================================'

for cmd in php composer git grep
    if type -q $cmd
        ok "comando disponível: $cmd"
    else
        fail "comando ausente: $cmd"
    end
end

if test $FALHAS -gt 0
    exit 1
end

composer validate --strict >/tmp/conectaeduca-composer-validate.txt 2>&1
if test $status -eq 0
    ok 'composer.json/composer.lock válidos e sincronizados'
else
    cat /tmp/conectaeduca-composer-validate.txt
    fail 'composer validate --strict'
end

php -r '
$d=json_decode(file_get_contents("composer.json"), true, flags: JSON_THROW_ON_ERROR);
$required=[
 "php"=>"^8.5",
 "ext-filter"=>"*",
 "ext-hash"=>"*",
 "ext-json"=>"*",
 "ext-mbstring"=>"*",
 "ext-openssl"=>"*",
 "ext-pdo"=>"*",
 "ext-pdo_mysql"=>"*",
 "ext-session"=>"*",
 "bacon/bacon-qr-code"=>"^3.1.1",
 "phpmailer/phpmailer"=>"^7.1",
 "phpseclib/phpseclib"=>"^3.0",
 "pragmarx/google2fa"=>"^9.1",
 "vlucas/phpdotenv"=>"^5.6.4",
];
foreach ($required as $k=>$v) {
 if (($d["require"][$k] ?? null) !== $v) {
  fwrite(STDERR, "$k esperado=$v atual=" . ($d["require"][$k] ?? "<ausente>") . PHP_EOL);
  exit(1);
 }
}
if (($d["require-dev"]["phpunit/phpunit"] ?? null) !== "^13.3") exit(2);
if (($d["config"]["policy"]["advisories"]["block"] ?? null) !== true) exit(3);
if (($d["config"]["policy"]["abandoned"]["block"] ?? null) !== true) exit(4);
' >/tmp/conectaeduca-composer-contract.txt 2>&1
if test $status -eq 0
    ok 'composer.json declara PHP 8.5, extensões da aplicação e política de dependências'
else
    cat /tmp/conectaeduca-composer-contract.txt
    fail 'contrato Composer do ConectaEduca incompleto'
end

composer check-platform-reqs >/tmp/conectaeduca-platform-all.txt 2>&1
if test $status -eq 0
    ok 'platform requirements completos atendidos'
else
    cat /tmp/conectaeduca-platform-all.txt
    fail 'platform requirements completos não atendidos'
end

composer check-platform-reqs --no-dev >/tmp/conectaeduca-platform-prod.txt 2>&1
if test $status -eq 0
    ok 'platform requirements de produção atendidos'
else
    cat /tmp/conectaeduca-platform-prod.txt
    fail 'platform requirements de produção não atendidos'
end

set AUDIT_FILE /tmp/conectaeduca-composer-audit-(date +%Y%m%d-%H%M%S).json
composer audit --locked --format=json >$AUDIT_FILE 2>/tmp/conectaeduca-composer-audit.err
set AUDIT_RC $status
if test $AUDIT_RC -eq 0
    ok 'composer audit não encontrou advisories, malware ou pacotes abandonados'
else
    cat /tmp/conectaeduca-composer-audit.err
    cat $AUDIT_FILE
    fail 'composer audit encontrou problema na cadeia de dependências'
end

php -r '
$d=json_decode(file_get_contents($argv[1]), true, flags: JSON_THROW_ON_ERROR);
if (!empty($d["advisories"] ?? [])) exit(1);
if (!empty($d["abandoned"] ?? [])) exit(2);
if (!empty($d["malware"] ?? [])) exit(3);
' $AUDIT_FILE
if test $status -eq 0
    ok 'JSON do audit confirma zero advisories/abandonados/malware'
else
    fail 'JSON do composer audit contém ocorrência não aceita'
end

php -r '
$d=json_decode(file_get_contents("composer.lock"), true, flags: JSON_THROW_ON_ERROR);
$all=array_merge($d["packages"] ?? [], $d["packages-dev"] ?? []);
$map=[]; foreach ($all as $p) $map[$p["name"]]=ltrim($p["version"], "v");
$checks=[
 "bacon/bacon-qr-code"=>["3.1.1","4.0.0"],
 "phpmailer/phpmailer"=>["7.1.0","8.0.0"],
 "phpseclib/phpseclib"=>["3.0.0","4.0.0"],
 "pragmarx/google2fa"=>["9.1.0","10.0.0"],
 "vlucas/phpdotenv"=>["5.6.4","6.0.0"],
 "phpunit/phpunit"=>["13.3.0","14.0.0"],
];
foreach ($checks as $name=>[$min,$max]) {
 if (!isset($map[$name])) { fwrite(STDERR,"ausente: $name\n"); exit(1); }
 if (version_compare($map[$name],$min,"<") || version_compare($map[$name],$max,">=")) {
   fwrite(STDERR,"versão fora do perfil: $name={$map[$name]}\n"); exit(2);
 }
}
' >/tmp/conectaeduca-composer-versions.txt 2>&1
if test $status -eq 0
    ok 'dependências diretas estão no perfil de versões aprovado'
else
    cat /tmp/conectaeduca-composer-versions.txt
    fail 'versões diretas fora do perfil aprovado'
end

composer install --dry-run --no-dev --no-interaction --no-scripts >/tmp/conectaeduca-composer-prod-dryrun.txt 2>&1
if test $status -eq 0
    ok 'lock permite instalação de produção sem dependências de desenvolvimento'
else
    cat /tmp/conectaeduca-composer-prod-dryrun.txt
    fail 'composer install --no-dev --dry-run reprovou'
end

if test -f deploy/dmz/php/Dockerfile
    if grep -Eq -- 'composer install.*|--no-dev' deploy/dmz/php/Dockerfile
        if grep -q -- '--no-dev' deploy/dmz/php/Dockerfile
            ok 'Dockerfile PHP mantém Composer --no-dev na imagem de produção'
        else
            fail 'Dockerfile PHP não evidencia --no-dev'
        end
    else
        fail 'Dockerfile PHP não contém instalação Composer reconhecível'
    end
else
    warn 'Dockerfile PHP não disponível para verificar separação dev/prod'
end

composer licenses >/tmp/conectaeduca-composer-licenses.txt 2>&1
if test $status -eq 0
    ok 'inventário de licenças Composer gerado'
    if grep -q 'LGPL-2.1-only' /tmp/conectaeduca-composer-licenses.txt
        info 'PHPMailer permanece LGPL-2.1-only; manter avisos/licença da dependência na distribuição'
    end
else
    fail 'composer licenses reprovou'
end

set TEST_FILE /tmp/conectaeduca-phpunit-eall-(date +%Y%m%d-%H%M%S).txt
env APP_ENV=test php -d error_reporting=E_ALL vendor/bin/phpunit >$TEST_FILE 2>&1
set TEST_RC $status
if test $TEST_RC -eq 0
    ok 'PHPUnit aprovado com E_ALL'
else
    cat $TEST_FILE
    fail 'PHPUnit reprovou com E_ALL'
end

if grep -Eqi 'deprecated|warning|fatal|PHP_ERROR' $TEST_FILE
    grep -Ein 'deprecated|warning|fatal|PHP_ERROR' $TEST_FILE
    fail 'runtime de testes contém warning/deprecation/fatal'
else
    ok 'runtime de testes sem warnings/deprecations'
end

git diff --check >/tmp/conectaeduca-composer-gitdiff.txt 2>&1
if test $status -eq 0
    ok 'git diff --check'
else
    cat /tmp/conectaeduca-composer-gitdiff.txt
    fail 'git diff --check'
end

printf '\n%s\n' '======================================================================'
printf '%s\n' ' RESULTADO'
printf '%s\n' '======================================================================'
printf 'Aprovacoes:   %d\n' $APROVACOES
printf 'Advertencias: %d\n' $ADVERTENCIAS
printf 'Falhas:       %d\n' $FALHAS
printf 'Audit JSON:   %s\n' $AUDIT_FILE
printf 'PHPUnit EALL: %s\n' $TEST_FILE

if test $FALHAS -gt 0
    printf '%s\n' 'CHECKPOINT COMPOSER / SUPPLY CHAIN: REPROVADO.'
    exit 1
end

if test $ADVERTENCIAS -gt 0
    printf '%s\n' 'CHECKPOINT COMPOSER / SUPPLY CHAIN: APROVADO COM ADVERTENCIAS.'
else
    printf '%s\n' 'CHECKPOINT COMPOSER / SUPPLY CHAIN: APROVADO.'
end
