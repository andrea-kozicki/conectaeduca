#!/bin/sh
set -eu

# O rootfs permanece read-only. O Compose fornece tmpfs vazios exatamente
# nos diretórios que o entrypoint upstream precisa materializar dinamicamente.
cp -a /usr/local/bootstrap/nginx/. /etc/nginx/
cp -a /usr/local/bootstrap/modsecurity.d/. /etc/modsecurity.d/
cp -a /usr/local/bootstrap/owasp-crs/. /opt/owasp-crs/

exit 0
