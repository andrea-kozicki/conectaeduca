# syntax=docker/dockerfile:1

FROM owasp/modsecurity-crs:4.25.1-nginx-lts@sha256:60af5abe3175856b8945d8827ab3f52e3906d66ebbb2c8617f45a771b38facad

USER 0

RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
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

COPY 00-conectaeduca-bootstrap-readonly.sh /docker-entrypoint.d/00-conectaeduca-bootstrap-readonly.sh

RUN chmod 0755 /docker-entrypoint.d/00-conectaeduca-bootstrap-readonly.sh

USER nginx
