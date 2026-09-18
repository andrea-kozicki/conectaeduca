#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.0.0"
TARGET="${1:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="${PROJECT_ROOT:-$(cd -- "$SCRIPT_DIR/../.." && pwd -P)}"

PASS=0
FAIL=0

pass() {
    PASS=$((PASS + 1))
    printf '[PASS] %s\n' "$*"
}

fail() {
    FAIL=$((FAIL + 1))
    printf '[FAIL] %s\n' "$*" >&2
}

require_file() {
    local rel="$1"
    if [[ -f "$ROOT/$rel" ]]; then
        pass "arquivo presente: $rel"
    else
        fail "arquivo ausente: $rel"
    fi
}

require_absent() {
    local rel="$1"
    if [[ ! -e "$ROOT/$rel" ]]; then
        pass "artefato ausente como esperado: $rel"
    else
        fail "artefato proibido presente: $rel"
    fi
}

require_metadata() {
    local expected="$1"
    if grep -Fxq "$expected" "$ROOT/RELEASE-METADATA.txt"; then
        pass "metadata: $expected"
    else
        fail "metadata ausente/divergente: $expected"
    fi
}

printf '=== CONECTAEDUCA — HANDOFF SMOKE TEST ===\n'
printf 'VERSION=%s\n' "$VERSION"
printf 'TARGET=%s\n' "$TARGET"
printf 'ROOT=%s\n' "$ROOT"
printf 'MODE=READ_ONLY\n'
printf 'DOCKER_REQUIRED=0\n'
printf 'NETWORK_REQUIRED=0\n'
printf 'SYSTEMD_REQUIRED=0\n'
printf 'SECRET_REQUIRED=0\n'

case "$TARGET" in
    dmz|interna) ;;
    *)
        echo "Uso: $0 {dmz|interna}" >&2
        exit 2
        ;;
esac

[[ -d "$ROOT" ]] || {
    echo "FALHA: raiz do handoff ausente: $ROOT" >&2
    exit 1
}

if [[ -e "$ROOT/.git" ]]; then
    fail "bundle extraído não deve conter .git"
else
    pass "bundle executado fora de checkout Git"
fi

require_file RELEASE-METADATA.txt
require_file SHA256SUMS
require_file IMAGES.txt
require_file scripts/release/verificar_handoff.sh
require_file scripts/evidencias/checkpoint_portabilidade_containers.sh

if [[ -f "$ROOT/RELEASE-METADATA.txt" ]]; then
    require_metadata "project=ConectaEduca"
    require_metadata "target=$TARGET"
    require_metadata "runtime_secrets_included=no"
    require_metadata "lab_runtime_included=no"
    require_metadata "source_checkout_required=no"
fi

printf '%s\n' "--- sintaxe dos scripts do bundle ---"
while IFS= read -r -d '' file; do
    rel="${file#"$ROOT/"}"
    first="$(head -n 1 "$file" || true)"

    case "$file" in
        *.sh)
            if [[ "$first" == *bash* ]]; then
                if bash -n "$file"; then
                    pass "bash -n: $rel"
                else
                    fail "bash -n: $rel"
                fi
            else
                if sh -n "$file"; then
                    pass "sh -n: $rel"
                else
                    fail "sh -n: $rel"
                fi
            fi
            ;;
        *.py)
            if python3 -m py_compile "$file"; then
                pass "python compile: $rel"
            else
                fail "python compile: $rel"
            fi
            ;;
    esac
done < <(
    find "$ROOT/scripts" -type f \
        \( -name '*.sh' -o -name '*.py' \) \
        -print0 2>/dev/null
)

if [[ "$TARGET" == "dmz" ]]; then
    require_file deploy/dmz/compose.yml
    require_file deploy/dmz/compose.host.yml
    require_file deploy/dmz/bacula-fd/bacula-fd.conf.example
    require_file scripts/implantacao/preparar_bacula_fd_ubuntu.sh

    require_absent deploy/interna
    require_absent deploy/dmz/compose.database.yml

    if grep -q '__RUNTIME_SECRET_'         "$ROOT/deploy/dmz/bacula-fd/bacula-fd.conf.example"; then
        pass "Bacula FD DMZ mantém placeholder runtime sem segredo"
    else
        fail "template Bacula FD DMZ perdeu placeholder runtime"
    fi
else
    require_file deploy/interna/bacula/compose.yml
    require_file deploy/interna/bacula/images/Dockerfile
    require_file deploy/interna/bacula/fd/bacula-fd.conf.example
    require_file deploy/interna/twingate/compose.yml
    require_file scripts/bootstrap/preparar_bacula_director_db.fish
    require_file scripts/implantacao/reconciliar_wazuh_dashboard_acl.sh
    require_file scripts/implantacao/reconciliar_wazuh_api_pki.py
    require_file scripts/implantacao/reconciliar_wazuh_teste_readonly.py
    require_file scripts/implantacao/validar_wazuh_operacional.sh

    require_absent deploy/dmz
    require_absent deploy/interna/wazuh/compose.lab.yml
    require_absent deploy/interna/openbao/OPERACIONAL-SMTP.md
    require_absent deploy/interna/openbao/policies/conectaeduca-smtp-read.hcl
    require_absent scripts/bootstrap/materializar_bacula_core.py
    require_absent scripts/bootstrap/preparar_bacula_core.fish
    require_absent scripts/bootstrap/provisionar_openbao_smtp.py
    require_absent scripts/bootstrap/operacionalizar_openbao_smtp.fish
    require_absent scripts/bootstrap/materializar_openbao_smtp_runtime.py
    require_absent scripts/bootstrap/materializar_openbao_smtp_runtime.fish
    require_absent scripts/recuperacao/recuperar_approle_smtp_pos_reboot.py

    require_metadata "bacula_final_runtime_materialization=host_gate"
    require_metadata "bacula_director_config_source=external_volume_director_config"
    require_metadata "bacula_director_db_transport=pgbouncer_unix_socket_6432"
    require_metadata "bacula_host_baseline_role=rollback_only"
    require_metadata "openbao_smtp_cross_vm_included=no"
    require_metadata "openbao_smtp_cross_vm_status=not_enabled"
    require_metadata "twingate_artifacts_included=yes"
    require_metadata "twingate_active=no"

    DIRECTOR_DB="$ROOT/scripts/bootstrap/preparar_bacula_director_db.fish"
    if grep -Eq "^[[:space:]]*echo 'BACULA_DB_HOST=/run/pgbouncer'[[:space:]]*$"         "$DIRECTOR_DB"        && grep -Eq "^[[:space:]]*echo 'BACULA_DB_PORT=6432'[[:space:]]*$"         "$DIRECTOR_DB"; then
        pass "Director DB bootstrap usa PgBouncer Unix socket:6432"
    else
        fail "Director DB bootstrap diverge de PgBouncer Unix socket:6432"
    fi

    if grep -Eq 'filedaemon-lab|fd-lab-source|fd-lab-restore'         "$ROOT/deploy/interna/bacula/compose.yml"         "$ROOT/deploy/interna/bacula/images/Dockerfile"; then
        fail "Bacula lab reapareceu no runtime final"
    else
        pass "Bacula lab ausente do Compose/Dockerfile finais"
    fi

    TWINGATE="$ROOT/deploy/interna/twingate/compose.yml"
    if grep -Eq '^[[:space:]]*network_mode:[[:space:]]*host[[:space:]]*$' "$TWINGATE"        && grep -Fq 'no-new-privileges:true' "$TWINGATE"        && ! grep -Eq '^[[:space:]]*(ports|volumes|devices|cap_add|privileged):' "$TWINGATE"; then
        pass "Twingate declarativo mantém superfície aprovada"
    else
        fail "Twingate declarativo divergiu da superfície aprovada"
    fi

    if PROJECT_ROOT="$ROOT"         bash "$ROOT/scripts/implantacao/reconciliar_wazuh_dashboard_acl.sh"         --self-test; then
        pass "self-test Wazuh Dashboard ACL executa dentro do bundle"
    else
        fail "self-test Wazuh Dashboard ACL falhou dentro do bundle"
    fi
fi

printf '%s\n' ""
printf '=== SUMMARY ===\n'
printf 'PASS=%d\n' "$PASS"
printf 'FAIL=%d\n' "$FAIL"

if [[ "$FAIL" -ne 0 ]]; then
    printf 'HANDOFF_SMOKE=FAIL\n'
    exit 1
fi

printf 'HANDOFF_SMOKE=PASS\n'
printf 'TARGET=%s\n' "$TARGET"
