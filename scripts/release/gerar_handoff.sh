#!/usr/bin/env bash
set -Eeuo pipefail

TARGET="${1:-}"
OUTDIR="${2:-$HOME/Downloads}"
REF="${3:-HEAD}"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "ERRO: execute dentro do repositório Git." >&2
    exit 1
}
cd "$ROOT"

case "$TARGET" in
    dmz|interna) ;;
    *)
        echo "Uso: $0 {dmz|interna} [diretorio_saida] [git_ref]" >&2
        exit 2
        ;;
esac

REF_SHA="$(git rev-parse "$REF^{commit}")"
SHORT_SHA="${REF_SHA:0:12}"
SOURCE_EPOCH="$(git show -s --format=%ct "$REF_SHA")"
STAMP="$(date -u -d "@$SOURCE_EPOCH" +%Y%m%dT%H%M%SZ)"

mkdir -p "$OUTDIR"
TMP="$(mktemp -d -t conectaeduca-release-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

ARCHIVE="$TMP/archive"
STAGE="$TMP/conectaeduca-$TARGET"
mkdir -p "$ARCHIVE" "$STAGE"

git archive --format=tar "$REF_SHA" | tar -xf - -C "$ARCHIVE"

copy_path() {
    local rel="$1"
    local src="$ARCHIVE/$rel"
    local dst="$STAGE/$rel"

    [[ -e "$src" ]] || {
        echo "ERRO: arquivo obrigatório ausente no ref $REF_SHA: $rel" >&2
        exit 1
    }

    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
}

copy_if_exists() {
    local rel="$1"
    [[ -e "$ARCHIVE/$rel" ]] || return 0
    mkdir -p "$(dirname "$STAGE/$rel")"
    cp -a "$ARCHIVE/$rel" "$STAGE/$rel"
}

# Documentação comum.
for rel in \
    README.md \
    .env.example \
    deploy/ARQUITETURA-VMs.md \
    deploy/CONTRATO-IMPLANTACAO.md \
    deploy/IMAGENS-VALIDADAS.md \
    docs/release/HANDOFF-FINAL.md \
    scripts/release/verificar_handoff.sh
do
    copy_path "$rel"
done

if [[ "$TARGET" == "dmz" ]]; then
    # Aplicação e build da DMZ.
    for rel in \
        .dockerignore \
        composer.json \
        composer.lock \
        bootstrap \
        public \
        src \
        deploy/dmz/compose.yml \
        deploy/dmz/compose.host.yml \
        deploy/dmz/compose.app-secrets.yml \
        deploy/dmz/compose.app-tls.yml \
        deploy/dmz/compose.smtp.yml \
        deploy/dmz/compose.waf.yml \
        deploy/dmz/compose.waf-tls.yml \
        deploy/dmz/compose.waf-policy.yml \
        deploy/dmz/compose.waf-tuning.yml \
        deploy/dmz/nginx \
        deploy/dmz/php \
        deploy/dmz/waf \
        deploy/dmz/bacula-fd \
        scripts/implantacao/preparar_bacula_fd_ubuntu.sh
    do
        copy_path "$rel"
    done

    # compose.database.yml é recurso de laboratório/local e não pertence à VM DMZ final.
else
    # Banco e serviços internos.
    copy_path sql
    copy_path deploy/interna/mariadb
    copy_path deploy/interna/openbao
    copy_path deploy/interna/ferret
    copy_path deploy/interna/wazuh
    copy_path deploy/interna/bacula

    # O handoff final usa a variante Bacula sem File Daemon containerizado de laboratório.
    rm -f "$STAGE/deploy/interna/bacula/compose.yml"
    copy_path deploy/interna/bacula/compose.vm.yml
    mv "$STAGE/deploy/interna/bacula/compose.vm.yml" \
       "$STAGE/deploy/interna/bacula/compose.yml"

    # Wazuh compose.lab.yml é bancada local, não configuração da VM final.
    rm -f "$STAGE/deploy/interna/wazuh/compose.lab.yml"

    # Scripts operacionais necessários no destino.
    for rel in \
        scripts/implantacao/preparar_bacula_fd_ubuntu.sh \
        scripts/bootstrap/preparar_openbao.fish \
        scripts/bootstrap/provisionar_openbao_smtp.py \
        scripts/bootstrap/operacionalizar_openbao_smtp.fish \
        scripts/bootstrap/materializar_openbao_smtp_runtime.py \
        scripts/bootstrap/materializar_openbao_smtp_runtime.fish \
        scripts/bootstrap/preparar_ferret.fish \
        scripts/bootstrap/subir_ferret.fish \
        scripts/bootstrap/parar_ferret.fish \
        scripts/bootstrap/preparar_bacula_catalog.fish \
        scripts/bootstrap/preparar_bacula_core.fish \
        scripts/bootstrap/preparar_bacula_director_db.fish \
        scripts/bootstrap/materializar_bacula_core.py \
        scripts/recuperacao/recuperar_approle_bacula_snapshot.py \
        scripts/recuperacao/recuperar_approle_smtp_pos_reboot.py \
        scripts/dlp
    do
        copy_path "$rel"
    done

    # Checkpoints úteis na implantação, sem carregar a bateria de laboratório.
    for rel in \
        scripts/evidencias/checkpoint_bacula_fd_vm_readiness.sh \
        scripts/evidencias/checkpoint_openbao_bacula_readiness.sh \
        scripts/evidencias/checkpoint_yara_antiapt_readiness.sh \
        scripts/evidencias/checkpoint_bacula_openbao_raft_final.sh \
        scripts/evidencias/checkpoint_wazuh_handoff.sh \
        scripts/evidencias/verificar_segredos_estaticos.py
    do
        copy_path "$rel"
    done

    # Materiais explicitamente reservados ao laboratório não entram.
    rm -f "$STAGE/scripts/bootstrap/materializar_bacula_workloads_lab.py"
fi

# Metadados reproduzíveis.
cat > "$STAGE/RELEASE-METADATA.txt" <<EOF
project=ConectaEduca
target=$TARGET
git_commit=$REF_SHA
git_short=$SHORT_SHA
source_epoch=$SOURCE_EPOCH
source_utc=$STAMP
runtime_secrets_included=no
lab_runtime_included=no
twingate_active=no
wazuh_agent_fim_yara_activation=reserved_for_class
EOF

# Inventário de imagens declaradas nos YAMLs do pacote. Não resolve nem lê secrets.
{
    echo "# Referências image: declaradas no handoff $TARGET"
    grep -RhsE '^[[:space:]]*image:[[:space:]]*' "$STAGE/deploy" \
        | sed -E 's/^[[:space:]]*image:[[:space:]]*//' \
        | sed -E 's/[[:space:]]+#.*$//' \
        | sort -u
} > "$STAGE/IMAGES.txt"

# Denylist por caminho.
mapfile -t BAD_PATHS < <(
    find "$STAGE" -type f -printf '%P\n' \
        | grep -E \
          '(^|/)\.runtime(/|$)|(^|/)\.env$|(^|/)(role-id|secret-id)$|unseal-share|root-token|(^|/).*\.key$|(^|/).*\.pem$|(^|/)deploy/lab(/|$)|mailpit|filedaemon-lab|fd-lab-(source|restore)' \
        || true
)

if ((${#BAD_PATHS[@]})); then
    printf 'ERRO: caminhos proibidos no handoff:\n' >&2
    printf ' - %s\n' "${BAD_PATHS[@]}" >&2
    exit 1
fi

# Não permita chave privada materializada em conteúdo rastreado.
if grep -RIlE -- \
    '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----' \
    "$STAGE" 2>/dev/null | grep -q .
then
    echo "ERRO: cabeçalho de chave privada detectado no handoff." >&2
    exit 1
fi

# Regras específicas de alvo.
if [[ "$TARGET" == "dmz" ]]; then
    [[ ! -e "$STAGE/deploy/interna" ]] || {
        echo "ERRO: conteúdo de rede interna vazou para o pacote DMZ." >&2
        exit 1
    }
    [[ ! -e "$STAGE/deploy/dmz/compose.database.yml" ]] || {
        echo "ERRO: compose.database.yml não deve entrar na DMZ final." >&2
        exit 1
    }
else
    [[ ! -e "$STAGE/deploy/dmz" ]] || {
        echo "ERRO: conteúdo DMZ vazou para o pacote interno." >&2
        exit 1
    }
    if grep -RIlE \
        'conectaeduca-bacula-filedaemon-lab|fd-lab-source|fd-lab-restore' \
        "$STAGE/deploy/interna/bacula" 2>/dev/null | grep -q .
    then
        echo "ERRO: referência ao Bacula FD de laboratório entrou no handoff interno." >&2
        exit 1
    fi
fi

# Checksums internos.
(
    cd "$STAGE"
    find . -type f ! -name SHA256SUMS -print0 \
        | LC_ALL=C sort -z \
        | xargs -0 sha256sum
) > "$STAGE/SHA256SUMS"

BUNDLE="$OUTDIR/conectaeduca-handoff-$TARGET-$SHORT_SHA.tar.gz"

(
    cd "$TMP"
    tar \
        --sort=name \
        --mtime="@$SOURCE_EPOCH" \
        --owner=0 \
        --group=0 \
        --numeric-owner \
        -cf - "conectaeduca-$TARGET" \
        | gzip -n > "$BUNDLE"
)

echo "$BUNDLE"
