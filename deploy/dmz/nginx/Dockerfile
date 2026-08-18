FROM nginx:stable-alpine

COPY deploy/dmz/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY public/ /var/www/conectaeduca/public/

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
    CMD wget -q -O- http://127.0.0.1:8080/_container_health >/dev/null || exit 1
