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

(
    cd "$ROOT"
    sha256sum -c SHA256SUMS
)

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
bash -n "$ROOT/scripts/evidencias/checkpoint_portabilidade_containers.sh"

if [[ "$TARGET" == "dmz" ]]; then
    [[ ! -e "$ROOT/deploy/interna" ]] || exit 1
    [[ ! -e "$ROOT/deploy/dmz/compose.database.yml" ]] || exit 1
    [[ -f "$ROOT/deploy/dmz/bacula-fd/bacula-fd.conf.example" ]] || exit 1
else
    [[ ! -e "$ROOT/deploy/dmz" ]] || exit 1
    [[ ! -e "$ROOT/deploy/interna/wazuh/compose.lab.yml" ]] || exit 1
    [[ -f "$ROOT/deploy/interna/bacula/compose.yml" ]] || exit 1
    [[ -f "$ROOT/deploy/interna/bacula/images/Dockerfile" ]] || exit 1
    [[ -f "$ROOT/deploy/interna/bacula/fd/bacula-fd.conf.example" ]] || exit 1
    [[ -f "$ROOT/deploy/interna/twingate/compose.yml" ]] || {
        echo "ERRO: Twingate declarativo ausente do handoff interno." >&2
        exit 1
    }

    REQUIRED_INTERNAL_TOOLS=(
        scripts/implantacao/vms/10-interna/12-preparar-wazuh-runtime-vm.sh
        scripts/implantacao/vms/lib/comum.sh
        scripts/implantacao/instalar_ferret_operacao.sh
        scripts/implantacao/instalar_openbao_wazuh_bridge.sh
        scripts/implantacao/ativar_twingate_connector.fish
        scripts/bootstrap/preparar_twingate_runtime.fish
        scripts/observabilidade/sanitizar_openbao_audit.py
        scripts/observabilidade/verificar_ferret_health.sh
        scripts/evidencias/checkpoint_twingate_readiness.sh
        scripts/evidencias/checkpoint_twingate_operacional.sh
    )

    for rel in "${REQUIRED_INTERNAL_TOOLS[@]}"; do
        [[ -f "$ROOT/$rel" ]] || {
            echo "ERRO: artefato operacional interno ausente: $rel" >&2
            exit 1
        }
    done

    # Rotas antigas de laboratório/futuras não pertencem ao handoff final.
    FORBIDDEN_INTERNAL_TOOLS=(
        scripts/bootstrap/materializar_bacula_core.py
        scripts/bootstrap/provisionar_openbao_smtp.py
        scripts/bootstrap/operacionalizar_openbao_smtp.fish
        scripts/bootstrap/materializar_openbao_smtp_runtime.py
        scripts/bootstrap/materializar_openbao_smtp_runtime.fish
        scripts/recuperacao/recuperar_approle_smtp_pos_reboot.py
    )

    for rel in "${FORBIDDEN_INTERNAL_TOOLS[@]}"; do
        [[ ! -e "$ROOT/$rel" ]] || {
            echo "ERRO: rota obsoleta/lab entrou no handoff final: $rel" >&2
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
        "$ROOT/scripts/implantacao/reconciliar_wazuh_teste_readonly.py"

    bash -n \
        "$ROOT/scripts/implantacao/reconciliar_wazuh_dashboard_acl.sh" \
        "$ROOT/scripts/implantacao/validar_wazuh_operacional.sh" \
        "$ROOT/scripts/implantacao/vms/10-interna/12-preparar-wazuh-runtime-vm.sh" \
        "$ROOT/scripts/implantacao/vms/lib/comum.sh" \
        "$ROOT/scripts/implantacao/instalar_ferret_operacao.sh" \
        "$ROOT/scripts/implantacao/instalar_openbao_wazuh_bridge.sh" \
        "$ROOT/scripts/observabilidade/verificar_ferret_health.sh" \
        "$ROOT/scripts/evidencias/checkpoint_twingate_readiness.sh" \
        "$ROOT/scripts/evidencias/checkpoint_twingate_operacional.sh"

    python3 -m py_compile \
        "$ROOT/scripts/observabilidade/sanitizar_openbao_audit.py"

    # Twingate precisa continuar opt-in, sem porta/volume/capability no Compose.
    grep -Eq '^[[:space:]]*-[[:space:]]+twingate[[:space:]]*
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
echo "BUNDLE_SHA256=$(sha256sum "$BUNDLE" | awk '{print $1}')" \
        "$ROOT/deploy/interna/twingate/compose.yml" || {
            echo "ERRO: profile Twingate ausente." >&2
            exit 1
        }
    grep -Eq '^[[:space:]]*network_mode:[[:space:]]*host[[:space:]]*
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
echo "BUNDLE_SHA256=$(sha256sum "$BUNDLE" | awk '{print $1}')" \
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