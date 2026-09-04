FROM nginx:stable-alpine@sha256:dc5069ad14f19660b141b21236140b91656bf89bbc3e2417c70ae650cd66104c

COPY --chmod=0644 deploy/dmz/nginx/app-http.conf /etc/nginx/conf.d/default.conf
COPY public/ /var/www/conectaeduca/public/

RUN find /var/www/conectaeduca/public -type d -exec chmod 0755 {} + \
 && find /var/www/conectaeduca/public -type f -exec chmod 0644 {} +

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
    CMD wget -q -O- http://127.0.0.1:8080/_container_health >/dev/null || exit 1
