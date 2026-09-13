#!/bin/sh
# ConectaEduca — PostgreSQL/Bacula Catalog fresh-volume hardening v2.
# Executado somente durante a inicialização de PGDATA vazio.
# Não contém segredo e deve permanecer executável no checkout.

: "${PGDATA:?PGDATA ausente}"
: "${POSTGRES_USER:?POSTGRES_USER ausente}"
: "${POSTGRES_DB:?POSTGRES_DB ausente}"

HBA="${PGDATA}/pg_hba.conf"
TMP="${HBA}.conectaeduca.$$"

awk '
  /^[[:space:]]*#/ || NF == 0 { print; next }

  $1 == "local" && $4 == "trust" {
    $4 = "scram-sha-256"
    print
    next
  }

  $1 ~ /^host/ && $5 == "trust" {
    $5 = "scram-sha-256"
    print
    next
  }

  { print }
' "$HBA" > "$TMP" || exit 1

chmod 0600 "$TMP" || exit 1
mv "$TMP" "$HBA" || exit 1

if awk '
  /^[[:space:]]*#/ || NF == 0 { next }
  $1 == "local" && $4 == "trust" { bad = 1 }
  $1 ~ /^host/ && $5 == "trust" { bad = 1 }
  END { exit bad ? 0 : 1 }
' "$HBA"; then
  echo "ERRO: pg_hba.conf ainda contém regra trust após hardening." >&2
  exit 1
fi

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"   -c "ALTER SYSTEM SET log_connections = 'on';" || exit 1

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"   -c "ALTER SYSTEM SET log_disconnections = 'on';" || exit 1

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"   -c "ALTER SYSTEM SET password_encryption = 'scram-sha-256';" || exit 1
