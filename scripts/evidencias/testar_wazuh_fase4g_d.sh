#!/usr/bin/env bash
set -u

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"
WAZUH_DIR="$ROOT/deploy/interna/wazuh"
RUNTIME="$WAZUH_DIR/.runtime"
PROJECT="conectaeduca-wazuh"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/conectaeduca-wazuh-fase4g-d-${STAMP}.txt"

FAIL=0
STARTED=0
TEST_INDEX="conectaeduca-fase4g-d-persistencia"
TEST_MARKER="/var/ossec/etc/.conectaeduca-fase4g-d.marker"
TOKEN="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(16))
PY
)"

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

cleanup_on_exit() {
  set +e
  if [[ "$STARTED" -eq 1 ]]; then
    compose down --remove-orphans >/dev/null 2>&1
  fi
}
trap cleanup_on_exit EXIT INT TERM

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
    if printf '%s' "$out" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"(green|yellow)"'; then
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
      eyJ*) echo "manager_api_wait t=${elapsed}s token=obtido"; return 0 ;;
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

wait_stack() {
  local label="$1"
  echo
  echo "=== SAÚDE DA STACK — $label ==="
  if wait_indexer; then
    ok "Indexer funcional ($label)"
  else
    fail "Indexer não ficou funcional ($label)"
  fi

  if wait_manager_api; then
    ok "Manager API funcional ($label)"
  else
    fail "Manager API não ficou funcional ($label)"
  fi

  if wait_dashboard; then
    ok "Dashboard funcional ($label)"
  else
    fail "Dashboard não ficou funcional ($label)"
  fi
}

list_project_volumes() {
  docker volume ls \
    --filter "label=com.docker.compose.project=$PROJECT" \
    --format '{{.Name}}' \
    | sort
}

write_test_artifacts() {
  echo
  echo "=== CRIAÇÃO DOS MARCADORES DE PERSISTÊNCIA ==="

  # Remove somente resíduos de uma eventual tentativa anterior desta fase.
  compose exec -T wazuh.manager \
    bash -ec '
      rm -f /var/ossec/etc/.conectaeduca-fase4g-d.marker
      curl -k -sS --max-time 10 \
        -u "$INDEXER_USERNAME:$INDEXER_PASSWORD" \
        -X DELETE \
        https://wazuh.indexer:9200/conectaeduca-fase4g-d-persistencia \
        >/dev/null 2>&1 || true
    '

  if printf '%s' "$TOKEN" | compose exec -T wazuh.manager \
      bash -ec 'cat > /var/ossec/etc/.conectaeduca-fase4g-d.marker'
  then
    ok "marcador criado no volume persistente do Manager"
  else
    fail "não foi possível criar marcador no Manager"
  fi

  if compose exec -T -e FASE4GD_TOKEN="$TOKEN" wazuh.manager \
      bash -ec '
        curl -k -sS --fail --max-time 10 \
          -u "$INDEXER_USERNAME:$INDEXER_PASSWORD" \
          -H "Content-Type: application/json" \
          -X PUT \
          "https://wazuh.indexer:9200/conectaeduca-fase4g-d-persistencia/_doc/checkpoint?refresh=true" \
          -d "{\"token\":\"$FASE4GD_TOKEN\",\"fase\":\"4G-D\"}" \
          >/dev/null
      '
  then
    ok "documento criado no volume persistente do Indexer"
  else
    fail "não foi possível criar documento de persistência no Indexer"
  fi
}

verify_test_artifacts() {
  local label="$1"

  echo
  echo "=== VERIFICAÇÃO DOS MARCADORES — $label ==="

  MANAGER_VALUE="$(
    compose exec -T wazuh.manager \
      bash -ec 'cat /var/ossec/etc/.conectaeduca-fase4g-d.marker 2>/dev/null || true' \
      2>/dev/null || true
  )"

  if [[ "$MANAGER_VALUE" == "$TOKEN" ]]; then
    ok "marcador do Manager sobreviveu ($label)"
  else
    fail "marcador do Manager não foi preservado ($label)"
  fi

  INDEXER_DOC="$(
    compose exec -T wazuh.manager \
      bash -ec '
        curl -k -sS --max-time 10 \
          -u "$INDEXER_USERNAME:$INDEXER_PASSWORD" \
          https://wazuh.indexer:9200/conectaeduca-fase4g-d-persistencia/_doc/checkpoint
      ' 2>/dev/null || true
  )"

  if printf '%s' "$INDEXER_DOC" | grep -Fq "$TOKEN"; then
    ok "documento do Indexer sobreviveu ($label)"
  else
    fail "documento do Indexer não foi preservado ($label)"
  fi
}

remove_test_artifacts() {
  echo
  echo "=== LIMPEZA DOS MARCADORES DE TESTE ==="

  if compose exec -T wazuh.manager \
      bash -ec 'rm -f /var/ossec/etc/.conectaeduca-fase4g-d.marker'
  then
    ok "marcador temporário removido do Manager"
  else
    fail "falha ao remover marcador temporário do Manager"
  fi

  if compose exec -T wazuh.manager \
      bash -ec '
        curl -k -sS --fail --max-time 10 \
          -u "$INDEXER_USERNAME:$INDEXER_PASSWORD" \
          -X DELETE \
          https://wazuh.indexer:9200/conectaeduca-fase4g-d-persistencia \
          >/dev/null
      '
  then
    ok "índice temporário removido do Indexer"
  else
    fail "falha ao remover índice temporário do Indexer"
  fi
}

exec > >(tee "$REPORT") 2>&1

echo "======================================================================"
echo " CONECTAEDUCA - FASE 4G-D"
echo " Persistência e recriação da stack Wazuh"
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
  || fail "esta fase deve ser executada exclusivamente em feature/auth-local"

git diff --check \
  && ok "git diff --check" \
  || fail "git diff --check"

echo
echo "=== RUNTIME SEGURO ==="
for f in manager.env dashboard.env internal_users.yml wazuh.yml; do
  if [[ -f "$RUNTIME/$f" ]]; then
    mode="$(stat -c '%a' "$RUNTIME/$f" 2>/dev/null || echo '?')"
    if [[ "$mode" == "600" ]]; then
      ok "$f presente e modo 600"
    else
      fail "$f com modo inesperado: $mode"
    fi
  else
    fail "$f ausente"
  fi
done

git check-ignore -q deploy/interna/wazuh/.runtime/manager.env \
  && ok ".runtime continua ignorado pelo Git" \
  || fail ".runtime não está ignorado"

if git ls-files deploy/interna/wazuh/.runtime | grep -q .; then
  fail "runtime sensível rastreado pelo Git"
else
  ok "nenhum runtime sensível rastreado"
fi

echo
echo "=== ESTADO HERDADO DA 4G-C ==="
RUNNING_BEFORE="$(
  docker ps -q \
    --filter "label=com.docker.compose.project=$PROJECT" \
    2>/dev/null || true
)"
if [[ -z "$RUNNING_BEFORE" ]]; then
  ok "nenhum container Wazuh em execução antes da 4G-D"
else
  fail "containers Wazuh já estavam em execução antes da 4G-D"
  docker ps \
    --filter "label=com.docker.compose.project=$PROJECT" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
fi

VOLUMES_BEFORE="$(list_project_volumes)"
VOL_COUNT_BEFORE="$(printf '%s\n' "$VOLUMES_BEFORE" | sed '/^$/d' | wc -l)"
echo "volumes_antes=$VOL_COUNT_BEFORE"
printf '%s\n' "$VOLUMES_BEFORE"

if (( VOL_COUNT_BEFORE == 14 )); then
  ok "14 volumes persistentes herdados da 4G-C"
else
  fail "esperados 14 volumes da 4G-C; encontrados $VOL_COUNT_BEFORE"
fi

echo
echo "=== COMPOSE ==="
cd "$WAZUH_DIR" || exit 1
if compose config >/dev/null; then
  ok "Compose válido"
else
  fail "Compose inválido"
fi

echo
echo "=== PRIMEIRA SUBIDA ==="
if compose up -d; then
  STARTED=1
  ok "stack iniciou usando os volumes existentes"
else
  fail "falha ao iniciar stack"
fi

compose ps || true
wait_stack "primeira subida"

echo
echo "=== POLÍTICA DE REINÍCIO ==="
RESTART_BAD=0
for svc in wazuh.manager wazuh.indexer wazuh.dashboard; do
  cid="$(compose ps -q "$svc" 2>/dev/null || true)"
  policy="$(docker inspect "$cid" --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null || true)"
  echo "$svc restart_policy=$policy"
  if [[ "$policy" == "unless-stopped" ]]; then
    ok "$svc usa restart unless-stopped"
  else
    fail "$svc com restart policy inesperada: $policy"
    RESTART_BAD=1
  fi
done

IDS_BEFORE="$(
  for svc in wazuh.manager wazuh.indexer wazuh.dashboard; do
    compose ps -q "$svc"
  done | sort
)"
echo "container_ids_primeira_subida:"
printf '%s\n' "$IDS_BEFORE"

write_test_artifacts
verify_test_artifacts "antes da recriação"

echo
echo "=== DOWN SEM APAGAR VOLUMES ==="
if compose down --remove-orphans; then
  STARTED=0
  ok "containers e rede removidos sem -v"
else
  fail "docker compose down falhou"
fi

CONTAINERS_AFTER_DOWN="$(
  docker ps -aq \
    --filter "label=com.docker.compose.project=$PROJECT" \
    2>/dev/null || true
)"
[[ -z "$CONTAINERS_AFTER_DOWN" ]] \
  && ok "nenhum container permaneceu após down" \
  || fail "container residual após down"

VOLUMES_AFTER_DOWN="$(list_project_volumes)"
VOL_COUNT_AFTER_DOWN="$(printf '%s\n' "$VOLUMES_AFTER_DOWN" | sed '/^$/d' | wc -l)"
echo "volumes_apos_down=$VOL_COUNT_AFTER_DOWN"

if [[ "$VOLUMES_AFTER_DOWN" == "$VOLUMES_BEFORE" ]]; then
  ok "conjunto de volumes permaneceu idêntico após down"
else
  fail "conjunto de volumes mudou após down"
fi

echo
echo "=== RECRIAÇÃO DOS CONTAINERS ==="
if compose up -d; then
  STARTED=1
  ok "containers recriados a partir dos volumes persistentes"
else
  fail "falha ao recriar containers"
fi

wait_stack "após recriação"

IDS_AFTER="$(
  for svc in wazuh.manager wazuh.indexer wazuh.dashboard; do
    compose ps -q "$svc"
  done | sort
)"
echo "container_ids_recriacao:"
printf '%s\n' "$IDS_AFTER"

if [[ "$IDS_AFTER" != "$IDS_BEFORE" ]]; then
  ok "IDs dos containers mudaram: houve recriação real"
else
  fail "IDs dos containers não mudaram"
fi

verify_test_artifacts "depois da recriação"

echo
echo "=== RESTART DOS CONTAINERS RECRIADOS ==="
if compose restart; then
  ok "restart solicitado"
else
  fail "restart falhou"
fi

wait_stack "após restart"
verify_test_artifacts "depois do restart"

remove_test_artifacts

echo
echo "=== ENCERRAMENTO PRESERVANDO VOLUMES ==="
if compose down --remove-orphans; then
  STARTED=0
  ok "stack encerrada sem excluir volumes"
else
  fail "falha ao encerrar stack"
fi

FINAL_CONTAINERS="$(
  docker ps -aq \
    --filter "label=com.docker.compose.project=$PROJECT" \
    2>/dev/null || true
)"
[[ -z "$FINAL_CONTAINERS" ]] \
  && ok "nenhum container residual" \
  || fail "container residual encontrado"

VOLUMES_FINAL="$(list_project_volumes)"
VOL_COUNT_FINAL="$(printf '%s\n' "$VOLUMES_FINAL" | sed '/^$/d' | wc -l)"
echo "volumes_finais=$VOL_COUNT_FINAL"

if [[ "$VOLUMES_FINAL" == "$VOLUMES_BEFORE" ]]; then
  ok "os mesmos 14 volumes foram preservados para a 4G-E"
else
  fail "volumes finais diferem do conjunto inicial"
fi

echo
echo "=== GIT FINAL ==="
cd "$ROOT"
git status -sb

if git ls-files deploy/interna/wazuh/.runtime | grep -q .; then
  fail "runtime sensível rastreado ao final"
else
  ok "runtime sensível continua fora do Git"
fi

echo
echo "=== RESULTADO ==="
echo "Falhas: $FAIL"
if [[ "$FAIL" -eq 0 ]]; then
  echo "FASE 4G-D: APROVADA."
  echo "Persistência do Manager e do Indexer comprovada após recriação real dos containers e restart."
  echo "Os 14 volumes foram preservados para a Fase 4G-E."
else
  echo "FASE 4G-D: REPROVADA."
fi
echo "Relatório: $REPORT"
echo "======================================================================"

[[ "$FAIL" -eq 0 ]]
