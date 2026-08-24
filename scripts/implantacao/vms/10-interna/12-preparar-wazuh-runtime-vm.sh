#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C LANG=C
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
[[ -n "$ROOT" && -d "$ROOT/.git" ]] || { echo "ERRO: repositório ConectaEduca não localizado" >&2; exit 1; }
WAZUH_DIR="$ROOT/deploy/interna/wazuh"; RUNTIME="$WAZUH_DIR/.runtime"; WAZUH_VERSION=4.14.7; CERT_PROJECT=conectaeduca-wazuh-certs-vm
if [[ "${1:-}" == "--self-test" ]]; then
  for f in compose.yml generate-indexer-certs.yml templates/internal_users.yml.tpl templates/wazuh.yml.tpl; do [[ -f "$WAZUH_DIR/$f" ]] || { echo "SELF_TEST_WAZUH_RUNTIME=REPROVADO:$f"; exit 1; }; done
  echo "SELF_TEST_WAZUH_RUNTIME=APROVADO"; exit 0
fi
[[ "$(hostname)" == conectaeduca-interna ]] || { echo "ERRO: execute somente em CE-UBUNTU-INT" >&2; exit 1; }
for c in docker python3 grep stat git; do command -v "$c" >/dev/null || { echo "ERRO: comando ausente: $c" >&2; exit 1; }; done
docker info >/dev/null 2>&1 || { echo "ERRO: Docker indisponível" >&2; exit 1; }
if [[ -d "$RUNTIME" ]] && find "$RUNTIME" -type f -print -quit 2>/dev/null | grep -q .; then
  complete=1; for f in manager.env dashboard.env internal_users.yml wazuh.yml; do [[ -s "$RUNTIME/$f" ]] || complete=0; done; [[ -d "$RUNTIME/certs" ]] || complete=0
  if (( complete )); then echo "OK: runtime Wazuh existente preservado."; exit 0; fi
  echo "ERRO: runtime Wazuh parcial encontrado; não será sobrescrito." >&2; exit 1
fi
install -d -m 0700 "$RUNTIME" "$RUNTIME/certs"
TMP="$(mktemp)"; chmod 600 "$TMP"; trap 'rm -f "$TMP"' EXIT
python3 - >"$TMP" <<'PASSGEN'
import secrets,string
alphabet=string.ascii_letters+string.digits+'!%@_+-='
def pw(n=32):
    while True:
        p=''.join(secrets.choice(alphabet) for _ in range(n))
        if any(c.islower() for c in p) and any(c.isupper() for c in p) and any(c.isdigit() for c in p) and any(c in '!%@_+-=' for c in p): return p
for n in ['ADMIN_PASSWORD','KIBANASERVER_PASSWORD','KIBANARO_PASSWORD','LOGSTASH_PASSWORD','READALL_PASSWORD','SNAPSHOTRESTORE_PASSWORD','API_PASSWORD']: print(f'{n}={pw()}')
PASSGEN
# shellcheck disable=SC1090
source "$TMP"; rm -f "$TMP"; trap - EXIT
hash_password(){ local output hash; output="$(docker run --rm -e WAZUH_HASH_PASSWORD="$1" "wazuh/wazuh-indexer:${WAZUH_VERSION}" bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh -env WAZUH_HASH_PASSWORD 2>&1)"; hash="$(printf '%s\n' "$output" | grep -Eo '\$2[aby]\$[0-9]{2}\$[^[:space:]]+' | tail -1 || true)"; [[ -n "$hash" ]] || { echo "$output" >&2; return 1; }; printf '%s' "$hash"; }
ADMIN_HASH="$(hash_password "$ADMIN_PASSWORD")"; KIBANASERVER_HASH="$(hash_password "$KIBANASERVER_PASSWORD")"; KIBANARO_HASH="$(hash_password "$KIBANARO_PASSWORD")"; LOGSTASH_HASH="$(hash_password "$LOGSTASH_PASSWORD")"; READALL_HASH="$(hash_password "$READALL_PASSWORD")"; SNAPSHOTRESTORE_HASH="$(hash_password "$SNAPSHOTRESTORE_PASSWORD")"
export ADMIN_HASH KIBANASERVER_HASH KIBANARO_HASH LOGSTASH_HASH READALL_HASH SNAPSHOTRESTORE_HASH API_PASSWORD
python3 - "$WAZUH_DIR/templates/internal_users.yml.tpl" "$RUNTIME/internal_users.yml" <<'RENDER_USERS'
from pathlib import Path
import os,sys
s=Path(sys.argv[1]).read_text()
for k in ['ADMIN_HASH','KIBANASERVER_HASH','KIBANARO_HASH','LOGSTASH_HASH','READALL_HASH','SNAPSHOTRESTORE_HASH']: s=s.replace('__'+k+'__',os.environ[k])
if '__' in s: raise SystemExit('placeholder restante')
Path(sys.argv[2]).write_text(s)
RENDER_USERS
chmod 600 "$RUNTIME/internal_users.yml"
cat >"$RUNTIME/manager.env" <<EOF
INDEXER_URL=https://wazuh.indexer:9200
INDEXER_USERNAME=admin
INDEXER_PASSWORD=$ADMIN_PASSWORD
FILEBEAT_SSL_VERIFICATION_MODE=full
SSL_CERTIFICATE_AUTHORITIES=/etc/ssl/root-ca.pem
SSL_CERTIFICATE=/etc/ssl/filebeat.pem
SSL_KEY=/etc/ssl/filebeat.key
API_USERNAME=wazuh-wui
API_PASSWORD=$API_PASSWORD
EOF
cat >"$RUNTIME/dashboard.env" <<EOF
INDEXER_USERNAME=admin
INDEXER_PASSWORD=$ADMIN_PASSWORD
WAZUH_API_URL=https://wazuh.manager
DASHBOARD_USERNAME=kibanaserver
DASHBOARD_PASSWORD=$KIBANASERVER_PASSWORD
API_USERNAME=wazuh-wui
API_PASSWORD=$API_PASSWORD
EOF
python3 - "$WAZUH_DIR/templates/wazuh.yml.tpl" "$RUNTIME/wazuh.yml" <<'RENDER_WAZUH'
from pathlib import Path
import os,sys
Path(sys.argv[2]).write_text(Path(sys.argv[1]).read_text().replace('__API_PASSWORD__',os.environ['API_PASSWORD']))
RENDER_WAZUH
chmod 600 "$RUNTIME/manager.env" "$RUNTIME/dashboard.env" "$RUNTIME/wazuh.yml"
unset ADMIN_PASSWORD KIBANASERVER_PASSWORD KIBANARO_PASSWORD LOGSTASH_PASSWORD READALL_PASSWORD SNAPSHOTRESTORE_PASSWORD API_PASSWORD
(cd "$WAZUH_DIR"; docker compose -p "$CERT_PROJECT" -f generate-indexer-certs.yml run --rm generator; docker compose -p "$CERT_PROJECT" -f generate-indexer-certs.yml down --remove-orphans >/dev/null 2>&1 || true)
for f in manager.env dashboard.env internal_users.yml wazuh.yml; do [[ "$(stat -c '%a' "$RUNTIME/$f")" == 600 ]] || { echo "ERRO: modo incorreto: $f" >&2; exit 1; }; done
for f in root-ca.pem root-ca-manager.pem admin.pem admin-key.pem wazuh.indexer.pem wazuh.indexer-key.pem wazuh.manager.pem wazuh.manager-key.pem wazuh.dashboard.pem wazuh.dashboard-key.pem; do [[ -e "$RUNTIME/certs/$f" ]] || { echo "ERRO: certificado ausente: $f" >&2; exit 1; }; done
echo "WAZUH_RUNTIME_VM=PREPARADO"; echo "SEGREDOS_EXIBIDOS=NAO"
