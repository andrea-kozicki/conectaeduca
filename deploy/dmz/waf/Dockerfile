# syntax=docker/dockerfile:1

FROM owasp/modsecurity-crs:4.25.1-nginx-lts@sha256:60af5abe3175856b8945d8827ab3f52e3906d66ebbb2c8617f45a771b38facad

ARG CONECTAEDUCA_SOURCE_COMMIT=UNSET

LABEL org.opencontainers.image.source="https://github.com/andrea-kozicki/conectaeduca" \
      org.opencontainers.image.revision="${CONECTAEDUCA_SOURCE_COMMIT}" \
      io.conectaeduca.build-policy="security-refresh-traceable"

USER 0

RUN test "${CONECTAEDUCA_SOURCE_COMMIT}" != "UNSET" \
    && apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && mkdir -p /usr/share/conectaeduca \
    && dpkg-query -W -f='${Package}\t${Version}\n' | sort \
        > /usr/share/conectaeduca/build-packages.txt \
    && printf '%s\n' \
        'component=waf-dmz' \
        'base=owasp/modsecurity-crs:4.25.1-nginx-lts@sha256:60af5abe3175856b8945d8827ab3f52e3906d66ebbb2c8617f45a771b38facad' \
        "source_commit=${CONECTAEDUCA_SOURCE_COMMIT}" \
        'package_policy=security-refresh-traceable' \
        > /usr/share/conectaeduca/build-provenance.txt \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p \
        /usr/local/bootstrap/nginx \
        /usr/local/bootstrap/modsecurity.d \
        /usr/local/bootstrap/owasp-crs \
        /run/conectaeduca-waf-policy \
    && cp -a /etc/nginx/. /usr/local/bootstrap/nginx/ \
    && cp -a /etc/modsecurity.d/. /usr/local/bootstrap/modsecurity.d/ \
    && cp -a /opt/owasp-crs/. /usr/local/bootstrap/owasp-crs/ \
    && touch /run/conectaeduca-waf-policy/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf \
    && chown -R nginx:nginx /usr/local/bootstrap /run/conectaeduca-waf-policy

COPY --chmod=0755 deploy/dmz/waf/00-conectaeduca-bootstrap-readonly.sh \
    /docker-entrypoint.d/00-conectaeduca-bootstrap-readonly.sh

USER nginx
