#!/usr/bin/env fish

# ==========================================================================
# CONECTAEDUCA - CHECKPOINT FERRET SCAN DLP
# ==========================================================================

set -g PASS_COUNT 0
set -g WARN_COUNT 0
set -g FAIL_COUNT 0

function ok
    set -g PASS_COUNT (math "$PASS_COUNT + 1")
    set -l msg (string join ' ' -- $argv)
    printf 'OK       %s\n' "$msg" | tee -a "$REPORT"
end

function warn
    set -g WARN_COUNT (math "$WARN_COUNT + 1")
    set -l msg (string join ' ' -- $argv)
    printf 'AVISO    %s\n' "$msg" | tee -a "$REPORT"
end

function fail
    set -g FAIL_COUNT (math "$FAIL_COUNT + 1")
    set -l msg (string join ' ' -- $argv)
    printf 'FALHA    %s\n' "$msg" | tee -a "$REPORT"
end

function line
    set -l msg (string join ' ' -- $argv)
    printf '%s\n' "$msg" | tee -a "$REPORT"
end

set -g ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    printf 'ERRO: execute dentro do repositório ConectaEduca.\n' >&2
    exit 1
end

cd "$ROOT"

set -g TIMESTAMP (date '+%Y%m%d-%H%M%S')
set -g REPORT "/tmp/conectaeduca-checkpoint-ferret-$TIMESTAMP.txt"
set -g COMPOSE deploy/interna/ferret/compose.yml
set -g RUNTIME deploy/interna/ferret/.runtime
set -g IMAGE 'public.ecr.aws/awslabs/ferret-scan:2.2.1@sha256:898951c5d81d249858ce400bf2c727f028ebe27e7c89e2a23448e483897f0f21'
set -g EXPECTED_DIGEST 'sha256:898951c5d81d249858ce400bf2c727f028ebe27e7c89e2a23448e483897f0f21'

if set -q FERRET_WEB_PORT
    set -g PORT "$FERRET_WEB_PORT"
else
    set -g PORT 18082
end

touch "$REPORT"

line "======================================================================"
line " CONECTAEDUCA - CHECKPOINT FERRET SCAN DLP"
line " Data: "(date --iso-8601=seconds)
line "======================================================================"
line ""

line "=== 1. ARQUIVOS / GIT ==="
for f in \
    deploy/interna/ferret/compose.yml \
    deploy/interna/ferret/config/ferret.yaml \
    deploy/interna/ferret/IMAGENS-VALIDADAS.md \
    deploy/interna/ferret/README.md
    if test -f "$f"
        ok "$f"
    else
        fail "arquivo ausente: $f"
    end
end

if git diff --check >/dev/null
    ok "git diff --check"
else
    fail "git diff --check"
end

if git check-ignore -q "$RUNTIME/prova-ignore" 2>/dev/null
    ok ".runtime do Ferret permanece fora do Git"
else
    fail ".runtime do Ferret não está coberto pelo .gitignore"
end

set TRACKED_RUNTIME (git ls-files | grep -E '^deploy/interna/ferret/\.runtime(/|$)')
if test (count $TRACKED_RUNTIME) -eq 0
    ok ".runtime do Ferret não é rastreado pelo Git"
else
    fail ".runtime do Ferret contém caminho(s) rastreado(s) pelo Git"
    for tracked_file in $TRACKED_RUNTIME
        line "            $tracked_file"
    end
end

line ""
line "=== 2. IMAGEM / PLATAFORMA ==="
if docker pull "$IMAGE" >/dev/null 2>&1
    ok "imagem exata por digest resolvível"
else
    fail "pull exato da imagem Ferret"
end

set IMG_ARCH (docker image inspect "$IMAGE" --format '{{.Architecture}}' 2>/dev/null)
set IMG_OS (docker image inspect "$IMAGE" --format '{{.Os}}' 2>/dev/null)
set IMG_USER (docker image inspect "$IMAGE" --format '{{.Config.User}}' 2>/dev/null)
set IMG_DIGEST (docker image inspect "$IMAGE" --format '{{index .RepoDigests 0}}' 2>/dev/null | string replace -r '^.*@' '')

if test "$IMG_ARCH" = amd64
    ok "arquitetura amd64"
else
    fail "arquitetura inesperada: $IMG_ARCH"
end

if test "$IMG_OS" = linux
    ok "sistema linux"
else
    fail "SO inesperado: $IMG_OS"
end

if test "$IMG_USER" = ferret
    ok "imagem executa como usuário não-root ferret"
else
    fail "usuário inesperado: $IMG_USER"
end

if test "$IMG_DIGEST" = "$EXPECTED_DIGEST"
    ok "digest esperado confirmado"
else
    fail "digest inesperado: $IMG_DIGEST"
end

line ""
line "=== 3. COMPOSE / HARDENING ==="
if docker compose -f "$COMPOSE" config >/dev/null 2>&1
    ok "Compose válido"
else
    fail "Compose inválido"
end

if fish scripts/bootstrap/preparar_ferret.fish >>"$REPORT" 2>&1
    ok "runtime preparado"
else
    fail "preparação do runtime"
end

for runtime_dir in \
    "$RUNTIME" \
    "$RUNTIME/state" \
    "$RUNTIME/inbox" \
    "$RUNTIME/reports"

    set RUNTIME_MODE (stat -c '%a' "$runtime_dir" 2>/dev/null)
    set RUNTIME_OWNER (stat -c '%u:%g' "$runtime_dir" 2>/dev/null)

    if test "$RUNTIME_MODE" = 700
        ok "$runtime_dir protegido com modo 0700"
    else
        fail "$runtime_dir possui modo inesperado: $RUNTIME_MODE"
    end

    if test "$RUNTIME_OWNER" = "1000:1000"
        ok "$runtime_dir pertence ao UID/GID do Ferret (1000:1000)"
    else
        fail "$runtime_dir possui proprietário inesperado: $RUNTIME_OWNER"
    end
end

if docker compose -f "$COMPOSE" up -d ferret >>"$REPORT" 2>&1
    ok "serviço Ferret iniciado"
else
    fail "subida do serviço Ferret"
end

set CID (docker compose -f "$COMPOSE" ps -q ferret 2>/dev/null)
if test -n "$CID"
    ok "container Ferret localizado"
else
    fail "container Ferret não localizado"
end

if test -n "$CID"
    set RUNNING (docker inspect "$CID" --format '{{.State.Running}}')
    set READONLY (docker inspect "$CID" --format '{{.HostConfig.ReadonlyRootfs}}')
    set PRIVILEGED (docker inspect "$CID" --format '{{.HostConfig.Privileged}}')
    set CAPDROP (docker inspect "$CID" --format '{{json .HostConfig.CapDrop}}')
    set SECURITYOPT (docker inspect "$CID" --format '{{json .HostConfig.SecurityOpt}}')
    set RESTART_POLICY (docker inspect "$CID" --format '{{.HostConfig.RestartPolicy.Name}}')
    set PIDS_LIMIT (docker inspect "$CID" --format '{{.HostConfig.PidsLimit}}')
    set CONTAINER_USER (docker inspect "$CID" --format '{{.Config.User}}')
    set PORTS (docker inspect "$CID" --format '{{json .NetworkSettings.Ports}}')
    set MOUNTS (docker inspect "$CID" --format '{{json .Mounts}}')

    if test "$RUNNING" = true
        ok "container running"
    else
        fail "container não está running"
    end

    if test "$READONLY" = true
        ok "root filesystem somente leitura"
    else
        fail "root filesystem não está read-only"
    end

    if test "$PRIVILEGED" = false
        ok "privileged desabilitado"
    else
        fail "container privilegiado"
    end

    if string match -q '*ALL*' "$CAPDROP"
        ok "capabilities removidas"
    else
        fail "cap_drop ALL ausente"
    end

    if string match -q '*no-new-privileges:true*' "$SECURITYOPT"
        ok "no-new-privileges ativo"
    else
        fail "no-new-privileges ausente"
    end

    if test "$RESTART_POLICY" = "unless-stopped"
        ok "restart policy unless-stopped ativa"
    else
        fail "restart policy inesperada: $RESTART_POLICY"
    end

    if test "$PIDS_LIMIT" = 128
        ok "pids_limit=128 aplicado"
    else
        fail "pids_limit inesperado: $PIDS_LIMIT"
    end

    if test "$CONTAINER_USER" = ferret
        ok "container efetivamente configurado com usuário ferret"
    else
        fail "usuário efetivo configurado no container é inesperado: $CONTAINER_USER"
    end

    if string match -q '*127.0.0.1*' "$PORTS"
        ok "Web UI publicada apenas em loopback"
    else
        fail "binding da Web UI não está restrito a loopback"
    end

    if string match -q '*/var/run/docker.sock*' "$MOUNTS"
        fail "Docker socket montado no Ferret"
    else
        ok "Docker socket não montado"
    end

    set MOUNT_MATRIX (docker inspect "$CID" --format '{{range .Mounts}}{{println .Destination .RW}}{{end}}' 2>/dev/null)

    if string match -q '*/etc/ferret/ferret.yaml false*' "$MOUNT_MATRIX"
        ok "configuração Ferret montada somente leitura"
    else
        fail "montagem RO da configuração Ferret não confirmada"
    end

    if string match -q '*/data/inbox false*' "$MOUNT_MATRIX"
        ok "inbox montado somente leitura no container"
    else
        fail "inbox não está somente leitura no container"
    end

    if string match -q '*/var/lib/ferret true*' "$MOUNT_MATRIX" \
        && string match -q '*/data/reports true*' "$MOUNT_MATRIX"
        ok "estado e reports possuem escrita persistente controlada"
    else
        fail "montagens persistentes de estado/reports não correspondem ao contrato"
    end
end

line ""
line "=== 4. WEB UI / CONFIGURAÇÃO ==="
set HTTP_OK 0
for tentativa in (seq 1 20)
    if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/" >/dev/null 2>&1
        set HTTP_OK 1
        break
    end
    sleep 1
end

if test "$HTTP_OK" -eq 1
    ok "Web UI responde em loopback"
else
    fail "Web UI não responde"
end

set CONFIG_TMP "/tmp/conectaeduca-ferret-config-info-$fish_pid"
set CONFIG_HTTP (curl -sS -o "$CONFIG_TMP" -w '%{http_code}' --max-time 3 "http://127.0.0.1:$PORT/config-info" 2>/dev/null)
if test "$CONFIG_HTTP" = 200
    ok "endpoint /config-info responde"
else
    warn "endpoint /config-info respondeu HTTP $CONFIG_HTTP"
end
rm -f "$CONFIG_TMP"

line ""
line "=== 5. VARREDURA SINTÉTICA / NÃO EXPOSIÇÃO DO MATCH ==="
set SYNTH_FILE "$RUNTIME/inbox/checkpoint-synthetic-$TIMESTAMP.txt"
set SYNTH_REPORT "$RUNTIME/reports/checkpoint-synthetic-$TIMESTAMP.json"
set SYNTH_TOKEN (python3 -c 'import secrets,string; a=string.ascii_letters+string.digits; print("ghp_"+"".join(secrets.choice(a) for _ in range(36)))')

printf 'synthetic_credential=%s\n' "$SYNTH_TOKEN" > "$SYNTH_FILE"
chmod 0600 "$SYNTH_FILE"

set SYNTH_BASENAME (basename "$SYNTH_FILE")
set REPORT_BASENAME (basename "$SYNTH_REPORT")

docker compose -f "$COMPOSE" run --rm --no-deps ferret \
    --file "/data/inbox/$SYNTH_BASENAME" \
    --checks SECRETS \
    --confidence all \
    --format json \
    --no-color \
    --output "/data/reports/$REPORT_BASENAME" \
    --suppression-file /var/lib/ferret/suppressions.yaml >>"$REPORT" 2>&1
set SCAN_RC $status

if test -f "$SYNTH_REPORT"
    ok "relatório sintético produzido (rc=$SCAN_RC)"

    if grep -Fq "$SYNTH_TOKEN" "$SYNTH_REPORT"
        fail "relatório expôs o valor sintético; show_match deve permanecer false"
    else
        ok "relatório não contém o valor sensível sintético"
    end

    if grep -Eqi 'secret|credential|finding|ghp' "$SYNTH_REPORT"
        ok "relatório contém evidência de processamento/detecção"
    else
        warn "relatório foi produzido, mas a detecção sintética não ficou evidente"
    end
else
    fail "relatório sintético não foi produzido (rc=$SCAN_RC)"
end

rm -f "$SYNTH_FILE" "$SYNTH_REPORT"
set -e SYNTH_TOKEN

line ""
line "=== 6. RESTART / PERSISTÊNCIA OPERACIONAL ==="
set SENTINEL "$RUNTIME/state/checkpoint-persistencia-$TIMESTAMP"
printf 'ferret-persistencia\n' > "$SENTINEL"
chmod 0600 "$SENTINEL"

if test -n "$CID"
    if docker restart "$CID" >/dev/null 2>&1
        ok "container reiniciado"
    else
        fail "restart do container"
    end
end

set HTTP_RESTART 0
for tentativa in (seq 1 20)
    if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/" >/dev/null 2>&1
        set HTTP_RESTART 1
        break
    end
    sleep 1
end

if test "$HTTP_RESTART" -eq 1
    ok "Web UI voltou após restart"
else
    fail "Web UI não voltou após restart"
end

if test -f "$SENTINEL"
    ok "runtime persistiu após restart"
else
    fail "runtime não persistiu"
end
rm -f "$SENTINEL"

line ""
line "======================================================================"
line " RESULTADO"
line "======================================================================"
line "Aprovações:   $PASS_COUNT"
line "Advertências: $WARN_COUNT"
line "Falhas:       $FAIL_COUNT"

if test "$FAIL_COUNT" -eq 0
    line "CHECKPOINT FERRET DLP: APROVADO."
else
    line "CHECKPOINT FERRET DLP: REPROVADO."
end

line "Relatório: $REPORT"

if test "$FAIL_COUNT" -gt 0
    exit 1
end

exit 0
