#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="3.1.0"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEFAULT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
ROLE="${1:-}"
REPO="${2:-${PROJECT_ROOT:-$DEFAULT_ROOT}}"
STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
HOST_SHORT="$(hostname -s 2>/dev/null || printf unknown)"
OUT="${CONECTAEDUCA_EVIDENCE_DIR:-/var/tmp}/conectaeduca-bacula-fd-bootstrap-${ROLE:-unknown}-${HOST_SHORT}-${STAMP}-pid$$.txt"

PASS=0
WARN=0
FAIL=0
POLICY_CREATED=0
AUTO_START_OBSERVED=0
POLICY_RC="/usr/sbin/policy-rc.d"
PACKAGE="bacula-client"
SERVICE="bacula-fd.service"
BACULA_FD_BIN="/opt/bacula/bin/bacula-fd"
BACULA_ETC="/opt/bacula/etc"
EFFECTIVE_CONFIG="${BACULA_ETC}/bacula-fd.conf"
CANDIDATE_CONFIG="${BACULA_ETC}/bacula-fd.conf.conectaeduca"

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
    return 1
}

cleanup_policy() {
    if [[ "$POLICY_CREATED" -eq 1 ]]; then
        rm -f -- "$POLICY_RC" || true
        POLICY_CREATED=0
    fi
}

finish() {
    rc=$?
    cleanup_policy

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
    log "FINAL=$final"
    log "SERVICE_ACTIVATED=0"
    log "AUTO_START_OBSERVED=$AUTO_START_OBSERVED"
    log "EFFECTIVE_CONFIG_OVERWRITTEN=0"
    log "RUNTIME_SECRET_PRINTED=0"
    log "ROOT_SHELL_USED=0"
    log "EVIDENCE_FILE=$OUT"

    digest="$(sha256sum "$OUT" | awk '{print $1}')"
    printf '%s  %s\n' "$digest" "$(basename "$OUT")" >"$OUT.sha256"
    printf 'SHA256=%s\n' "$digest"
    printf 'SHA256_FILE=%s\n' "$OUT.sha256"

    exit "$rc"
}

trap finish EXIT
trap 'exit 130' INT TERM

log "=== CONECTAEDUCA — BACULA FD PACKAGE BOOTSTRAP ==="
log "VERSION=$VERSION"
log "MODE=PREPARE_ONLY"
log "PACKAGE=$PACKAGE"
log "SERVICE_ACTIVATED=0"
log "RUNTIME_SECRET_PRINTED=0"
log "ROOT_SHELL_USED=0"
log "ROLE=${ROLE:-MISSING}"
log "REPO=$REPO"

if [[ "$EUID" -ne 0 ]]; then
    fail "Execute pontualmente com sudo: sudo $0 {dmz|interna} [caminho-repo]"
    exit 1
fi

case "$ROLE" in
    dmz)
        TEMPLATE="$REPO/deploy/dmz/bacula-fd/bacula-fd.conf.example"
        ;;
    interna)
        TEMPLATE="$REPO/deploy/interna/bacula/fd/bacula-fd.conf.example"
        ;;
    *)
        fail "Uso: sudo $0 {dmz|interna} [caminho-repo]"
        exit 2
        ;;
esac

[[ -f "$TEMPLATE" ]] || {
    fail "Template ausente: $TEMPLATE"
    exit 1
}
pass "Template localizado: $TEMPLATE"

COMPOSE_SOURCE=""
for candidate in \
    "$REPO/deploy/interna/bacula/compose.vm.yml" \
    "$REPO/deploy/interna/bacula/compose.yml"
do
    if [[ -f "$candidate" ]]; then
        COMPOSE_SOURCE="$candidate"
        break
    fi
done

[[ -n "$COMPOSE_SOURCE" ]] || {
    fail "Compose Bacula de referência não encontrado."
    exit 1
}

EXPECTED_VERSION="$(
    sed -nE \
        's/^[[:space:]]*image:[[:space:]]*conectaeduca\/bacula-director:([0-9]+\.[0-9]+\.[0-9]+).*$/\1/p' \
        "$COMPOSE_SOURCE" | head -n 1
)"

[[ "$EXPECTED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    fail "Não foi possível derivar a versão esperada do Director em $COMPOSE_SOURCE."
    exit 1
}

log "BACULA_VERSION_SOURCE=$COMPOSE_SOURCE"
log "BACULA_EXPECTED_VERSION=$EXPECTED_VERSION"
pass "Versão esperada derivada do Director versionado."

command -v apt-get >/dev/null 2>&1 || {
    fail "apt-get ausente; este bootstrap é específico para Ubuntu/Debian."
    exit 1
}
command -v apt-cache >/dev/null 2>&1 || {
    fail "apt-cache ausente."
    exit 1
}
command -v systemctl >/dev/null 2>&1 || {
    fail "systemctl ausente; não é possível garantir serviço inativo."
    exit 1
}

if systemctl is-active --quiet "$SERVICE"; then
    fail "$SERVICE já está ativo. Este bootstrap é para preparação/reconciliação controlada e recusa alterar runtime live."
    exit 1
fi
pass "Nenhum bacula-fd ativo será sobreposto pelo bootstrap."

log "$ apt-get update"
apt-get update >>"$OUT" 2>&1 || {
    fail "apt-get update falhou."
    exit 1
}
pass "Índice APT atualizado."

POLICY_OUTPUT="$(LC_ALL=C apt-cache policy "$PACKAGE")"
printf '%s\n' "$POLICY_OUTPUT" >>"$OUT"

APT_CANDIDATE="$(
    printf '%s\n' "$POLICY_OUTPUT" |
        awk '/^[[:space:]]*Candidate:/ {print $2; exit}'
)"

if [[ -z "$APT_CANDIDATE" || "$APT_CANDIDATE" == "(none)" ]]; then
    fail "Nenhum candidato APT disponível para $PACKAGE."
    exit 1
fi

log "BACULA_CLIENT_APT_CANDIDATE=$APT_CANDIDATE"

case "$APT_CANDIDATE" in
    "$EXPECTED_VERSION"|"$EXPECTED_VERSION"-*|"$EXPECTED_VERSION"+*|"$EXPECTED_VERSION"~*)
        pass "Candidato $PACKAGE compatível com o Director $EXPECTED_VERSION."
        ;;
    *)
        fail "Candidato $APT_CANDIDATE de $PACKAGE não corresponde ao Director $EXPECTED_VERSION."
        exit 1
        ;;
esac

EXPECTED_REPO="https://www.bacula.org/packages/community/debs/$EXPECTED_VERSION"
if ! printf '%s\n' "$POLICY_OUTPUT" | grep -Fq "$EXPECTED_REPO"; then
    fail "Candidato compatível não foi comprovado no repositório Bacula Community esperado: $EXPECTED_REPO"
    exit 1
fi
pass "Origem APT Bacula Community $EXPECTED_VERSION comprovada."

SIM_OUTPUT="$(
    apt-get -s --no-install-recommends install "$PACKAGE=$APT_CANDIDATE" 2>&1
)" || {
    printf '%s\n' "$SIM_OUTPUT" >>"$OUT"
    fail "Simulação APT para $PACKAGE=$APT_CANDIDATE falhou."
    exit 1
}
printf '%s\n' "$SIM_OUTPUT" >>"$OUT"
if printf '%s\n' "$SIM_OUTPUT" | grep -Eq '^(Remv|Purg)[[:space:]]'; then
    fail "Simulação APT prevê remoção de pacote; bootstrap recusado."
    exit 1
fi
pass "Simulação APT não prevê remoções."

if [[ -e "$POLICY_RC" ]]; then
    set +e
    "$POLICY_RC" bacula-fd start >/dev/null 2>&1
    policy_rc=$?
    set -e

    log "EXISTING_POLICY_RC_D_RESULT=$policy_rc"

    if [[ "$policy_rc" -ne 101 ]]; then
        fail "policy-rc.d existente não comprovou bloqueio (esperado rc=101); instalação recusada."
        exit 1
    fi

    pass "policy-rc.d existente já bloqueia auto-start."
else
    cat >"$POLICY_RC" <<'EOF_POLICY'
#!/bin/sh
# ConectaEduca: bloqueio temporário de auto-start durante bootstrap do Bacula FD.
exit 101
EOF_POLICY
    chmod 0755 "$POLICY_RC"
    POLICY_CREATED=1
    pass "policy-rc.d temporário instalado para impedir auto-start."
fi

log "$ apt-get install -y --no-install-recommends $PACKAGE=$APT_CANDIDATE"
DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends "$PACKAGE=$APT_CANDIDATE" >>"$OUT" 2>&1 || {
        fail "Instalação de $PACKAGE falhou."
        exit 1
    }

if systemctl is-active --quiet "$SERVICE"; then
    AUTO_START_OBSERVED=1
    systemctl stop "$SERVICE" >/dev/null 2>&1 || true
    fail "$SERVICE iniciou durante a instalação apesar do policy-rc.d; serviço foi parado e o bootstrap abortou."
    exit 1
fi

cleanup_policy
pass "Pacote $PACKAGE instalado sem auto-start observado."

INSTALLED_VERSION="$(
    dpkg-query -W -f='${Version}' "$PACKAGE" 2>/dev/null || true
)"

[[ -n "$INSTALLED_VERSION" ]] || {
    fail "dpkg-query não confirmou $PACKAGE instalado."
    exit 1
}

log "BACULA_CLIENT_PACKAGE=$INSTALLED_VERSION"

case "$INSTALLED_VERSION" in
    "$EXPECTED_VERSION"|"$EXPECTED_VERSION"-*|"$EXPECTED_VERSION"+*|"$EXPECTED_VERSION"~*)
        pass "Versão instalada permanece compatível com o Director."
        ;;
    *)
        fail "Versão instalada $INSTALLED_VERSION diverge do Director $EXPECTED_VERSION."
        exit 1
        ;;
esac

[[ -x "$BACULA_FD_BIN" ]] || {
    fail "Binário esperado ausente após instalação: $BACULA_FD_BIN"
    exit 1
}
pass "Binário package-based localizado em $BACULA_FD_BIN."

[[ -d "$BACULA_ETC" && ! -L "$BACULA_ETC" ]] || {
    fail "Diretório Bacula esperado ausente ou inseguro: $BACULA_ETC"
    exit 1
}

systemctl disable "$SERVICE" >/dev/null 2>&1 || true
systemctl mask "$SERVICE" >/dev/null 2>&1 || {
    fail "Não foi possível mascarar $SERVICE."
    exit 1
}
pass "$SERVICE permanece desabilitado/mascarado até ativação controlada."

if systemctl is-active --quiet "$SERVICE"; then
    fail "$SERVICE está ativo após o gate de preparação."
    exit 1
fi
pass "Serviço Bacula FD comprovadamente inativo."

tmp_candidate="$(mktemp "$BACULA_ETC/.bacula-fd.conf.conectaeduca.XXXXXX")"
chmod 0600 "$tmp_candidate"
cp -- "$TEMPLATE" "$tmp_candidate"
chown root:root "$tmp_candidate"

if [[ -e "$CANDIDATE_CONFIG" ]]; then
    if cmp -s -- "$tmp_candidate" "$CANDIDATE_CONFIG"; then
        rm -f -- "$tmp_candidate"
        pass "Candidato existente já corresponde ao template versionado."
    else
        rm -f -- "$tmp_candidate"
        fail "Candidato já existe e diverge do template; recusa de sobrescrita para não destruir possível materialização runtime."
        exit 1
    fi
else
    mv -- "$tmp_candidate" "$CANDIDATE_CONFIG"
    pass "Candidato materializado em $CANDIDATE_CONFIG como root:root 0600."
fi

if grep -q '__RUNTIME_SECRET_' "$CANDIDATE_CONFIG"; then
    warn "Placeholder runtime permanece; segredo/TLS devem ser materializados antes da ativação."
    log "BACULA_FD_CONFIG_STATUS=PENDING_RUNTIME_SECRET_AND_TLS"
    log "EFFECTIVE_CONFIG=$EFFECTIVE_CONFIG"
    log "CANDIDATE_CONFIG=$CANDIDATE_CONFIG"
    log "NEXT_GATE=MATERIALIZE_SECRET_TLS_VALIDATE_PROMOTE_AND_ACTIVATE"
    exit 0
fi

log "$ $BACULA_FD_BIN -t -c $CANDIDATE_CONFIG"
if "$BACULA_FD_BIN" -t -c "$CANDIDATE_CONFIG" >>"$OUT" 2>&1; then
    pass "Config candidato aprovado por bacula-fd -t."
    log "BACULA_FD_CONFIG_STATUS=SYNTAX_VALID_SERVICE_STILL_MASKED"
    log "NEXT_GATE=VALIDATE_TLS_PROMOTE_EFFECTIVE_CONFIG_AND_ACTIVATE"
else
    fail "bacula-fd -t rejeitou o candidato; serviço permanece mascarado."
    exit 1
fi
