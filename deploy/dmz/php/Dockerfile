FROM composer:2 AS vendor

WORKDIR /app

COPY composer.json composer.lock ./

RUN composer install \
    --no-dev \
    --no-interaction \
    --no-progress \
    --prefer-dist \
    --optimize-autoloader \
    --no-scripts

FROM php:8.5-fpm-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev \
        libicu-dev \
        libonig-dev \
        libzip-dev \
    && docker-php-ext-install -j"$(nproc)" \
        curl \
        intl \
        mbstring \
        pdo_mysql \
        zip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/conectaeduca

COPY --chown=www-data:www-data bootstrap/ ./bootstrap/
COPY --chown=www-data:www-data public/ ./public/
COPY --chown=www-data:www-data src/ ./src/
COPY --chown=www-data:www-data composer.json composer.lock ./
COPY --from=vendor --chown=www-data:www-data /app/vendor ./vendor/

RUN mkdir -p storage/logs \
    && chown -R www-data:www-data storage \
    && chmod 0770 storage/logs \
    && php -m | grep -qi '^pdo_mysql$' \
    && php -m | grep -qi '^openssl$' \
    && php -m | grep -qi '^sodium$' \
    && php -m | grep -qi '^mbstring$' \
    && php -m | grep -qi '^curl$' \
    && php -m | grep -qi '^intl$'

COPY deploy/dmz/php/php.ini /usr/local/etc/php/conf.d/zz-conectaeduca.ini
COPY deploy/dmz/php/zz-conectaeduca.conf /usr/local/etc/php-fpm.d/zz-conectaeduca.conf

USER www-data

HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=5 \
    CMD php-fpm -t || exit 1

CMD ["php-fpm", "-F"]
