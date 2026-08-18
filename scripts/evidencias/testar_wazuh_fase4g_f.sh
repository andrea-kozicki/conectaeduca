#!/usr/bin/env bash
set -u
export LC_ALL=C
export LANG=C

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"
WAZUH_DIR="$ROOT/deploy/interna/wazuh"
RUNTIME="$WAZUH_DIR/.runtime"
PROJECT="conectaeduca-wazuh"
WAZUH_VERSION="4.14.7"
POLICY_ID="conectaeduca-alertas-retencao-30d"
POLICY_FILE="$WAZUH_DIR/config/ism/conectaeduca-alertas-retencao-30d.json"

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/conectaeduca-wazuh-fase4g-f-${STAMP}.txt"
TEST_INDEX="wazuh-alerts-conectaeduca-checkpoint-${STAMP}"
MARKER="/var/ossec/etc/.conectaeduca-fase4g-f.marker"
TOKEN="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(16))
PY
)"

FAIL=0
STARTED=0

ok(){ echo "OK       $*"; }
fail(){ echo "FALHA    $*"; FAIL=$((FAIL+1)); }
info(){ echo "INFO     $*"; }

compose() {
  docker compose \
    -p "$PROJECT" \
    -f "$WAZUH_DIR/compose.yml" \
    -f "$WAZUH_DIR/compose.lab.yml" \
    "$@"
}

wait_indexer() {
  local elapsed=0 out
  while (( elapsed <= 300 )); do
    out="$(
      compose exec -T wazuh.manager \
        bash -ec '
          curl -k -sS --max-time 5 \
            -u "$INDEXER_USERNAME:$INDEXER_PASSWORD" \
            https://wazuh.indexer:9200/_cluster/health
        ' 2>/dev/null || true
    )"
    if printf '%s' "$out" |
       grep -Eq '"status"[[:space:]]*:[[:space:]]*"(green|yellow)"'
    then
      echo "indexer_wait t=${elapsed}s status=ok"
      return 0
    fi
    (( elapsed % 10 == 0 )) && echo "indexer_wait t=${elapsed}s aguardando"
    sleep 5
    elapsed=$((elapsed+5))
  done
  return 1
}

wait_manager_api() {
  local elapsed=0 token
  while (( elapsed <= 300 )); do
    token="$(
      compose exec -T wazuh.manager \
        bash -ec '
          curl -k -sS --max-time 5 \
            -u "$API_USERNAME:$API_PASSWORD" \
            -X POST \
            "https://127.0.0.1:55000/security/user/authenticate?raw=true"
        ' 2>/dev/null || true
    )"
    case "$token" in
      eyJ*)
        echo "manager_api_wait t=${elapsed}s token=obtido"
        return 0
        ;;
    esac
    (( elapsed % 10 == 0 )) && echo "manager_api_wait t=${elapsed}s aguardando"
    sleep 5
    elapsed=$((elapsed+5))
  done
  return 1
}

wait_dashboard() {
  local elapsed=0 code
  while (( elapsed <= 300 )); do
    code="$(
      curl -k -sS --max-time 8 \
        -o /dev/null \
        -w '%{http_code}' \
        https://127.0.0.1:8443/ \
        2>/dev/null || true
    )"
    case "$code" in
      200|302)
        echo "dashboard_wait t=${elapsed}s http=$code"
        return 0
        ;;
    esac
    (( elapsed % 10 == 0 )) && echo "dashboard_wait t=${elapsed}s http=${code:-sem-resposta}"
    sleep 5
    elapsed=$((elapsed+5))
  done
  return 1
}

stack_health() {
  local label="$1"
  echo
  echo "=== SAÚDE DA STACK — $label ==="

  if wait_indexer; then
    ok "Indexer funcional ($label)"
  else
    fail "Indexer indisponível ($label)"
  fi

  if wait_manager_api; then
    ok "Manager API funcional ($label)"
  else
    fail "Manager API indisponível ($label)"
  fi

  if wait_dashboard; then
    ok "Dashboard funcional ($label)"
  else
    fail "Dashboard indisponível ($label)"
  fi
}

indexer_request() {
  local method="$1"
  local path="$2"
  local data="${3:-}"

  if [[ -n "$data" ]]; then
    printf '%s' "$data" |
      compose exec -T wazuh.manager \
        bash -ec '
          method="$1"
          path="$2"
          curl -k -sS --max-time 20 \
            -u "$INDEXER_USERNAME:$INDEXER_PASSWORD" \
            -H "Content-Type: application/json" \
            -X "$method" \
            "https://wazuh.indexer:9200/$path" \
            --data-binary @-
        ' bash "$method" "$path"
  else
    compose exec -T wazuh.manager \
      bash -ec '
        method="$1"
        path="$2"
        curl -k -sS --max-time 20 \
          -u "$INDEXER_USERNAME:$INDEXER_PASSWORD" \
          -X "$method" \
          "https://wazuh.indexer:9200/$path"
      ' bash "$method" "$path"
  fi
}

indexer_status() {
  local method="$1"
  local path="$2"
  local data="${3:-}"

  if [[ -n "$data" ]]; then
    printf '%s' "$data" |
      compose exec -T wazuh.manager \
        bash -ec '
          method="$1"
          path="$2"
          curl -k -sS --max-time 20 \
            -o /tmp/conectaeduca-checkpoint-response.json \
            -w "%{http_code}" \
            -u "$INDEXER_USERNAME:$INDEXER_PASSWORD" \
            -H "Content-Type: application/json" \
            -X "$method" \
            "https://wazuh.indexer:9200/$path" \
            --data-binary @-
        ' bash "$method" "$path"
  else
    compose exec -T wazuh.manager \
      bash -ec '
        method="$1"
        path="$2"
        curl -k -sS --max-time 20 \
          -o /tmp/conectaeduca-checkpoint-response.json \
          -w "%{http_code}" \
          -u "$INDEXER_USERNAME:$INDEXER_PASSWORD" \
          -X "$method" \
          "https://wazuh.indexer:9200/$path"
      ' bash "$method" "$path"
  fi
}

list_volumes() {
  docker volume ls \
    --filter "label=com.docker.compose.project=$PROJECT" \
    --format '{{.Name}}' |
    sort
}

volume_size_kb() {
  local vol="$1"
  docker run --rm \
    --user 0:0 \
    --entrypoint /bin/bash \
    -v "$vol:/data:ro" \
    "wazuh/wazuh-manager:${WAZUH_VERSION}" \
    -ec 'du -sk /data 2>/dev/null | awk "{print \$1}"' \
    2>/dev/null || echo 0
}

cleanup() {
  set +e
  if [[ "$STARTED" -eq 1 ]]; then
    compose exec -T wazuh.manager \
      bash -ec 'rm -f /var/ossec/etc/.conectaeduca-fase4g-f.marker' \
      >/dev/null 2>&1 || true

    compose exec -T wazuh.manager \
      bash -ec '
        curl -k -sS --max-time 10 \
          -u "$INDEXER_USERNAME:$INDEXER_PASSWORD" \
          -X DELETE \
          "https://wazuh.indexer:9200/'"$TEST_INDEX"'" \
          >/dev/null 2>&1 || true
      ' >/dev/null 2>&1 || true

    compose down --remove-orphans >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

exec > >(tee "$REPORT") 2>&1

echo "======================================================================"
echo " CONECTAEDUCA - FASE 4G-F"
echo " CHECKPOINT FINAL DO WAZUH"
echo " Data: $(date --iso-8601=seconds)"
echo " Wazuh: $WAZUH_VERSION"
echo "======================================================================"

cd "$ROOT" || exit 1

echo
echo "=== 1. BRANCH / HIGIENE GIT ==="
git status -sb

BRANCH="$(git branch --show-current 2>/dev/null || true)"
echo "branch_atual=$BRANCH"
[[ "$BRANCH" == "feature/auth-local" ]] \
  && ok "branch feature/auth-local confirmada" \
  || fail "checkpoint deve rodar exclusivamente em feature/auth-local"

git diff --check \
  && ok "git diff --check" \
  || fail "git diff --check"

for tracked in \
  deploy/interna/wazuh/compose.yml \
  deploy/interna/wazuh/compose.lab.yml \
  deploy/interna/wazuh/generate-indexer-certs.yml \
  deploy/interna/wazuh/RETENCAO.md \
  deploy/interna/wazuh/config/ism/conectaeduca-alertas-retencao-30d.json \
  scripts/evidencias/preparar_wazuh_fase4g_c.sh \
  scripts/evidencias/testar_wazuh_fase4g_c.sh \
  scripts/evidencias/testar_wazuh_fase4g_d.sh \
  scripts/evidencias/testar_wazuh_fase4g_e.sh \
  scripts/evidencias/diagnosticar_wazuh_fase4g_e.sh
do
  if git ls-files --error-unmatch "$tracked" >/dev/null 2>&1; then
    ok "rastreado: $tracked"
  else
    fail "arquivo esperado não está versionado: $tracked"
  fi
done

if git ls-files deploy/interna/wazuh/.runtime | grep -q .; then
  fail "runtime sensível rastreado pelo Git"
else
  ok "nenhum arquivo de .runtime rastreado"
fi

if git diff --cached --name-only |
   grep -Eq '(^|/)\.runtime/|\.pem$|-key\.pem$'
then
  fail "há segredo/certificado sensível no staging"
else
  ok "nenhum segredo/certificado sensível no staging"
fi

if git grep -n -E 'SecretPassword|MyS3cr37P450r\.\*-' \
     -- deploy/interna/wazuh >/dev/null 2>&1
then
  fail "credencial padrão do Wazuh encontrada em arquivo versionado"
else
  ok "credenciais padrão do Wazuh ausentes dos arquivos versionados"
fi

echo
echo "=== 2. RUNTIME / CERTIFICADOS LOCAIS ==="
for f in manager.env dashboard.env internal_users.yml wazuh.yml; do
  if [[ -f "$RUNTIME/$f" ]]; then
    mode="$(stat -c '%a' "$RUNTIME/$f" 2>/dev/null || echo '?')"
    [[ "$mode" == "600" ]] \
      && ok "$f presente e modo 600" \
      || fail "$f com modo inesperado: $mode"
  else
    fail "$f ausente"
  fi
done

git check-ignore -q deploy/interna/wazuh/.runtime/manager.env \
  && ok ".runtime continua ignorado pelo Git" \
  || fail ".runtime não está ignorado"

echo
echo "=== 3. COMPOSE / VERSÕES / SUPERFÍCIE DECLARADA ==="
cd "$WAZUH_DIR" || exit 1

if compose config >/dev/null; then
  ok "Compose base + laboratório válido"
else
  fail "Compose inválido"
fi

CONFIG_JSON="$(compose config --format json 2>/dev/null || true)"

if printf '%s' "$CONFIG_JSON" | python3 -c '
import json, sys
c=json.load(sys.stdin)
expected={
 "wazuh.manager":"wazuh/wazuh-manager:4.14.7",
 "wazuh.indexer":"wazuh/wazuh-indexer:4.14.7",
 "wazuh.dashboard":"wazuh/wazuh-dashboard:4.14.7",
}
for name, image in expected.items():
    assert c["services"][name]["image"] == image
'
then
  ok "imagens fixadas em Wazuh 4.14.7"
else
  fail "versões das imagens diferem do checkpoint"
fi

if printf '%s' "$CONFIG_JSON" | python3 -c '
import json, sys
c=json.load(sys.stdin)["services"]
assert not c["wazuh.manager"].get("ports")
assert not c["wazuh.indexer"].get("ports")
ports=c["wazuh.dashboard"].get("ports", [])
assert len(ports)==1
p=ports[0]
assert str(p.get("host_ip"))=="127.0.0.1"
assert int(p.get("published"))==8443
assert int(p.get("target"))==5601
'
then
  ok "somente Dashboard 127.0.0.1:8443 é publicado no laboratório"
else
  fail "superfície declarada maior que a esperada"
fi

HEAP_DECLARED="$(
  printf '%s' "$CONFIG_JSON" |
  python3 -c '
import json,sys
c=json.load(sys.stdin)
print(c["services"]["wazuh.indexer"]["environment"].get("OPENSEARCH_JAVA_OPTS",""))
' 2>/dev/null || true
)"
echo "heap_declarado=$HEAP_DECLARED"
[[ "$HEAP_DECLARED" == *"-Xms1g"* && "$HEAP_DECLARED" == *"-Xmx1g"* ]] \
  && ok "heap do Indexer permanece 1 GiB / 1 GiB" \
  || fail "heap declarado difere do esperado"

echo
echo "=== 4. VOLUMES HERDADOS ==="
VOLUMES_BEFORE="$(list_volumes)"
VOL_COUNT_BEFORE="$(printf '%s\n' "$VOLUMES_BEFORE" | sed '/^$/d' | wc -l)"
echo "volumes_antes=$VOL_COUNT_BEFORE"
(( VOL_COUNT_BEFORE == 14 )) \
  && ok "14 volumes persistentes presentes" \
  || fail "esperados 14 volumes; encontrados $VOL_COUNT_BEFORE"

TOTAL_KB=0
while IFS= read -r vol; do
  [[ -n "$vol" ]] || continue
  kb="$(volume_size_kb "$vol")"
  [[ "$kb" =~ ^[0-9]+$ ]] || kb=0
  TOTAL_KB=$((TOTAL_KB + kb))
  mib="$(awk -v kb="$kb" 'BEGIN{printf "%.3f", kb/1024}')"
  printf '%-64s %12s MiB\n' "$vol" "$mib"
done <<< "$VOLUMES_BEFORE"
awk -v kb="$TOTAL_KB" 'BEGIN{printf "volumes_total_gib=%.3f\n", kb/1024/1024}'

echo
echo "=== 5. SUBIDA FINAL ==="
if compose up -d; then
  STARTED=1
  ok "stack Wazuh iniciou"
else
  fail "stack Wazuh não iniciou"
fi

compose ps || true
stack_health "subida inicial"

echo
echo "=== 6. CERTIFICADOS POR COMPONENTE ==="
if compose exec -T wazuh.indexer \
  bash -ec '
    test -r /usr/share/wazuh-indexer/config/certs/root-ca.pem
    test -r /usr/share/wazuh-indexer/config/certs/wazuh.indexer.pem
    test -r /usr/share/wazuh-indexer/config/certs/wazuh.indexer.key
    test -r /usr/share/wazuh-indexer/config/certs/admin.pem
    test -r /usr/share/wazuh-indexer/config/certs/admin-key.pem
  '
then
  ok "Indexer lê certificados esperados"
else
  fail "certificados do Indexer"
fi

if compose exec -T wazuh.manager \
  bash -ec '
    test -r /etc/ssl/root-ca.pem
    test -r /etc/ssl/filebeat.pem
    test -r /etc/ssl/filebeat.key
  '
then
  ok "Manager/Filebeat lê certificados esperados"
else
  fail "certificados do Manager/Filebeat"
fi

if compose exec -T wazuh.dashboard \
  bash -ec '
    test -r /usr/share/wazuh-dashboard/certs/root-ca.pem
    test -r /usr/share/wazuh-dashboard/certs/wazuh-dashboard.pem
    test -r /usr/share/wazuh-dashboard/certs/wazuh-dashboard-key.pem
  '
then
  ok "Dashboard lê certificados esperados"
else
  fail "certificados do Dashboard"
fi

echo
echo "=== 7. SUPERFÍCIE REAL / RESTART POLICY ==="
docker ps \
  --filter "label=com.docker.compose.project=$PROJECT" \
  --format 'table {{.Names}}\t{{.Ports}}'

NON_EXPECTED="$(
  IDS="$(compose ps -q)"
  for id in $IDS; do
    docker inspect "$id" \
      --format '{{range $p,$b := .NetworkSettings.Ports}}{{range $b}}{{println $.Name $p .HostIp .HostPort}}{{end}}{{end}}'
  done |
  grep -vE '^/conectaeduca-wazuh-wazuh\.dashboard-1 5601/tcp 127\.0\.0\.1 8443$' ||
  true
)"

if [[ -z "$NON_EXPECTED" ]]; then
  ok "nenhuma porta adicional publicada no host"
else
  printf '%s\n' "$NON_EXPECTED"
  fail "porta inesperada publicada"
fi

for svc in wazuh.manager wazuh.indexer wazuh.dashboard; do
  cid="$(compose ps -q "$svc" 2>/dev/null || true)"
  policy="$(docker inspect "$cid" --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null || true)"
  echo "$svc restart_policy=$policy"
  [[ "$policy" == "unless-stopped" ]] \
    && ok "$svc usa restart unless-stopped" \
    || fail "$svc com restart policy inesperada"
done

echo
echo "=== 8. ARCHIVES / VULNERABILITY DETECTION ==="
if compose exec -T wazuh.manager \
  bash -ec '
    awk "
      /^[[:space:]]*archives:[[:space:]]*$/ {inside=1; next}
      inside && /^[^[:space:]]/ {inside=0}
      inside && /^[[:space:]]*enabled:[[:space:]]*false[[:space:]]*$/ {found=1}
      END {exit(found ? 0 : 1)}
    " /etc/filebeat/filebeat.yml
  ' >/dev/null 2>&1
then
  ok "wazuh-archives permanece desabilitado"
else
  fail "não foi possível confirmar archives.enabled=false"
fi

VD_BLOCK="$(
  compose exec -T wazuh.manager bash -ec '
    awk "
      /<vulnerability-detection>/ {inside=1}
      inside {print}
      /<\/vulnerability-detection>/ {inside=0}
    " /var/ossec/etc/ossec.conf
  ' 2>/dev/null || true
)"
printf '%s\n' "$VD_BLOCK"

if printf '%s' "$VD_BLOCK" | grep -Fq '<enabled>yes</enabled>'; then
  ok "Vulnerability Detection habilitado"
else
  fail "Vulnerability Detection não está habilitado"
fi

echo
echo "=== 9. ISM / RETENÇÃO ==="
[[ -f "$POLICY_FILE" ]] \
  && ok "arquivo versionado da política presente" \
  || fail "arquivo de política ausente"

POLICY_REMOTE="$(
  indexer_request GET "_plugins/_ism/policies/$POLICY_ID" 2>/dev/null || true
)"

if printf '%s' "$POLICY_REMOTE" | python3 -c '
import json, sys
x=json.load(sys.stdin)
p=x["policy"]
assert p["policy_id"]=="conectaeduca-alertas-retencao-30d"
assert p["default_state"]=="retention_state"
assert any(
    t.get("conditions",{}).get("min_index_age")=="30d"
    for s in p["states"] if s["name"]=="retention_state"
    for t in s.get("transitions",[])
)
assert any(
    "delete" in a
    for s in p["states"] if s["name"]=="delete_alerts"
    for a in s.get("actions",[])
)
assert any(
    "wazuh-alerts-*" in t.get("index_patterns",[])
    for t in p.get("ism_template",[])
)
'
then
  ok "ISM persistiu: wazuh-alerts-* → 30d → delete"
else
  fail "política ISM remota diverge do esperado"
fi

echo
echo "=== 10. SAÚDE DOS SHARDS ==="
SHARDS="$(
  indexer_request GET \
    '_cat/shards?h=index,shard,prirep,state,unassigned.reason&s=state,index' \
    2>/dev/null || true
)"
printf '%s\n' "$SHARDS"

UNASSIGNED_PRIMARY="$(
  printf '%s\n' "$SHARDS" |
  awk '$3=="p" && $4=="UNASSIGNED"{print}'
)"
UNASSIGNED_REPLICA="$(
  printf '%s\n' "$SHARDS" |
  awk '$3=="r" && $4=="UNASSIGNED"{print}'
)"

if [[ -z "$UNASSIGNED_PRIMARY" ]]; then
  ok "nenhum shard primário não alocado"
else
  printf '%s\n' "$UNASSIGNED_PRIMARY"
  fail "há shard primário não alocado"
fi

if [[ -n "$UNASSIGNED_REPLICA" ]]; then
  info "há réplica não alocada, compatível com implantação single-node"
  printf '%s\n' "$UNASSIGNED_REPLICA"
else
  ok "nenhuma réplica não alocada"
fi

echo
echo "=== 11. PROVA FINAL DE PERSISTÊNCIA ==="
IDS_BEFORE="$(
  for svc in wazuh.manager wazuh.indexer wazuh.dashboard; do
    compose ps -q "$svc"
  done | sort
)"

if printf '%s' "$TOKEN" |
   compose exec -T wazuh.manager \
     bash -ec 'cat > /var/ossec/etc/.conectaeduca-fase4g-f.marker'
then
  ok "marcador do Manager criado"
else
  fail "não foi possível criar marcador do Manager"
fi

DOC_CODE="$(
  indexer_status PUT "$TEST_INDEX/_doc/checkpoint?refresh=true" \
    "{\"token\":\"$TOKEN\",\"fase\":\"4G-F\"}" \
    2>/dev/null || true
)"
echo "checkpoint_doc_http=$DOC_CODE"

case "$DOC_CODE" in
  200|201)
    ok "documento sintético do Indexer criado"
    ;;
  *)
    fail "documento sintético do Indexer não foi criado"
    ;;
esac

ISM_ATTACHED=0
for attempt in $(seq 1 12); do
  EXPLAIN="$(
    indexer_request GET \
      "_plugins/_ism/explain/$TEST_INDEX?show_policy=true" \
      2>/dev/null || true
  )"
  if printf '%s' "$EXPLAIN" |
     grep -Fq "\"policy_id\":\"$POLICY_ID\""
  then
    ISM_ATTACHED=1
    echo "ism_checkpoint tentativa=$attempt status=anexada"
    break
  fi
  echo "ism_checkpoint tentativa=$attempt status=aguardando"
  sleep 5
done

[[ "$ISM_ATTACHED" -eq 1 ]] \
  && ok "índice futuro recebeu automaticamente a política ISM" \
  || fail "política ISM não foi anexada ao índice de checkpoint"

echo
echo "--- destruindo os containers sem apagar volumes ---"
if compose down --remove-orphans; then
  STARTED=0
  ok "containers removidos sem -v"
else
  fail "falha no down"
fi

VOLUMES_MID="$(list_volumes)"
[[ "$VOLUMES_MID" == "$VOLUMES_BEFORE" ]] \
  && ok "mesmos 14 volumes preservados após down" \
  || fail "conjunto de volumes mudou"

echo
echo "--- recriando ---"
if compose up -d; then
  STARTED=1
  ok "containers recriados"
else
  fail "falha ao recriar containers"
fi

stack_health "após recriação"

IDS_AFTER="$(
  for svc in wazuh.manager wazuh.indexer wazuh.dashboard; do
    compose ps -q "$svc"
  done | sort
)"

[[ "$IDS_AFTER" != "$IDS_BEFORE" ]] \
  && ok "IDs mudaram: recriação real comprovada" \
  || fail "IDs dos containers não mudaram"

MARKER_VALUE="$(
  compose exec -T wazuh.manager \
    bash -ec 'cat /var/ossec/etc/.conectaeduca-fase4g-f.marker 2>/dev/null || true' \
    2>/dev/null || true
)"

[[ "$MARKER_VALUE" == "$TOKEN" ]] \
  && ok "marcador do Manager sobreviveu à recriação" \
  || fail "marcador do Manager não sobreviveu"

INDEX_DOC="$(
  indexer_request GET "$TEST_INDEX/_doc/checkpoint" 2>/dev/null || true
)"
printf '%s' "$INDEX_DOC" | grep -Fq "$TOKEN" \
  && ok "documento do Indexer sobreviveu à recriação" \
  || fail "documento do Indexer não sobreviveu"

echo
echo "=== 12. SNAPSHOT DE RECURSOS ESTABILIZADOS ==="
sleep 20

for sample in 1 2 3; do
  echo "--- amostra $sample/3 ---"
  IDS="$(compose ps -q)"
  docker stats --no-stream \
    --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.BlockIO}}' \
    $IDS || true
  (( sample < 3 )) && sleep 10
done

echo
echo "=== 13. LIMPEZA DOS ARTEFATOS DE CHECKPOINT ==="
if compose exec -T wazuh.manager \
   bash -ec 'rm -f /var/ossec/etc/.conectaeduca-fase4g-f.marker'
then
  ok "marcador temporário removido"
else
  fail "falha ao remover marcador temporário"
fi

DELETE_CODE="$(
  indexer_status DELETE "$TEST_INDEX" 2>/dev/null || true
)"
echo "checkpoint_index_delete_http=$DELETE_CODE"
[[ "$DELETE_CODE" == "200" ]] \
  && ok "índice temporário removido" \
  || fail "falha ao remover índice temporário"

echo
echo "=== 14. ENCERRAMENTO FINAL ==="
if compose down --remove-orphans; then
  STARTED=0
  ok "stack encerrada preservando volumes"
else
  fail "falha ao encerrar stack"
fi

RESIDUAL="$(
  docker ps -aq \
    --filter "label=com.docker.compose.project=$PROJECT" \
    2>/dev/null || true
)"
[[ -z "$RESIDUAL" ]] \
  && ok "nenhum container residual" \
  || fail "container residual encontrado"

VOLUMES_FINAL="$(list_volumes)"
FINAL_COUNT="$(printf '%s\n' "$VOLUMES_FINAL" | sed '/^$/d' | wc -l)"
echo "volumes_finais=$FINAL_COUNT"

[[ "$VOLUMES_FINAL" == "$VOLUMES_BEFORE" && "$FINAL_COUNT" -eq 14 ]] \
  && ok "os mesmos 14 volumes permanecem preservados" \
  || fail "volumes finais diferem do baseline"

echo
echo "=== 15. GIT FINAL ==="
cd "$ROOT"
git status -sb

if git ls-files deploy/interna/wazuh/.runtime | grep -q .; then
  fail "runtime sensível rastreado ao final"
else
  ok "runtime sensível continua fora do Git"
fi

echo
echo "======================================================================"
echo " RESULTADO DO CHECKPOINT 4G-F"
echo "======================================================================"
echo "Falhas: $FAIL"

if [[ "$FAIL" -eq 0 ]]; then
  echo "CHECKPOINT FASE 4G-F: APROVADO."
  echo "Bloco Wazuh concluído para o laboratório ConectaEduca."
  echo "Validado: versão, configuração, segredos, certificados, rede, autenticação,"
  echo "persistência, ISM 30d, archives desabilitado, shards primários e recursos."
else
  echo "CHECKPOINT FASE 4G-F: REPROVADO."
fi

echo "Relatório: $REPORT"
echo "======================================================================"

[[ "$FAIL" -eq 0 ]]
