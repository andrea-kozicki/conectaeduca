#!/usr/bin/env bash
set -euo pipefail

HBA="${PGDATA:?}/pg_hba.conf"
CERT="$PGDATA/server.crt"
KEY="$PGDATA/server.key"

# Material exclusivo do volume. Não é exportado nem versionado; em produção,
# pode ser substituído por certificado emitido pela PKI interna.
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 397 \
  -subj '/CN=catalog' \
  -addext 'subjectAltName=DNS:catalog,DNS:conectaeduca-bacula-catalog' \
  -keyout "$KEY" -out "$CERT" >/dev/null 2>&1
chmod 0600 "$KEY"
chmod 0644 "$CERT"

python3 - "$HBA" <<'PY'
from pathlib import Path
import re,sys

p=Path(sys.argv[1])
lines=p.read_text().splitlines(True)

pat=re.compile(
  r'^(\s*)host(\s+)all(\s+)all(\s+)all(\s+)scram-sha-256(\s*(?:#.*)?)$',
  re.I
)

out=[]
count=0

for line in lines:
    raw=line.rstrip("\n")
    m=pat.match(raw)
    if m:
        count+=1
        out.append(
          f'{m.group(1)}hostssl{m.group(2)}all{m.group(3)}all'
          f'{m.group(4)}all{m.group(5)}scram-sha-256{m.group(6)}\n'
        )
    else:
        out.append(line)

if count != 1:
    raise SystemExit(f"expected exactly one broad host rule; found {count}")

p.write_text("".join(out))
PY

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
ALTER SYSTEM SET ssl = 'on';
ALTER SYSTEM SET ssl_cert_file = 'server.crt';
ALTER SYSTEM SET ssl_key_file = 'server.key';
SQL
