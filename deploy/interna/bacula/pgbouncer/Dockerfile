ARG BACULA_BASE_IMAGE=conectaeduca/bacula-director:15.0.3
FROM ${BACULA_BASE_IMAGE}

ARG BACULA_BASE_IMAGE
ARG CONECTAEDUCA_SOURCE_COMMIT=UNSET
ARG PGBOUNCER_UPSTREAM_VERSION=1.24.1

LABEL org.opencontainers.image.source="https://github.com/andrea-kozicki/conectaeduca" \
      org.opencontainers.image.revision="${CONECTAEDUCA_SOURCE_COMMIT}" \
      org.opencontainers.image.version="${PGBOUNCER_UPSTREAM_VERSION}" \
      io.conectaeduca.build-policy="security-refresh-traceable-version-asserted" \
      io.conectaeduca.parent-image-ref="${BACULA_BASE_IMAGE}"

USER root

RUN test "${CONECTAEDUCA_SOURCE_COMMIT}" != "UNSET" \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends pgbouncer \
 && actual="$(pgbouncer --version | awk 'NR==1 {print $2}')" \
 && test "$actual" = "${PGBOUNCER_UPSTREAM_VERSION}" \
 && install -d -m 0755 /usr/share/conectaeduca \
 && dpkg-query -W -f='${Package}\t${Version}\n' | sort \
    > /usr/share/conectaeduca/build-packages.txt \
 && dpkg-query -W -f='${Version}\n' pgbouncer \
    > /usr/share/conectaeduca/pgbouncer-package-version.txt \
 && printf '%s\n' \
    'component=pgbouncer-tls-bridge' \
    "parent_image_ref=${BACULA_BASE_IMAGE}" \
    "source_commit=${CONECTAEDUCA_SOURCE_COMMIT}" \
    "pgbouncer_upstream_version=${PGBOUNCER_UPSTREAM_VERSION}" \
    'package_policy=security-refresh-traceable-version-asserted' \
    > /usr/share/conectaeduca/build-provenance.txt \
 && rm -rf /var/lib/apt/lists/*

USER bacula:bacula
ENTRYPOINT ["pgbouncer"]
