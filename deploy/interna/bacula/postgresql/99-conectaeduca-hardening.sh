#!/bin/sh
# ConectaEduca — hardening de fresh volume do PostgreSQL/Bacula Catalog.
#
# Este arquivo é carregado pelo entrypoint oficial do PostgreSQL somente
# durante a inicialização de um PGDATA vazio. Não contém credenciais.
# O entrypoint pode executá-lo ou fazer source; por isso o script evita
# alterar opções globais do shell do processo chamador.

: "${PGDATA:?PGDATA ausente}"
: "${POSTGRES_USER:?POSTGRES_USER ausente}"
: "${POSTGRES_DB:?POSTGRES_DB ausente}"

HBA="${PGDATA}/pg_hba.conf"
TMP="${HBA}.conectaeduca.$$"

awk '
  /^[[:space:]]*#/ || NF==0 { print; next }

  $1 == "local" && $NF == "trust" {
    $NF = "scram-sha-256"
    print
    next
  }

  $1 ~ /^host/ && $NF == "trust" {
    $NF = "scram-sha-256"
    print
    next
  }

  { print }
' "$HBA" > "$TMP"

chmod 0600 "$TMP"
mv "$TMP" "$HBA"

psql \
  -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  -c "ALTER SYSTEM SET log_connections = 'on';"

psql \
  -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  -c "ALTER SYSTEM SET log_disconnections = 'on';"
