#!/usr/bin/env bash
set -Eeuo pipefail

BUNDLE="${1:-}"
TARGET="${2:-}"

[[ -f "$BUNDLE" ]] || {
    echo "ERRO: bundle inexistente: $BUNDLE" >&2
    exit 1
}

case "$TARGET" in
    dmz|interna) ;;
    *)
        echo "Uso: $0 <bundle.tar.gz> {dmz|interna}" >&2
        exit 2
        ;;
esac

TMP="$(mktemp -d -t conectaeduca-verify-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

tar -xzf "$BUNDLE" -C "$TMP"
ROOT="$TMP/conectaeduca-$TARGET"

[[ -d "$ROOT" ]] || {
    echo "ERRO: raiz esperada não encontrada no bundle." >&2
    exit 1
}
read_bacula_version_manifest() {
    local path="$1"

    awk '
        BEGIN { found = 0; invalid = 0 }
        /^[[:space:]]*(#.*)?$/ { next }
        /^[[:space:]]*BACULA_VERSION[[:space:]]*=/ {
            if ($0 !~ /^[[:space:]]*BACULA_VERSION[[:space:]]*=[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$/) { invalid = 1; next }
            if (found != 0) { invalid = 1; next }
            value = $0
            sub(/^[[:space:]]*BACULA_VERSION[[:space:]]*=[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            found = 1
            next
        }
        { invalid = 1; next }
        END { if (invalid || found != 1) exit 1; print value }
    ' "$path"
}

bacula_fd_tls_contract_ok() {
    local path="$1"

    awk '
        BEGIN {
            enable_yes = 0
            enable_other = 0
            require_yes = 0
            require_other = 0
            verify_peer = 0
        }
        /^[[:space:]]*#/ { next }
        {
            line = $0
            sub(/[[:space:]]*#.*/, "", line)

            if (line ~ /^[[:space:]]*TLS[[:space:]]+Enable[[:space:]]*=/) {
                value = line
                sub(/^[[:space:]]*TLS[[:space:]]+Enable[[:space:]]*=[[:space:]]*/, "", value)
                sub(/[[:space:]]*$/, "", value)
                if (value == "yes") enable_yes++
                else enable_other++
            }

            if (line ~ /^[[:space:]]*TLS[[:space:]]+Require[[:space:]]*=/) {
                value = line
                sub(/^[[:space:]]*TLS[[:space:]]+Require[[:space:]]*=[[:space:]]*/, "", value)
                sub(/[[:space:]]*$/, "", value)
                if (value == "yes") require_yes++
                else require_other++
            }

            if (line ~ /^[[:space:]]*TLS[[:space:]]+Verify[[:space:]]+Peer[[:space:]]*=/) {
                verify_peer++
            }
        }
        END {
            if (
                enable_yes != 1 || enable_other != 0 ||
                require_yes != 1 || require_other != 0 ||
                verify_peer != 0
            ) exit 1
        }
    ' "$path"
}

BACULA_VERSION_MANIFEST="$ROOT/deploy/BACULA-VERSION.env"
[[ -f "$BACULA_VERSION_MANIFEST" && ! -L "$BACULA_VERSION_MANIFEST" ]] || {
    echo "ERRO: manifesto portátil Bacula ausente/inseguro." >&2
    exit 1
}
BACULA_VERSION="$(read_bacula_version_manifest "$BACULA_VERSION_MANIFEST")" || {
    echo "ERRO: manifesto BACULA_VERSION malformado no handoff; esperado exatamente BACULA_VERSION=X.Y.Z." >&2
    exit 1
}

(
    cd "$ROOT"
    sha256sum -c SHA256SUMS
)

[[ -f "$ROOT/RELEASE-METADATA.txt" ]] || {
    echo "ERRO: RELEASE-METADATA.txt ausente." >&2
    exit 1
}
grep -Eq '^git_commit=[0-9a-f]{40}$' "$ROOT/RELEASE-METADATA.txt" || {
    echo "ERRO: metadata sem git_commit válido." >&2
    exit 1
}
grep -Fxq "target=$TARGET" "$ROOT/RELEASE-METADATA.txt" || {
    echo "ERRO: target da metadata diverge do bundle." >&2
    exit 1
}
grep -Fxq 'runtime_secrets_included=no' "$ROOT/RELEASE-METADATA.txt" || {
    echo "ERRO: metadata não declara exclusão de runtime secrets." >&2
    exit 1
}
grep -Fxq 'source_checkout_required=no' "$ROOT/RELEASE-METADATA.txt" || {
    echo "ERRO: metadata não declara independência de checkout Git." >&2
    exit 1
}

mapfile -t BAD_PATHS < <(
    find "$ROOT" -type f -printf '%P\n' \
        | grep -E \
          '(^|/)\.runtime(/|$)|(^|/)\.env$|(^|/)(role-id|secret-id)$|unseal-share|root-token|(^|/).*\.key$|(^|/).*\.pem$|(^|/)deploy/lab(/|$)' \
        || true
)

if ((${#BAD_PATHS[@]})); then
    printf 'ERRO: caminhos proibidos encontrados:\n' >&2
    printf ' - %s\n' "${BAD_PATHS[@]}" >&2
    exit 1
fi

if grep -RIlE -- \
    '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----' \
    "$ROOT" 2>/dev/null | grep -q .
then
    echo "ERRO: chave privada detectada." >&2
    exit 1
fi

[[ -f "$ROOT/scripts/evidencias/checkpoint_portabilidade_containers.sh" ]] || {
    echo "ERRO: checkpoint de portabilidade ausente do handoff." >&2
    exit 1
}
[[ -f "$ROOT/scripts/release/smoke_handoff.sh" ]] || {
    echo "ERRO: smoke harness ausente do handoff." >&2
    exit 1
}
bash -n "$ROOT/scripts/evidencias/checkpoint_portabilidade_containers.sh"
bash -n "$ROOT/scripts/release/smoke_handoff.sh"

mapfile -t SCRIPT_FILES < <(
    find \
        "$ROOT/scripts/bootstrap" \
        "$ROOT/scripts/implantacao" \
        "$ROOT/scripts/recuperacao" \
        "$ROOT/scripts/dlp" \
        "$ROOT/scripts/evidencias" \
        "$ROOT/scripts/observabilidade" \
        -type f \
        \( -name '*.sh' -o -name '*.fish' -o -name '*.py' \) \
        -print 2>/dev/null
)

if ((${#SCRIPT_FILES[@]})) && grep -IlE \
    '/srv/www/htdocs/conectaeduca|(^|[^A-Za-z_])(ROOT|REPO)="/opt/conectaeduca"|git[[:space:]]+rev-parse[[:space:]]+--show-toplevel' \
    "${SCRIPT_FILES[@]}" 2>/dev/null | grep -q .
then
    echo "ERRO: script do handoff depende de raiz fixa ou checkout Git:" >&2
    grep -IlE \
        '/srv/www/htdocs/conectaeduca|(^|[^A-Za-z_])(ROOT|REPO)="/opt/conectaeduca"|git[[:space:]]+rev-parse[[:space:]]+--show-toplevel' \
        "${SCRIPT_FILES[@]}" 2>/dev/null \
        | sed "s#^$ROOT/##" >&2
    exit 1
fi

if [[ "$TARGET" == "dmz" ]]; then
    [[ ! -e "$ROOT/deploy/interna" ]] || exit 1
    [[ ! -e "$ROOT/deploy/dmz/compose.database.yml" ]] || exit 1
    [[ -f "$ROOT/deploy/dmz/bacula-fd/bacula-fd.conf.example" ]] || exit 1
    DMZ_FD_TEMPLATE="$ROOT/deploy/dmz/bacula-fd/bacula-fd.conf.example"
    bacula_fd_tls_contract_ok "$DMZ_FD_TEMPLATE" || {
        echo "ERRO: template Bacula FD DMZ divergiu do contrato TLS ativo." >&2
        exit 1
    }
    [[ -x "$ROOT/scripts/implantacao/preparar_bacula_fd_ubuntu.sh" ]] || {
        echo "ERRO: bootstrap Bacula DMZ ausente ou sem bit executável." >&2
        exit 1
    }
    grep -Fq 'deploy/BACULA-VERSION.env' "$ROOT/scripts/implantacao/preparar_bacula_fd_ubuntu.sh" || {
        echo "ERRO: bootstrap Bacula DMZ não usa manifesto portátil de versão." >&2
        exit 1
    }
else
    [[ ! -e "$ROOT/deploy/dmz" ]] || exit 1
    [[ ! -e "$ROOT/deploy/interna/wazuh/compose.lab.yml" ]] || exit 1
    [[ -f "$ROOT/deploy/interna/bacula/compose.yml" ]] || exit 1
    [[ -f "$ROOT/deploy/interna/bacula/images/Dockerfile" ]] || exit 1
    [[ -f "$ROOT/deploy/interna/bacula/fd/bacula-fd.conf.example" ]] || exit 1
    INTERNAL_FD_TEMPLATE="$ROOT/deploy/interna/bacula/fd/bacula-fd.conf.example"
    bacula_fd_tls_contract_ok "$INTERNAL_FD_TEMPLATE" || {
        echo "ERRO: template Bacula FD interno divergiu do contrato TLS ativo." >&2
        exit 1
    }
    DIRECTOR_VERSION="$(
        sed -nE 's/^[[:space:]]*image:[[:space:]]*conectaeduca\/bacula-director:([0-9]+\.[0-9]+\.[0-9]+).*$/\1/p' \
            "$ROOT/deploy/interna/bacula/compose.yml" | head -n 1
    )"
    [[ "$DIRECTOR_VERSION" == "$BACULA_VERSION" ]] || {
        echo "ERRO: manifesto Bacula diverge do Director no handoff interno." >&2
        exit 1
    }
    [[ -f "$ROOT/deploy/interna/bacula/compose.storage-emulado.yml" ]] || {
        echo "ERRO: overlay do Storage emulado ausente do handoff interno." >&2
        exit 1
    }
    MIGRADOR="$ROOT/deploy/interna/bacula/preparar_storage_emulado.py"
    [[ -f "$MIGRADOR" ]] || {
        echo "ERRO: migrador fail-closed do Storage emulado ausente." >&2
        exit 1
    }
    python3 -m py_compile "$MIGRADOR" || {
        echo "ERRO: migrador do Storage emulado não compila." >&2
        exit 1
    }
    grep -Fq 'python3 preparar_storage_emulado.py check' "$ROOT/docs/release/HANDOFF-FINAL.md" || {
        echo "ERRO: handoff não exige preflight do Storage emulado." >&2
        exit 1
    }
    grep -Fq 'python3 preparar_storage_emulado.py apply' "$ROOT/docs/release/HANDOFF-FINAL.md" || {
        echo "ERRO: handoff não exige migração/ativação do Storage emulado." >&2
        exit 1
    }
    [[ -f "$ROOT/deploy/interna/twingate/compose.yml" ]] || {
        echo "ERRO: Twingate declarativo ausente do handoff interno." >&2
        exit 1
    }

    REQUIRED_INTERNAL_TOOLS=(
        scripts/implantacao/vms/10-interna/12-preparar-wazuh-runtime-vm.sh
        scripts/implantacao/vms/lib/comum.sh
        scripts/implantacao/instalar_ferret_operacao.sh
        scripts/implantacao/materializar_pentest_principal_uid.py
        scripts/bootstrap/preparar_ferret.sh
        scripts/dlp/processar_inbox_ferret.sh
        scripts/dlp/snapshot_ferret_input.py
        scripts/dlp/submeter_ferret_pentest.py
        scripts/dlp/sanitizar_ferret.py
        scripts/dlp/validar_eventos_ferret.py
        scripts/dlp/limpar_retencao_ferret.sh
        scripts/implantacao/instalar_openbao_wazuh_bridge.sh
        scripts/implantacao/ativar_twingate_connector.fish
        scripts/bootstrap/preparar_twingate_runtime.fish
        scripts/observabilidade/sanitizar_openbao_audit.py
        scripts/observabilidade/verificar_ferret_health.sh
        scripts/evidencias/checkpoint_openbao_bacula_readiness.sh
        scripts/evidencias/checkpoint_yara_antiapt_readiness.sh
        scripts/evidencias/checkpoint_twingate_readiness.sh
        scripts/evidencias/checkpoint_twingate_operacional.sh
    )

    for rel in "${REQUIRED_INTERNAL_TOOLS[@]}"; do
        [[ -f "$ROOT/$rel" ]] || {
            echo "ERRO: artefato operacional interno ausente: $rel" >&2
            exit 1
        }
    done

    WAZUH_CONFIG_PERM_PREFLIGHT="$ROOT/deploy/interna/wazuh/preparar-permissoes-config.sh"
    [[ -f "$WAZUH_CONFIG_PERM_PREFLIGHT" ]] || {
        echo "ERRO: preflight de permissões Wazuh ausente do handoff interno." >&2
        exit 1
    }
    bash -n "$WAZUH_CONFIG_PERM_PREFLIGHT" || {
        echo "ERRO: preflight de permissões Wazuh possui erro sintático." >&2
        exit 1
    }

    WAZUH_PERM_FIXTURE="$TMP/wazuh-perm-fixture"
    mkdir -p "$WAZUH_PERM_FIXTURE/config/decoders" "$WAZUH_PERM_FIXTURE/config/rules"
    printf '<decoder name="verify"/>\n' > "$WAZUH_PERM_FIXTURE/config/decoders/verify.xml"
    printf '<group name="verify"/>\n' > "$WAZUH_PERM_FIXTURE/config/rules/verify.xml"
    chmod 0600 \
        "$WAZUH_PERM_FIXTURE/config/decoders/verify.xml" \
        "$WAZUH_PERM_FIXTURE/config/rules/verify.xml"

    bash "$WAZUH_CONFIG_PERM_PREFLIGHT" "$WAZUH_PERM_FIXTURE" >/dev/null || {
        echo "ERRO: preflight de permissões Wazuh falhou no fixture isolado." >&2
        exit 1
    }
    [[ "$(stat -c '%a' "$WAZUH_PERM_FIXTURE/config/decoders/verify.xml")" == "644" ]] || {
        echo "ERRO: preflight Wazuh não normalizou decoder para 0644." >&2
        exit 1
    }
    [[ "$(stat -c '%a' "$WAZUH_PERM_FIXTURE/config/rules/verify.xml")" == "644" ]] || {
        echo "ERRO: preflight Wazuh não normalizou rule para 0644." >&2
        exit 1
    }

    PENTEST_UID_MATERIALIZER="$ROOT/scripts/implantacao/materializar_pentest_principal_uid.py"
    grep -Fq 'TARGET = Path("/etc/conectaeduca/pentest-principal.uid")' "$PENTEST_UID_MATERIALIZER" || {
        echo "ERRO: materializador UID do pentest perdeu o contrato canônico." >&2
        exit 1
    }
    grep -Fq 'parser.add_argument("--principal", required=True' "$PENTEST_UID_MATERIALIZER" || {
        echo "ERRO: materializador UID do pentest não exige principal explícito." >&2
        exit 1
    }
    grep -Fq 'if os.geteuid() != 0:' "$PENTEST_UID_MATERIALIZER" || {
        echo "ERRO: materializador UID do pentest perdeu o gate root pré-corte." >&2
        exit 1
    }

    DIRECTOR_DB_BOOTSTRAP="$ROOT/scripts/bootstrap/preparar_bacula_director_db.fish"
    grep -Eq "^[[:space:]]*echo 'BACULA_DB_HOST=/run/pgbouncer'[[:space:]]*$"         "$DIRECTOR_DB_BOOTSTRAP" || {
            echo "ERRO: bootstrap do Director não aponta para /run/pgbouncer." >&2
            exit 1
        }
    grep -Eq "^[[:space:]]*echo 'BACULA_DB_PORT=6432'[[:space:]]*$"         "$DIRECTOR_DB_BOOTSTRAP" || {
            echo "ERRO: bootstrap do Director não aponta para porta 6432." >&2
            exit 1
        }
    if grep -Eq "BACULA_DB_HOST=(catalog|postgres)|BACULA_DB_PORT=5432"         "$DIRECTOR_DB_BOOTSTRAP"; then
        echo "ERRO: bootstrap do Director reintroduziu acesso direto ao PostgreSQL." >&2
        exit 1
    fi

    FORBIDDEN_INTERNAL_TOOLS=(
        scripts/bootstrap/materializar_bacula_core.py
        scripts/bootstrap/preparar_bacula_core.fish
        scripts/bootstrap/preparar_ferret.fish
        scripts/bootstrap/subir_ferret.fish
        scripts/bootstrap/parar_ferret.fish
        scripts/dlp/processar_inbox_ferret.fish
        scripts/bootstrap/provisionar_openbao_smtp.py
        scripts/bootstrap/operacionalizar_openbao_smtp.fish
        scripts/bootstrap/materializar_openbao_smtp_runtime.py
        scripts/bootstrap/materializar_openbao_smtp_runtime.fish
        scripts/recuperacao/recuperar_approle_smtp_pos_reboot.py
        deploy/interna/openbao/OPERACIONAL-SMTP.md
        deploy/interna/openbao/policies/conectaeduca-smtp-read.hcl
        scripts/evidencias/checkpoint_bacula_fd_vm_readiness.sh
        scripts/evidencias/checkpoint_bacula_openbao_raft_final.sh
        scripts/evidencias/checkpoint_wazuh_handoff.sh
        scripts/evidencias/verificar_segredos_estaticos.py
    )

    grep -Fxq 'bacula_final_runtime_materialization=host_gate' "$ROOT/RELEASE-METADATA.txt" || {
        echo "ERRO: gate de materialização final Bacula não está explícito." >&2
        exit 1
    }
    grep -Fxq 'bacula_director_config_source=external_volume_director_config' "$ROOT/RELEASE-METADATA.txt" || {
        echo "ERRO: fonte canônica do Director não está declarada como volume externo." >&2
        exit 1
    }
    grep -Fxq 'bacula_director_db_transport=pgbouncer_unix_socket_6432' "$ROOT/RELEASE-METADATA.txt" || {
        echo "ERRO: transporte final Director -> Catalog não está fixado em PgBouncer/socket 6432." >&2
        exit 1
    }
    grep -Fxq 'bacula_host_baseline_role=rollback_only' "$ROOT/RELEASE-METADATA.txt" || {
        echo "ERRO: baseline host do Bacula não está declarada como rollback-only." >&2
        exit 1
    }
    grep -Fxq 'openbao_smtp_cross_vm_included=no' "$ROOT/RELEASE-METADATA.txt" || {
        echo "ERRO: integração SMTP cross-VM deve permanecer fora do handoff." >&2
        exit 1
    }
    grep -Fxq 'openbao_smtp_cross_vm_status=not_enabled' "$ROOT/RELEASE-METADATA.txt" || {
        echo "ERRO: status SMTP cross-VM não está declarado como não habilitado." >&2
        exit 1
    }
    grep -Fxq 'twingate_artifacts_included=yes' "$ROOT/RELEASE-METADATA.txt" || {
        echo "ERRO: metadata não confirma artefatos Twingate no handoff interno." >&2
        exit 1
    }

    for rel in "${FORBIDDEN_INTERNAL_TOOLS[@]}"; do
        [[ ! -e "$ROOT/$rel" ]] || {
            echo "ERRO: rota de fonte/lab/integração futura entrou no handoff final: $rel" >&2
            exit 1
        }
    done

    for wazuh_tool in \
        scripts/implantacao/reconciliar_wazuh_api_pki.py \
        scripts/implantacao/reconciliar_wazuh_teste_readonly.py \
        scripts/implantacao/reconciliar_wazuh_dashboard_acl.sh \
        scripts/implantacao/validar_wazuh_operacional.sh
    do
        [[ -f "$ROOT/$wazuh_tool" ]] || {
            echo "ERRO: ferramenta Wazuh reproduzível ausente: $wazuh_tool" >&2
            exit 1
        }
    done

    python3 -m py_compile \
        "$ROOT/scripts/implantacao/reconciliar_wazuh_api_pki.py" \
        "$ROOT/scripts/implantacao/reconciliar_wazuh_teste_readonly.py" \
        "$ROOT/scripts/implantacao/materializar_pentest_principal_uid.py" \
        "$ROOT/scripts/dlp/snapshot_ferret_input.py" \
        "$ROOT/scripts/dlp/submeter_ferret_pentest.py" \
        "$ROOT/scripts/observabilidade/sanitizar_openbao_audit.py" \
        "$ROOT/scripts/recuperacao/recuperar_approle_bacula_snapshot.py"

    [[ -x "$ROOT/scripts/implantacao/reconciliar_wazuh_dashboard_acl.sh" ]] || {
        echo "ERRO: reconciliador Wazuh Dashboard ACL sem bit executável no handoff." >&2
        exit 1
    }

    bash -n \
        "$ROOT/scripts/implantacao/reconciliar_wazuh_dashboard_acl.sh" \
        "$ROOT/scripts/implantacao/validar_wazuh_operacional.sh" \
        "$ROOT/scripts/implantacao/vms/10-interna/12-preparar-wazuh-runtime-vm.sh" \
        "$ROOT/scripts/implantacao/vms/lib/comum.sh" \
        "$ROOT/scripts/implantacao/instalar_ferret_operacao.sh" \
        "$ROOT/scripts/implantacao/instalar_openbao_wazuh_bridge.sh" \
        "$ROOT/scripts/observabilidade/verificar_ferret_health.sh" \
        "$ROOT/scripts/evidencias/checkpoint_openbao_bacula_readiness.sh" \
        "$ROOT/scripts/evidencias/checkpoint_yara_antiapt_readiness.sh" \
        "$ROOT/scripts/evidencias/checkpoint_twingate_readiness.sh" \
        "$ROOT/scripts/evidencias/checkpoint_twingate_operacional.sh"

    grep -Eq '^[[:space:]]*-[[:space:]]+twingate[[:space:]]*$' \
        "$ROOT/deploy/interna/twingate/compose.yml" || {
            echo "ERRO: profile Twingate ausente." >&2
            exit 1
        }

    grep -Eq '^[[:space:]]*network_mode:[[:space:]]*host[[:space:]]*$' \
        "$ROOT/deploy/interna/twingate/compose.yml" || {
            echo "ERRO: network_mode host Twingate ausente." >&2
            exit 1
        }

    if grep -Eq '^[[:space:]]*(ports|volumes|devices|cap_add|privileged):' \
        "$ROOT/deploy/interna/twingate/compose.yml"; then
        echo "ERRO: superfície Twingate expandida sem aprovação." >&2
        exit 1
    fi

    mapfile -t BACULA_OPERATIONAL < <(
        find "$ROOT/deploy/interna/bacula" -type f \
            \( -name 'compose*.yml' -o -name 'compose*.yaml' -o \
               -name 'Dockerfile' -o -name '*.conf' -o -name '*.example' \) \
            -print
    )

    if ((${#BACULA_OPERATIONAL[@]})) && \
       grep -IlE \
         'conectaeduca-bacula-filedaemon-lab|filedaemon-lab|fd-lab-source|fd-lab-restore' \
         "${BACULA_OPERATIONAL[@]}" 2>/dev/null | grep -q .
    then
        echo "ERRO: material operacional do Bacula FD lab detectado." >&2
        exit 1
    fi

    grep -Eq '^FROM .* AS (director|storage)$' \
        "$ROOT/deploy/interna/bacula/images/Dockerfile" \
        || {
            echo "ERRO: Dockerfile Bacula final sem targets esperados." >&2
            exit 1
        }

    ! grep -Eqi '^FROM .* AS filedaemon$' \
        "$ROOT/deploy/interna/bacula/images/Dockerfile" \
        || {
            echo "ERRO: target filedaemon de laboratório presente no Dockerfile final." >&2
            exit 1
        }
fi

echo "HANDOFF_VERIFICADO=SIM"
echo "TARGET=$TARGET"
echo "BUNDLE_SHA256=$(sha256sum "$BUNDLE" | awk '{print $1}')"