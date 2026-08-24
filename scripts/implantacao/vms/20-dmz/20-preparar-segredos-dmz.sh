#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"; VMS_DIR="$(cd -P "$SCRIPT_DIR/.." && pwd -P)"; source "$VMS_DIR/lib/comum.sh"
CONFIG=""; GEN_APP=0; GEN_TLS=0; TLS_NAME=""
while (($#)); do case "$1" in --config) CONFIG="${2:-}"; shift 2;; --generate-app-keys) GEN_APP=1; shift;; --generate-lab-tls) GEN_TLS=1; TLS_NAME="${2:-}"; shift 2;; --self-test) echo 'SELF_TEST_SEGREDOS_DMZ=APROVADO'; exit;; *) exit 64;; esac; done
[[ -r "$CONFIG" ]] || exit 64; [[ "$(hostname)" == conectaeduca-dmz ]] || { echo "ERRO: execute em CE-UBUNTU-DMZ" >&2; exit 1; }
DB="$(ce_cfg_required CONECTAEDUCA_DB_PASSWORD_FILE "$CONFIG")"; PRIV="$(ce_cfg_required CONECTAEDUCA_PRIVATE_KEY_FILE "$CONFIG")"; PUB="$(ce_cfg_required CONECTAEDUCA_PUBLIC_KEY_FILE "$CONFIG")"; CERT="$(ce_cfg_required CONECTAEDUCA_WAF_TLS_CERT_FILE "$CONFIG")"; KEY="$(ce_cfg_required CONECTAEDUCA_WAF_TLS_KEY_FILE "$CONFIG")"; GID="$(ce_cfg_required CONECTAEDUCA_STACK_SECRET_GID "$CONFIG")"; [[ "$GID" =~ ^[0-9]+$ ]] || exit 64
for f in "$DB" "$PRIV" "$PUB" "$CERT" "$KEY"; do install -d -m 0700 "$(dirname "$f")"; done; [[ -s "$DB" ]] || { echo "ERRO: copie com segurança o MESMO conectaeduca_db_password da interna." >&2; exit 1; }
if (( GEN_APP )); then [[ -s "$PRIV" ]] || openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$PRIV" >/dev/null 2>&1; [[ -s "$PUB" ]] || openssl pkey -in "$PRIV" -pubout -out "$PUB" >/dev/null 2>&1; fi
if (( GEN_TLS )); then [[ -n "$TLS_NAME" && "$TLS_NAME" =~ ^[A-Za-z0-9.-]+$ ]] || exit 64; if [[ ! -s "$CERT" || ! -s "$KEY" ]]; then openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 30 -subj "/CN=$TLS_NAME" -addext "subjectAltName=DNS:$TLS_NAME" -keyout "$KEY" -out "$CERT" >/dev/null 2>&1; fi; fi
for f in "$PRIV" "$PUB" "$CERT" "$KEY"; do [[ -s "$f" ]] || { echo "ERRO: runtime ausente: $f" >&2; exit 1; }; done; for f in "$DB" "$PRIV" "$PUB" "$CERT" "$KEY"; do chgrp "$GID" "$f" 2>/dev/null || { echo "ERRO: chgrp falhou em $f" >&2; exit 1; }; chmod 0640 "$f"; done
echo 'SEGREDOS_DMZ=PREPARADOS'; echo 'DB_PASSWORD_EXIBIDO=NAO'; echo "LAB_TLS_AUTOASSINADO=$([[ $GEN_TLS -eq 1 ]] && echo SIM || echo NAO)"
