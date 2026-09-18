#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel)}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT="${1:-/tmp/conectaeduca-correcoes-codex-$STAMP.txt}"
PASS=0; FAIL=0
cd "$ROOT"

ok(){ echo "[PASS] $*"; PASS=$((PASS+1)); }
bad(){ echo "[FAIL] $*"; FAIL=$((FAIL+1)); }
has(){ grep -Fq -- "$2" "$1" && ok "$3" || bad "$3"; }

exec 3> >(tee "$REPORT")
{
  echo "ConectaEduca — regressão das correções Codex"
  echo "UTC=$STAMP"
  has scripts/evidencias/testar_container_mariadb_fase4c.sh 'exec 3> >(tee "$REPORT")' "gate MariaDB preserva FAIL"
  has scripts/release/gerar_handoff.sh 'scripts/bootstrap/materializar_bacula_catalog_secret.py' "handoff inclui dependência do Catalog"
  has deploy/interna/bacula/compose.postgresql-hardening.yml '99z-conectaeduca-hostssl.sh' "fresh volume monta hostssl/TLS"
  has deploy/interna/bacula/compose.storage-hardening.yml 'chmod 0750 /backup' "Storage reaplica modo do volume"
  has deploy/interna/bacula/compose.vm.yml '192.168.6.50:9103:9103' "Storage possui binding privado"
  has scripts/implantacao/instalar_openbao_wazuh_bridge.sh 'Restart=on-failure' "bridge OpenBao/Wazuh reinicia em falha"
  has deploy/interna/wazuh/compose.yml './.runtime/internal_users.yml:/usr/share/wazuh-indexer/config/opensearch-security/internal_users.yml:ro' "Indexer monta internal_users runtime em read-only"
  has scripts/implantacao/reconciliar_wazuh_dashboard_acl.sh 'WAZUH_DASHBOARD_ACL_REPRODUCIBLE=1' "reconciliador ACL Wazuh é versionado"
  has scripts/implantacao/instalar_ferret_operacao.sh '    daily' "logrotate Ferret preserva rotação diária"
  has scripts/observabilidade/verificar_ferret_health.sh 'URL="${FERRET_HEALTH_URL:-http://127.0.0.1:18082/health}"' "health URL Ferret possui default versionado"
  has scripts/dlp/processar_inbox_ferret.sh 'processed-runs.tsv' "retenção correlaciona execução"

  while IFS= read -r f; do
    bash -n "$f" && ok "bash -n $f" || bad "bash -n $f"
  done < <(git diff --name-only --diff-filter=ACM | while read -r f; do
    head -n1 "$f" 2>/dev/null | grep -Eq '^#!.*(bash|sh)' && echo "$f" || true
  done)

  git diff --check >/dev/null && ok "git diff --check" || bad "git diff --check"
  echo "PASS=$PASS WARN=0 FAIL=$FAIL GAP=0"
} >&3
exec 3>&-

sha256sum "$REPORT" >"$REPORT.sha256"
echo "ARQUIVO_SAIDA=$REPORT"
echo "SHA256_FILE=$REPORT.sha256"
(( FAIL == 0 ))