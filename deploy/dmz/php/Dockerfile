FROM composer:2@sha256:4d71c3c2109c61d5415544264b59ad4087e4c5b7244481723664138fd36d5040 AS composer-bin

FROM php:8.5.9-fpm-alpine3.24@sha256:9dc81f4086ea5402227a6bcc489b04b4baba12394624d9621faa92ed812fb8ee AS php-base

USER root

RUN set -eux; \
    apk add --no-cache icu-libs libzip; \
    apk add --no-cache --virtual .conecta-build-deps \
        $PHPIZE_DEPS icu-dev libzip-dev; \
    docker-php-ext-install -j"$(nproc)" intl pdo_mysql zip; \
    apk del --no-network .conecta-build-deps; \
    apk upgrade --no-cache \
        openssl libssl3 libcrypto3 curl libcurl; \
    rm -rf /tmp/* /var/cache/apk/* /usr/src/php*; \
    rm -f /usr/local/bin/phpize /usr/local/bin/php-config

FROM php-base AS vendor
COPY --from=composer-bin /usr/bin/composer /usr/bin/composer
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install \
    --no-dev \
    --no-interaction \
    --no-progress \
    --prefer-dist \
    --optimize-autoloader \
    --no-scripts

FROM php-base AS runtime
WORKDIR /var/www/conectaeduca

COPY --chown=www-data:www-data bootstrap/ ./bootstrap/
COPY --chown=www-data:www-data public/ ./public/
COPY --chown=www-data:www-data src/ ./src/
COPY --chown=www-data:www-data composer.json composer.lock ./
COPY --from=vendor --chown=www-data:www-data /app/vendor ./vendor/

RUN set -eux; \
    mkdir -p storage/logs; \
    chown -R www-data:www-data storage; \
    chmod 0770 storage/logs; \
    for module in curl intl mbstring openssl pdo_mysql sodium zip; do \
        php -m | grep -qi "^${module}$"; \
    done

# Permissoes explicitas: o build nao depende do umask/permissoes do checkout.
COPY --chmod=0644 deploy/dmz/php/php.ini /usr/local/etc/php/conf.d/zz-conectaeduca.ini
COPY --chmod=0644 deploy/dmz/php/zz-conectaeduca.conf /usr/local/etc/php-fpm.d/zz-conectaeduca.conf

USER www-data

HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=5 \
    CMD php-fpm -t || exit 1

CMD ["php-fpm", "-F"]
