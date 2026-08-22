#!/usr/bin/env bash
set -Eeuo pipefail

ROLE="${1:-}"
REPO="${2:-/srv/www/htdocs/conectaeduca}"

if [[ "$EUID" -ne 0 ]]; then
    echo "ERRO: execute como root/sudo na VM Ubuntu." >&2
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
        echo "Uso: sudo $0 {dmz|interna} [caminho-repo]" >&2
        exit 2
        ;;
esac

[[ -f "$TEMPLATE" ]] || {
    echo "ERRO: template ausente: $TEMPLATE" >&2
    exit 1
}

apt-get update
apt-get install -y --no-install-recommends bacula-fd

echo "BACULA_FD_PACKAGE=$(dpkg-query -W -f='${Version}' bacula-fd)"

install -d -m 0750 /etc/bacula
install -m 0640 "$TEMPLATE" /etc/bacula/bacula-fd.conf.conectaeduca

if grep -q '__RUNTIME_SECRET_' /etc/bacula/bacula-fd.conf.conectaeduca; then
    echo "PENDENTE: substitua o placeholder por segredo runtime e materialize TLS."
    echo "INFO: o serviço NÃO será iniciado automaticamente por este script."
    exit 0
fi

echo "INFO: template sem placeholder; valide com bacula-fd -t antes de habilitar."
