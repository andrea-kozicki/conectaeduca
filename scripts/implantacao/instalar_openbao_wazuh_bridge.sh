#!/usr/bin/env bash
set -euo pipefail

REPO="/opt/conectaeduca"
SAN="$REPO/scripts/observabilidade/sanitizar_openbao_audit.py"
EVENT_DIR="$REPO/deploy/interna/openbao/.runtime/events"
EVENT_FILE="$EVENT_DIR/openbao-audit.jsonl"
UNIT_NAME="conectaeduca-openbao-audit-bridge.service"
UNIT="/etc/systemd/system/$UNIT_NAME"
ROTATE="/etc/logrotate.d/conectaeduca-openbao-audit"
CTR="conectaeduca-openbao"

MODE="${1:-install}"
if [[ "$MODE" != "install" && "$MODE" != "--check" ]]; then
  echo "Uso: $0 [install|--check]" >&2
  exit 2
fi

CURRENT_USER="$(id -un)"
CURRENT_GROUP="$(id -gn)"
PYBIN="$(command -v python3)"
DOCKERBIN="/usr/bin/docker"

check_base() {
  [[ -f "$SAN" ]] || { echo "ERRO: sanitizador ausente: $SAN" >&2; return 1; }
  [[ -x "$DOCKERBIN" ]] || { echo "ERRO: docker ausente no caminho confiável: $DOCKERBIN" >&2; return 1; }
  "$PYBIN" -m py_compile "$SAN"
  "$DOCKERBIN" logs --tail 1 "$CTR" >/dev/null 2>&1 || {
    echo "ERRO: usuário atual não acessa docker logs de $CTR" >&2
    return 1
  }
}

check_runtime() {
  systemctl is-enabled --quiet "$UNIT_NAME"
  systemctl is-active --quiet "$UNIT_NAME"
  [[ -f "$UNIT" ]]
  [[ -f "$ROTATE" ]]
  grep -Fq "User=$CURRENT_USER" "$UNIT"
  grep -Fxq "ExecStart=$PYBIN $SAN --follow" "$UNIT"
  grep -Fq "NoNewPrivileges=true" "$UNIT"
  grep -Fq "ProtectSystem=strict" "$UNIT"
  grep -Fq "ReadWritePaths=$EVENT_DIR" "$UNIT"
  grep -Fxq "Restart=always" "$UNIT"
  grep -Fq "$EVENT_FILE {" "$ROTATE"
}

check_base

if [[ "$MODE" == "--check" ]]; then
  check_runtime
  echo "PASS: bridge OpenBao/Wazuh instalada e coerente com o checkout atual."
  exit 0
fi

install -d -m 0750 "$EVENT_DIR"

TMP_UNIT="$(mktemp)"
TMP_ROTATE="$(mktemp)"
trap 'rm -f "$TMP_UNIT" "$TMP_ROTATE"' EXIT

cat >"$TMP_UNIT" <<EOF
[Unit]
Description=ConectaEduca OpenBao audit sanitizer bridge
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=$CURRENT_USER
ExecStart=$PYBIN $SAN --follow
Restart=always
RestartSec=3
UMask=0027
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
MemoryDenyWriteExecute=true
CapabilityBoundingSet=
ReadWritePaths=$EVENT_DIR

[Install]
WantedBy=multi-user.target
EOF

cat >"$TMP_ROTATE" <<EOF
$EVENT_FILE {
    daily
    rotate 7
    size 5M
    compress
    delaycompress
    copytruncate
    missingok
    notifempty
}
EOF

sudo install -m 0644 "$TMP_UNIT" "$UNIT"
sudo install -m 0644 "$TMP_ROTATE" "$ROTATE"
sudo systemctl daemon-reload
sudo systemctl enable "$UNIT_NAME" >/dev/null

# A unit já ativa precisa ser reiniciada explicitamente: daemon-reload e
# enable --now não substituem o processo existente nem recarregam o Python.
sudo systemctl restart "$UNIT_NAME"

check_runtime
echo "PASS: bridge OpenBao/Wazuh instalada/revalidada."