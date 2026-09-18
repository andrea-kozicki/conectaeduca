#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.0.0"
ACTION="${1:-check}"
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
WAZUH_DIR="$ROOT/deploy/interna/wazuh"
RUNTIME_DIR="$WAZUH_DIR/.runtime"
TARGET="$RUNTIME_DIR/wazuh.yml"

HELPER="/usr/local/libexec/conectaeduca-wazuh-yml-acl"
SERVICE="/etc/systemd/system/conectaeduca-wazuh-yml-acl.service"
PATH_UNIT="/etc/systemd/system/conectaeduca-wazuh-yml-acl.path"

TARGET_UID="1000"
STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
HOST_SHORT="$(hostname -s 2>/dev/null || printf unknown)"
OUT="${CONECTAEDUCA_EVIDENCE_DIR:-/var/tmp}/conectaeduca-wazuh-dashboard-acl-${HOST_SHORT}-${STAMP}-pid$$.txt"

PASS=0
WARN=0
FAIL=0
MUTATION_STARTED=0
ROLLBACK_USED=0

mkdir -p "$(dirname "$OUT")"
: >"$OUT"
chmod 0644 "$OUT"

log() {
    printf '%s\n' "$*"
    printf '%s\n' "$*" >>"$OUT"
}

pass() {
    PASS=$((PASS + 1))
    log "[PASS] $*"
}

warn() {
    WARN=$((WARN + 1))
    log "[WARN] $*"
}

fail() {
    FAIL=$((FAIL + 1))
    log "[FAIL] $*"
}

sha_file() {
    sha256sum "$1" | awk '{print $1}'
}

render_helper() {
    cat <<EOF
#!/bin/sh
set -eu

TARGET='$TARGET'
TARGET_UID='$TARGET_UID'

[ -f "\$TARGET" ] || exit 0

/usr/bin/setfacl -b -- "\$TARGET"
/usr/bin/chmod 0600 -- "\$TARGET"
/usr/bin/setfacl -m "u:\$TARGET_UID:r--,m::r--" -- "\$TARGET"
EOF
}

render_service() {
    cat <<EOF
[Unit]
Description=ConectaEduca - reaplicar ACL minima do Wazuh Dashboard
Documentation=file://$ROOT/docs/seguranca/WAZUH-INDEXER-DASHBOARD-RUNTIME-HARDENING.md

[Service]
Type=oneshot
ExecStart=$HELPER
User=root
Group=root
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$TARGET
EOF
}

render_path_unit() {
    cat <<EOF
[Unit]
Description=ConectaEduca - observar mudancas no runtime wazuh.yml

[Path]
PathChanged=$RUNTIME_DIR
Unit=conectaeduca-wazuh-yml-acl.service

[Install]
WantedBy=multi-user.target
EOF
}

validate_acl_text() {
    python3 -c '
import sys

owner = None
group = None
mask = None
other = None
named_users = {}
named_groups = {}

for raw in sys.stdin:
    line = raw.strip()
    if not line:
        continue
    if line.startswith("default:"):
        raise SystemExit(10)

    parts = line.split(":")
    if len(parts) != 3:
        raise SystemExit(11)

    kind, who, perms = parts

    if kind == "user":
        if who == "":
            owner = perms
        else:
            named_users[who] = perms
    elif kind == "group":
        if who == "":
            group = perms
        else:
            named_groups[who] = perms
    elif kind == "mask":
        if who != "":
            raise SystemExit(12)
        mask = perms
    elif kind == "other":
        if who != "":
            raise SystemExit(13)
        other = perms
    else:
        raise SystemExit(14)

ok = (
    owner in {"rw-", "r--"}
    and named_users == {"1000": "r--"}
    and named_groups == {}
    and group == "---"
    and mask == "r--"
    and other == "---"
)

raise SystemExit(0 if ok else 20)
'
}

validate_acl_live() {
    local acl_text mode

    mode="$(sudo -n stat -c '%a' -- "$TARGET")" || return 1
    [[ "$mode" == "640" || "$mode" == "440" ]] || return 1

    acl_text="$(sudo -n getfacl -cpn -- "$TARGET")" || return 1
    printf '%s\n' "$acl_text" | validate_acl_text
}

validate_installed_artifacts() {
    local helper_mode helper_owner
    local service_mode service_owner
    local path_mode path_owner

    helper_mode="$(sudo -n stat -c '%a' -- "$HELPER")" || return 1
    helper_owner="$(sudo -n stat -c '%U:%G' -- "$HELPER")" || return 1
    service_mode="$(sudo -n stat -c '%a' -- "$SERVICE")" || return 1
    service_owner="$(sudo -n stat -c '%U:%G' -- "$SERVICE")" || return 1
    path_mode="$(sudo -n stat -c '%a' -- "$PATH_UNIT")" || return 1
    path_owner="$(sudo -n stat -c '%U:%G' -- "$PATH_UNIT")" || return 1

    [[ "$helper_mode" == "755" && "$helper_owner" == "root:root" ]] || return 1
    [[ "$service_mode" == "644" && "$service_owner" == "root:root" ]] || return 1
    [[ "$path_mode" == "644" && "$path_owner" == "root:root" ]] || return 1

    sudo -n systemctl is-enabled --quiet conectaeduca-wazuh-yml-acl.path || return 1
    sudo -n systemctl is-active --quiet conectaeduca-wazuh-yml-acl.path || return 1
    validate_acl_live
}

write_atomic_root() {
    local path="$1"
    local mode="$2"
    local content="$3"
    local tmp="${path}.tmp-${STAMP}-$$"

    printf '%s' "$content" | sudo -n tee "$tmp" >/dev/null
    sudo -n chmod "$mode" "$tmp"
    sudo -n chown root:root "$tmp"
    sudo -n mv -f "$tmp" "$path"
}

self_test() {
    local valid invalid

    valid=$'user::rw-\nuser:1000:r--\ngroup::---\nmask::r--\nother::---\n'
    invalid=$'user::rw-\nuser:1000:rw-\ngroup::---\nmask::rw-\nother::---\n'

    printf '%s' "$valid" | validate_acl_text || {
        echo "SELF_TEST_WAZUH_DASHBOARD_ACL=FAIL valid_acl_rejected" >&2
        return 1
    }

    if printf '%s' "$invalid" | validate_acl_text; then
        echo "SELF_TEST_WAZUH_DASHBOARD_ACL=FAIL writable_acl_accepted" >&2
        return 1
    fi

    render_helper | grep -Fq '/usr/bin/setfacl -b' || {
        echo "SELF_TEST_WAZUH_DASHBOARD_ACL=FAIL helper_missing_acl_reset" >&2
        return 1
    }

    render_service | grep -Fq "ReadWritePaths=$TARGET" || {
        echo "SELF_TEST_WAZUH_DASHBOARD_ACL=FAIL service_missing_write_scope" >&2
        return 1
    }

    render_path_unit | grep -Fq "PathChanged=$RUNTIME_DIR" || {
        echo "SELF_TEST_WAZUH_DASHBOARD_ACL=FAIL path_missing_runtime_watch" >&2
        return 1
    }

    echo "SELF_TEST_WAZUH_DASHBOARD_ACL=PASS"
}

finish() {
    local rc=$?
    local final digest

    if [[ "$rc" -ne 0 && "$FAIL" -eq 0 ]]; then
        FAIL=$((FAIL + 1))
    fi

    if [[ "$FAIL" -gt 0 ]]; then
        final="FAIL"
    elif [[ "$WARN" -gt 0 ]]; then
        final="WARN"
    else
        final="PASS"
    fi

    log ""
    log "=== SUMMARY ==="
    log "PASS=$PASS"
    log "WARN=$WARN"
    log "FAIL=$FAIL"
    log "MUTATION_STARTED=$MUTATION_STARTED"
    log "ROLLBACK_USED=$ROLLBACK_USED"
    log "FINAL=$final"
    log "EVIDENCE_FILE=$OUT"

    digest="$(sha_file "$OUT")"
    printf 'SHA256=%s\n' "$digest"

    exit "$rc"
}

if [[ "$ACTION" == "--self-test" || "$ACTION" == "self-test" ]]; then
    self_test
    exit $?
fi

trap finish EXIT

log "=== CONECTAEDUCA — WAZUH DASHBOARD ACL RECONCILER ==="
log "VERSION=$VERSION"
log "ACTION=$ACTION"
log "TARGET=$TARGET"
log "TARGET_UID=$TARGET_UID"
log "ROOT_SHELL_USED=0"
log "SECRET_VALUE_PRINTED=0"

[[ -n "$ROOT" && -d "$ROOT/.git" ]] || {
    fail "Repositório ConectaEduca não localizado."
    exit 1
}

case "$ACTION" in
    check|apply)
        ;;
    *)
        fail "Uso: $0 {check|apply|--self-test}"
        exit 2
        ;;
esac

for cmd in python3 sha256sum stat systemctl getfacl setfacl sudo; do
    command -v "$cmd" >/dev/null 2>&1 || {
        fail "Comando ausente: $cmd"
        exit 1
    }
done
pass "Dependências locais disponíveis."

[[ -f "$TARGET" ]] || {
    fail "Runtime wazuh.yml ausente: $TARGET"
    exit 1
}
pass "wazuh.yml runtime localizado."

if [[ "$ACTION" == "check" ]]; then
    if validate_installed_artifacts; then
        pass "Watcher e ACL mínima estão íntegros."
        log "WAZUH_DASHBOARD_ACL_REPRODUCIBLE=1"
        log "NEXT_GATE=NONE"
        exit 0
    fi

    warn "Watcher/ACL não estão integralmente materializados."
    log "WAZUH_DASHBOARD_ACL_REPRODUCIBLE=0"
    log "NEXT_GATE=RUN_APPLY"
    exit 10
fi

log "$ sudo -v"
sudo -v
pass "sudo autenticado para comandos pontuais."

printf 'Digite APPLY para reconciliar o watcher de ACL do Wazuh Dashboard: '
read -r confirm
if [[ "$confirm" != "APPLY" ]]; then
    warn "APPLY cancelado pelo operador."
    exit 11
fi

BACKUP_DIR="/var/tmp/conectaeduca-wazuh-dashboard-acl-backup-${STAMP}-pid$$"
sudo -n install -d -m 0700 -o root -g root "$BACKUP_DIR"

OLD_HELPER=0
OLD_SERVICE=0
OLD_PATH=0
OLD_ENABLED=0
OLD_ACTIVE=0

if sudo -n test -e "$HELPER"; then
    sudo -n cp -a "$HELPER" "$BACKUP_DIR/helper.before"
    OLD_HELPER=1
fi
if sudo -n test -e "$SERVICE"; then
    sudo -n cp -a "$SERVICE" "$BACKUP_DIR/service.before"
    OLD_SERVICE=1
fi
if sudo -n test -e "$PATH_UNIT"; then
    sudo -n cp -a "$PATH_UNIT" "$BACKUP_DIR/path.before"
    OLD_PATH=1
fi
if sudo -n systemctl is-enabled --quiet conectaeduca-wazuh-yml-acl.path; then
    OLD_ENABLED=1
fi
if sudo -n systemctl is-active --quiet conectaeduca-wazuh-yml-acl.path; then
    OLD_ACTIVE=1
fi

pass "Estado anterior e backups privados registrados."

rollback() {
    ROLLBACK_USED=1
    warn "Rollback do watcher Wazuh iniciado."

    sudo -n systemctl disable --now conectaeduca-wazuh-yml-acl.path >/dev/null 2>&1 || true

    if [[ "$OLD_HELPER" -eq 1 ]]; then
        sudo -n cp -a "$BACKUP_DIR/helper.before" "$HELPER"
    else
        sudo -n rm -f "$HELPER"
    fi

    if [[ "$OLD_SERVICE" -eq 1 ]]; then
        sudo -n cp -a "$BACKUP_DIR/service.before" "$SERVICE"
    else
        sudo -n rm -f "$SERVICE"
    fi

    if [[ "$OLD_PATH" -eq 1 ]]; then
        sudo -n cp -a "$BACKUP_DIR/path.before" "$PATH_UNIT"
    else
        sudo -n rm -f "$PATH_UNIT"
    fi

    sudo -n systemctl daemon-reload || true

    if [[ "$OLD_ENABLED" -eq 1 ]]; then
        sudo -n systemctl enable conectaeduca-wazuh-yml-acl.path >/dev/null 2>&1 || true
    fi
    if [[ "$OLD_ACTIVE" -eq 1 ]]; then
        sudo -n systemctl start conectaeduca-wazuh-yml-acl.path >/dev/null 2>&1 || true
    fi
}

MUTATION_STARTED=1

set +e
{
    helper_content="$(render_helper)"
    service_content="$(render_service)"
    path_content="$(render_path_unit)"

    sudo -n install -d -m 0755 -o root -g root /usr/local/libexec
    write_atomic_root "$HELPER" 0755 "$helper_content"
    write_atomic_root "$SERVICE" 0644 "$service_content"
    write_atomic_root "$PATH_UNIT" 0644 "$path_content"

    sudo -n systemctl daemon-reload
    sudo -n systemctl enable --now conectaeduca-wazuh-yml-acl.path
    sudo -n systemctl start conectaeduca-wazuh-yml-acl.service

    "$HELPER" >/dev/null 2>&1
    "$HELPER" >/dev/null 2>&1

    validate_installed_artifacts
}
apply_rc=$?
set -e

if [[ "$apply_rc" -ne 0 ]]; then
    fail "Reconciliação falhou; restaurando estado anterior."
    rollback
    exit 1
fi

pass "Helper/service/path promovidos e idempotência executada duas vezes."
pass "ACL mínima UID 1000 read-only validada."

log "HELPER_SHA256=$(sudo -n sha256sum "$HELPER" | awk '{print $1}')"
log "SERVICE_SHA256=$(sudo -n sha256sum "$SERVICE" | awk '{print $1}')"
log "PATH_UNIT_SHA256=$(sudo -n sha256sum "$PATH_UNIT" | awk '{print $1}')"
log "WAZUH_DASHBOARD_ACL_REPRODUCIBLE=1"
log "ROLLBACK_USED=0"
log "NEXT_GATE=VALIDATE_DASHBOARD_READ_AND_OPERATIONAL_WAZUH"
