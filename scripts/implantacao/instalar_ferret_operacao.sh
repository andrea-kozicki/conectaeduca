#!/usr/bin/env bash
set -euo pipefail

REPO="/opt/conectaeduca"
HEALTH="$REPO/scripts/observabilidade/verificar_ferret_health.sh"
RETENTION="$REPO/scripts/dlp/limpar_retencao_ferret.sh"
RUNTIME="$REPO/deploy/interna/ferret/.runtime"
EVENTS="$RUNTIME/events/dlp.jsonl"

HEALTH_SERVICE="/etc/systemd/system/conectaeduca-ferret-healthcheck.service"
HEALTH_TIMER="/etc/systemd/system/conectaeduca-ferret-healthcheck.timer"
RET_SERVICE="/etc/systemd/system/conectaeduca-ferret-retention.service"
RET_TIMER="/etc/systemd/system/conectaeduca-ferret-retention.timer"
ROTATE="/etc/logrotate.d/conectaeduca-ferret-dlp"

MODE="${1:-install}"
case "$MODE" in
  install|--check) ;;
  *) echo "Uso: $0 [install|--check]" >&2; exit 2 ;;
esac

CURRENT_USER="$(id -un)"
BASH_BIN="$(command -v bash)"

check_files(){
  [[ -x "$HEALTH" ]]
  [[ -x "$RETENTION" ]]
  "$BASH_BIN" -n "$HEALTH"
  "$BASH_BIN" -n "$RETENTION"
  "$HEALTH" >/dev/null
  sudo -u '#1000' -- "$RETENTION" --dry-run >/dev/null
}

check_runtime(){
  systemctl is-enabled --quiet conectaeduca-ferret-healthcheck.timer
  systemctl is-active --quiet conectaeduca-ferret-healthcheck.timer
  systemctl is-enabled --quiet conectaeduca-ferret-retention.timer
  systemctl is-active --quiet conectaeduca-ferret-retention.timer
  [[ -f "$HEALTH_SERVICE" && -f "$HEALTH_TIMER" && -f "$RET_SERVICE" && -f "$RET_TIMER" && -f "$ROTATE" ]]
  grep -Fq "User=$CURRENT_USER" "$HEALTH_SERVICE"
  grep -Fq "ExecStart=$HEALTH" "$HEALTH_SERVICE"
  grep -Fq "User=1000" "$RET_SERVICE"
  grep -Fq "ExecStart=$RETENTION --apply" "$RET_SERVICE"
  grep -Fq "$EVENTS {" "$ROTATE"
}

check_files

if [[ "$MODE" == "--check" ]]; then
  check_runtime
  echo "PASS: operação Ferret instalada e coerente."
  exit 0
fi

TMPDIR_LOCAL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

cat >"$TMPDIR_LOCAL/health.service" <<EOF
[Unit]
Description=ConectaEduca Ferret HTTP health monitor
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$CURRENT_USER
ExecStart=$HEALTH
UMask=0077
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
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
EOF

cat >"$TMPDIR_LOCAL/health.timer" <<'EOF'
[Unit]
Description=ConectaEduca Ferret health monitor timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
AccuracySec=15s

[Install]
WantedBy=timers.target
EOF

cat >"$TMPDIR_LOCAL/retention.service" <<EOF
[Unit]
Description=ConectaEduca Ferret local retention cleanup
After=docker.service

[Service]
Type=oneshot
User=1000
ExecStart=$RETENTION --apply
Environment=FERRET_RETENTION_DAYS=7
UMask=0077
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
ReadWritePaths=$RUNTIME
EOF

cat >"$TMPDIR_LOCAL/retention.timer" <<'EOF'
[Unit]
Description=ConectaEduca Ferret retention timer

[Timer]
OnCalendar=daily
RandomizedDelaySec=30min

[Install]
WantedBy=timers.target
EOF

cat >"$TMPDIR_LOCAL/logrotate" <<EOF
$EVENTS {
    daily
    rotate 30
    maxage 30
    size 5M
    compress
    delaycompress
    copytruncate
    missingok
    notifempty
}
EOF

sudo install -m 0644 "$TMPDIR_LOCAL/health.service" "$HEALTH_SERVICE"
sudo install -m 0644 "$TMPDIR_LOCAL/health.timer" "$HEALTH_TIMER"
sudo install -m 0644 "$TMPDIR_LOCAL/retention.service" "$RET_SERVICE"
sudo install -m 0644 "$TMPDIR_LOCAL/retention.timer" "$RET_TIMER"
sudo install -m 0644 "$TMPDIR_LOCAL/logrotate" "$ROTATE"

sudo systemctl daemon-reload
sudo systemctl enable --now conectaeduca-ferret-healthcheck.timer >/dev/null
sudo systemctl enable --now conectaeduca-ferret-retention.timer >/dev/null

check_runtime
echo "PASS: health monitor, retenção e logrotate Ferret instalados."
