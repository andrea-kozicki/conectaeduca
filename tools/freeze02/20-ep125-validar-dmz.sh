#!/usr/bin/env bash
# FREEZE-02 / EP125 - validacao tecnica pos-rebuild
# Nao armazena credenciais. Login/MFA/RBAC continua como smoke manual curto.

EXPECTED_HEAD="c37bdce07a9ae71ceb1a1e0c8e0e1e2b51e112ce"
REPO="/opt/conectaeduca"
DMZ="$REPO/deploy/dmz"
OUT="$HOME/Downloads"
[ -d "$OUT" ] || OUT="$HOME"
STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
REPORT="$OUT/conectaeduca-freeze02-ep125-validacao-$STAMP.txt"
FAIL=0

echo "=== FREEZE-02 / EP125 VALIDACAO POS-REBUILD ==="

HOST="$(hostname)"
HEAD="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)"
BRANCH="$(git -C "$REPO" branch --show-current 2>/dev/null)"
DIRTY="$(git -C "$REPO" status --short 2>/dev/null)"

[ "$HOST" = "ep125-pucpr" ] || { echo "HOST_MATCH=FAIL"; FAIL=1; }
[ "$HEAD" = "$EXPECTED_HEAD" ] || { echo "HEAD_MATCH=FAIL"; FAIL=1; }
[ "$BRANCH" = "main" ] || { echo "BRANCH_MAIN=FAIL"; FAIL=1; }
[ -z "$DIRTY" ] || { echo "WORKTREE_CLEAN=FAIL"; printf '%s\n' "$DIRTY"; FAIL=1; }

for NAME in conectaeduca-dmz-php-1 conectaeduca-dmz-nginx-1 conectaeduca-dmz-waf-1; do
  STATUS="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$NAME" 2>/dev/null)"
  IMAGE_ID="$(docker inspect -f '{{.Image}}' "$NAME" 2>/dev/null)"
  REV="$(docker inspect -f '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$NAME" 2>/dev/null)"
  echo "CONTAINER=$NAME|HEALTH=$STATUS|IMAGE_ID=$IMAGE_ID|REVISION=$REV"
  [ "$STATUS" = "healthy" ] || FAIL=1
  [ "$REV" = "$EXPECTED_HEAD" ] || FAIL=1
done

HOST_LOCK="$(sha256sum "$REPO/composer.lock" 2>/dev/null | awk '{print $1}')"
CONT_LOCK="$(docker exec conectaeduca-dmz-php-1 sha256sum /var/www/conectaeduca/composer.lock 2>/dev/null | awk '{print $1}')"
echo "HOST_COMPOSER_LOCK_SHA256=$HOST_LOCK"
echo "CONTAINER_COMPOSER_LOCK_SHA256=$CONT_LOCK"
if [ -n "$HOST_LOCK" ] && [ "$HOST_LOCK" = "$CONT_LOCK" ]; then
  echo "COMPOSER_LOCK_MATCH=PASS"
else
  echo "COMPOSER_LOCK_MATCH=FAIL"
  FAIL=1
fi

docker exec conectaeduca-dmz-php-1 sh -lc   'test ! -e /var/www/conectaeduca/vendor/phpunit && test ! -e /var/www/conectaeduca/vendor/bin/phpunit'
if [ "$?" -eq 0 ]; then
  echo "VENDOR_NO_DEV_PHPUNIT=PASS"
else
  echo "VENDOR_NO_DEV_PHPUNIT=FAIL"
  FAIL=1
fi

POLICY="$DMZ/waf/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf"
HOST_POLICY="$(sha256sum "$POLICY" 2>/dev/null | awk '{print $1}')"
LIVE_POLICY="$(docker exec conectaeduca-dmz-waf-1 sha256sum /etc/modsecurity.d/owasp-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf 2>/dev/null | awk '{print $1}')"
echo "WAF_POLICY_HOST_SHA256=$HOST_POLICY"
echo "WAF_POLICY_LIVE_SHA256=$LIVE_POLICY"
if [ -n "$HOST_POLICY" ] && [ "$HOST_POLICY" = "$LIVE_POLICY" ]; then
  echo "WAF_POLICY_MATCH=PASS"
else
  echo "WAF_POLICY_MATCH=FAIL"
  FAIL=1
fi

docker exec conectaeduca-dmz-waf-1 grep -Fq   'ctl:ruleRemoveTargetById=932240;ARGS:senha'   /etc/modsecurity.d/owasp-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
if [ "$?" -eq 0 ]; then
  echo "LOGIN_932240_EXCLUSION=ACTIVE"
else
  echo "LOGIN_932240_EXCLUSION=MISSING"
  FAIL=1
fi

docker exec conectaeduca-dmz-waf-1 nginx -t >/dev/null 2>&1
if [ "$?" -eq 0 ]; then
  echo "WAF_NGINX_TEST=PASS"
else
  echo "WAF_NGINX_TEST=FAIL"
  FAIL=1
fi

HTTP_CODE="$(curl -k -sS --max-time 8 -o /dev/null -w '%{http_code}'   --resolve conectaeduca.local:443:192.168.6.34   https://conectaeduca.local/healthz 2>/dev/null)"
echo "HTTPS_HEALTHZ_CODE=$HTTP_CODE"
case "$HTTP_CODE" in
  200|204) echo "HTTPS_HEALTHZ=PASS" ;;
  *) echo "HTTPS_HEALTHZ=FAIL"; FAIL=1 ;;
esac

if systemctl is-active --quiet suricata; then
  echo "SURICATA_ACTIVE=PASS"
else
  echo "SURICATA_ACTIVE=FAIL"
  FAIL=1
fi

if systemctl is-active --quiet wazuh-agent; then
  echo "WAZUH_AGENT_ACTIVE=PASS"
else
  echo "WAZUH_AGENT_ACTIVE=FAIL"
  FAIL=1
fi

{
  echo "=== CONECTAEDUCA FREEZE-02 / EP125 VALIDACAO ==="
  echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "HOST=$HOST"
  echo "HEAD=$HEAD"
  echo "HOST_COMPOSER_LOCK_SHA256=$HOST_LOCK"
  echo "CONTAINER_COMPOSER_LOCK_SHA256=$CONT_LOCK"
  echo "WAF_POLICY_HOST_SHA256=$HOST_POLICY"
  echo "WAF_POLICY_LIVE_SHA256=$LIVE_POLICY"
  echo "HTTPS_HEALTHZ_CODE=$HTTP_CODE"
  echo "MANUAL_AUTH_SMOKE_REQUIRED=YES"
  echo "MANUAL_AUTH_SMOKE_SCOPE=login_mfa_rbac"
  if [ "$FAIL" -eq 0 ]; then
    echo "FREEZE02_DMZ_TECHNICAL_VALIDATION=PASS"
  else
    echo "FREEZE02_DMZ_TECHNICAL_VALIDATION=FAIL"
  fi
  echo "SECRET_VALUES_RECORDED=NO"
} > "$REPORT"

sha256sum "$REPORT" > "$REPORT.sha256"
echo "REPORT=$REPORT"
echo "REPORT_SHA256=$(awk '{print $1}' "$REPORT.sha256")"
echo "NEXT=smoke manual login/MFA/RBAC no navegador; nao registrar senha/TOTP."

[ "$FAIL" -eq 0 ]
