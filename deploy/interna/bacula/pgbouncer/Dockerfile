ARG BACULA_BASE_IMAGE=conectaeduca/bacula-director:15.0.3
FROM ${BACULA_BASE_IMAGE}

USER root
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends pgbouncer \
 && rm -rf /var/lib/apt/lists/*

USER bacula:bacula
ENTRYPOINT ["pgbouncer"]
