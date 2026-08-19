FROM nginx:stable-alpine@sha256:97d490c12ba55b4946b01546d1c3ed324e8d41ab1c9fcb2a616aa470620e5b46

COPY deploy/dmz/nginx/app-http.conf /etc/nginx/conf.d/default.conf
COPY public/ /var/www/conectaeduca/public/

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
    CMD wget -q -O- http://127.0.0.1:8080/_container_health >/dev/null || exit 1
