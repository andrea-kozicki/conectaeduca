#!/usr/bin/env bash
set -euo pipefail

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"
WAZUH_DIR="$ROOT/deploy/interna/wazuh"
RUNTIME="$WAZUH_DIR/.runtime"
WAZUH_VERSION="4.14.7"
PROJECT="conectaeduca-wazuh"
CERT_PROJECT="conectaeduca-wazuh-certs"

ok(){ echo "OK       $*"; }
fail(){ echo "FALHA    $*" >&2; exit 1; }
info(){ echo "INFO     $*"; }

cd "$ROOT"

echo "======================================================================"
echo " CONECTAEDUCA - FASE 4G-C — preparação v3"
echo " Preparação segura de credenciais e certificados Wazuh"
echo "======================================================================"

BRANCH="$(git branch --show-current 2>/dev/null || true)"
echo "branch_atual=$BRANCH"
[[ "$BRANCH" == "feature/auth-local" ]] \
  && ok "branch feature/auth-local confirmada" \
  || fail "execute exclusivamente na branch feature/auth-local"

git diff --check
ok "git diff --check"

for f in \
  "$WAZUH_DIR/compose.yml" \
  "$WAZUH_DIR/compose.lab.yml" \
  "$WAZUH_DIR/generate-indexer-certs.yml" \
  "$WAZUH_DIR/templates/internal_users.yml.tpl" \
  "$WAZUH_DIR/templates/wazuh.yml.tpl"
do
  [[ -f "$f" ]] || fail "arquivo ausente: $f"
done
ok "arquivos versionáveis presentes"

docker info >/dev/null 2>&1 || fail "Docker daemon indisponível"
docker compose version >/dev/null 2>&1 || fail "Docker Compose indisponível"
python3 --version >/dev/null 2>&1 || fail "Python 3 ausente"
ok "pré-requisitos disponíveis"

RESIDUAL="$(
  docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" 2>/dev/null || true
)"
VOLUMES="$(
  docker volume ls -q --filter "label=com.docker.compose.project=$PROJECT" 2>/dev/null || true
)"
if [[ -n "$RESIDUAL" || -n "$VOLUMES" ]]; then
  fail "há containers/volumes do Wazuh existentes; não regenere credenciais sobre uma instalação persistente"
fi

RESUME_RUNTIME=0

if [[ -d "$RUNTIME" ]]; then
  RUNTIME_FILES="$(
    find "$RUNTIME" -type f -print 2>/dev/null || true
  )"

  if [[ -z "$RUNTIME_FILES" ]]; then
    info "runtime parcial vazio encontrado de tentativa anterior; removendo para recriação segura"
    rm -rf "$RUNTIME"
  elif [[ -f "$RUNTIME/manager.env" \
       && -f "$RUNTIME/dashboard.env" \
       && -f "$RUNTIME/internal_users.yml" \
       && -f "$RUNTIME/wazuh.yml" \
       && -d "$RUNTIME/certs" ]]; then
    RESUME_RUNTIME=1
    info "runtime já contém a preparação anterior; retomando somente validações, sem regenerar credenciais"
  elif [[ "${CONFIRM_REGENERATE:-NAO}" == "SIM" ]]; then
    info "regeneração explicitamente autorizada"
    sudo rm -rf "$RUNTIME"
  else
    echo "Runtime parcial encontrado (somente nomes, sem conteúdo):"
    find "$RUNTIME" -type f -printf '  %P\n' 2>/dev/null || true
    fail "runtime parcial contém dados. Não sobrescreverei sem CONFIRM_REGENERATE=SIM"
  fi
fi

if [[ "$RESUME_RUNTIME" -eq 0 ]]; then
  install -d -m 0700 "$RUNTIME"
  install -d -m 0700 "$RUNTIME/certs"
  TMP_PASS="$(mktemp)"
  chmod 600 "$TMP_PASS"

python3 - > "$TMP_PASS" <<'PY'
import secrets
import string

alphabet = string.ascii_letters + string.digits + "!%@_+-="

def password(n=32):
    while True:
        p = "".join(secrets.choice(alphabet) for _ in range(n))
        if (any(c.islower() for c in p)
            and any(c.isupper() for c in p)
            and any(c.isdigit() for c in p)
            and any(c in "!%@_+-=" for c in p)):
            return p

names = [
    "ADMIN_PASSWORD",
    "KIBANASERVER_PASSWORD",
    "KIBANARO_PASSWORD",
    "LOGSTASH_PASSWORD",
    "READALL_PASSWORD",
    "SNAPSHOTRESTORE_PASSWORD",
    "API_PASSWORD",
]
for name in names:
    print(f"{name}={password()}")
PY

# Valores usam alfabeto deliberadamente seguro para source em Bash.
# shellcheck disable=SC1090
source "$TMP_PASS"
rm -f "$TMP_PASS"

hash_password() {
  local password="$1"
  local output hash

  # O hash.sh 4.14.7 abre um console quando nenhuma opção é fornecida.
  # Em execução não interativa isso resulta em "Cannot allocate a console".
  # A opção oficial -env permite automação sem colocar a senha na linha
  # de comando do processo.
  output="$(
    docker run --rm \
      -e WAZUH_HASH_PASSWORD="$password" \
      "wazuh/wazuh-indexer:${WAZUH_VERSION}" \
      bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh \
        -env WAZUH_HASH_PASSWORD \
      2>&1
  )"

  hash="$(
    printf '%s\n' "$output" |
      grep -Eo '\$2[aby]\$[0-9]{2}\$[^[:space:]]+' |
      tail -n1 || true
  )"

  [[ -n "$hash" ]] || {
    # A saída da ferramenta não contém a senha em texto claro.
    echo "$output" >&2
    fail "não foi possível gerar bcrypt com a imagem oficial"
  }

  printf '%s' "$hash"
}

echo
echo "=== HASHES DO INDEXER ==="
ADMIN_HASH="$(hash_password "$ADMIN_PASSWORD")"; ok "hash admin gerado"
KIBANASERVER_HASH="$(hash_password "$KIBANASERVER_PASSWORD")"; ok "hash kibanaserver gerado"
KIBANARO_HASH="$(hash_password "$KIBANARO_PASSWORD")"; ok "hash kibanaro gerado"
LOGSTASH_HASH="$(hash_password "$LOGSTASH_PASSWORD")"; ok "hash logstash gerado"
READALL_HASH="$(hash_password "$READALL_PASSWORD")"; ok "hash readall gerado"
SNAPSHOTRESTORE_HASH="$(hash_password "$SNAPSHOTRESTORE_PASSWORD")"; ok "hash snapshotrestore gerado"

export ADMIN_HASH KIBANASERVER_HASH KIBANARO_HASH LOGSTASH_HASH READALL_HASH SNAPSHOTRESTORE_HASH
python3 - "$WAZUH_DIR/templates/internal_users.yml.tpl" "$RUNTIME/internal_users.yml" <<'PY'
from pathlib import Path
import os, sys

src = Path(sys.argv[1]).read_text(encoding="utf-8")
dst = Path(sys.argv[2])
repl = {
    "__ADMIN_HASH__": os.environ["ADMIN_HASH"],
    "__KIBANASERVER_HASH__": os.environ["KIBANASERVER_HASH"],
    "__KIBANARO_HASH__": os.environ["KIBANARO_HASH"],
    "__LOGSTASH_HASH__": os.environ["LOGSTASH_HASH"],
    "__READALL_HASH__": os.environ["READALL_HASH"],
    "__SNAPSHOTRESTORE_HASH__": os.environ["SNAPSHOTRESTORE_HASH"],
}
for k, v in repl.items():
    src = src.replace(k, v)
if "__" in src:
    raise SystemExit("placeholder não substituído em internal_users.yml")
dst.write_text(src, encoding="utf-8")
PY
chmod 600 "$RUNTIME/internal_users.yml"
ok "internal_users.yml de runtime criado"

cat > "$RUNTIME/manager.env" <<EOF
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
chmod 600 "$RUNTIME/manager.env"

cat > "$RUNTIME/dashboard.env" <<EOF
INDEXER_USERNAME=admin
INDEXER_PASSWORD=$ADMIN_PASSWORD
WAZUH_API_URL=https://wazuh.manager
DASHBOARD_USERNAME=kibanaserver
DASHBOARD_PASSWORD=$KIBANASERVER_PASSWORD
API_USERNAME=wazuh-wui
API_PASSWORD=$API_PASSWORD
EOF
chmod 600 "$RUNTIME/dashboard.env"

export API_PASSWORD
python3 - "$WAZUH_DIR/templates/wazuh.yml.tpl" "$RUNTIME/wazuh.yml" <<'PY'
from pathlib import Path
import os, sys
src = Path(sys.argv[1]).read_text(encoding="utf-8")
src = src.replace("__API_PASSWORD__", os.environ["API_PASSWORD"])
Path(sys.argv[2]).write_text(src, encoding="utf-8")
PY
chmod 600 "$RUNTIME/wazuh.yml"

# Não preservar senhas dos usuários internos não utilizados; só seus hashes permanecem.
unset KIBANARO_PASSWORD LOGSTASH_PASSWORD READALL_PASSWORD SNAPSHOTRESTORE_PASSWORD
ok "arquivos de credenciais de runtime criados com modo 0600"

echo
echo "=== CERTIFICADOS ==="
(
  cd "$WAZUH_DIR"
  docker compose -p "$CERT_PROJECT" -f generate-indexer-certs.yml run --rm generator
  docker compose -p "$CERT_PROJECT" -f generate-indexer-certs.yml down --remove-orphans >/dev/null 2>&1 || true
)
ok "gerador oficial executado"
fi

echo
echo "=== VALIDAÇÃO DO RUNTIME EXISTENTE ==="

for f in manager.env dashboard.env internal_users.yml wazuh.yml; do
  [[ -f "$RUNTIME/$f" ]] || fail "arquivo de runtime ausente: $f"
  mode="$(stat -c '%a' "$RUNTIME/$f" 2>/dev/null || echo '?')"
  [[ "$mode" == "600" ]] \
    && ok "$f modo 600" \
    || fail "$f modo inesperado: $mode"
done

# A validação desta etapa é de existência. O gerador oficial ajusta ownership e
# permissões diferentes para os certificados de Manager, Indexer e Dashboard;
# portanto não é correto exigir que um único usuário de um único componente leia
# todos os certificados. A legibilidade por componente é testada em 4G-C.
if CERT_OUTPUT="$(
  docker run --rm --user 0:0 \
    -v "$RUNTIME/certs:/certs:ro" \
    "wazuh/wazuh-indexer:${WAZUH_VERSION}" \
    bash -ec '
      missing=0
      for f in \
        root-ca.pem root-ca-manager.pem \
        admin.pem admin-key.pem \
        wazuh.indexer.pem wazuh.indexer-key.pem \
        wazuh.manager.pem wazuh.manager-key.pem \
        wazuh.dashboard.pem wazuh.dashboard-key.pem
      do
        if test -e "/certs/$f"; then
          echo "OK:$f"
        else
          echo "MISSING:$f"
          missing=1
        fi
      done
      exit "$missing"
    ' 2>&1
)"; then
  printf '%s\n' "$CERT_OUTPUT"
  ok "todos os certificados esperados existem"
else
  printf '%s\n' "$CERT_OUTPUT"
  fail "há certificado esperado ausente"
fi

echo
echo "=== HIGIENE ==="
if git check-ignore -q deploy/interna/wazuh/.runtime/manager.env; then
  ok ".runtime está ignorado pelo Git"
else
  fail ".runtime não está ignorado pelo Git"
fi

if git ls-files deploy/interna/wazuh/.runtime | grep -q .; then
  fail "há arquivo de runtime rastreado pelo Git"
else
  ok "nenhum segredo/certificado de runtime rastreado"
fi

if grep -RqsF --exclude-dir=.runtime 'SecretPassword' "$WAZUH_DIR" \
   || grep -RqsF --exclude-dir=.runtime 'MyS3cr37P450r.*-' "$WAZUH_DIR"; then
  fail "credencial padrão Wazuh encontrada em arquivo versionável"
else
  ok "credenciais padrão Wazuh ausentes dos arquivos versionáveis"
fi

echo
echo "FASE 4G-C: PREPARAÇÃO CONCLUÍDA."
echo "Runtime sensível: $RUNTIME"
echo "NÃO envie nem versione esse diretório."
echo "Próximo comando:"
echo "  bash scripts/evidencias/testar_wazuh_fase4g_c.sh"
echo "======================================================================"
