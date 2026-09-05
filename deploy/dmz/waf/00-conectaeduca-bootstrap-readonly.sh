#!/bin/sh
set -eu

# O rootfs permanece read-only. O Compose fornece tmpfs vazios exatamente
# nos diretórios que o entrypoint upstream precisa materializar dinamicamente.
cp -a /usr/local/bootstrap/nginx/. /etc/nginx/
cp -a /usr/local/bootstrap/modsecurity.d/. /etc/modsecurity.d/
cp -a /usr/local/bootstrap/owasp-crs/. /opt/owasp-crs/

# A policy local não é montada diretamente dentro do tmpfs de /etc/modsecurity.d.
# O bind read-only fica em staging e só então é copiado para a árvore efêmera.
if [ -r /run/conectaeduca-waf-policy/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf ]; then
    cp -f         /run/conectaeduca-waf-policy/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf         /etc/modsecurity.d/owasp-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
fi

exit 0
