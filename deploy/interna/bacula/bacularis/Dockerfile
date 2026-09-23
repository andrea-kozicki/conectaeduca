# syntax=docker/dockerfile:1

ARG UPSTREAM_IMAGE=bacularis/bacularis-standalone@sha256:ee6d769e1dd8cae1a90a32d4a4a59098c29afef8d53e05ea24f4f2d7740be2a2
FROM ${UPSTREAM_IMAGE} AS source

# O stage scratch remove VOLUME/CMD/ENTRYPOINT herdados do standalone.
FROM scratch
COPY --from=source / /

ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    BACULARIS_VERSION="6.5.2" \
    DEBIAN_FRONTEND="noninteractive"

USER root

COPY conectaeduca-bacularis-entrypoint-v2 /usr/local/sbin/conectaeduca-bacularis-entrypoint-v2
COPY api.conf.failclosed /tmp/api.conf.failclosed
COPY conectaeduca-bacularis-readonly.conf /etc/nginx/snippets/conectaeduca-bacularis-readonly.conf
COPY 00-conectaeduca-api-readonly-map.conf /etc/nginx/conf.d/00-conectaeduca-api-readonly-map.conf

RUN set -eux; \
    chmod 0755 /usr/local/sbin/conectaeduca-bacularis-entrypoint-v2; \
    apt-get update; \
    remove_pkgs="$(dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' 2>/dev/null \
      | awk '$1 ~ /^ii/ && ($2 ~ /^postgresql/ || $2 ~ /^bacula-director/ || $2 ~ /^bacula-sd/ || $2 ~ /^bacula-fd/) {print $2}')"; \
    if [ -n "$remove_pkgs" ]; then apt-get purge -y $remove_pkgs; fi; \
    apt-get install -y --no-install-recommends bacula-console ca-certificates; \
    if dpkg-query -W -f='${db:Status-Abbrev}' sudo 2>/dev/null | grep -q '^ii'; then \
      SUDO_FORCE_REMOVE=yes apt-get purge -y sudo; \
    fi; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /var/lib/postgresql /etc/postgresql; \
    rm -f /etc/sudoers.d/bacularis-*; \
    rm -f /usr/sbin/bdirjson /usr/sbin/bsdjson /usr/sbin/bfdjson /usr/sbin/bbconsjson; \
    install -o root -g www-data -m 0640 /tmp/api.conf.failclosed \
      /var/www/bacularis/protected/vendor/bacularis/bacularis-api/API/Config/api.conf; \
    : > /var/www/bacularis/protected/vendor/bacularis/bacularis-api/API/Config/bacularis.users; \
    : > /var/www/bacularis/protected/vendor/bacularis/bacularis-web/Web/Config/bacularis.users; \
    : > /var/www/bacularis/protected/vendor/bacularis/bacularis-web/Web/Config/users.conf; \
    : > /var/www/bacularis/protected/vendor/bacularis/bacularis-web/Web/Config/hosts.conf; \
    chown root:www-data \
      /var/www/bacularis/protected/vendor/bacularis/bacularis-api/API/Config/bacularis.users \
      /var/www/bacularis/protected/vendor/bacularis/bacularis-web/Web/Config/bacularis.users \
      /var/www/bacularis/protected/vendor/bacularis/bacularis-web/Web/Config/users.conf \
      /var/www/bacularis/protected/vendor/bacularis/bacularis-web/Web/Config/hosts.conf; \
    chmod 0640 \
      /var/www/bacularis/protected/vendor/bacularis/bacularis-api/API/Config/bacularis.users \
      /var/www/bacularis/protected/vendor/bacularis/bacularis-web/Web/Config/bacularis.users \
      /var/www/bacularis/protected/vendor/bacularis/bacularis-web/Web/Config/users.conf \
      /var/www/bacularis/protected/vendor/bacularis/bacularis-web/Web/Config/hosts.conf; \
    rm -f /tmp/api.conf.failclosed; \
    site=/etc/nginx/sites-available/bacularis.conf; \
    pool=/etc/php/8.4/fpm/pool.d/www.conf; \
    req=/var/www/bacularis/protected/vendor/bacularis/bacularis-common/Common/Modules/GeneralRequirements.php; \
    test -f "$site"; test -f "$pool"; test -f "$req"; \
    if ! grep -Eq '^[[:space:]]*fastcgi_param[[:space:]]+HTTP_AUTHORIZATION[[:space:]]+\$http_authorization;' "$site"; then \
      sed -i '/include fastcgi_params;/i\        fastcgi_param HTTP_AUTHORIZATION $http_authorization;' "$site"; \
    fi; \
    if ! grep -Fq 'env[PGSSLMODE] = verify-full' "$pool"; then \
      printf '\n; ConectaEduca GUI-01B: PostgreSQL TLS policy for FPM workers\nenv[PGSSLMODE] = verify-full\nenv[PGSSLROOTCERT] = /var/www/bacularis/protected/vendor/bacularis/bacularis-api/API/Config/postgresql-root-ca.crt\n' >> "$pool"; \
    fi; \
    grep -Fq "'Config', 'Logs'" "$req"; \
    sed -i "s/'Config', 'Logs'/'Logs'/" "$req"; \
    if ! grep -Fq 'include /etc/nginx/snippets/conectaeduca-bacularis-readonly.conf;' "$site"; then \
      sed -i '/^[[:space:]]*server_name[[:space:]]/a\    include /etc/nginx/snippets/conectaeduca-bacularis-readonly.conf;' "$site"; \
    fi; \
    if ! grep -Fq 'if ($ce_api_mutation_block = 1) { return 405; }' "$site"; then \
      sed -i '/^[[:space:]]*server_name[[:space:]]/a\    if ($ce_api_mutation_block = 1) { return 405; }' "$site"; \
    fi; \
    test -x /usr/sbin/bconsole || test -x /usr/bin/bconsole; \
    command -v nginx; \
    command -v php-fpm8.4; \
    php -r 'exit(extension_loaded("pdo_pgsql") ? 0 : 2);'; \
    ! command -v sudo; \
    ! command -v bdirjson; ! command -v bsdjson; ! command -v bfdjson; ! command -v bbconsjson; \
    ! command -v bacula-dir; ! command -v bacula-sd; ! command -v bacula-fd; ! command -v postgres; \
    ! grep -Fq "'Config', 'Logs'" "$req"; \
    grep -Fq "'Logs'" "$req"; grep -Fq "'assets'" "$req"; grep -Fq "'runtime'" "$req"; \
    grep -Eq '^[[:space:]]*fastcgi_param[[:space:]]+HTTP_AUTHORIZATION[[:space:]]+\$http_authorization;' "$site"; \
    grep -Fq 'env[PGSSLMODE] = verify-full' "$pool"; \
    grep -Fq 'include /etc/nginx/snippets/conectaeduca-bacularis-readonly.conf;' "$site"; \
    grep -Fq 'if ($ce_api_mutation_block = 1) { return 405; }' "$site"; \
    grep -Fq 'map $uri $ce_api_path' /etc/nginx/conf.d/00-conectaeduca-api-readonly-map.conf; \
    grep -Fq 'GET 1;' /etc/nginx/conf.d/00-conectaeduca-api-readonly-map.conf; \
    grep -Fq 'HEAD 1;' /etc/nginx/conf.d/00-conectaeduca-api-readonly-map.conf; \
    nginx -t; \
    php-fpm8.4 -t

LABEL org.opencontainers.image.title="ConectaEduca Bacularis Web+API" \
      org.opencontainers.image.description="Bacularis 6.5.2 em perfil read-only para a EP126" \
      org.opencontainers.image.version="6.5.2" \
      conectaeduca.component="bacularis-webapi" \
      conectaeduca.version="6.5.2" \
      conectaeduca.gui01b.image_contract="v31-readonly-api-method-firewall" \
      conectaeduca.gui01b.config_policy="read-only" \
      conectaeduca.gui01b.api_policy="GET-HEAD-only-mutation-block" \
      conectaeduca.gui01b.runtime_writable="assets,protected-runtime,logs,tmp"

EXPOSE 9097/tcp
USER www-data
ENTRYPOINT ["/usr/local/sbin/conectaeduca-bacularis-entrypoint-v2"]
CMD []
