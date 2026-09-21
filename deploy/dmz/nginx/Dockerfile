FROM nginx:stable-alpine@sha256:dc5069ad14f19660b141b21236140b91656bf89bbc3e2417c70ae650cd66104c

ARG CONECTAEDUCA_SOURCE_COMMIT=UNSET

LABEL org.opencontainers.image.source="https://github.com/andrea-kozicki/conectaeduca" \
      org.opencontainers.image.revision="${CONECTAEDUCA_SOURCE_COMMIT}" \
      io.conectaeduca.build-policy="base-digest"

RUN test "${CONECTAEDUCA_SOURCE_COMMIT}" != "UNSET" \
 && mkdir -p /usr/share/conectaeduca \
 && printf '%s\n' \
      'component=nginx-dmz' \
      'base=nginx:stable-alpine@sha256:dc5069ad14f19660b141b21236140b91656bf89bbc3e2417c70ae650cd66104c' \
      "source_commit=${CONECTAEDUCA_SOURCE_COMMIT}" \
      'package_policy=base-image-only' \
      > /usr/share/conectaeduca/build-provenance.txt

COPY --chmod=0644 deploy/dmz/nginx/app-http.conf /etc/nginx/conf.d/default.conf
COPY public/ /var/www/conectaeduca/public/

RUN find /var/www/conectaeduca/public -type d -exec chmod 0755 {} + \
 && find /var/www/conectaeduca/public -type f -exec chmod 0644 {} +

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
    CMD wget -q -O- http://127.0.0.1:8080/_container_health >/dev/null || exit 1
