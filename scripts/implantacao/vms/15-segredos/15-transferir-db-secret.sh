#!/usr/bin/env bash
set -euo pipefail
MODE="check"; SOURCE_FILE=""; DEST_HOST=""; DEST_USER=""; DEST_FILE=""
IDENTITY_FILE=""; KNOWN_HOSTS="${HOME}/.ssh/known_hosts"; SELF_TEST=0

usage(){ cat <<'EOF'
Uso:
  15-transferir-db-secret.sh --source ARQUIVO --dest-host IP_OU_FQDN \
    --dest-user USUARIO --dest-file CAMINHO_ABSOLUTO \
    [--identity-file CHAVE] [--known-hosts ARQUIVO] [--check|--apply]

Transfere o mesmo segredo da aplicação MariaDB da interna para a DMZ por SSH/SCP.
Não imprime o conteúdo; exige host key conhecida; compara SHA-256; destino 0600.
EOF
}
valid_host(){ [[ "$1" =~ ^[A-Za-z0-9.-]+$ ]]; }
valid_user(){ [[ "$1" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; }
valid_path(){ [[ "$1" == /* && "$1" != *" "* && "$1" != *";"* && "$1" != *"\`"* && "$1" != *'$('* ]]; }

while (($#)); do
 case "$1" in
  --source) SOURCE_FILE="${2:-}"; shift 2;;
  --dest-host) DEST_HOST="${2:-}"; shift 2;;
  --dest-user) DEST_USER="${2:-}"; shift 2;;
  --dest-file) DEST_FILE="${2:-}"; shift 2;;
  --identity-file) IDENTITY_FILE="${2:-}"; shift 2;;
  --known-hosts) KNOWN_HOSTS="${2:-}"; shift 2;;
  --check) MODE="check"; shift;;
  --apply) MODE="apply"; shift;;
  --self-test) SELF_TEST=1; shift;;
  -h|--help) usage; exit 0;;
  *) echo "ERRO: argumento desconhecido: $1" >&2; exit 64;;
 esac
done

if ((SELF_TEST)); then
 valid_host "192.0.2.10"; valid_host "conectaeduca-dmz.example"; valid_user "ubuntu"
 valid_path "/etc/conectaeduca/secrets/conectaeduca_db_password"
 ! valid_path "/tmp/a;rm"
 echo "SELF_TEST_TRANSFERENCIA_DB_SECRET=APROVADO"; exit 0
fi

for c in scp ssh ssh-keygen sha256sum stat; do
 command -v "$c" >/dev/null 2>&1 || { echo "ERRO: comando ausente: $c" >&2; exit 1; }
done
[[ -s "$SOURCE_FILE" ]] || { echo "ERRO: segredo de origem ausente ou vazio: $SOURCE_FILE" >&2; exit 66; }
valid_host "$DEST_HOST" || { echo "ERRO: --dest-host inválido" >&2; exit 64; }
valid_user "$DEST_USER" || { echo "ERRO: --dest-user inválido" >&2; exit 64; }
valid_path "$DEST_FILE" || { echo "ERRO: --dest-file inválido" >&2; exit 64; }
[[ -r "$KNOWN_HOSTS" ]] || { echo "ERRO: known_hosts ausente: $KNOWN_HOSTS" >&2; exit 66; }

ssh-keygen -F "$DEST_HOST" -f "$KNOWN_HOSTS" >/dev/null 2>&1 || {
 echo "ERRO: host SSH ainda não confiado: $DEST_HOST. Verifique a fingerprint manualmente antes." >&2; exit 65;
}

MODE_SRC="$(stat -c '%a' "$SOURCE_FILE" 2>/dev/null || true)"
case "$MODE_SRC" in 400|440|600|640) ;; *) echo "ERRO: permissão excessiva na origem: ${MODE_SRC:-?}" >&2; exit 1;; esac

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$KNOWN_HOSTS")
SCP_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$KNOWN_HOSTS")
if [[ -n "$IDENTITY_FILE" ]]; then
 [[ -r "$IDENTITY_FILE" ]] || { echo "ERRO: chave SSH não legível" >&2; exit 66; }
 SSH_OPTS+=(-i "$IDENTITY_FILE" -o IdentitiesOnly=yes)
 SCP_OPTS+=(-i "$IDENTITY_FILE" -o IdentitiesOnly=yes)
fi

REMOTE="${DEST_USER}@${DEST_HOST}"; DEST_DIR="${DEST_FILE%/*}"; TMP_REMOTE="/tmp/conectaeduca-db-secret.$$"
echo "DESTINO_HOST=$DEST_HOST"; echo "DESTINO_ARQUIVO=$DEST_FILE"; echo "CONTEUDO_EXIBIDO=NAO"; echo "HOST_KEY_CHECKING=STRICT"

ssh "${SSH_OPTS[@]}" "$REMOTE" "test -d '$DEST_DIR' && test -w '$DEST_DIR'" >/dev/null ||
 { echo "ERRO: diretório remoto inexistente ou sem permissão: $DEST_DIR" >&2; exit 1; }

if [[ "$MODE" == "check" ]]; then echo "TRANSFERENCIA_DB_SECRET=PRONTA_PARA_APPLY"; exit 0; fi

LOCAL_SHA="$(sha256sum "$SOURCE_FILE" | awk '{print $1}')"
cleanup(){ ssh "${SSH_OPTS[@]}" "$REMOTE" "rm -f '$TMP_REMOTE'" >/dev/null 2>&1 || true; }
trap cleanup EXIT
scp "${SCP_OPTS[@]}" "$SOURCE_FILE" "$REMOTE:$TMP_REMOTE" >/dev/null
REMOTE_SHA="$(ssh "${SSH_OPTS[@]}" "$REMOTE" "sha256sum '$TMP_REMOTE' | awk '{print \$1}'")"
[[ "$REMOTE_SHA" == "$LOCAL_SHA" ]] || { echo "ERRO: SHA-256 temporário diverge" >&2; exit 1; }
ssh "${SSH_OPTS[@]}" "$REMOTE" "chmod 600 '$TMP_REMOTE' && mv -f '$TMP_REMOTE' '$DEST_FILE' && chmod 600 '$DEST_FILE'"
FINAL_SHA="$(ssh "${SSH_OPTS[@]}" "$REMOTE" "sha256sum '$DEST_FILE' | awk '{print \$1}'")"
[[ "$FINAL_SHA" == "$LOCAL_SHA" ]] || { echo "ERRO: SHA-256 final diverge" >&2; exit 1; }
trap - EXIT
echo "TRANSFERENCIA_DB_SECRET=CONCLUIDA"; echo "SHA256_ORIGEM_DESTINO=IGUAL"; echo "PERMISSAO_DESTINO=0600"; echo "CONTEUDO_EXIBIDO=NAO"
