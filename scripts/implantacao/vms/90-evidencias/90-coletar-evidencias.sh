#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"; VMS_DIR="$(cd -P "$SCRIPT_DIR/.." && pwd -P)"; source "$VMS_DIR/lib/comum.sh"
ROLE=""; while (($#)); do case "$1" in --role) ROLE="${2:-}"; shift 2;; --self-test) ce_valid_role dmz && echo 'SELF_TEST_COLETOR_VMS=APROVADO'; exit;; *) exit 64;; esac; done
ce_valid_role "$ROLE" || exit 64; ROOT="$(ce_require_project_root)"; STAMP="$(date +%Y%m%d-%H%M%S)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; OUT="$HOME/Downloads/conectaeduca-evidencias-${ROLE}-$STAMP.tar.gz"
{ echo "DATA=$(date --iso-8601=seconds 2>/dev/null || date)"; echo "ROLE=$ROLE"; echo "HOSTNAME=$(hostname)"; echo "HEAD=$(git -C "$ROOT" rev-parse HEAD)"; uname -a; echo; ip -brief address 2>/dev/null || true; echo; ip route 2>/dev/null || true; echo; docker version --format 'Docker={{.Server.Version}}' 2>/dev/null || true; docker compose version 2>/dev/null || true; echo; docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true; } >"$TMP/ambiente.txt"
find "$HOME/Downloads" -maxdepth 1 -type f \( -name 'conectaeduca-preflight-ubuntu-*.txt' -o -name 'conectaeduca-checkpoint-*.txt' -o -name 'conectaeduca-validacao-wazuh-operacional-*.txt' \) -print0 2>/dev/null | while IFS= read -r -d '' f; do cp -p "$f" "$TMP/"; done
if grep -RIlE '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|POSTGRES_PASSWORD=|INDEXER_PASSWORD=|API_PASSWORD=|MARIADB_ROOT_PASSWORD=)' "$TMP" 2>/dev/null | grep -q .; then echo 'ERRO: possível segredo detectado; pacote não criado.' >&2; exit 1; fi
tar -C "$TMP" -czf "$OUT" .; sha256sum "$OUT" >"$OUT.sha256"; echo "EVIDENCIAS=$OUT"; echo "SHA256_FILE=$OUT.sha256"
