# syntax=docker/dockerfile:1

FROM owasp/modsecurity-crs:4.25.1-nginx-lts@sha256:60af5abe3175856b8945d8827ab3f52e3906d66ebbb2c8617f45a771b38facad

USER 0

RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

USER nginx
