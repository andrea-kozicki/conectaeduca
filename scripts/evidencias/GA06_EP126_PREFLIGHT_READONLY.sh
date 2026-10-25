#!/usr/bin/env bash
# GA-06 / PA-07 — preflight EP126 SOMENTE LEITURA antes de change control.
# Nao executa sudo, docker run/up/load/pull/restart, backups ou leitura de logs brutos.
set -u
echo "=== GA06 EP126 PREFLIGHT READ-ONLY ==="
echo "DATA=$(date --iso-8601=seconds)"
echo "HOST=$(hostname -s)"
if [[ "$(hostname -s)" != "ep126-pucpr" || "$(id -u)" -eq 0 ]]; then
  echo "BLOQUEIO: somente usuario comum na EP126"; exit 2
fi
for t in docker curl python3; do
  command -v "$t" >/dev/null 2>&1 || { echo "BLOQUEIO: falta $t"; exit 2; }
done
ROOT="/opt/conectaeduca"
if [[ -n "$(printenv PROJECT_ROOT 2>/dev/null)" ]]; then ROOT="$(printenv PROJECT_ROOT)"; fi
BASE="$ROOT/deploy/interna/ferret/compose.yml"
[[ -f "$BASE" ]] || {
  echo "BLOQUEIO: nao encontrei $BASE; definir PROJECT_ROOT para o checkout correto"; exit 2;
}
docker info --format '{{.ServerVersion}}' >/dev/null 2>&1 || {
  echo "BLOQUEIO: Docker inacessivel ao usuario atual; NAO alterar grupos/sudo"; exit 2;
}
docker compose version >/dev/null 2>&1 || { echo "BLOQUEIO: Docker Compose ausente"; exit 2; }

echo "=== Imagem declarada pelo Compose ==="
declared="$(docker compose -f "$BASE" config --images 2>/dev/null)" || {
  echo "BLOQUEIO: compose config falhou"; exit 2;
}
printf '%s\n' "$declared"
echo "=== Container atual ==="
cid="$(docker compose -f "$BASE" ps -q ferret 2>/dev/null)" || exit 2
[[ -n "$cid" ]] || { echo "BLOQUEIO: Ferret nao encontrado; nao iniciar via preflight"; exit 1; }
echo "CONTAINER_ID=$cid"

echo "=== Metadados de seguranca (sem secrets ou volumes do host) ==="
docker inspect --format 'IMAGE_ID={{.Image}}
USER={{.Config.User}}
READONLY_ROOTFS={{.HostConfig.ReadonlyRootfs}}
RESTART_POLICY={{.HostConfig.RestartPolicy.Name}}
PIDS_LIMIT={{.HostConfig.PidsLimit}}
MEMORY_LIMIT_BYTES={{.HostConfig.Memory}}
NANO_CPUS={{.HostConfig.NanoCpus}}
CAP_DROP={{json .HostConfig.CapDrop}}
SECURITY_OPT={{json .HostConfig.SecurityOpt}}
TMPFS={{json .HostConfig.Tmpfs}}' "$cid" || exit 2
echo "=== Destinos dos mounts (nao inclui origem/arquivos) ==="
docker inspect --format '{{range .Mounts}}{{println .Destination}}{{end}}' "$cid" || true

echo "=== Imagem declarada disponivel localmente? ==="
docker image inspect "$declared" --format 'DECLARED_IMAGE_ID={{.Id}}' 2>/dev/null ||
  echo "AVISO: imagem declarada nao identificada pelo Docker image inspect"

echo "=== Health via loopback 127.0.0.1:18082 ==="
if body="$(curl --noproxy '*' -fsS --max-time 6 http://127.0.0.1:18082/health 2>/dev/null)"; then
  printf '%s' "$body" | python3 -c '
import json,sys
try:
 d=json.load(sys.stdin)
 print("HEALTH_STATUS="+str(d.get("status","MISSING")))
 print("HEALTH_SERVICE="+str(d.get("service","MISSING")))
 print("HEALTH_VERSION="+str(d.get("version","MISSING")))
 print("HEALTH_BASELINE_2_4_3="+str(d.get("version")=="2.4.3").upper())
except Exception:
 print("AVISO: JSON de health inesperado")
'
else
  echo "AVISO: health indisponivel, nao iniciar ou reiniciar"
fi
echo "=== Status dos timers e Wazuh agent ==="
for unit in conectaeduca-ferret-healthcheck.timer conectaeduca-ferret-retention.timer wazuh-agent; do
  enabled="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
  active="$(systemctl is-active "$unit" 2>/dev/null || true)"
  printf '%s | enabled=%s | active=%s\n' "$unit" "$enabled" "$active"
done
echo "=== FIM | SEM MUTACAO DE CONTÊINER, IMAGEM OU RUNTIME ==="
echo "Revisar a saida antes de compartilhar; nenhum dado bruto do Ferret foi lido."
