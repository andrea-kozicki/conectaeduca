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
        BEGIN {
            found = 0
            invalid = 0
        }

        /^[[:space:]]*(#.*)?$/ {
            next
        }

        /^[[:space:]]*BACULA_VERSION[[:space:]]*=/ {
            if ($0 !~ /^[[:space:]]*BACULA_VERSION[[:space:]]*=[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$/) {
                invalid = 1
                next
            }
            if (found != 0) {
                invalid = 1
                next
            }
            value = $0
            sub(/^[[:space:]]*BACULA_VERSION[[:space:]]*=[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            found = 1
            next
        }

        {
            invalid = 1
            next
        }

        END {
            if (invalid || found != 1) {
                exit 1
            }
            print value
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

if [[ "$TARGET" == "dmz" ]]; then
    [[ ! -e "$ROOT/deploy/interna" ]] || exit 1
    [[ ! -e "$ROOT/deploy/dmz/compose.database.yml" ]] || exit 1
    [[ -f "$ROOT/deploy/dmz/bacula-fd/bacula-fd.conf.example" ]] || exit 1
    [[ -x "$ROOT/scripts/implantacao/preparar_bacula_fd_ubuntu.sh" ]] || {
        echo "ERRO: bootstrap Bacula DMZ ausente ou sem bit executável." >&2
        exit 1
    }
    grep -Fq 'deploy/BACULA-VERSION.env'         "$ROOT/scripts/implantacao/preparar_bacula_fd_ubuntu.sh" || {
            echo "ERRO: bootstrap Bacula DMZ não usa manifesto portátil de versão." >&2
            exit 1
        }
else
    [[ ! -e "$ROOT/deploy/dmz" ]] || exit 1
    [[ ! -e "$ROOT/deploy/interna/wazuh/compose.lab.yml" ]] || exit 1
    [[ -f "$ROOT/deploy/interna/bacula/compose.yml" ]] || exit 1
    DIRECTOR_VERSION="$(
        sed -nE             's/^[[:space:]]*image:[[:space:]]*conectaeduca\/bacula-director:([0-9]+\.[0-9]+\.[0-9]+).*$/\1/p'             "$ROOT/deploy/interna/bacula/compose.yml" | head -n 1
    )"
    [[ "$DIRECTOR_VERSION" == "$BACULA_VERSION" ]] || {
        echo "ERRO: manifesto Bacula diverge do Director no handoff interno." >&2
        exit 1
    }
    [[ -f "$ROOT/deploy/interna/bacula/images/Dockerfile" ]] || exit 1
    [[ -f "$ROOT/deploy/interna/bacula/fd/bacula-fd.conf.example" ]] || exit 1
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

    grep -Fq 'python3 preparar_storage_emulado.py check' \
        "$ROOT/docs/release/HANDOFF-FINAL.md" || {
            echo "ERRO: handoff não exige preflight do Storage emulado." >&2
            exit 1
        }

    grep -Fq 'python3 preparar_storage_emulado.py apply' \
        "$ROOT/docs/release/HANDOFF-FINAL.md" || {
            echo "ERRO: handoff não exige migração/ativação do Storage emulado." >&2
            exit 1
        }

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

    [[ -x "$ROOT/scripts/implantacao/reconciliar_wazuh_dashboard_acl.sh" ]] || {
        echo "ERRO: reconciliador Wazuh Dashboard ACL sem bit executável no handoff." >&2
        exit 1
    }

    bash -n \
        "$ROOT/scripts/implantacao/reconciliar_wazuh_dashboard_acl.sh" \
        "$ROOT/scripts/implantacao/validar_wazuh_operacional.sh"

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