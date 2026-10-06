#!/usr/bin/env bash
# FREEZE-02 / EP125 - rebuild final da DMZ
# Branch de apoio: nao fazer merge em main antes do fechamento.
# Nao usa sudo -s, nao imprime segredos e nao altera Git.

EXPECTED_HEAD="c37bdce07a9ae71ceb1a1e0c8e0e1e2b51e112ce"
REPO="/opt/conectaeduca"
DMZ="$REPO/deploy/dmz"
OUT="$HOME/Downloads"
[ -d "$OUT" ] || OUT="$HOME"
STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
REPORT="$OUT/conectaeduca-freeze02-ep125-rebuild-$STAMP.txt"
FAIL=0

dc() {
  docker compose     -p conectaeduca-dmz     -f "$DMZ/compose.yml"     -f "$DMZ/compose.database.yml"     -f "$DMZ/compose.app-secrets.yml"     -f "$DMZ/compose.waf.yml"     -f "$DMZ/compose.waf-tls.yml"     -f "$DMZ/compose.waf-policy.yml"     -f "$DMZ/compose.host.yml"     -f "$DMZ/compose.vm.yml"     -f "$DMZ/compose.database-tls.yml"     "$@"
}

wait_health() {
  NAME="$1"
  LIMIT=$((SECONDS + 180))
  while [ "$SECONDS" -lt "$LIMIT" ]; do
    STATUS="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$NAME" 2>/dev/null)"
    if [ "$STATUS" = "healthy" ]; then
      echo "HEALTH=$NAME|PASS"
      return 0
    fi
    if [ "$STATUS" = "exited" ] || [ "$STATUS" = "dead" ]; then
      echo "HEALTH=$NAME|FAIL|$STATUS"
      return 1
    fi
    sleep 3
  done
  echo "HEALTH=$NAME|FAIL|timeout"
  return 1
}

echo "=== FREEZE-02 / EP125 REBUILD DMZ ==="
HOST="$(hostname)"
HEAD="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)"
BRANCH="$(git -C "$REPO" branch --show-current 2>/dev/null)"
DIRTY="$(git -C "$REPO" status --short 2>/dev/null)"

echo "HOST=$HOST"
echo "HEAD=$HEAD"
echo "BRANCH=$BRANCH"

[ "$HOST" = "ep125-pucpr" ] || { echo "HOST_MATCH=FAIL"; FAIL=1; }
[ "$HEAD" = "$EXPECTED_HEAD" ] || { echo "HEAD_MATCH=FAIL"; FAIL=1; }
[ "$BRANCH" = "main" ] || { echo "BRANCH_MAIN=FAIL"; FAIL=1; }
[ -z "$DIRTY" ] || { echo "WORKTREE_CLEAN=FAIL"; printf '%s\n' "$DIRTY"; FAIL=1; }

POLICY="$DMZ/waf/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf"
MODE="$(stat -c '%a' "$POLICY" 2>/dev/null)"
echo "WAF_POLICY_MODE_BEFORE=$MODE"
if [ "$FAIL" -eq 0 ] && [ "$MODE" != "644" ]; then
  chmod 0644 "$POLICY"
  MODE="$(stat -c '%a' "$POLICY" 2>/dev/null)"
  echo "WAF_POLICY_MODE_AFTER=$MODE"
fi
[ "$MODE" = "644" ] || FAIL=1

export CONECTAEDUCA_SOURCE_COMMIT="$EXPECTED_HEAD"
export CONECTAEDUCA_WAF_BIND_ADDRESS="192.168.6.34"
export CONECTAEDUCA_HTTP_PORT="80"
export CONECTAEDUCA_HTTPS_PORT="443"
export CONECTAEDUCA_DB_HOST="192.168.6.50"
export CONECTAEDUCA_DB_PORT="3306"
export CONECTAEDUCA_DB_PASSWORD_FILE="/etc/conectaeduca/secrets/dmz/conectaeduca_db_password"
export CONECTAEDUCA_DB_TLS_CA_FILE="/etc/conectaeduca/pki/mariadb/ca.crt"
export CONECTAEDUCA_PRIVATE_KEY_FILE="/etc/conectaeduca/secrets/dmz/app_private.pem"
export CONECTAEDUCA_PUBLIC_KEY_FILE="/etc/conectaeduca/secrets/dmz/app_public.pem"
export CONECTAEDUCA_WAF_TLS_CERT_FILE="/etc/conectaeduca/secrets/dmz/waf_tls.crt"
export CONECTAEDUCA_WAF_TLS_KEY_FILE="/etc/conectaeduca/secrets/dmz/waf_tls.key"
export CONECTAEDUCA_APP_URL="https://192.168.6.34"
export CONECTAEDUCA_STACK_SECRET_GID="996"

CONFIG_RC=99
BUILD_RC=99
UP_RC=99

if [ "$FAIL" -eq 0 ]; then
  dc config -q
  CONFIG_RC=$?
  echo "COMPOSE_CONFIG_RC=$CONFIG_RC"
  [ "$CONFIG_RC" -eq 0 ] || FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  dc build php nginx waf
  BUILD_RC=$?
  echo "BUILD_RC=$BUILD_RC"
  [ "$BUILD_RC" -eq 0 ] || FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  dc up -d
  UP_RC=$?
  echo "UP_RC=$UP_RC"
  [ "$UP_RC" -eq 0 ] || FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  wait_health conectaeduca-dmz-php-1 || FAIL=1
  wait_health conectaeduca-dmz-nginx-1 || FAIL=1
  wait_health conectaeduca-dmz-waf-1 || FAIL=1
fi

docker ps --filter label=com.docker.compose.project=conectaeduca-dmz   --format 'NAME={{.Names}} IMAGE={{.Image}} STATUS={{.Status}}'

{
  echo "=== CONECTAEDUCA FREEZE-02 / EP125 REBUILD ==="
  echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "HOST=$HOST"
  echo "HEAD=$(git -C "$REPO" rev-parse HEAD 2>/dev/null)"
  echo "BRANCH=$(git -C "$REPO" branch --show-current 2>/dev/null)"
  echo "WORKTREE_CLEAN=$([ -z "$(git -C "$REPO" status --short 2>/dev/null)" ] && echo PASS || echo FAIL)"
  echo "COMPOSE_CONFIG_RC=$CONFIG_RC"
  echo "BUILD_RC=$BUILD_RC"
  echo "UP_RC=$UP_RC"
  echo "WAF_POLICY_MODE=$MODE"
  if [ "$FAIL" -eq 0 ]; then
    echo "FREEZE02_DMZ_REBUILD=PASS"
  else
    echo "FREEZE02_DMZ_REBUILD=FAIL"
  fi
  echo "SECRET_VALUES_RECORDED=NO"
} > "$REPORT"

sha256sum "$REPORT" > "$REPORT.sha256"
echo "REPORT=$REPORT"
echo "REPORT_SHA256=$(awk '{print $1}' "$REPORT.sha256")"

[ "$FAIL" -eq 0 ]
