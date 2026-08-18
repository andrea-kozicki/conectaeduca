#!/usr/bin/env bash
set -u

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"
WAZUH_DIR="$ROOT/deploy/interna/wazuh"
RUNTIME="$WAZUH_DIR/.runtime"
PROJECT="conectaeduca-wazuh"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/conectaeduca-wazuh-fase4g-c-${STAMP}.txt"
FAIL=0
STARTED=0

ok(){ echo "OK       $*"; }
fail(){ echo "FALHA    $*"; FAIL=$((FAIL+1)); }
info(){ echo "INFO     $*"; }

cleanup() {
  set +e
  if [[ "$STARTED" -eq 1 ]]; then
    (
      cd "$WAZUH_DIR" || exit 0
      docker compose -p "$PROJECT" -f compose.yml -f compose.lab.yml down --remove-orphans
    ) >/dev/null 2>&1
  fi
}
trap cleanup EXIT INT TERM

wait_dashboard() {
  local elapsed=0 code
  while (( elapsed <= 300 )); do
    code="$(curl -k -sS --max-time 8 -o /dev/null -w '%{http_code}' https://127.0.0.1:8443/ 2>/dev/null || true)"
    case "$code" in
      200|302) echo "dashboard_wait t=${elapsed}s http=$code"; return 0 ;;
    esac
    (( elapsed % 10 == 0 )) && echo "dashboard_wait t=${elapsed}s http=${code:-sem-resposta}"
    sleep 5
    elapsed=$((elapsed+5))
  done
  return 1
}

exec > >(tee "$REPORT") 2>&1

echo "======================================================================"
echo " CONECTAEDUCA - FASE 4G-C"
echo " Validação da configuração segura/versionável do Wazuh"
echo " Data: $(date --iso-8601=seconds)"
echo "======================================================================"

cd "$ROOT" || exit 1

echo
echo "=== BRANCH / GIT ==="
git status -sb
BRANCH="$(git branch --show-current 2>/dev/null || true)"
echo "branch_atual=$BRANCH"
[[ "$BRANCH" == "feature/auth-local" ]] \
  && ok "branch feature/auth-local confirmada" \
  || fail "branch incorreta"

git diff --check && ok "git diff --check" || fail "git diff --check"

echo
echo "=== HIGIENE DE SEGREDOS ==="
git check-ignore -q deploy/interna/wazuh/.runtime/manager.env \
  && ok ".runtime ignorado" \
  || fail ".runtime não ignorado"

if git ls-files deploy/interna/wazuh/.runtime | grep -q .; then
  fail "runtime sensível rastreado pelo Git"
else
  ok "nenhum runtime sensível rastreado"
fi

if grep -RqsF --exclude-dir=.runtime 'SecretPassword' "$WAZUH_DIR" \
   || grep -RqsF --exclude-dir=.runtime 'MyS3cr37P450r.*-' "$WAZUH_DIR"; then
  fail "credencial padrão encontrada em arquivo versionável"
else
  ok "credenciais padrão ausentes dos arquivos versionáveis"
fi

for f in manager.env dashboard.env internal_users.yml wazuh.yml; do
  [[ -f "$RUNTIME/$f" ]] && ok "runtime/$f presente" || fail "runtime/$f ausente"
done

for f in "$RUNTIME/manager.env" "$RUNTIME/dashboard.env" "$RUNTIME/internal_users.yml" "$RUNTIME/wazuh.yml"; do
  mode="$(stat -c '%a' "$f" 2>/dev/null || echo '?')"
  [[ "$mode" == "600" ]] \
    && ok "$(basename "$f") modo 600" \
    || fail "$(basename "$f") modo inesperado: $mode"
done

echo
echo "=== COMPOSE ==="
cd "$WAZUH_DIR" || exit 1
if docker compose -p "$PROJECT" -f compose.yml -f compose.lab.yml config >/dev/null; then
  ok "Compose base + laboratório válido"
else
  fail "Compose inválido"
fi

echo
echo "=== SUPERFÍCIE DE REDE DECLARADA ==="
CONFIG_JSON="$(docker compose -p "$PROJECT" -f compose.yml -f compose.lab.yml config --format json 2>/dev/null || true)"
python3 - "$CONFIG_JSON" <<'PY'
import json, sys
cfg = json.loads(sys.argv[1])
services = cfg["services"]
for name, s in services.items():
    print(name, "ports=", s.get("ports", []))
PY

if python3 - "$CONFIG_JSON" <<'PY'
import json, sys
cfg=json.loads(sys.argv[1])
svc=cfg["services"]
if svc["wazuh.manager"].get("ports"): raise SystemExit(1)
if svc["wazuh.indexer"].get("ports"): raise SystemExit(1)
ports=svc["wazuh.dashboard"].get("ports", [])
if len(ports) != 1: raise SystemExit(1)
p=ports[0]
if str(p.get("host_ip")) != "127.0.0.1" or int(p.get("published")) != 8443 or int(p.get("target")) != 5601:
    raise SystemExit(1)
PY
then
  ok "somente Dashboard 127.0.0.1:8443 é publicado no laboratório"
else
  fail "superfície de rede maior que a esperada"
fi

echo
echo "=== SUBIDA ==="
if docker compose -p "$PROJECT" -f compose.yml -f compose.lab.yml up -d; then
  STARTED=1
  ok "stack segura iniciou"
else
  fail "stack não iniciou"
fi

docker compose -p "$PROJECT" -f compose.yml -f compose.lab.yml ps || true

echo
echo "=== CERTIFICADOS DENTRO DOS COMPONENTES ==="
if docker compose -p "$PROJECT" -f compose.yml -f compose.lab.yml exec -T wazuh.indexer \
  bash -ec '
    test -r /usr/share/wazuh-indexer/config/certs/root-ca.pem
    test -r /usr/share/wazuh-indexer/config/certs/wazuh.indexer.pem
    test -r /usr/share/wazuh-indexer/config/certs/wazuh.indexer.key
    test -r /usr/share/wazuh-indexer/config/certs/admin.pem
    test -r /usr/share/wazuh-indexer/config/certs/admin-key.pem
  '
then ok "Indexer lê seus certificados"; else fail "certificados do Indexer"; fi

if docker compose -p "$PROJECT" -f compose.yml -f compose.lab.yml exec -T wazuh.manager \
  bash -ec '
    test -r /etc/ssl/root-ca.pem
    test -r /etc/ssl/filebeat.pem
    test -r /etc/ssl/filebeat.key
  '
then ok "Manager/Filebeat lê seus certificados"; else fail "certificados do Manager"; fi

if docker compose -p "$PROJECT" -f compose.yml -f compose.lab.yml exec -T wazuh.dashboard \
  bash -ec '
    test -r /usr/share/wazuh-dashboard/certs/root-ca.pem
    test -r /usr/share/wazuh-dashboard/certs/wazuh-dashboard.pem
    test -r /usr/share/wazuh-dashboard/certs/wazuh-dashboard-key.pem
  '
then ok "Dashboard lê seus certificados"; else fail "certificados do Dashboard"; fi

echo
echo "=== INDEXER COM CREDENCIAL GERADA ==="
INDEXER_RESULT="$(
  docker compose -p "$PROJECT" -f compose.yml -f compose.lab.yml exec -T wazuh.manager \
    bash -ec '
      for i in $(seq 1 60); do
        out="$(curl -k -sS --max-time 5 -u "$INDEXER_USERNAME:$INDEXER_PASSWORD" \
          https://wazuh.indexer:9200/_cluster/health 2>/dev/null || true)"
        if echo "$out" | grep -Eq "\"status\"[[:space:]]*:[[:space:]]*\"(green|yellow)\""; then
          echo "$out"
          exit 0
        fi
        sleep 5
      done
      exit 1
    ' 2>/dev/null || true
)"
if echo "$INDEXER_RESULT" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"(green|yellow)"'; then
  echo "$INDEXER_RESULT" | sed -E 's/"number_of_nodes":[0-9]+/"number_of_nodes":<n>/'
  ok "Indexer autenticou com senha aleatória da implantação"
else
  fail "Indexer não autenticou com credencial gerada"
fi

echo
echo "=== MANAGER API COM CREDENCIAL GERADA ==="
TOKEN="$(
  docker compose -p "$PROJECT" -f compose.yml -f compose.lab.yml exec -T wazuh.manager \
    bash -ec '
      for i in $(seq 1 60); do
        t="$(curl -k -sS --max-time 5 -u "$API_USERNAME:$API_PASSWORD" \
          -X POST "https://127.0.0.1:55000/security/user/authenticate?raw=true" 2>/dev/null || true)"
        case "$t" in eyJ*) printf "%s" "$t"; exit 0;; esac
        sleep 5
      done
      exit 1
    ' 2>/dev/null || true
)"
if [[ "$TOKEN" == eyJ* ]]; then
  ok "Manager API autenticou com senha aleatória"
else
  fail "Manager API não autenticou"
fi
unset TOKEN

echo
echo "=== DASHBOARD ==="
if wait_dashboard; then
  code="$(curl -k -sS -o /dev/null -w '%{http_code}' https://127.0.0.1:8443/)"
  echo "dashboard_http=$code"
  ok "Dashboard HTTPS acessível somente em loopback"
else
  fail "Dashboard não ficou acessível"
fi

echo
echo "=== AUSÊNCIA DAS CREDENCIAIS PADRÃO EM RUNTIME ==="
DEFAULT_FOUND=0
for svc in wazuh.manager wazuh.dashboard; do
  if docker compose -p "$PROJECT" -f compose.yml -f compose.lab.yml exec -T "$svc" env 2>/dev/null \
      | grep -Eq 'SecretPassword|MyS3cr37P450r\.\*-'; then
    DEFAULT_FOUND=1
  fi
done
if [[ "$DEFAULT_FOUND" -eq 0 ]]; then
  ok "credenciais padrão não aparecem nos ambientes dos containers"
else
  fail "credencial padrão encontrada no runtime"
fi

echo
echo "=== PORTAS REAIS ==="
IDS="$(docker compose -p "$PROJECT" -f compose.yml -f compose.lab.yml ps -q)"
docker ps --filter "label=com.docker.compose.project=$PROJECT" \
  --format 'table {{.Names}}\t{{.Ports}}'

NON_EXPECTED="$(
  for id in $IDS; do
    docker inspect "$id" --format '{{range $p,$b := .NetworkSettings.Ports}}{{range $b}}{{println $.Name $p .HostIp .HostPort}}{{end}}{{end}}'
  done | grep -vE '^/conectaeduca-wazuh-wazuh\.dashboard-1 5601/tcp 127\.0\.0\.1 8443$' || true
)"
if [[ -z "$NON_EXPECTED" ]]; then
  ok "nenhuma porta adicional publicada"
else
  echo "$NON_EXPECTED"
  fail "porta inesperada publicada"
fi

echo
echo "=== PERSISTÊNCIA PREPARADA ==="
VOL_COUNT="$(docker volume ls -q --filter "label=com.docker.compose.project=$PROJECT" | wc -l)"
echo "volumes_wazuh=$VOL_COUNT"
if (( VOL_COUNT >= 10 )); then
  ok "volumes nomeados criados e serão preservados para a 4G-D"
else
  fail "quantidade inesperada de volumes"
fi

echo
echo "=== ENCERRAMENTO SEM APAGAR VOLUMES ==="
if docker compose -p "$PROJECT" -f compose.yml -f compose.lab.yml down --remove-orphans; then
  STARTED=0
  ok "containers removidos e volumes preservados"
else
  fail "falha ao encerrar stack"
fi

REMAINING_CONTAINERS="$(docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" || true)"
[[ -z "$REMAINING_CONTAINERS" ]] \
  && ok "nenhum container residual" \
  || fail "container residual encontrado"

VOL_AFTER="$(docker volume ls -q --filter "label=com.docker.compose.project=$PROJECT" | wc -l)"
echo "volumes_preservados=$VOL_AFTER"
(( VOL_AFTER >= 10 )) \
  && ok "dados persistentes preservados para a próxima fase" \
  || fail "volumes não foram preservados"

echo
echo "=== GIT FINAL ==="
cd "$ROOT"
git status -sb
if git ls-files deploy/interna/wazuh/.runtime | grep -q .; then
  fail "runtime sensível rastreado"
else
  ok "runtime sensível continua fora do Git"
fi

echo
echo "=== RESULTADO ==="
echo "Falhas: $FAIL"
if [[ "$FAIL" -eq 0 ]]; then
  echo "FASE 4G-C: APROVADA."
  echo "Configuração Wazuh segura e versionável validada."
  echo "Volumes foram preservados para a Fase 4G-D."
else
  echo "FASE 4G-C: REPROVADA."
fi
echo "Relatório: $REPORT"
echo "======================================================================"

[[ "$FAIL" -eq 0 ]]
