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

# Fonte exclusivamente versionada: arquivos locais/untracked jamais entram.
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

for rel in \
    README.md \
    .env.example \
    deploy/ARQUITETURA-VMs.md \
    deploy/CONTRATO-IMPLANTACAO.md \
    deploy/IMAGENS-VALIDADAS.md \
    docs/release/HANDOFF-FINAL.md \
    docs/release/INVENTARIO-COMPONENTES.md \
    scripts/release/inventariar_handoff.sh \
    scripts/release/verificar_handoff.sh \
    scripts/release/smoke_handoff.sh \
    scripts/evidencias/checkpoint_portabilidade_containers.sh
do
    copy_path "$rel"
done

if [[ "$TARGET" == "dmz" ]]; then
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
else
    copy_path sql
    copy_path deploy/interna/mariadb
    copy_path deploy/interna/openbao

    # Integração OpenBao -> SMTP cross-VM permanece futura/lab-only.
    # O handoff final não transporta policy nem runbook que possam sugerir
    # capacidade operacional habilitada.
    rm -f "$STAGE/deploy/interna/openbao/OPERACIONAL-SMTP.md"
    rm -f "$STAGE/deploy/interna/openbao/policies/conectaeduca-smtp-read.hcl"

    copy_path deploy/interna/ferret
    copy_path deploy/interna/wazuh
    copy_path deploy/interna/bacula
    copy_path deploy/interna/twingate

    # Substitui variantes de laboratório pelas variantes finais de VM.
    rm -f "$STAGE/deploy/interna/bacula/compose.yml"
    copy_path deploy/interna/bacula/compose.vm.yml
    mv "$STAGE/deploy/interna/bacula/compose.vm.yml" \
       "$STAGE/deploy/interna/bacula/compose.yml"

    rm -f "$STAGE/deploy/interna/bacula/images/Dockerfile"
    copy_path deploy/interna/bacula/images/Dockerfile.vm
    mv "$STAGE/deploy/interna/bacula/images/Dockerfile.vm" \
       "$STAGE/deploy/interna/bacula/images/Dockerfile"

    rm -f "$STAGE/deploy/interna/wazuh/compose.lab.yml"

    for rel in \
        scripts/implantacao/preparar_bacula_fd_ubuntu.sh \
        scripts/implantacao/reconciliar_wazuh_api_pki.py \
        scripts/implantacao/reconciliar_wazuh_teste_readonly.py \
        scripts/implantacao/reconciliar_wazuh_dashboard_acl.sh \
        scripts/implantacao/validar_wazuh_operacional.sh \
        scripts/implantacao/vms/10-interna/12-preparar-wazuh-runtime-vm.sh \
        scripts/implantacao/vms/lib/comum.sh \
        scripts/implantacao/instalar_ferret_operacao.sh \
        scripts/implantacao/instalar_openbao_wazuh_bridge.sh \
        scripts/implantacao/ativar_twingate_connector.fish \
        scripts/bootstrap/preparar_openbao.fish \
        scripts/bootstrap/preparar_ferret.sh \
        scripts/bootstrap/preparar_twingate_runtime.fish \
        scripts/bootstrap/preparar_bacula_catalog.fish \
        scripts/bootstrap/materializar_bacula_catalog_secret.py \
        scripts/bootstrap/preparar_bacula_director_db.fish \
        scripts/recuperacao/recuperar_approle_bacula_snapshot.py \
        scripts/observabilidade/sanitizar_openbao_audit.py \
        scripts/observabilidade/verificar_ferret_health.sh \
        scripts/dlp/processar_inbox_ferret.sh \
        scripts/dlp/sanitizar_ferret.py \
        scripts/dlp/validar_eventos_ferret.py \
        scripts/dlp/limpar_retencao_ferret.sh
    do
        copy_path "$rel"
    done

    for rel in \
        scripts/evidencias/checkpoint_openbao_bacula_readiness.sh \
        scripts/evidencias/checkpoint_yara_antiapt_readiness.sh \
        scripts/evidencias/checkpoint_twingate_readiness.sh \
        scripts/evidencias/checkpoint_twingate_operacional.sh
    do
        copy_path "$rel"
    done
fi

cat > "$STAGE/RELEASE-METADATA.txt" <<EOF
project=ConectaEduca
target=$TARGET
git_commit=$REF_SHA
git_short=$SHORT_SHA
source_epoch=$SOURCE_EPOCH
source_utc=$STAMP
runtime_secrets_included=no
lab_runtime_included=no
bacula_fd_container_lab_included=no
bacula_lab_materializer_included=no
bacula_final_runtime_materialization=host_gate
bacula_director_config_source=$([[ "$TARGET" == "interna" ]] && echo external_volume_director_config || echo not_applicable)
bacula_director_db_transport=$([[ "$TARGET" == "interna" ]] && echo pgbouncer_unix_socket_6432 || echo not_applicable)
bacula_host_baseline_role=$([[ "$TARGET" == "interna" ]] && echo rollback_only || echo not_applicable)
openbao_smtp_cross_vm_included=no
openbao_smtp_cross_vm_status=$([[ "$TARGET" == "interna" ]] && echo not_enabled || echo not_applicable)
twingate_artifacts_included=$([[ "$TARGET" == "interna" ]] && echo yes || echo no)
twingate_active=no
source_checkout_required=no
wazuh_agent_fim_yara_activation=reserved_for_class
EOF

{
    echo "# Referências image: declaradas no handoff $TARGET"
    grep -RhsE '^[[:space:]]*image:[[:space:]]*' "$STAGE/deploy" \
        | sed -E 's/^[[:space:]]*image:[[:space:]]*//' \
        | sed -E 's/[[:space:]]+#.*$//' \
        | sort -u
} > "$STAGE/IMAGES.txt"

# Denylist de arquivos/paths reais. Documentação pode mencionar itens de
# laboratório para registrar explicitamente que foram excluídos.
mapfile -t BAD_PATHS < <(
    find "$STAGE" -type f -printf '%P\n' \
        | grep -E \
          '(^|/)\.runtime(/|$)|(^|/)\.env$|(^|/)(role-id|secret-id)$|unseal-share|root-token|(^|/).*\.key$|(^|/).*\.pem$|(^|/)deploy/lab(/|$)' \
        || true
)

if ((${#BAD_PATHS[@]})); then
    printf 'ERRO: caminhos proibidos no handoff:\n' >&2
    printf ' - %s\n' "${BAD_PATHS[@]}" >&2
    exit 1
fi

if grep -RIlE -- \
    '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----' \
    "$STAGE" 2>/dev/null | grep -q .
then
    echo "ERRO: cabeçalho de chave privada detectado no handoff." >&2
    exit 1
fi

if [[ "$TARGET" == "dmz" ]]; then
    [[ ! -e "$STAGE/deploy/interna" ]] || {
        echo "ERRO: conteúdo interno vazou para o pacote DMZ." >&2
        exit 1
    }
    [[ ! -e "$STAGE/deploy/dmz/compose.database.yml" ]] || {
        echo "ERRO: compose.database.yml não pertence à DMZ final." >&2
        exit 1
    }
else
    [[ ! -e "$STAGE/deploy/dmz" ]] || {
        echo "ERRO: conteúdo DMZ vazou para o pacote interno." >&2
        exit 1
    }

    # Aqui a barreira olha somente artefatos executáveis/configuráveis,
    # não READMEs que documentam a exclusão do laboratório.
    mapfile -t BACULA_OPERATIONAL < <(
        find "$STAGE/deploy/interna/bacula" -type f \
            \( -name 'compose*.yml' -o -name 'compose*.yaml' -o \
               -name 'Dockerfile' -o -name '*.conf' -o -name '*.example' \) \
            -print
    )

    if ((${#BACULA_OPERATIONAL[@]})) && \
       grep -IlE \
         'conectaeduca-bacula-filedaemon-lab|filedaemon-lab|fd-lab-source|fd-lab-restore' \
         "${BACULA_OPERATIONAL[@]}" 2>/dev/null | grep -q .
    then
        echo "ERRO: referência operacional ao Bacula FD de laboratório entrou no handoff interno." >&2
        exit 1
    fi
fi

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