#!/usr/bin/env bash
set -u
export LC_ALL=C
export LANG=C

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"
WAZUH_DIR="$ROOT/deploy/interna/wazuh"
RUNTIME="$WAZUH_DIR/.runtime"
PROJECT="conectaeduca-wazuh"

SAMPLE_COUNT="${SAMPLE_COUNT:-12}"
SAMPLE_INTERVAL="${SAMPLE_INTERVAL:-10}"

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/conectaeduca-wazuh-fase4g-e-diagnostico-${STAMP}.txt"
STATS="/tmp/conectaeduca-wazuh-fase4g-e-diagnostico-${STAMP}.tsv"

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

cleanup() {
  set +e
  if [[ "$STARTED" -eq 1 ]]; then
    compose down --remove-orphans >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

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
    sleep 5
    elapsed=$((elapsed+5))
  done
  return 1
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

print_volume_sizes() {
  local label="$1"
  local total=0
  echo
  echo "=== VOLUMES — $label ==="
  while IFS= read -r vol; do
    [[ -n "$vol" ]] || continue
    kb="$(volume_size_kb "$vol")"
    [[ "$kb" =~ ^[0-9]+$ ]] || kb=0
    total=$((total + kb))
    mib="$(awk -v kb="$kb" 'BEGIN{printf "%.3f", kb/1024}')"
    printf '%-64s %12s MiB\n' "$vol" "$mib"
  done < <(
    docker volume ls \
      --filter "label=com.docker.compose.project=$PROJECT" \
      --format '{{.Name}}' | sort
  )
  awk -v kb="$total" 'BEGIN{printf "volumes_total_gib=%.3f\n", kb/1024/1024}'
}

exec > >(tee "$REPORT") 2>&1

echo "======================================================================"
echo " CONECTAEDUCA - FASE 4G-E — DIAGNÓSTICO DE DIMENSIONAMENTO"
echo " Investiga pico de RAM, crescimento de queue e shard não alocado"
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

git check-ignore -q deploy/interna/wazuh/.runtime/manager.env \
  && ok ".runtime ignorado" \
  || fail ".runtime não ignorado"

if git ls-files deploy/interna/wazuh/.runtime | grep -q .; then
  fail "runtime sensível rastreado"
else
  ok "nenhum runtime sensível rastreado"
fi

VOL_COUNT="$(
  docker volume ls \
    --filter "label=com.docker.compose.project=$PROJECT" \
    --format '{{.Name}}' | wc -l
)"
echo "volumes_herdados=$VOL_COUNT"
(( VOL_COUNT == 14 )) \
  && ok "14 volumes persistentes presentes" \
  || fail "esperados 14 volumes"

print_volume_sizes "antes da subida"

cd "$WAZUH_DIR" || exit 1

echo
echo "=== SUBIDA ==="
if compose up -d; then
  STARTED=1
  ok "stack iniciou"
else
  fail "stack não iniciou"
fi

if wait_indexer; then
  ok "Indexer operacional"
else
  fail "Indexer não ficou operacional"
fi

sleep 15

echo
echo "=== VULNERABILITY DETECTION — CONFIGURAÇÃO ==="
compose exec -T wazuh.manager bash -ec '
  awk "
    /<vulnerability-detection>/ {inside=1}
    inside {print}
    /<\/vulnerability-detection>/ {inside=0}
  " /var/ossec/etc/ossec.conf
' 2>/dev/null || true

echo
echo "=== PROCESSOS DO MANAGER ==="
compose exec -T wazuh.manager bash -ec '
  ps -eo pid,ppid,comm,rss,vsz,%cpu,%mem --sort=-rss 2>/dev/null | head -20
' 2>/dev/null || true

echo
echo "=== TOPOLOGIA DE /var/ossec/queue ==="
compose exec -T wazuh.manager bash -ec '
  echo "--- primeiro nível ---"
  du -sk /var/ossec/queue/* 2>/dev/null | sort -n | tail -30
  echo
  echo "--- maiores caminhos/arquivos ---"
  du -ak /var/ossec/queue 2>/dev/null | sort -n | tail -40
' || true

echo
echo "=== LOGS RELACIONADOS A VULNERABILIDADES/FEED/CTI ==="
compose exec -T wazuh.manager bash -ec '
  tail -n 1000 /var/ossec/logs/ossec.log 2>/dev/null |
    grep -Ei "vulnerab|vd_|cti|feed|content|database" |
    tail -80
' || true

echo
echo "=== SHARDS NÃO ALOCADOS ==="
SHARDS="$(
  compose exec -T wazuh.manager bash -ec '
    curl -k -sS --max-time 10 \
      -u "$INDEXER_USERNAME:$INDEXER_PASSWORD" \
      "https://wazuh.indexer:9200/_cat/shards?h=index,shard,prirep,state,unassigned.reason&s=state,index"
  ' 2>/dev/null || true
)"
printf '%s\n' "$SHARDS"

UNASSIGNED="$(printf '%s\n' "$SHARDS" | awk '$4=="UNASSIGNED"{print}')"
if [[ -n "$UNASSIGNED" ]]; then
  info "há shard não alocado; será identificado acima"
else
  ok "nenhum shard não alocado neste momento"
fi

echo
echo "=== AMOSTRAGEM DE RAM/CPU/Cgroup ==="
printf "sample\ttimestamp\tcontainer\tcpu_pct\tmem_usage\n" > "$STATS"

for sample in $(seq 1 "$SAMPLE_COUNT"); do
  ts="$(date --iso-8601=seconds)"
  echo "--- amostra $sample/$SAMPLE_COUNT @ $ts ---"

  IDS="$(compose ps -q)"
  docker stats --no-stream \
    --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' \
    $IDS |
  while IFS=$'\t' read -r name cpu mem; do
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$sample" "$ts" "$name" "$cpu" "$mem" >> "$STATS"
    printf '%-44s CPU=%-9s MEM=%s\n' "$name" "$cpu" "$mem"
  done

  echo "-- manager cgroup --"
  compose exec -T wazuh.manager bash -ec '
    if test -r /sys/fs/cgroup/memory.current; then
      echo "memory.current=$(cat /sys/fs/cgroup/memory.current)"
      grep -E "^(anon|file|kernel|slab|inactive_file|active_file) " \
        /sys/fs/cgroup/memory.stat 2>/dev/null || true
    fi
  ' 2>/dev/null || true

  echo "-- manager top RSS --"
  compose exec -T wazuh.manager bash -ec '
    ps -eo pid,comm,rss,vsz,%cpu,%mem --sort=-rss 2>/dev/null | head -12
  ' 2>/dev/null || true

  if (( sample < SAMPLE_COUNT )); then
    sleep "$SAMPLE_INTERVAL"
  fi
done

echo
echo "=== RESUMO DAS AMOSTRAS ==="
python3 - "$STATS" <<'PY'
import csv, re, sys
from collections import defaultdict

def mem_mib(raw):
    left=raw.split("/")[0].strip()
    m=re.fullmatch(r"([0-9.]+)([KMGTP]i?B)", left)
    if not m:
        raise ValueError(left)
    value=float(m.group(1))
    unit=m.group(2)
    factors={"KiB":1/1024,"MiB":1,"GiB":1024,"TiB":1024**2}
    return value*factors[unit]

by=defaultdict(list)
with open(sys.argv[1], encoding="utf-8", newline="") as f:
    for row in csv.DictReader(f, delimiter="\t"):
        by[row["container"]].append(
            (float(row["cpu_pct"].rstrip("%")), mem_mib(row["mem_usage"]))
        )

for name in sorted(by):
    vals=by[name]
    cpus=[v[0] for v in vals]
    mems=[v[1] for v in vals]
    print(
        f"{name}: "
        f"cpu_avg={sum(cpus)/len(cpus):.2f}% "
        f"cpu_max={max(cpus):.2f}% "
        f"mem_avg={sum(mems)/len(mems):.1f}MiB "
        f"mem_max={max(mems):.1f}MiB "
        f"mem_min={min(mems):.1f}MiB"
    )
PY

print_volume_sizes "depois da amostragem"

echo
echo "=== TOPOLOGIA FINAL DE /var/ossec/queue ==="
compose exec -T wazuh.manager bash -ec '
  du -sk /var/ossec/queue/* 2>/dev/null | sort -n | tail -30
' || true

echo
echo "=== SAÚDE FINAL ==="
compose exec -T wazuh.manager bash -ec '
  curl -k -sS --max-time 10 \
    -u "$INDEXER_USERNAME:$INDEXER_PASSWORD" \
    "https://wazuh.indexer:9200/_cluster/health?pretty"
' 2>/dev/null || true

echo
echo "=== ENCERRAMENTO ==="
if compose down --remove-orphans; then
  STARTED=0
  ok "containers removidos; volumes preservados"
else
  fail "falha no encerramento"
fi

FINAL_COUNT="$(
  docker volume ls \
    --filter "label=com.docker.compose.project=$PROJECT" \
    --format '{{.Name}}' | wc -l
)"
echo "volumes_finais=$FINAL_COUNT"
(( FINAL_COUNT == 14 )) \
  && ok "14 volumes preservados" \
  || fail "quantidade final de volumes inesperada"

echo
echo "=== RESULTADO ==="
echo "Falhas: $FAIL"
if [[ "$FAIL" -eq 0 ]]; then
  echo "DIAGNÓSTICO 4G-E: CONCLUÍDO."
  echo "Este diagnóstico não altera política, credenciais nem configuração versionada."
else
  echo "DIAGNÓSTICO 4G-E: CONCLUÍDO COM FALHAS."
fi
echo "Relatório: $REPORT"
echo "Amostras: $STATS"
echo "======================================================================"

[[ "$FAIL" -eq 0 ]]
