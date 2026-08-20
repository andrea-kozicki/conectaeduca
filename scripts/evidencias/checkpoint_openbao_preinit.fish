#!/usr/bin/env fish

set ROOT (git rev-parse --show-toplevel 2>/dev/null)

if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositorio ConectaEduca." >&2
    exit 1
end

cd "$ROOT"

set COMPOSE "deploy/interna/openbao/compose.yml"
set CONFIG "deploy/interna/openbao/config/openbao.hcl"
set IMAGENS "deploy/interna/openbao/IMAGENS-VALIDADAS.md"
set BOOTSTRAP "scripts/bootstrap/preparar_openbao.fish"
set CONTAINER "conectaeduca-openbao"

set -g OK 0
set -g WARN 0
set -g FAIL 0

function ok
    printf "OK          %s\n" "$argv"
    set -g OK (math $OK + 1)
end

function warn
    printf "AVISO       %s\n" "$argv"
    set -g WARN (math $WARN + 1)
end

function fail
    printf "FALHA       %s\n" "$argv"
    set -g FAIL (math $FAIL + 1)
end

function info
    printf "INFO        %s\n" "$argv"
end

echo "======================================================================"
echo " CONECTAEDUCA - CHECKPOINT OPENBAO PRE-INICIALIZACAO"
echo " Estado esperado: infraestrutura pronta, sem segredos provisionados"
echo " Plataforma alvo: linux/amd64"
echo " Data: "(date --iso-8601=seconds)
echo "======================================================================"

echo
echo "=== 1. GIT / ARQUIVOS ==="

if git diff --check
    ok "git diff --check"
else
    fail "git diff --check encontrou problemas"
end

for f in "$COMPOSE" "$CONFIG" "$IMAGENS" "$BOOTSTRAP"
    if test -f "$f"
        ok "arquivo presente: $f"
    else
        fail "arquivo ausente: $f"
    end
end

if git check-ignore -q deploy/interna/openbao/.runtime/__checkpoint_probe__
    ok ".runtime do OpenBao esta coberto pelo .gitignore"
else
    fail ".runtime do OpenBao NAO esta coberto pelo .gitignore"
end

if test -d deploy/interna/openbao/.runtime
    set RUNTIME_MODE (stat -c "%a" deploy/interna/openbao/.runtime 2>/dev/null)

    if test "$RUNTIME_MODE" = "700"
        ok ".runtime local protegido com modo 700"
    else
        fail ".runtime local possui modo $RUNTIME_MODE; esperado 700"
    end
else
    info ".runtime ainda nao existe neste host"
end

set TRACKED_RUNTIME \
    (git ls-files "deploy/interna/openbao/.runtime/**")

if test (count $TRACKED_RUNTIME) -eq 0
    ok "nenhum arquivo de runtime OpenBao rastreado pelo Git"
else
    fail "ha arquivo de runtime OpenBao rastreado pelo Git"
end


echo
echo "=== 2. HIGIENE DE SEGREDOS ==="

set SCAN_FILES "$COMPOSE" "$CONFIG" "$IMAGENS" "$BOOTSTRAP"

set SECRET_SCAN \
    (grep -Ein \
        "Initial Root Token|Unseal Key [0-9]+:|root_token[[:space:]]*=|secret_id[[:space:]]*=" \
        $SCAN_FILES \
        2>/dev/null)

if test (count $SECRET_SCAN) -eq 0
    ok "nenhum root token, unseal key ou SecretID obvio nos arquivos de implantacao"
else
    fail "possivel material sensivel localizado"
    printf "%s\n" $SECRET_SCAN
end


echo
echo "=== 3. COMPOSE / PORTABILIDADE ==="

if docker compose -f "$COMPOSE" config >/dev/null 2>&1
    ok "Docker Compose sintaticamente valido"
else
    fail "Docker Compose invalido"
end

if grep -Eq "^[[:space:]]*privileged:[[:space:]]*true" "$COMPOSE"
    fail "Compose usa privileged: true"
else
    ok "Compose nao usa privileged: true"
end

if grep -Eq "network_mode:[[:space:]]*host" "$COMPOSE"
    fail "Compose usa network_mode: host"
else
    ok "Compose nao usa network_mode: host"
end

if grep -q "/var/run/docker.sock" "$COMPOSE"
    fail "Compose monta Docker socket"
else
    ok "Docker socket nao e montado"
end

if grep -Fq "127.0.0.1:18200:8200" "$COMPOSE"
    ok "API OpenBao publicada apenas em loopback no laboratorio"
else
    fail "binding esperado 127.0.0.1:18200:8200 nao encontrado"
end

if grep -Eq "[0-9.]+:8201:8201" "$COMPOSE"
    fail "porta 8201 esta publicada no host"
else
    ok "porta de cluster 8201 nao e publicada no host"
end

if grep -Fq "openbao/openbao:2.6.1@sha256:5b2486ab0fb90bbc788cc345b0a08616dfb375873ee8be5df3a2fd4d378a67e0" "$COMPOSE"
    ok "imagem OpenBao fixada por versao e digest"
else
    fail "imagem OpenBao nao esta fixada pelo digest esperado"
end

if grep -Fq "name: conectaeduca-openbao-data" "$COMPOSE"
    ok "volume Raft possui nome estavel"
else
    fail "volume Raft nomeado nao localizado no Compose"
end

if docker volume inspect conectaeduca-openbao-data >/dev/null 2>&1
    ok "volume Raft existe no host"
else
    fail "volume Raft externo esta ausente"
end

set EXTERNAL_COUNT (grep -c "external: true" "$COMPOSE")

if test "$EXTERNAL_COUNT" = "1"
    ok "somente o volume Raft e externo ao Compose"
else
    fail "esperado 1 volume external:true; encontrados $EXTERNAL_COUNT"
end

if grep -Fq "/openbao/file:size=16m,mode=700,uid=100,gid=1000" "$COMPOSE"
    ok "/openbao/file declarado como tmpfs"
else
    fail "/openbao/file tmpfs nao localizado no Compose"
end

if grep -Fq "/openbao/logs:size=32m,mode=750,uid=100,gid=1000" "$COMPOSE"
    ok "/openbao/logs declarado como tmpfs"
else
    fail "/openbao/logs tmpfs nao localizado no Compose"
end


echo
echo "=== 4. BOOTSTRAP ==="

if fish -n "$BOOTSTRAP"
    ok "bootstrap passa em fish -n"
else
    fail "bootstrap possui erro de sintaxe Fish"
end

if grep -q "operator init" "$BOOTSTRAP"
    fail "bootstrap contem operator init"
else
    ok "bootstrap nao inicializa o cofre"
end

if grep -q "operator unseal" "$BOOTSTRAP"
    fail "bootstrap contem operator unseal"
else
    ok "bootstrap nao executa unseal"
end


echo
echo "=== 5. CONTAINER ==="

if not docker inspect "$CONTAINER" >/dev/null 2>&1
    fail "container OpenBao nao existe"
else
    set STATE \
        (docker inspect "$CONTAINER" --format "{{.State.Status}}")

    if test "$STATE" = "running"
        ok "container OpenBao esta em execucao"
    else
        fail "container OpenBao esta em estado $STATE"
    end

    set ARCH \
        (docker image inspect openbao/openbao:2.6.1 \
            --format "{{.Architecture}}" \
            2>/dev/null)

    if test "$ARCH" = "amd64"
        ok "imagem local usa arquitetura amd64"
    else
        fail "arquitetura inesperada: $ARCH"
    end

    set UID_OPENBAO \
        (docker exec "$CONTAINER" id -u 2>/dev/null)

    if test "$UID_OPENBAO" = "100"
        ok "OpenBao executa como usuario nao-root uid=100"
    else if test "$UID_OPENBAO" = "0"
        fail "OpenBao esta executando como root"
    else
        warn "UID inesperado no container: $UID_OPENBAO"
    end

    set SECURITY_OPT \
        (docker inspect "$CONTAINER" \
            --format "{{json .HostConfig.SecurityOpt}}")

    if string match -q "*no-new-privileges*" "$SECURITY_OPT"
        ok "no-new-privileges aplicado"
    else
        fail "no-new-privileges nao identificado"
    end

    set PORT8200 \
        (docker port "$CONTAINER" 8200/tcp 2>/dev/null)

    if test "$PORT8200" = "127.0.0.1:18200"
        ok "binding efetivo confirmado em 127.0.0.1:18200"
    else
        fail "binding inesperado para 8200/tcp: $PORT8200"
    end

    set PORT8201 \
        (docker port "$CONTAINER" 8201/tcp 2>/dev/null)

    if test -z "$PORT8201"
        ok "8201/tcp nao esta publicada"
    else
        fail "8201/tcp esta publicada: $PORT8201"
    end

    set MEMORY \
        (docker inspect "$CONTAINER" \
            --format "{{.HostConfig.Memory}}")

    set MEMORY_SWAP \
        (docker inspect "$CONTAINER" \
            --format "{{.HostConfig.MemorySwap}}")

    info "Memory=$MEMORY MemorySwap=$MEMORY_SWAP"

    if test "$MEMORY" = "1073741824"
        ok "limite efetivo de memoria = 1 GiB"
    else
        fail "limite de memoria inesperado: $MEMORY"
    end

    if test "$MEMORY" = "$MEMORY_SWAP"
        ok "MemorySwap igual a Memory"
    else
        fail "MemorySwap difere de Memory"
    end
end


echo
echo "=== 6. RAFT / MOUNTS ==="

set DATA_MOUNT \
    (docker inspect "$CONTAINER" \
        --format "{{range .Mounts}}{{if eq .Destination \"/openbao/data\"}}{{printf \"%s:%s\" .Name .Destination}}{{end}}{{end}}" \
        2>/dev/null)

if test "$DATA_MOUNT" = "conectaeduca-openbao-data:/openbao/data"
    ok "mount Raft nomeado correto"
else
    fail "mount Raft inesperado: $DATA_MOUNT"
end

set DATA_STAT \
    (docker exec "$CONTAINER" \
        stat -c "%u:%g:%a" /openbao/data \
        2>/dev/null)

if test "$DATA_STAT" = "100:1000:700"
    ok "/openbao/data pertence a openbao e possui modo 700"
else
    fail "/openbao/data possui estado inesperado: $DATA_STAT"
end


echo
echo "=== 7. TMPFS EFEMEROS ==="

set FILE_TMPFS \
    (docker inspect "$CONTAINER" \
        --format "{{index .HostConfig.Tmpfs \"/openbao/file\"}}" \
        2>/dev/null)

set LOGS_TMPFS \
    (docker inspect "$CONTAINER" \
        --format "{{index .HostConfig.Tmpfs \"/openbao/logs\"}}" \
        2>/dev/null)

info "/openbao/file tmpfs=$FILE_TMPFS"
info "/openbao/logs tmpfs=$LOGS_TMPFS"

if test -n "$FILE_TMPFS"
    ok "/openbao/file usa tmpfs efemero"
else
    fail "/openbao/file nao identificado como tmpfs"
end

if test -n "$LOGS_TMPFS"
    ok "/openbao/logs usa tmpfs efemero"
else
    fail "/openbao/logs nao identificado como tmpfs"
end

set FILE_STAT \
    (docker exec "$CONTAINER" \
        stat -c "%u:%g:%a" /openbao/file \
        2>/dev/null)

set LOGS_STAT \
    (docker exec "$CONTAINER" \
        stat -c "%u:%g:%a" /openbao/logs \
        2>/dev/null)

if test "$FILE_STAT" = "100:1000:700"
    ok "/openbao/file possui owner e modo esperados"
else
    fail "/openbao/file possui estado inesperado: $FILE_STAT"
end

if test "$LOGS_STAT" = "100:1000:750"
    ok "/openbao/logs possui owner e modo esperados"
else
    fail "/openbao/logs possui estado inesperado: $LOGS_STAT"
end


echo
echo "=== 8. ESTADO OPENBAO ==="

set BAO_OUTPUT \
    (docker exec "$CONTAINER" \
        bao status \
        -address=http://127.0.0.1:8200 \
        2>&1)

set BAO_RC $status

printf "%s\n" $BAO_OUTPUT

if test "$BAO_RC" = "2"
    ok "bao status retornou 2, compativel com sealed"
else
    fail "bao status retornou codigo inesperado: $BAO_RC"
end

if printf "%s\n" $BAO_OUTPUT | grep -Eq "^Initialized[[:space:]]+false\$"
    ok "OpenBao ainda NAO foi inicializado"
else
    fail "OpenBao nao esta no estado pre-init esperado"
end

if printf "%s\n" $BAO_OUTPUT | grep -Eq "^Sealed[[:space:]]+true\$"
    ok "OpenBao permanece sealed"
else
    fail "OpenBao nao esta sealed"
end

if printf "%s\n" $BAO_OUTPUT | grep -Eq "^Storage Type[[:space:]]+raft\$"
    ok "backend confirmado como Raft"
else
    fail "backend Raft nao confirmado"
end

docker exec "$CONTAINER" \
    bao operator init \
    -status \
    -address=http://127.0.0.1:8200 \
    >/dev/null 2>&1

set INIT_RC $status

if test "$INIT_RC" = "2"
    ok "operator init -status confirma cofre nao inicializado"
else if test "$INIT_RC" = "0"
    fail "cofre ja foi inicializado"
else
    fail "status de inicializacao indeterminado: rc=$INIT_RC"
end


echo
echo "=== 9. RESIDUOS ==="

set ANON_VOLUMES \
    (docker inspect "$CONTAINER" \
        --format "{{range .Mounts}}{{if eq .Type \"volume\"}}{{println .Name}}{{end}}{{end}}" \
        2>/dev/null \
        | string trim \
        | string match -rv "^conectaeduca-openbao-data\$" \
        | string match -rv "^\$")

if test (count $ANON_VOLUMES) -eq 0
    ok "container nao utiliza volumes anonimos"
else
    fail "container utiliza volumes nao previstos:"
    printf "%s\n" $ANON_VOLUMES
end


echo "======================================================================"
echo " RESULTADO"
echo "======================================================================"

printf "Aprovacoes:    %d\n" $OK
printf "Advertencias:  %d\n" $WARN
printf "Falhas:        %d\n" $FAIL

echo

if test $FAIL -gt 0
    echo "CHECKPOINT OPENBAO PRE-INICIALIZACAO: REPROVADO."
    exit 1
end

if test $WARN -gt 0
    echo "CHECKPOINT OPENBAO PRE-INICIALIZACAO: APROVADO COM ADVERTENCIAS."
    exit 0
end

echo "CHECKPOINT OPENBAO PRE-INICIALIZACAO: APROVADO."
echo "Infraestrutura pronta para implantacao na VM interna."
echo "Nenhum init, unseal ou segredo foi provisionado."

exit 0
