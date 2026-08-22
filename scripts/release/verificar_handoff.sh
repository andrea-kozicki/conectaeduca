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
          '(^|/)\.runtime(/|$)|(^|/)\.env$|(^|/)(role-id|secret-id)$|unseal-share|root-token|(^|/).*\.key$|(^|/).*\.pem$|(^|/)deploy/lab(/|$)|mailpit|filedaemon-lab|fd-lab-(source|restore)' \
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
else
    [[ ! -e "$ROOT/deploy/dmz" ]] || exit 1
    [[ ! -e "$ROOT/deploy/interna/wazuh/compose.lab.yml" ]] || exit 1
    [[ -f "$ROOT/deploy/interna/bacula/compose.yml" ]] || exit 1
    [[ -f "$ROOT/deploy/interna/bacula/fd/bacula-fd.conf.example" ]] || exit 1
    if grep -RIlE \
        'conectaeduca-bacula-filedaemon-lab|fd-lab-source|fd-lab-restore' \
        "$ROOT/deploy/interna/bacula" 2>/dev/null | grep -q .
    then
        exit 1
    fi
fi

echo "HANDOFF_VERIFICADO=SIM"
echo "TARGET=$TARGET"
echo "BUNDLE_SHA256=$(sha256sum "$BUNDLE" | awk '{print $1}')"
