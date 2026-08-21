#!/usr/bin/env fish

# ============================================================================
# CONECTAEDUCA - CHECKPOINT GERAL DA CONTEINERIZAÇÃO
#
# Baseline atual:
#   - DMZ: PHP-FPM + Nginx + ModSecurity/OWASP CRS
#   - Rede interna: MariaDB
#   - Segurança/SIEM: Wazuh Manager + Indexer + Dashboard
#   - Cofre de segredos: OpenBao operacional (inicializado e unsealed)
#   - Recuperação de senha + SMTP real via secret materializado
#   - Stack local persistente + WAF/TLS PL2 e tuning do envelope criptográfico
#   - DLP: Ferret Scan operacional, persistente e endurecido
#   - Pipeline DLP: relatório bruto -> sanitização allowlist -> JSONL minimizado
#   - Integração DLP/SIEM: regras Ferret validadas no Wazuh Manager
#   - Handoff parcial anterior preservado
#
# Próximos blocos ainda NÃO obrigatórios neste baseline:
#   - Wazuh Agent nativo / FIM / YARA na VM
#   - Bacula
#   - Twingate Connector
#
# Modos:
#   --rapido            Diagnóstico estático/não destrutivo (padrão)
#   --completo          Executa também checkpoints dinâmicos existentes
#   --handoff-profundo  Extrai os pacotes de handoff e valida hashes internos
#   --estrito           Advertências também tornam o resultado não limpo
#   --ajuda             Exibe ajuda
#
# Exit codes:
#   0 = aprovado
#   1 = uma ou mais falhas
#   2 = somente advertências, quando usado --estrito
#  64 = uso inválido
# ============================================================================

set -g SCRIPT_VERSION "1.4-dlp-integrado"

set -g MODE "rapido"
set -g STRICT 0
set -g DEEP_HANDOFF 0

set -g PASS_COUNT 0
set -g WARN_COUNT 0
set -g FAIL_COUNT 0
set -g INFO_COUNT 0

# ----------------------------------------------------------------------------
# Argumentos
# ----------------------------------------------------------------------------

for arg in $argv
    switch "$arg"
        case --rapido
            set -g MODE "rapido"

        case --completo
            set -g MODE "completo"

        case --handoff-profundo
            set -g DEEP_HANDOFF 1

        case --estrito
            set -g STRICT 1

        case --ajuda -h
            printf '%s\n' \
                "Uso:" \
                "  checkpoint_containerizacao_geral.fish [opções]" \
                "" \
                "Opções:" \
                "  --rapido            checks estáticos; não sobe stacks (padrão)" \
                "  --completo          executa checkpoints dinâmicos aprovados" \
                "  --handoff-profundo  extrai os handoffs e valida hashes internos" \
                "  --estrito           advertências resultam em exit code 2" \
                "  --ajuda             esta ajuda" \
                "" \
                "Exemplos:" \
                "  fish scripts/evidencias/checkpoint_containerizacao_geral.fish" \
                "  fish scripts/evidencias/checkpoint_containerizacao_geral.fish --completo" \
                "  fish scripts/evidencias/checkpoint_containerizacao_geral.fish --completo --handoff-profundo"
            exit 0

        case '*'
            printf 'ERRO: opção desconhecida: %s\n' "$arg" >&2
            exit 64
    end
end

# ----------------------------------------------------------------------------
# Descoberta do repositório
# ----------------------------------------------------------------------------

if not type -q git
    printf 'ERRO: git não encontrado.\n' >&2
    exit 1
end

set -g ROOT (git rev-parse --show-toplevel 2>/dev/null)

if test $status -ne 0 -o -z "$ROOT"
    printf 'ERRO: execute este script dentro do repositório ConectaEduca.\n' >&2
    exit 1
end

cd "$ROOT"

set -g TIMESTAMP (date '+%Y%m%d-%H%M%S')
set -g REPORT "/tmp/conectaeduca-checkpoint-geral-$TIMESTAMP.txt"

touch "$REPORT"

# ----------------------------------------------------------------------------
# Funções de relatório
# ----------------------------------------------------------------------------

function _message
    string join ' ' -- $argv
end

function line
    set -l msg (_message $argv)
    printf '%s\n' "$msg" | tee -a "$REPORT"
end

function blank
    printf '\n' | tee -a "$REPORT"
end

function section
    blank
    set -l title (_message $argv)
    printf '=== %s ===\n' "$title" | tee -a "$REPORT"
end

function ok
    set -g PASS_COUNT (math "$PASS_COUNT + 1")
    set -l msg (_message $argv)
    printf 'OK          %s\n' "$msg" | tee -a "$REPORT"
end

function warn
    set -g WARN_COUNT (math "$WARN_COUNT + 1")
    set -l msg (_message $argv)
    printf 'ADVERTÊNCIA %s\n' "$msg" | tee -a "$REPORT"
end

function fail
    set -g FAIL_COUNT (math "$FAIL_COUNT + 1")
    set -l msg (_message $argv)
    printf 'FALHA       %s\n' "$msg" | tee -a "$REPORT"
end

function info
    set -g INFO_COUNT (math "$INFO_COUNT + 1")
    set -l msg (_message $argv)
    printf 'INFO        %s\n' "$msg" | tee -a "$REPORT"
end

function note_lines
    for item in $argv
        printf '            %s\n' "$item" | tee -a "$REPORT"
    end
end

function require_command
    set -l cmd "$argv[1]"

    if type -q "$cmd"
        ok "comando disponível: $cmd"
        return 0
    end

    fail "comando obrigatório ausente: $cmd"
    return 1
end

function require_file
    set -l rel "$argv[1]"

    if test -f "$ROOT/$rel"
        ok "$rel"
        return 0
    end

    fail "arquivo obrigatório ausente: $rel"
    return 1
end

function check_port_free
    set -l port "$argv[1]"

    python3 -c '
import socket
import sys

port = int(sys.argv[1])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

try:
    s.bind(("127.0.0.1", port))
except OSError:
    sys.exit(1)
finally:
    s.close()

sys.exit(0)
' "$port" >/dev/null 2>&1

    if test $status -eq 0
        ok "porta sintética TCP $port está livre"
    else
        warn "porta sintética TCP $port está ocupada"
    end
end

function run_subcheckpoint
    set -l label "$argv[1]"
    set -l script "$argv[2]"

    if not test -f "$script"
        fail "$label: script ausente ($script)"
        return 1
    end

    set -l temp_output (mktemp "/tmp/conectaeduca-subcheckpoint.XXXXXX")

    line "----- INÍCIO SUBCHECKPOINT: $label -----"

    switch "$script"
        case '*.fish'
            fish "$script" >"$temp_output" 2>&1
        case '*'
            bash "$script" >"$temp_output" 2>&1
    end

    set -l rc $status

    cat "$temp_output" >>"$REPORT"

    line "----- FIM SUBCHECKPOINT: $label / rc=$rc -----"

    if test $rc -eq 0
        ok "$label aprovado"
    else
        fail "$label reprovado (exit code $rc)"
        line "Últimas linhas do subcheckpoint:"
        tail -n 15 "$temp_output" | tee -a "$REPORT"
    end

    rm -f "$temp_output"

    return $rc
end

# ----------------------------------------------------------------------------
# Cabeçalho
# ----------------------------------------------------------------------------

line "======================================================================"
line " CONECTAEDUCA - CHECKPOINT GERAL DA CONTEINERIZAÇÃO"
line " Versão do checkpoint: $SCRIPT_VERSION"
line " Baseline: DMZ + MariaDB + Wazuh + OpenBao + SMTP/recuperação + WAF/stack local + Ferret + pipeline DLP + regras Wazuh"
line " Modo: $MODE"
line " Handoff profundo: $DEEP_HANDOFF"
line " Plataforma alvo: linux/amd64"
line " Data: "(date --iso-8601=seconds)
line "======================================================================"

info "Wazuh Agent nativo/FIM/YARA, Bacula e Twingate ainda não pertencem aos critérios obrigatórios deste baseline"

# ============================================================================
# 1. GIT / RASTREABILIDADE
# ============================================================================

section "1. GIT / RASTREABILIDADE"

set -g HEAD_COMMIT (git rev-parse HEAD)
set -g HEAD_SHORT (git rev-parse --short=12 HEAD)
set -g CURRENT_BRANCH (git branch --show-current)

line "branch=$CURRENT_BRANCH"
line "commit=$HEAD_COMMIT"
line "ultimo_commit="(git log -1 --pretty='%h %s')

set -l expected_branch "feature/auth-local"

if test "$CURRENT_BRANCH" = "$expected_branch"
    ok "branch esperada confirmada: $expected_branch"
else
    warn "branch atual é '$CURRENT_BRANCH'; baseline foi desenvolvido em '$expected_branch'"
end

git diff --check >>"$REPORT" 2>&1

if test $status -eq 0
    ok "git diff --check"
else
    fail "git diff --check encontrou problemas"
end

set -l git_dirty (git status --porcelain=v1)

if test (count $git_dirty) -eq 0
    ok "working tree limpa"
else
    warn "working tree possui alterações"
    note_lines $git_dirty
end

set -l upstream (git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)

if test $status -eq 0 -a -n "$upstream"
    set -l ahead (git rev-list --count "$upstream"..HEAD 2>/dev/null)
    set -l behind (git rev-list --count HEAD.."$upstream" 2>/dev/null)

    line "upstream=$upstream ahead=$ahead behind=$behind"

    if test "$ahead" = "0" -a "$behind" = "0"
        ok "HEAD sincronizado com a referência remota local"
    else
        warn "divergência em relação a $upstream: ahead=$ahead behind=$behind"
    end

    info "esta comparação não executa git fetch; usa a referência remota local existente"
else
    warn "branch atual não possui upstream configurado"
end

# ============================================================================
# 2. FERRAMENTAS / CONTRATO DO HOST
# ============================================================================

section "2. FERRAMENTAS / CONTRATO DO HOST"

set -g COMMANDS_OK 1

for cmd in docker git python3 grep awk sed find sort tar gzip sha256sum stat df
    require_command "$cmd"
    or set -g COMMANDS_OK 0
end

if type -q fish
    ok "Fish disponível: "(fish --version)
else
    fail "Fish não disponível"
end

if type -q php
    ok "PHP disponível: "(php -r 'echo PHP_VERSION;' 2>/dev/null)
else
    warn "PHP CLI não encontrado"
end

if type -q composer
    ok "Composer disponível: "(composer --version --no-ansi 2>/dev/null)
else
    warn "Composer não encontrado"
end

set -g DOCKER_OK 0

if type -q docker
    docker info >/dev/null 2>&1

    if test $status -eq 0
        set -g DOCKER_OK 1
        ok "API Docker acessível"

        set -l docker_version (docker version --format '{{.Server.Version}}' 2>/dev/null)
        set -l compose_version (docker compose version --short 2>/dev/null)

        line "docker_engine=$docker_version"
        line "docker_compose=$compose_version"

        if test -n "$compose_version"
            ok "Docker Compose disponível"
        else
            fail "Docker Compose indisponível"
        end
    else
        fail "Docker instalado, mas API/daemon não está acessível"
    end
end

set -l host_os (uname -s)
set -l host_arch (uname -m)

line "host_os=$host_os"
line "host_arch=$host_arch"

if test "$host_os" = "Linux" -a "$host_arch" = "x86_64"
    ok "host compatível com plataforma alvo linux/amd64"
else
    fail "host atual diverge da plataforma alvo linux/amd64"
end

if test -r /proc/sys/vm/max_map_count
    set -l vm_max_map_count (cat /proc/sys/vm/max_map_count)
    line "vm.max_map_count=$vm_max_map_count"

    if string match -rq '^[0-9]+$' -- "$vm_max_map_count"
        if test "$vm_max_map_count" -ge 262144
            ok "vm.max_map_count >= 262144"
        else
            fail "vm.max_map_count insuficiente para o Wazuh Indexer"
        end
    else
        fail "não foi possível interpretar vm.max_map_count"
    end
else
    fail "/proc/sys/vm/max_map_count não está legível"
end

if test -r /proc/meminfo
    set -l ram_gib (awk '/MemTotal:/ {printf "%.1f", $2/1024/1024}' /proc/meminfo)
    line "ram_host_gib=$ram_gib"

    awk -v value="$ram_gib" 'BEGIN {exit !(value >= 8)}'

    if test $status -eq 0
        ok "host possui pelo menos 8 GiB de RAM"
    else
        fail "host possui menos de 8 GiB de RAM"
    end
end

if test "$DOCKER_OK" -eq 1
    set -l docker_root (docker info --format '{{.DockerRootDir}}' 2>/dev/null)

    if test -n "$docker_root" -a -d "$docker_root"
        set -l free_gib (df -Pk "$docker_root" | awk 'NR==2 {printf "%.1f", $4/1024/1024}')
        line "docker_root=$docker_root free_gib=$free_gib"

        awk -v value="$free_gib" 'BEGIN {exit !(value >= 50)}'

        if test $status -eq 0
            ok "filesystem do Docker possui pelo menos 50 GiB livres"
        else
            fail "filesystem do Docker possui menos de 50 GiB livres"
        end
    else
        warn "não foi possível determinar espaço livre do DockerRootDir"
    end
end

# ============================================================================
# 3. ARQUIVOS OBRIGATÓRIOS DO BASELINE
# ============================================================================

section "3. ARQUIVOS OBRIGATÓRIOS DO BASELINE"

set -l required_files \
    composer.json \
    composer.lock \
    phpunit.xml \
    sql/conectaeduca.sql \
    deploy/CONTRATO-IMPLANTACAO.md \
    deploy/IMAGENS-VALIDADAS.md \
    deploy/dmz/compose.yml \
    deploy/dmz/compose.database.yml \
    deploy/dmz/compose.app-secrets.yml \
    deploy/dmz/compose.waf.yml \
    deploy/dmz/compose.waf-tls.yml \
    deploy/dmz/compose.waf-policy.yml \
    deploy/dmz/compose.host.yml \
    deploy/dmz/compose.smtp.yml \
    deploy/dmz/waf/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf \
    deploy/dmz/SMTP-SECRET-BRIDGE.md \
    deploy/dmz/nginx/Dockerfile \
    deploy/dmz/php/Dockerfile \
    deploy/interna/mariadb/compose.yml \
    deploy/interna/mariadb/compose.host.yml \
    deploy/interna/mariadb/conectaeduca.cnf \
    deploy/interna/mariadb/20-minimos-privilegios.sql \
    deploy/interna/wazuh/compose.yml \
    deploy/interna/wazuh/compose.host.yml \
    deploy/interna/wazuh/compose.lab.yml \
    deploy/interna/wazuh/generate-indexer-certs.yml \
    deploy/interna/wazuh/CONTRATO-HOST.md \
    deploy/interna/wazuh/IMAGENS-VALIDADAS.md \
    deploy/interna/wazuh/RETENCAO.md \
    deploy/interna/wazuh/INTEGRACAO-FERRET-DLP.md \
    deploy/interna/wazuh/config/rules/conectaeduca_dlp_rules.xml \
    deploy/interna/wazuh/agent/conectaeduca-dlp-localfile.xml.example \
    deploy/interna/openbao/compose.yml \
    deploy/interna/openbao/config/openbao.hcl \
    deploy/interna/openbao/IMAGENS-VALIDADAS.md \
    deploy/interna/openbao/OPERACIONAL-SMTP.md \
    deploy/interna/openbao/policies/conectaeduca-smtp-read.hcl \
    deploy/interna/ferret/compose.yml \
    deploy/interna/ferret/config/ferret.yaml \
    deploy/interna/ferret/IMAGENS-VALIDADAS.md \
    deploy/interna/ferret/README.md \
    deploy/interna/ferret/CONTRATO-EVENTOS-DLP.md \
    deploy/interna/ferret/RETENCAO.md \
    deploy/lab/stack-local/README.md \
    deploy/lab/stack-local/compose.db-local.yml \
    deploy/lab/stack-local/compose.dmz-local.yml \
    scripts/bootstrap/preparar_openbao.fish \
    scripts/bootstrap/provisionar_openbao_smtp.py \
    scripts/bootstrap/operacionalizar_openbao_smtp.fish \
    scripts/bootstrap/preparar_ferret.fish \
    scripts/bootstrap/subir_ferret.fish \
    scripts/bootstrap/parar_ferret.fish \
    scripts/bootstrap/subir_stack_local.fish \
    scripts/bootstrap/parar_stack_local.fish \
    scripts/evidencias/checkpoint_smtp_real_container.fish \
    scripts/evidencias/checkpoint_stack_local.fish \
    scripts/evidencias/checkpoint_waf_envelope_criptografico.fish \
    scripts/evidencias/checkpoint_sast_pre_dlp.fish \
    scripts/evidencias/verificar_segredos_estaticos.py \
    scripts/evidencias/checkpoint_portabilidade_containers.sh \
    scripts/evidencias/checkpoint_reprodutibilidade_imagens.sh \
    scripts/evidencias/checkpoint_wazuh_handoff.sh \
    scripts/evidencias/checkpoint_ferret.fish \
    scripts/evidencias/checkpoint_ferret_pipeline.fish \
    scripts/dlp/processar_inbox_ferret.fish \
    scripts/dlp/sanitizar_ferret.py \
    scripts/dlp/validar_eventos_ferret.py \
    scripts/handoff/exportar_handoff_containers.sh

for file in $required_files
    require_file "$file"
end

# ============================================================================
# 4. HIGIENE DO GIT / SEGREDOS
# ============================================================================

section "4. HIGIENE DO GIT / SEGREDOS"

set -l tracked_sensitive

for file in (git ls-files)
    if string match -rq '(^|/)\.runtime(/|$)' -- "$file"
        set -a tracked_sensitive "$file"
        continue
    end

    if string match -rq '(^|/)\.env$' -- "$file"
        set -a tracked_sensitive "$file"
        continue
    end

    if string match -rq '\.(key|pem|p12|pfx|jks)$' -- "$file"
        set -a tracked_sensitive "$file"
        continue
    end
end

if test (count $tracked_sensitive) -eq 0
    ok "nenhum runtime, .env real, chave ou keystore sensível rastreado pelo Git"
else
    fail "arquivos potencialmente sensíveis estão rastreados pelo Git"
    note_lines $tracked_sensitive
end

set -l runtime_probe_dirs \
    deploy/dmz/.runtime \
    deploy/interna/mariadb/.runtime \
    deploy/interna/wazuh/.runtime \
    deploy/interna/openbao/.runtime \
    deploy/interna/ferret/.runtime

for runtime_dir in $runtime_probe_dirs
    git check-ignore -q "$runtime_dir/__checkpoint_probe__"

    if test $status -eq 0
        ok "$runtime_dir está coberto pelo .gitignore"
    else
        warn "$runtime_dir não foi confirmado pelo git check-ignore"
    end
end

# Pesquisa por bloco PEM fora das fixtures de teste e fora dos próprios
# scripts de evidência (evita o falso positivo que já tivemos no passado).
set -l private_key_hits (
    git grep -n -E \
        -e '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' \
        -- \
        ':!tests/**' \
        ':!scripts/evidencias/**' \
        2>/dev/null
)

if test (count $private_key_hits) -eq 0
    ok "nenhum cabeçalho de chave privada rastreado fora de tests/ e scripts/evidencias/"
else
    fail "possível chave privada rastreada fora das exceções permitidas"
    note_lines $private_key_hits
end

# Defaults famosos e frágeis: não são tratados automaticamente como vazamento,
# porque podem existir em documentação. São advertência para inspeção humana.
set -l weak_default_hits (
    git grep -n -i -E \
        -e '(change[m]e|password[1]23|secretpass[w]ord|admin[1]23)' \
        -- deploy \
        2>/dev/null
)

if test (count $weak_default_hits) -eq 0
    ok "nenhum marcador óbvio de credencial fraca/default detectado em deploy/"
else
    warn "marcadores de credencial default/fraca encontrados; revisar contexto"
    note_lines $weak_default_hits
end

# Evita imagens Docker, backups e pacotes gigantes dentro do Git.
set -l tracked_archives

for file in (git ls-files)
    if string match -rq '\.(tar|tar\.gz|tgz|zip|bak|backup)$' -- "$file"
        set -a tracked_archives "$file"
    end
end

if test (count $tracked_archives) -eq 0
    ok "nenhum arquivo de handoff/backup pesado rastreado pelo Git"
else
    warn "arquivos de archive/backup estão rastreados"
    note_lines $tracked_archives
end

# ============================================================================
# 5. PERMISSÕES DO RUNTIME LOCAL
# ============================================================================

section "5. PERMISSÕES DO RUNTIME LOCAL"

set -l wazuh_runtime "$ROOT/deploy/interna/wazuh/.runtime"

if test -d "$wazuh_runtime"
    ok "runtime local do Wazuh existe e permanece fora do Git"

    set -l runtime_dir_mode (stat -c '%a' "$wazuh_runtime" 2>/dev/null)
    line "wazuh_runtime_dir_mode=$runtime_dir_mode"

    if string match -rq '^[0-7]?00$' -- "$runtime_dir_mode"
        ok "diretório .runtime do Wazuh sem permissões para grupo/outros"
    else
        warn "diretório .runtime do Wazuh possui permissões para grupo/outros: $runtime_dir_mode"
    end

    set -l sensitive_runtime_files \
        manager.env \
        dashboard.env \
        internal_users.yml \
        wazuh.yml

    for basename in $sensitive_runtime_files
        set -l path "$wazuh_runtime/$basename"

        if not test -f "$path"
            fail "runtime esperado ausente: $basename"
            continue
        end

        set -l mode (stat -c '%a' "$path" 2>/dev/null)
        line "$basename mode=$mode"

        if test "$mode" = "600"
            ok "$basename protegido com modo 600"
        else
            fail "$basename deveria estar em modo 600; encontrado $mode"
        end
    end
else
    fail "runtime local do Wazuh ausente: deploy/interna/wazuh/.runtime"
end

# ============================================================================
# 6. POLÍTICAS DE PORTABILIDADE
# ============================================================================

section "6. POLÍTICAS DE PORTABILIDADE"

set -l handoff_files \
    deploy/dmz/compose.yml \
    deploy/dmz/compose.database.yml \
    deploy/dmz/compose.app-secrets.yml \
    deploy/dmz/compose.waf.yml \
    deploy/dmz/compose.waf-tls.yml \
    deploy/dmz/compose.waf-policy.yml \
    deploy/dmz/compose.host.yml \
    deploy/interna/mariadb/compose.yml \
    deploy/interna/mariadb/compose.host.yml \
    deploy/interna/wazuh/compose.yml \
    deploy/interna/wazuh/compose.host.yml \
    deploy/interna/wazuh/generate-indexer-certs.yml \
    deploy/interna/openbao/compose.yml \
    deploy/interna/ferret/compose.yml

set -l existing_handoff_files

for file in $handoff_files
    if test -f "$file"
        set -a existing_handoff_files "$file"
    end
end

set -l host_network_hits (
    grep -nE 'network_mode:[[:space:]]*["'\'']?host["'\'']?' \
        $existing_handoff_files 2>/dev/null
)

if test (count $host_network_hits) -eq 0
    ok "nenhum network_mode: host no conjunto real de handoff"
else
    fail "network_mode: host detectado no conjunto real de handoff"
    note_lines $host_network_hits
end

set -l privileged_hits (
    grep -nE 'privileged:[[:space:]]*true' \
        $existing_handoff_files 2>/dev/null
)

if test (count $privileged_hits) -eq 0
    ok "nenhum privileged: true no conjunto real de handoff"
else
    fail "privileged: true detectado no handoff"
    note_lines $privileged_hits
end

set -l socket_hits (
    grep -nE '/var/run/docker\.sock|/run/docker\.sock' \
        $existing_handoff_files 2>/dev/null
)

if test (count $socket_hits) -eq 0
    ok "Docker socket não é montado pelo conjunto real de handoff"
else
    fail "Docker socket montado em container"
    note_lines $socket_hits
end

set -l lab_ip_hits (
    grep -nE '172\.30\.25[0-9]\.' \
        $existing_handoff_files 2>/dev/null
)

if test (count $lab_ip_hits) -eq 0
    ok "nenhum IP 172.30.25x.x vazou para o handoff real"
else
    fail "IP de laboratório 172.30.25x.x encontrado no handoff"
    note_lines $lab_ip_hits
end

if grep -q 'CONECTAEDUCA_DB_HOST' deploy/dmz/compose.database.yml 2>/dev/null
    ok "endpoint do MariaDB é parametrizado para comunicação entre hosts/VMs"
else
    fail "compose.database.yml não contém CONECTAEDUCA_DB_HOST"
end

if grep -Eq '\$\{[^}]*BIND[^}]*\}' deploy/interna/mariadb/compose.host.yml 2>/dev/null
    ok "binding TCP do MariaDB é parametrizável"
else
    warn "não foi identificada variável *BIND* no compose.host.yml do MariaDB"
end

set -l wazuh_private_ip_hits (
    grep -nE \
        '(10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+)' \
        deploy/interna/wazuh/compose.host.yml \
        2>/dev/null
)

if test (count $wazuh_private_ip_hits) -eq 0
    ok "compose.host.yml do Wazuh não fixa IP RFC1918 real de infraestrutura"
else
    fail "compose.host.yml do Wazuh contém IP privado literal"
    note_lines $wazuh_private_ip_hits
end

# ============================================================================
# 7. PINNING / REPRODUTIBILIDADE DAS REFERÊNCIAS
# ============================================================================

section "7. PINNING / REPRODUTIBILIDADE DAS REFERÊNCIAS"

set -l pin_files \
    deploy/dmz/nginx/Dockerfile \
    deploy/dmz/php/Dockerfile \
    deploy/dmz/compose.waf.yml \
    deploy/interna/mariadb/compose.yml \
    deploy/interna/wazuh/compose.yml \
    deploy/interna/wazuh/generate-indexer-certs.yml \
    deploy/interna/openbao/compose.yml \
    deploy/interna/ferret/compose.yml

set -l refs_without_digest
set -l refs_checked 0

for file in $pin_files
    if not test -f "$file"
        continue
    end

    set -l docker_stage_aliases

    if string match -q '*Dockerfile' -- "$file"
        for from_line in (grep -E '^[[:space:]]*FROM[[:space:]]+' "$file" 2>/dev/null)
            set -l from_tokens (string split ' ' -- (string trim -- "$from_line"))

            if test (count $from_tokens) -ge 4
                if test (string upper -- "$from_tokens[3]") = "AS"
                    set -a docker_stage_aliases "$from_tokens[4]"
                end
            end
        end
    end

    set -l lines (
        grep -E '^[[:space:]]*(FROM[[:space:]]+|image:[[:space:]]*)' \
            "$file" 2>/dev/null
    )

    for raw_line in $lines
        set -l ref ""

        if string match -rq '^[[:space:]]*FROM[[:space:]]+' -- "$raw_line"
            set -l tokens (string split ' ' -- (string trim -- "$raw_line"))

            if test (count $tokens) -ge 2
                set ref "$tokens[2]"
            end
        else
            set ref (
                string replace -r \
                    '^[[:space:]]*image:[[:space:]]*' \
                    '' \
                    -- "$raw_line"
            )

            set ref (string replace -r '[[:space:]]+#.*$' '' -- "$ref")
            set ref (string trim -c "\"'" -- "$ref")
        end

        if test -z "$ref"
            continue
        end

        # Aliases de estágios multi-stage (ex.: php-base) são referências
        # internas do próprio Dockerfile, não imagens externas.
        if contains -- "$ref" $docker_stage_aliases
            continue
        end

        set refs_checked (math "$refs_checked + 1")

        # Imagens locais são identificadas pelo ID local e não precisam
        # possuir digest de registry no compose.
        if string match -q 'conectaeduca/*' -- "$ref"
            continue
        end

        # Referências integralmente parametrizadas serão resolvidas pelo
        # checkpoint específico.
        if string match -rq '^\$\{.*\}$' -- "$ref"
            continue
        end

        if not string match -rq '@sha256:[0-9a-fA-F]{64}' -- "$ref"
            set -a refs_without_digest "$file :: $ref"
        end
    end
end

line "referencias_inspecionadas=$refs_checked"

if test (count $refs_without_digest) -eq 0
    ok "referências externas do baseline estão fixadas por digest"
else
    fail "referências externas sem digest encontradas"
    note_lines $refs_without_digest
end

# ============================================================================
# 8. IMAGENS LOCAIS VALIDADAS
# ============================================================================

section "8. IMAGENS LOCAIS VALIDADAS"

set -l baseline_images \
    conectaeduca/php-fpm:dmz \
    conectaeduca/nginx:dmz \
    owasp/modsecurity-crs:4.25.1-nginx-lts \
    mariadb:12.3.2-ubi10 \
    wazuh/wazuh-manager:4.14.7 \
    wazuh/wazuh-indexer:4.14.7 \
    wazuh/wazuh-dashboard:4.14.7 \
    wazuh/wazuh-certs-generator:0.0.4 \
    openbao/openbao:2.6.1 \
    public.ecr.aws/awslabs/ferret-scan:2.2.1

if test "$DOCKER_OK" -eq 1
    for image in $baseline_images
        set -l inspect (
            docker image inspect "$image" \
                --format '{{.Os}}|{{.Architecture}}|{{.Id}}' \
                2>/dev/null
        )

        if test $status -ne 0 -o -z "$inspect"
            fail "imagem local ausente: $image"
            continue
        end

        set -l fields (string split '|' -- "$inspect")
        set -l image_os "$fields[1]"
        set -l image_arch "$fields[2]"
        set -l image_id "$fields[3]"

        line "$image|$image_os/$image_arch|$image_id"

        if test "$image_os" = "linux" -a "$image_arch" = "amd64"
            ok "$image disponível para linux/amd64"
        else
            fail "$image possui plataforma inesperada: $image_os/$image_arch"
        end
    end
else
    fail "imagens locais não puderam ser inspecionadas porque Docker está indisponível"
end

# Garante que as tags antigas não sejam confundidas com o baseline atual.
if test "$DOCKER_OK" -eq 1
    if docker image inspect conectaeduca/php-fpm:fase4b >/dev/null 2>&1
        info "imagem histórica conectaeduca/php-fpm:fase4b existe, mas não pertence ao baseline atual"
    end

    if docker image inspect conectaeduca/nginx:fase4b >/dev/null 2>&1
        info "imagem histórica conectaeduca/nginx:fase4b existe, mas não pertence ao baseline atual"
    end
end

# ============================================================================
# 9. VALIDAÇÃO ESTÁTICA DOS COMPOSES
# ============================================================================

section "9. VALIDAÇÃO ESTÁTICA DOS COMPOSES"

if test "$DOCKER_OK" -eq 1
    set -l compose_bases \
        deploy/dmz/compose.yml \
        deploy/interna/mariadb/compose.yml \
        deploy/interna/wazuh/compose.yml \
        deploy/interna/openbao/compose.yml \
        deploy/interna/ferret/compose.yml

    for compose_file in $compose_bases
        docker compose \
            -f "$compose_file" \
            config \
            --no-interpolate \
            >/dev/null 2>>"$REPORT"

        if test $status -eq 0
            ok "Compose sintaticamente válido: $compose_file"
        else
            fail "docker compose config falhou: $compose_file"
        end
    end
else
    fail "Compose não pôde ser validado porque Docker está indisponível"
end

# ============================================================================
# 10. VALIDAÇÃO DE SHELL / PHP / COMPOSER
# ============================================================================

section "10. VALIDAÇÃO DE SHELL / PHP / COMPOSER"

set -l shell_errors

for script in (find scripts -type f -name '*.sh' -print 2>/dev/null | sort)
    bash -n "$script" >/dev/null 2>&1

    if test $status -ne 0
        set -a shell_errors "$script"
    end
end

if test (count $shell_errors) -eq 0
    ok "todos os scripts Bash presentes passam em bash -n"
else
    fail "há script Bash presente com erro sintático"
    note_lines $shell_errors
end

set -l fish_errors
set -l fish_scripts (find scripts -type f -name '*.fish' -print 2>/dev/null | sort)

for script in $fish_scripts
    fish -n "$script" >/dev/null 2>&1

    if test $status -ne 0
        set -a fish_errors "$script"
    end
end

if test (count $fish_errors) -eq 0
    ok "todos os scripts Fish presentes passam em fish -n"
else
    fail "há script Fish presente com erro sintático"
    note_lines $fish_errors
end

set -l dlp_python_files \
    scripts/dlp/sanitizar_ferret.py \
    scripts/dlp/validar_eventos_ferret.py

set -l dlp_python_errors

for py_file in $dlp_python_files
    python3 -c '
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
compile(path.read_text(encoding="utf-8"), str(path), "exec")
' "$py_file" >/dev/null 2>&1

    if test $status -ne 0
        set -a dlp_python_errors "$py_file"
    end
end

if test (count $dlp_python_errors) -eq 0
    ok "scripts Python do pipeline DLP passam em py_compile"
else
    fail "há script Python do pipeline DLP com erro de compilação"
    note_lines $dlp_python_errors
end

if type -q php
    set -l php_errors

    for php_file in (git ls-files '*.php')
        php -l "$php_file" >/dev/null 2>&1

        if test $status -ne 0
            set -a php_errors "$php_file"
        end
    end

    if test (count $php_errors) -eq 0
        ok "arquivos PHP rastreados passam no lint"
    else
        fail "arquivos PHP com erro de sintaxe"
        note_lines $php_errors
    end
end

if type -q composer -a -f composer.json
    composer validate \
        --no-check-publish \
        --no-interaction \
        >/dev/null 2>>"$REPORT"

    if test $status -eq 0
        ok "composer.json/composer.lock validados"
    else
        fail "composer validate falhou"
    end
end

# Valida a fronteira versionada entre DLP e SIEM sem depender do runtime.
if grep -Fq '<log_format>json</log_format>' \
    deploy/interna/wazuh/agent/conectaeduca-dlp-localfile.xml.example \
    && grep -Fq '__CONECTAEDUCA_DLP_EVENTS_FILE__' \
        deploy/interna/wazuh/agent/conectaeduca-dlp-localfile.xml.example
    ok "modelo do Wazuh Agent declara coleta JSON do evento DLP sanitizado"
else
    fail "modelo do Wazuh Agent para o DLP está incompleto"
end

set -l dlp_agent_location (
    sed -n 's#.*<location>\(.*\)</location>.*#\1#p' \
        deploy/interna/wazuh/agent/conectaeduca-dlp-localfile.xml.example
)

if string match -q '*reports/raw*' -- "$dlp_agent_location"
    fail "modelo do Wazuh Agent aponta para superfície bruta/sensível do Ferret"
else if string match -q '*/inbox/*' -- "$dlp_agent_location"
    fail "modelo do Wazuh Agent aponta para superfície bruta/sensível do Ferret"
else
    ok "modelo do Wazuh Agent não aponta para inbox nem reports/raw"
end

python3 -c '
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
ids = {rule.get("id") for rule in root.findall("rule")}
expected = {"110100", "110101", "110102", "110110", "110111", "110112", "110113"}
raise SystemExit(0 if ids == expected else 1)
' deploy/interna/wazuh/config/rules/conectaeduca_dlp_rules.xml >/dev/null 2>&1

if test $status -eq 0
    ok "regras DLP Wazuh possuem exatamente os IDs esperados 110100-110113"
else
    fail "XML/IDs das regras DLP Wazuh divergem do contrato"
end

# ============================================================================
# 11. PORTAS SINTÉTICAS / RESÍDUOS DE TESTE
# ============================================================================

section "11. PORTAS SINTÉTICAS / RESÍDUOS DE TESTE"

for port in 13306 15114 15115 18445
    check_port_free "$port"
end

if test "$DOCKER_OK" -eq 1
    set -l containers (
        docker ps -a \
            --filter 'name=conectaeduca' \
            --format '{{.Names}}|{{.Status}}' \
            2>/dev/null
    )

    if test (count $containers) -eq 0
        ok "nenhum container ConectaEduca residual encontrado"
    else
        info "containers ConectaEduca existentes no host:"
        note_lines $containers

        set -l bad_containers

        for entry in $containers
            if string match -riq \
                '\|(Exited|Dead|Restarting|Removal In Progress)' \
                -- "$entry"
                set -a bad_containers "$entry"
            end
        end

        if test (count $bad_containers) -eq 0
            ok "nenhum container ConectaEduca em estado anormal"
        else
            warn "containers ConectaEduca residuais/anormais detectados"
            note_lines $bad_containers
        end
    end
end

# ============================================================================
# 12. HANDOFF PARCIAL JÁ GERADO
# ============================================================================

section "12. HANDOFF PARCIAL JÁ GERADO"

set -g HANDOFF_DIR ""

if set -q CONECTAEDUCA_HANDOFF_DIR
    set -g HANDOFF_DIR "$CONECTAEDUCA_HANDOFF_DIR"
else
    set -l found_handoff (
        find /var/tmp \
            -maxdepth 1 \
            -mindepth 1 \
            -type d \
            -name 'conectaeduca-handoff-20*' \
            -printf '%T@|%p\n' \
            2>/dev/null \
        | sort -n \
        | tail -n 1
    )

    if test -n "$found_handoff"
        set -g HANDOFF_DIR (
            string replace -r '^[^|]*\|' '' -- "$found_handoff"
        )
    end
end

if test -n "$HANDOFF_DIR" -a -d "$HANDOFF_DIR/packages"
    line "handoff_dir=$HANDOFF_DIR"
    ok "handoff parcial localizado"

    if test -f "$HANDOFF_DIR/packages/SHA256SUMS"
        pushd "$HANDOFF_DIR/packages" >/dev/null

        sha256sum -c SHA256SUMS >>"$REPORT" 2>&1
        set -l sha_rc $status

        popd >/dev/null

        if test $sha_rc -eq 0
            ok "SHA-256 externo dos pacotes de handoff"
        else
            fail "SHA-256 externo dos pacotes de handoff falhou"
        end
    else
        fail "SHA256SUMS externo ausente no handoff"
    end

    set -l packages (
        find "$HANDOFF_DIR/packages" \
            -maxdepth 1 \
            -type f \
            -name 'conectaeduca-handoff-*.tar' \
            2>/dev/null \
        | sort
    )

    if test (count $packages) -ge 2
        ok "pacotes DMZ e interna localizados"

        for package in $packages
            line (du -h "$package")
            set -l package_name (basename "$package")

            set -l suspicious_names (
                tar -tf "$package" 2>/dev/null \
                | grep -E \
                    '(^|/)\.runtime(/|$)|(^|/)\.env$|\.(key|pem|p12|pfx|jks)$'
            )

            if test (count $suspicious_names) -eq 0
                ok "$package_name não contém nomes de arquivos sensíveis proibidos"
            else
                fail "$package_name contém arquivo potencialmente sensível"
                note_lines $suspicious_names
            end
        end

        set -l dmz_package (
            find "$HANDOFF_DIR/packages" \
                -maxdepth 1 \
                -type f \
                -name 'conectaeduca-handoff-dmz-*.tar' \
                | head -n 1
        )

        if test -n "$dmz_package"
            set -l manifest (
                tar -xOf "$dmz_package" dmz/MANIFESTO.txt 2>/dev/null
            )

            set -l manifest_commit (
                printf '%s\n' $manifest \
                | awk '/^Commit:/ {print $2; exit}'
            )

            line "handoff_manifest_commit=$manifest_commit"

            if test "$manifest_commit" = "$HEAD_COMMIT"
                ok "handoff corresponde exatamente ao HEAD atual"
            else if test -n "$manifest_commit"
                git merge-base --is-ancestor "$manifest_commit" "$HEAD_COMMIT" 2>/dev/null

                if test $status -eq 0
                    info "handoff é snapshot válido de commit ancestral: $manifest_commit"
                else
                    warn "commit do handoff não pertence à história atual: $manifest_commit"
                end
            else
                fail "commit não pôde ser lido do manifesto do handoff"
            end
        end
    else
        fail "não foram encontrados os dois pacotes de handoff esperados"
    end
else
    warn "nenhum handoff parcial localizado em /var/tmp"
end

# ============================================================================
# 13. HANDOFF PROFUNDO OPCIONAL
# ============================================================================

section "13. HANDOFF PROFUNDO"

if test "$DEEP_HANDOFF" -eq 0
    info "validação profunda do handoff não solicitada; use --handoff-profundo"
else if test -z "$HANDOFF_DIR" -o not -d "$HANDOFF_DIR/packages"
    fail "handoff profundo solicitado, mas pacote não foi localizado"
else
    set -l deep_free_gib (
        df -Pk /var/tmp \
        | awk 'NR==2 {printf "%.1f", $4/1024/1024}'
    )

    line "var_tmp_free_gib=$deep_free_gib"

    awk -v value="$deep_free_gib" 'BEGIN {exit !(value >= 8)}'

    if test $status -ne 0
        fail "menos de 8 GiB livres em /var/tmp para validação profunda"
    else
        set -l deep_dir (
            mktemp -d "/var/tmp/conectaeduca-handoff-check.XXXXXX"
        )

        set -l deep_extract_ok 1

        for package in (
            find "$HANDOFF_DIR/packages" \
                -maxdepth 1 \
                -type f \
                -name 'conectaeduca-handoff-*.tar' \
                | sort
        )
            tar -xf "$package" -C "$deep_dir" >>"$REPORT" 2>&1

            if test $status -ne 0
                set deep_extract_ok 0
                fail "falha ao extrair "(basename "$package")
            end
        end

        if test "$deep_extract_ok" -eq 1
            ok "pacotes extraídos para validação profunda"
        end

        for component in dmz interna
            if test -f "$deep_dir/$component/SHA256SUMS"
                pushd "$deep_dir/$component" >/dev/null

                sha256sum -c SHA256SUMS >>"$REPORT" 2>&1
                set -l internal_rc $status

                popd >/dev/null

                if test $internal_rc -eq 0
                    ok "SHA-256 interno do componente $component"
                else
                    fail "SHA-256 interno do componente $component falhou"
                end
            else
                fail "SHA256SUMS interno ausente: $component"
            end
        end

        if test -f "$deep_dir/dmz/images/dmz-images.tar.gz"
            gzip -t "$deep_dir/dmz/images/dmz-images.tar.gz" \
                >>"$REPORT" 2>&1

            if test $status -eq 0
                ok "arquivo de imagens DMZ passa em gzip -t"
            else
                fail "arquivo de imagens DMZ está corrompido"
            end
        else
            fail "dmz-images.tar.gz ausente"
        end

        if test -f "$deep_dir/interna/images/interna-images.tar.gz"
            gzip -t "$deep_dir/interna/images/interna-images.tar.gz" \
                >>"$REPORT" 2>&1

            if test $status -eq 0
                ok "arquivo de imagens da VM interna passa em gzip -t"
            else
                fail "arquivo de imagens da VM interna está corrompido"
            end
        else
            fail "interna-images.tar.gz ausente"
        end

        set -l deep_sensitive (
            find "$deep_dir" \
                -type f \
                \( \
                    -name '.env' \
                    -o -name '*.key' \
                    -o -name '*.pem' \
                    -o -name '*.p12' \
                    -o -name '*.pfx' \
                    -o -name '*.jks' \
                    -o -path '*/.runtime/*' \
                \) \
                -print \
                2>/dev/null
        )

        if test (count $deep_sensitive) -eq 0
            ok "handoff extraído permanece livre de runtime/segredos proibidos"
        else
            fail "arquivos sensíveis encontrados após extrair handoff"
            note_lines $deep_sensitive
        end

        rm -rf "$deep_dir"
        ok "diretório temporário da validação profunda removido"
    end
end

# ============================================================================
# 14. TESTES PHPUNIT
# ============================================================================

section "14. TESTES PHPUNIT"

if test "$MODE" = "rapido"
    info "PHPUnit não executado no modo rápido; use --completo"
else
    if test -f vendor/bin/phpunit -a -f phpunit.xml
        set -l phpunit_output (
            mktemp "/tmp/conectaeduca-phpunit.XXXXXX"
        )

        php vendor/bin/phpunit \
            --configuration phpunit.xml \
            >"$phpunit_output" 2>&1

        set -l phpunit_rc $status

        cat "$phpunit_output" >>"$REPORT"

        if test $phpunit_rc -eq 0
            ok "PHPUnit aprovado"
        else
            fail "PHPUnit reprovado"
            tail -n 20 "$phpunit_output" | tee -a "$REPORT"
        end

        rm -f "$phpunit_output"
    else
        fail "vendor/bin/phpunit ou phpunit.xml ausente"
    end
end

# ============================================================================
# 15. CHECKPOINTS DINÂMICOS
# ============================================================================

section "15. CHECKPOINTS DINÂMICOS"

if test "$MODE" = "rapido"
    info "checkpoints dinâmicos não executados no modo rápido"
    info "use --completo para testar reprodutibilidade, DMZ/MariaDB, Ferret, pipeline DLP, integração Wazuh, OpenBao, stack local, WAF e SAST"
else
    if test "$DOCKER_OK" -ne 1
        fail "modo completo solicitado, mas Docker não está acessível"
    else
        set -l git_before (
            git status --porcelain=v1
        )

        run_subcheckpoint \
            "Reprodutibilidade das imagens" \
            "$ROOT/scripts/evidencias/checkpoint_reprodutibilidade_imagens.sh"

        run_subcheckpoint \
            "Portabilidade DMZ / MariaDB" \
            "$ROOT/scripts/evidencias/checkpoint_portabilidade_containers.sh"

        run_subcheckpoint \
            "Ferret Scan DLP" \
            "$ROOT/scripts/evidencias/checkpoint_ferret.fish"

        run_subcheckpoint \
            "Pipeline DLP Ferret -> evento sanitizado" \
            "$ROOT/scripts/evidencias/checkpoint_ferret_pipeline.fish"

        run_subcheckpoint \
            "Wazuh / handoff / regras Ferret DLP" \
            "$ROOT/scripts/evidencias/checkpoint_wazuh_handoff.sh"

        if docker ps --format '{{.Names}}' | grep -Fxq 'conectaeduca-openbao'
            set -l openbao_status (
                docker exec \
                    -e BAO_ADDR=http://127.0.0.1:8200 \
                    conectaeduca-openbao \
                    bao status -format=json \
                    2>/dev/null
            )

            if string match -rq '"initialized"[[:space:]]*:[[:space:]]*true' -- "$openbao_status" \
                && string match -rq '"sealed"[[:space:]]*:[[:space:]]*false' -- "$openbao_status"
                ok "OpenBao operacional: inicializado e unsealed"
            else
                fail "OpenBao em execução, mas não está simultaneamente inicializado e unsealed"
            end
        else
            fail "OpenBao operacional não está em execução"
        end

        run_subcheckpoint \
            "Stack local persistente" \
            "$ROOT/scripts/evidencias/checkpoint_stack_local.fish"

        run_subcheckpoint \
            "WAF / envelope criptográfico" \
            "$ROOT/scripts/evidencias/checkpoint_waf_envelope_criptografico.fish"

        run_subcheckpoint \
            "SAST / higiene pré-DLP" \
            "$ROOT/scripts/evidencias/checkpoint_sast_pre_dlp.fish"

        set -l git_after (
            git status --porcelain=v1
        )

        set -l before_string (
            string join \n -- $git_before
        )

        set -l after_string (
            string join \n -- $git_after
        )

        if test "$before_string" = "$after_string"
            ok "checkpoints dinâmicos não alteraram o estado do Git"
        else
            fail "estado do Git mudou durante os checkpoints dinâmicos"
            line "Antes:"
            note_lines $git_before
            line "Depois:"
            note_lines $git_after
        end
    end
end

# ============================================================================
# 16. SUPERFÍCIE DOCKER ATUAL
# ============================================================================

section "16. SUPERFÍCIE DOCKER ATUAL"

if test "$DOCKER_OK" -eq 1
    set -l running (
        docker ps \
            --filter 'name=conectaeduca' \
            --format '{{.Names}}|{{.Image}}|{{.Ports}}' \
            2>/dev/null
    )

    if test (count $running) -eq 0
        ok "nenhum container ConectaEduca ficou ativo após o checkpoint"
    else
        info "containers ConectaEduca atualmente ativos:"
        note_lines $running
    end

    set -l published_forbidden (
        docker ps \
            --filter 'name=conectaeduca-wazuh' \
            --format '{{.Names}}|{{.Ports}}' \
            2>/dev/null \
        | grep -E \
            '(0\.0\.0\.0|:::).*:(9200|55000|514)->'
    )

    if test (count $published_forbidden) -eq 0
        ok "nenhuma API sensível Wazuh 9200/55000/514 está publicada em wildcard"
    else
        fail "API sensível Wazuh publicada no host"
        note_lines $published_forbidden
    end
end

# ============================================================================
# 17. GIT FINAL
# ============================================================================

section "17. GIT FINAL"

git status --short | tee -a "$REPORT"

git diff --check >>"$REPORT" 2>&1

if test $status -eq 0
    ok "git diff --check final"
else
    fail "git diff --check final falhou"
end

set -l final_head (git rev-parse HEAD)

if test "$final_head" = "$HEAD_COMMIT"
    ok "HEAD permaneceu no commit $HEAD_SHORT durante o checkpoint"
else
    fail "HEAD mudou durante a execução do checkpoint"
end

# ============================================================================
# RESULTADO
# ============================================================================

blank
line "======================================================================"
line " RESULTADO"
line "======================================================================"

line "Versão:       $SCRIPT_VERSION"
line "Modo:         $MODE"
line "Commit:       $HEAD_COMMIT"
line "Aprovações:   $PASS_COUNT"
line "Advertências: $WARN_COUNT"
line "Falhas:       $FAIL_COUNT"
line "Informações:  $INFO_COUNT"

blank

if test "$FAIL_COUNT" -gt 0
    line "CHECKPOINT GERAL DA CONTEINERIZAÇÃO: REPROVADO."
    line "Há $FAIL_COUNT falha(s) que devem ser resolvidas antes de considerar o baseline íntegro."
    line "Relatório: $REPORT"
    line "======================================================================"
    exit 1
end

if test "$WARN_COUNT" -gt 0
    line "CHECKPOINT GERAL DA CONTEINERIZAÇÃO: APROVADO COM ADVERTÊNCIAS."
    line "Não há falhas, mas existem $WARN_COUNT ponto(s) para revisão."
    line "Relatório: $REPORT"
    line "======================================================================"

    if test "$STRICT" -eq 1
        exit 2
    end

    exit 0
end

line "CHECKPOINT GERAL DA CONTEINERIZAÇÃO: APROVADO."
line "Baseline DLP integrado íntegro: Ferret + pipeline sanitizado + classificação no Wazuh Manager, além dos blocos anteriores."
line "Próximo bloco planejado: Bacula; Wazuh Agent nativo/FIM/YARA e Twingate permanecem posteriores."
line "Relatório: $REPORT"
line "======================================================================"

exit 0
