#!/usr/bin/env bash
set -u

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"
WAZUH_DIR="$ROOT/deploy/interna/wazuh"
RUNTIME="$WAZUH_DIR/.runtime"
POLICY_FILE="$WAZUH_DIR/config/ism/conectaeduca-alertas-retencao-30d.json"
PROJECT="conectaeduca-wazuh"
POLICY_ID="conectaeduca-alertas-retencao-30d"

TARGET_VM_RAM_GB="${TARGET_VM_RAM_GB:-16}"
TARGET_VM_DISK_GB="${TARGET_VM_DISK_GB:-100}"
TARGET_VM_VCPU="${TARGET_VM_VCPU:-desconhecido}"

SAMPLE_COUNT="${SAMPLE_COUNT:-6}"
SAMPLE_INTERVAL="${SAMPLE_INTERVAL:-10}"

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/conectaeduca-wazuh-fase4g-e-${STAMP}.txt"
STATS_FILE="/tmp/conectaeduca-wazuh-fase4g-e-stats-${STAMP}.tsv"

FAIL=0
STARTED=0
TEST_INDEX="wazuh-alerts-conectaeduca-retention-test-${STAMP}"

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
            -o /tmp/response.json \
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
          -o /tmp/response.json \
          -w "%{http_code}" \
          -u "$INDEXER_USERNAME:$INDEXER_PASSWORD" \
          -X "$method" \
          "https://wazuh.indexer:9200/$path"
      ' bash "$method" "$path"
  fi
}

volume_size_kb() {
  local vol="$1"

  docker run --rm \
    --user 0:0 \
    --entrypoint /bin/bash \
    -v "$vol:/data:ro" \
    wazuh/wazuh-manager:4.14.7 \
    -ec 'du -sk /data 2>/dev/null | awk "{print \$1}"' \
    2>/dev/null || echo 0
}

exec > >(tee "$REPORT") 2>&1

echo "======================================================================"
echo " CONECTAEDUCA - FASE 4G-E"
echo " Recursos, armazenamento e retenção do Wazuh"
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
  || fail "execute exclusivamente em feature/auth-local"

git diff --check \
  && ok "git diff --check" \
  || fail "git diff --check"

echo
echo "=== ALVO FUTURO DA VM INTERNA ==="
echo "target_ram_gb=$TARGET_VM_RAM_GB"
echo "target_disk_gb=$TARGET_VM_DISK_GB"
echo "target_vcpu=$TARGET_VM_VCPU"

if [[ "$TARGET_VM_VCPU" =~ ^[0-9]+$ ]]; then
  if (( TARGET_VM_VCPU >= 4 )); then
    ok "vCPU alvo atende ao mínimo de 4 cores do Wazuh Docker single-node"
  else
    fail "vCPU alvo abaixo de 4"
  fi
else
  info "quantidade de vCPU da VM futura continua pendente de confirmação"
fi

echo
echo "=== RUNTIME / PERSISTÊNCIA ==="
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
  && ok ".runtime ignorado pelo Git" \
  || fail ".runtime não ignorado"

if git ls-files deploy/interna/wazuh/.runtime | grep -q .; then
  fail "runtime sensível rastreado"
else
  ok "nenhum runtime sensível rastreado"
fi

VOLUMES="$(
  docker volume ls \
    --filter "label=com.docker.compose.project=$PROJECT" \
    --format '{{.Name}}' \
    | sort
)"
VOL_COUNT="$(printf '%s\n' "$VOLUMES" | sed '/^$/d' | wc -l)"
echo "volumes_herdados=$VOL_COUNT"

(( VOL_COUNT == 14 )) \
  && ok "14 volumes herdados da 4G-D" \
  || fail "esperados 14 volumes; encontrados $VOL_COUNT"

echo
echo "=== BASELINE DO HOST ==="
echo "cpu_logicas=$(nproc)"
echo "load_average=$(awk '{print $1,$2,$3}' /proc/loadavg)"

MEM_TOTAL_KB="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
MEM_AVAIL_KB="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
SWAP_TOTAL_KB="$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)"
SWAP_FREE_KB="$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)"

python3 - "$MEM_TOTAL_KB" "$MEM_AVAIL_KB" "$SWAP_TOTAL_KB" "$SWAP_FREE_KB" <<'PY'
import sys
vals = list(map(int, sys.argv[1:]))
labels = ["ram_total_gib", "ram_disponivel_gib", "swap_total_gib", "swap_livre_gib"]
for label, kb in zip(labels, vals):
    print(f"{label}={kb/1024/1024:.2f}")
PY

DOCKER_ROOT="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
echo "docker_root=$DOCKER_ROOT"
df -h "$DOCKER_ROOT" 2>/dev/null || true

echo
echo "=== TAMANHO DOS 14 VOLUMES ANTES DA SUBIDA ==="
TOTAL_VOL_KB=0
while IFS= read -r vol; do
  [[ -n "$vol" ]] || continue
  kb="$(volume_size_kb "$vol")"
  [[ "$kb" =~ ^[0-9]+$ ]] || kb=0
  TOTAL_VOL_KB=$((TOTAL_VOL_KB + kb))
  printf '%-62s %10.2f MiB\n' "$vol" "$(awk -v kb="$kb" 'BEGIN{print kb/1024}')"
done <<< "$VOLUMES"

awk -v kb="$TOTAL_VOL_KB" 'BEGIN{printf "volumes_total_antes_gib=%.3f\n", kb/1024/1024}'

echo
echo "=== COMPOSE ==="
cd "$WAZUH_DIR" || exit 1

if compose config >/dev/null; then
  ok "Compose válido"
else
  fail "Compose inválido"
fi

echo
echo "=== SUBIDA DA STACK ==="
if compose up -d; then
  STARTED=1
  ok "stack iniciou usando os volumes persistentes"
else
  fail "falha ao iniciar stack"
fi

compose ps || true

if wait_indexer; then
  ok "Indexer funcional"
else
  fail "Indexer não ficou funcional"
fi

if wait_manager_api; then
  ok "Manager API funcional"
else
  fail "Manager API não ficou funcional"
fi

if wait_dashboard; then
  ok "Dashboard funcional"
else
  fail "Dashboard não ficou funcional"
fi

echo
echo "=== HEAP DO INDEXER ==="
INDEXER_HEAP="$(
  compose exec -T wazuh.indexer \
    bash -ec 'printf "%s" "${OPENSEARCH_JAVA_OPTS:-}"' \
    2>/dev/null || true
)"
echo "OPENSEARCH_JAVA_OPTS=$INDEXER_HEAP"

if [[ "$INDEXER_HEAP" == *"-Xms1g"* && "$INDEXER_HEAP" == *"-Xmx1g"* ]]; then
  ok "heap permanece em 1 GiB / 1 GiB conforme configuração atual"
else
  fail "heap do Indexer difere do esperado"
fi

echo
echo "=== ARQUIVAMENTO COMPLETO DE EVENTOS ==="
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

echo
echo "=== ÍNDICES / ALOCAÇÃO ATUAIS ==="
indexer_request GET '_cat/allocation?v&s=node' || true
echo
indexer_request GET '_cat/indices?h=health,status,index,docs.count,store.size&s=index' || true

echo
echo "=== POLÍTICA ISM DE RETENÇÃO ==="
if [[ -f "$POLICY_FILE" ]]; then
  ok "política versionável presente"
else
  fail "arquivo da política ausente: $POLICY_FILE"
fi

if python3 - "$POLICY_FILE" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding="utf-8"))["policy"]
assert p["default_state"] == "retention_state"
assert any(
    t.get("conditions", {}).get("min_index_age") == "30d"
    for s in p["states"] if s["name"] == "retention_state"
    for t in s.get("transitions", [])
)
assert any(
    "delete" in action
    for s in p["states"] if s["name"] == "delete_alerts"
    for action in s.get("actions", [])
)
templates=p["ism_template"]
assert any("wazuh-alerts-*" in t.get("index_patterns", []) for t in templates)
PY
then
  ok "política local: padrão wazuh-alerts-* + exclusão após 30d"
else
  fail "estrutura da política local não corresponde ao desenho da 4G-E"
fi

GET_CODE="$(indexer_status GET "_plugins/_ism/policies/$POLICY_ID" 2>/dev/null || true)"
echo "ism_get_http=$GET_CODE"

if [[ "$GET_CODE" == "404" ]]; then
  POLICY_BODY="$(cat "$POLICY_FILE")"
  CREATE_CODE="$(indexer_status PUT "_plugins/_ism/policies/$POLICY_ID" "$POLICY_BODY" 2>/dev/null || true)"
  echo "ism_create_http=$CREATE_CODE"

  case "$CREATE_CODE" in
    200|201)
      ok "política ISM criada no Indexer"
      ;;
    *)
      fail "não foi possível criar política ISM"
      ;;
  esac
elif [[ "$GET_CODE" == "200" ]]; then
  info "política ISM já existia; não será sobrescrita automaticamente"
else
  fail "resposta inesperada ao consultar política ISM: $GET_CODE"
fi

POLICY_REMOTE="$(
  indexer_request GET "_plugins/_ism/policies/$POLICY_ID" 2>/dev/null || true
)"

if printf '%s' "$POLICY_REMOTE" | python3 -c '
import json, sys
x=json.load(sys.stdin)
p=x["policy"]
assert p["policy_id"] == "conectaeduca-alertas-retencao-30d"
assert p["default_state"] == "retention_state"
assert any(
    t.get("conditions", {}).get("min_index_age") == "30d"
    for s in p["states"] if s["name"] == "retention_state"
    for t in s.get("transitions", [])
)
assert any(
    "wazuh-alerts-*" in t.get("index_patterns", [])
    for t in p.get("ism_template", [])
)
assert any(
    "delete" in a
    for s in p["states"] if s["name"] == "delete_alerts"
    for a in s.get("actions", [])
)
'
then
  ok "política remota confere: wazuh-alerts-* / 30d / delete"
else
  fail "política remota não corresponde ao arquivo esperado"
fi

echo
echo "=== TESTE NÃO DESTRUTIVO DO ISM TEMPLATE ==="
indexer_request DELETE "$TEST_INDEX" >/dev/null 2>&1 || true

CREATE_TEST="$(
  indexer_status PUT "$TEST_INDEX" \
    '{"settings":{"number_of_shards":1,"number_of_replicas":0}}' \
    2>/dev/null || true
)"
echo "test_index_create_http=$CREATE_TEST"

case "$CREATE_TEST" in
  200|201)
    ok "índice sintético criado"
    ;;
  *)
    fail "não foi possível criar índice sintético"
    ;;
esac

ISM_ATTACHED=0
for attempt in $(seq 1 12); do
  EXPLAIN="$(
    indexer_request GET "_plugins/_ism/explain/$TEST_INDEX?show_policy=true" \
      2>/dev/null || true
  )"

  if printf '%s' "$EXPLAIN" | grep -Fq "\"policy_id\":\"$POLICY_ID\""; then
    ISM_ATTACHED=1
    echo "ism_attach_wait tentativa=$attempt status=anexada"
    break
  fi

  echo "ism_attach_wait tentativa=$attempt status=aguardando"
  sleep 5
done

if [[ "$ISM_ATTACHED" -eq 1 ]]; then
  ok "ism_template anexou automaticamente a política ao índice futuro"
else
  fail "ism_template não foi observado no índice sintético"
fi

DELETE_TEST="$(
  indexer_status DELETE "$TEST_INDEX" 2>/dev/null || true
)"
echo "test_index_delete_http=$DELETE_TEST"

case "$DELETE_TEST" in
  200)
    ok "índice sintético removido"
    ;;
  *)
    fail "não foi possível remover índice sintético"
    ;;
esac

echo
echo "=== AMOSTRAGEM DE RECURSOS ==="
echo "amostras=$SAMPLE_COUNT"
echo "intervalo_segundos=$SAMPLE_INTERVAL"
printf "sample\ttimestamp\tcontainer\tcpu_pct\tmem_usage\n" > "$STATS_FILE"

sleep 20

for sample in $(seq 1 "$SAMPLE_COUNT"); do
  ts="$(date --iso-8601=seconds)"
  echo "--- amostra $sample/$SAMPLE_COUNT @ $ts ---"

  IDS="$(compose ps -q)"
  docker stats --no-stream \
    --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' \
    $IDS |
  while IFS=$'\t' read -r name cpu mem; do
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$sample" "$ts" "$name" "$cpu" "$mem" >> "$STATS_FILE"
    printf '%-44s CPU=%-9s MEM=%s\n' "$name" "$cpu" "$mem"
  done

  HOST_AVAIL_KB="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
  awk -v kb="$HOST_AVAIL_KB" \
    'BEGIN{printf "host_mem_available_gib=%.2f\n", kb/1024/1024}'

  if (( sample < SAMPLE_COUNT )); then
    sleep "$SAMPLE_INTERVAL"
  fi
done

echo
echo "=== RESUMO DA AMOSTRAGEM ==="
python3 - "$STATS_FILE" "$TARGET_VM_RAM_GB" <<'PY'
import csv, re, sys
from collections import defaultdict

path=sys.argv[1]
target=float(sys.argv[2])

def mem_to_mib(s):
    left=s.split("/")[0].strip()
    m=re.fullmatch(r"([0-9.]+)([KMGTP]i?B)", left)
    if not m:
        raise ValueError(left)
    val=float(m.group(1))
    unit=m.group(2)
    scale={
        "KiB":1/1024, "MiB":1, "GiB":1024, "TiB":1024**2,
        "KB":1/1000, "MB":1000/1024, "GB":1000**2/1024,
        "TB":1000**3/1024,
    }[unit]
    return val*scale

rows=[]
with open(path, newline="", encoding="utf-8") as f:
    for r in csv.DictReader(f, delimiter="\t"):
        rows.append({
            "sample":int(r["sample"]),
            "container":r["container"],
            "cpu":float(r["cpu_pct"].rstrip("%")),
            "mem":mem_to_mib(r["mem_usage"]),
        })

by_container=defaultdict(list)
by_sample=defaultdict(float)

for r in rows:
    by_container[r["container"]].append(r)
    by_sample[r["sample"]]+=r["mem"]

for name in sorted(by_container):
    vals=by_container[name]
    avg_cpu=sum(x["cpu"] for x in vals)/len(vals)
    max_cpu=max(x["cpu"] for x in vals)
    avg_mem=sum(x["mem"] for x in vals)/len(vals)
    max_mem=max(x["mem"] for x in vals)
    print(
        f"{name}: "
        f"cpu_avg={avg_cpu:.2f}% cpu_max={max_cpu:.2f}% "
        f"mem_avg={avg_mem:.1f}MiB mem_max={max_mem:.1f}MiB"
    )

peak_total=max(by_sample.values()) if by_sample else 0
avg_total=sum(by_sample.values())/len(by_sample) if by_sample else 0
target_mib=target*1024

print(f"stack_mem_avg={avg_total/1024:.3f}GiB")
print(f"stack_mem_peak={peak_total/1024:.3f}GiB")
print(f"stack_peak_vs_target_ram={100*peak_total/target_mib:.1f}%")
print("nota=baseline estabilizada sem carga real de agentes/Suricata; não é pico de produção")
PY

echo
echo "=== TAMANHO DOS VOLUMES APÓS A MEDIÇÃO ==="
VOLUMES_AFTER="$(
  docker volume ls \
    --filter "label=com.docker.compose.project=$PROJECT" \
    --format '{{.Name}}' \
    | sort
)"

TOTAL_VOL_AFTER_KB=0
while IFS= read -r vol; do
  [[ -n "$vol" ]] || continue
  kb="$(volume_size_kb "$vol")"
  [[ "$kb" =~ ^[0-9]+$ ]] || kb=0
  TOTAL_VOL_AFTER_KB=$((TOTAL_VOL_AFTER_KB + kb))
  printf '%-62s %10.2f MiB\n' "$vol" "$(awk -v kb="$kb" 'BEGIN{print kb/1024}')"
done <<< "$VOLUMES_AFTER"

awk -v kb="$TOTAL_VOL_AFTER_KB" 'BEGIN{printf "volumes_total_depois_gib=%.3f\n", kb/1024/1024}'

echo
echo "=== CHECAGEM FINAL DO INDEXER ==="
indexer_request GET '_cluster/health?pretty' || true
echo
indexer_request GET '_cat/indices?h=health,status,index,docs.count,store.size&s=index' || true

echo
echo "=== ENCERRAMENTO PRESERVANDO VOLUMES ==="
if compose down --remove-orphans; then
  STARTED=0
  ok "containers removidos e volumes preservados"
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

VOLUMES_FINAL="$(
  docker volume ls \
    --filter "label=com.docker.compose.project=$PROJECT" \
    --format '{{.Name}}' \
    | sort
)"
FINAL_VOL_COUNT="$(printf '%s\n' "$VOLUMES_FINAL" | sed '/^$/d' | wc -l)"
echo "volumes_finais=$FINAL_VOL_COUNT"

(( FINAL_VOL_COUNT == 14 )) \
  && ok "14 volumes preservados para a 4G-F" \
  || fail "quantidade final de volumes inesperada"

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
  echo "FASE 4G-E: APROVADA."
  echo "Baseline de recursos medida e retenção ISM de 30 dias validada para índices futuros wazuh-alerts-*."
  echo "Arquivamento completo permanece desabilitado."
  echo "Os 14 volumes foram preservados para a Fase 4G-F."
else
  echo "FASE 4G-E: REPROVADA."
fi

echo "Relatório: $REPORT"
echo "Amostras brutas: $STATS_FILE"
echo "======================================================================"

[[ "$FAIL" -eq 0 ]]
