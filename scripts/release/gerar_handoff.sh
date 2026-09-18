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
        scripts/bootstrap/preparar_ferret.fish \
        scripts/bootstrap/subir_ferret.fish \
        scripts/bootstrap/parar_ferret.fish \
        scripts/bootstrap/preparar_twingate_runtime.fish \
        scripts/bootstrap/preparar_bacula_catalog.fish \
        scripts/bootstrap/materializar_bacula_catalog_secret.py \
        scripts/bootstrap/preparar_bacula_core.fish \
        scripts/bootstrap/preparar_bacula_director_db.fish \
        scripts/recuperacao/recuperar_approle_bacula_snapshot.py \
        scripts/observabilidade/sanitizar_openbao_audit.py \
        scripts/observabilidade/verificar_ferret_health.sh \
        scripts/dlp
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
twingate_active=no
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