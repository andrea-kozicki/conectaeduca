#!/usr/bin/env bash
# EP125 / 18A — auditoria: diagnostico NAO DESTRUTIVO de persistencia e coleta.
# Nao imprime logs, variaveis de ambiente, configuracoes ou segredos.
set -Eeuo pipefail
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"
mkdir -p "$BASE/HOMOLOG"
OUT="$BASE/HOMOLOG/EP125_HOMOLOG_ETAPA18A_$(date +%Y%m%dT%H%M%S).txt"
{
 echo "ETAPA=18A DATA=$(date --iso-8601=seconds) HOST=$(hostname)"
 cd /opt/conectaeduca
 echo "BRANCH=$(git branch --show-current)"
 echo "HEAD=$(git rev-parse --short HEAD)"
 echo "GIT_STATUS_INICIO"
 git status --short
 echo "GIT_STATUS_FIM"
 echo "COMPOSE_AUDIT_PERSISTENT_EXISTE=$([ -f deploy/dmz/compose.audit-persistent.yml ] && echo SIM || echo NAO)"
 echo "COMPOSE_AUDIT_PERSISTENT_TRACKED=$(git ls-files --error-unmatch deploy/dmz/compose.audit-persistent.yml >/dev/null 2>&1 && echo SIM || echo NAO)"
 echo "CONTAINERS_AUDITORIA"
 docker ps --format '{{.Names}}|{{.Status}}' | grep -Ei 'php|wazuh|nginx|waf' || true
 PHP="${PHP_CONTAINER:-conectaeduca-dmz-php-1}"
 echo "PHP_CONTAINER=$PHP"
 docker inspect "$PHP" --format 'PHP_STATUS={{.State.Status}} PHP_HEALTH={{if .State.Health}}{{.State.Health.Status}}{{else}}NA{{end}}'
 echo "MOUNTS_PHP_SEM_CAMINHOS_HOST"
 docker inspect "$PHP" --format '{{range .Mounts}}MOUNT_TYPE={{.Type}} DEST={{.Destination}} RW={{.RW}}{{println}}{{end}}'
 echo "AUDIT_PATH_DIAGNOSTICO"
 docker exec -i "$PHP" sh -s <<'INNER'
set -eu
for p in /var/www/conectaeduca/storage /var/www/conectaeduca/storage/logs /var/www/conectaeduca/storage/logs/audit.log; do
 if [ -e "$p" ]; then
  if [ -d "$p" ]; then
   echo "PATH=$p TYPE=DIR"
  elif [ -f "$p" ]; then
   echo "PATH=$p TYPE=FILE"
  else
   echo "PATH=$p TYPE=OTHER"
  fi
  [ -r "$p" ] && echo "READABLE=YES" || echo "READABLE=NO"
  [ -w "$p" ] && echo "WRITABLE=YES" || echo "WRITABLE=NO"
 else
  echo "PATH=$p EXISTS=NO"
 fi
done
if [ -f /var/www/conectaeduca/storage/logs/audit.log ]; then
 stat -c 'AUDIT_BYTES=%s AUDIT_MTIME=%y' /var/www/conectaeduca/storage/logs/audit.log 2>/dev/null || true
fi
INNER
 echo "WAZUH_AGENT_SERVICOS"
 if command -v systemctl >/dev/null 2>&1; then
  systemctl is-active wazuh-agent 2>/dev/null || true
 fi
 echo "COMPOSE_CONFIG_NAO_RENDERIZADA=SIM"
 echo "CONTAINER_RESTART=NAO CONFIG_ALTERADA=NAO LOG_CONTENT_READ=NAO"
} > "$OUT" 2>&1 || { rc=$?; cat "$OUT"; exit "$rc"; }
cat "$OUT"
sha256sum "$OUT"
