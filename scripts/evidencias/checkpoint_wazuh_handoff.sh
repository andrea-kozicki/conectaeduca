#!/usr/bin/env bash
set -u
export LC_ALL=C
export LANG=C

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"
WAZUH_DIR="$ROOT/deploy/interna/wazuh"
BASE="$WAZUH_DIR/compose.yml"
HOST="$WAZUH_DIR/compose.host.yml"
TARGET_PLATFORM="${TARGET_PLATFORM:-linux/amd64}"

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$HOME/Downloads/conectaeduca-checkpoint-wazuh-handoff-${STAMP}.txt"
FAIL=0
WARN=0

ok(){ echo "OK       $*"; }
fail(){ echo "FALHA    $*"; FAIL=$((FAIL+1)); }
warn(){ echo "ATENÇÃO  $*"; WARN=$((WARN+1)); }
info(){ echo "INFO     $*"; }

export CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS="127.0.0.1"
export CONECTAEDUCA_WAZUH_AGENT_PORT="15114"
export CONECTAEDUCA_WAZUH_ENROLLMENT_PORT="15115"
export CONECTAEDUCA_WAZUH_DASHBOARD_BIND_ADDRESS="127.0.0.1"
export CONECTAEDUCA_WAZUH_DASHBOARD_PORT="18445"

DC=(docker compose -p conectaeduca-wazuh -f "$BASE" -f "$HOST")

cleanup() {
  set +e
  "${DC[@]}" down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

exec > >(tee "$REPORT") 2>&1

echo "======================================================================"
echo " CONECTAEDUCA - CHECKPOINT WAZUH / HANDOFF E PORTABILIDADE"
echo " Plataforma alvo: $TARGET_PLATFORM"
echo " Data: $(date --iso-8601=seconds)"
echo "======================================================================"

cd "$ROOT" || exit 1

echo
echo "=== 1. GIT / DOCKER ==="
git status -sb

BRANCH="$(git branch --show-current 2>/dev/null || true)"
[[ "$BRANCH" == "main" ]] \
  && ok "branch main confirmada" \
  || fail "branch deve ser main"

git diff --check \
  && ok "git diff --check" \
  || fail "git diff --check"

if docker info >/dev/null 2>&1; then
  ok "API Docker acessível"
else
  fail "API Docker inacessível"
  echo "Relatório: $REPORT"
  exit 1
fi

echo
echo "=== 2. CONTRATO DO HOST ==="
VM_MAX="$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 0)"
echo "vm.max_map_count=$VM_MAX"
if [[ "$VM_MAX" =~ ^[0-9]+$ ]] && (( VM_MAX >= 262144 )); then
  ok "vm.max_map_count >= 262144"
else
  fail "vm.max_map_count insuficiente para o Wazuh Indexer"
fi

RAM_GB="$(awk '/MemTotal:/ {printf "%.1f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)"
echo "ram_host_gib=$RAM_GB"
python3 -c 'import sys; raise SystemExit(0 if float(sys.argv[1]) >= 8 else 1)' "$RAM_GB" \
  && ok "host local possui pelo menos 8 GiB de RAM" \
  || fail "host local possui menos de 8 GiB de RAM"

DOCKER_ROOT="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
FREE_GB="$(df -Pk "$DOCKER_ROOT" 2>/dev/null | awk 'NR==2 {printf "%.1f", $4/1024/1024}')"
echo "docker_root=$DOCKER_ROOT free_gib=${FREE_GB:-indisponivel}"
if [[ -n "${FREE_GB:-}" ]]; then
  python3 -c 'import sys; raise SystemExit(0 if float(sys.argv[1]) >= 50 else 1)' "$FREE_GB" \
    && ok "filesystem do Docker possui pelo menos 50 GiB livres" \
    || warn "filesystem do Docker possui menos de 50 GiB livres"
fi

echo
echo "=== 3. ARQUIVOS / HIGIENE ==="
for f in \
  "$BASE" \
  "$HOST" \
  "$WAZUH_DIR/compose.lab.yml" \
  "$WAZUH_DIR/generate-indexer-certs.yml" \
  "$WAZUH_DIR/CONTRATO-HOST.md" \
  "$WAZUH_DIR/IMAGENS-VALIDADAS.md" \
  "$WAZUH_DIR/RETENCAO.md" \
  "$WAZUH_DIR/INTEGRACAO-FERRET-DLP.md" \
  "$WAZUH_DIR/config/rules/conectaeduca_dlp_rules.xml" \
  "$WAZUH_DIR/agent/conectaeduca-dlp-localfile.xml.example"
do
  [[ -f "$f" ]] && ok "${f#$ROOT/}" || fail "arquivo ausente: ${f#$ROOT/}"
done

if git ls-files | grep -Eq '^deploy/interna/wazuh/\.runtime/'; then
  fail ".runtime do Wazuh possui arquivo rastreado"
else
  ok ".runtime não é rastreado pelo Git"
fi

if grep -RInE \
  '(SecretPassword|MyS3cr37P450r|kibanaserver[[:space:]]*$)' \
  "$WAZUH_DIR" \
  --exclude-dir=.runtime \
  2>/dev/null | grep -q .; then
  fail "credencial padrão encontrada em arquivo versionável do Wazuh"
else
  ok "credenciais padrão ausentes dos arquivos versionáveis"
fi

if grep -RInE '([0-9]{1,3}\.){3}[0-9]{1,3}' \
  "$HOST" 2>/dev/null | grep -q .; then
  fail "compose.host.yml contém IP literal"
else
  ok "compose.host.yml não fixa IP real de infraestrutura"
fi

if grep -Fq './config/rules/conectaeduca_dlp_rules.xml:/wazuh-config-mount/etc/rules/conectaeduca_dlp_rules.xml:ro' "$BASE"; then
  ok "regra DLP customizada é entregue ao Manager por montagem somente leitura"
else
  fail "Compose não entrega a regra DLP customizada ao Manager"
fi

if grep -Fq '<log_format>json</log_format>' "$WAZUH_DIR/agent/conectaeduca-dlp-localfile.xml.example" \
   && grep -Fq '__CONECTAEDUCA_DLP_EVENTS_FILE__' "$WAZUH_DIR/agent/conectaeduca-dlp-localfile.xml.example"; then
  ok "modelo do Wazuh Agent coleta JSONL DLP por caminho explícito"
else
  fail "modelo do Wazuh Agent para DLP está incompleto"
fi

AGENT_DLP_LOCATION="$(
  sed -n 's#.*<location>\(.*\)</location>.*#\1#p' \
    "$WAZUH_DIR/agent/conectaeduca-dlp-localfile.xml.example" \
    | head -n 1
)"
if [[ "$AGENT_DLP_LOCATION" == *"reports/raw"* || "$AGENT_DLP_LOCATION" == *"/inbox/"* ]]; then
  fail "location do agente referencia superfície bruta/sensível do Ferret"
else
  ok "location do agente não referencia inbox nem reports/raw"
fi

python3 - "$WAZUH_DIR/config/rules/conectaeduca_dlp_rules.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
p = sys.argv[1]
root = ET.parse(p).getroot()
ids = {r.get("id") for r in root.findall("rule")}
expected = {"110100","110101","110102","110110","110111","110112","110113"}
raise SystemExit(0 if ids == expected else 1)
PY
[[ $? -eq 0 ]] \
  && ok "regras DLP XML possuem exatamente os IDs customizados esperados" \
  || fail "regras DLP XML/IDs divergentes"

echo
echo "=== 4. IMAGENS / DIGEST / PLATAFORMA ==="
python3 -c '
from pathlib import Path
import re

targets = [
    ("manager", "deploy/interna/wazuh/compose.yml", r"image:\s*[\"\x27]?(wazuh/wazuh-manager:4\.14\.7@sha256:[0-9a-f]{64})"),
    ("indexer", "deploy/interna/wazuh/compose.yml", r"image:\s*[\"\x27]?(wazuh/wazuh-indexer:4\.14\.7@sha256:[0-9a-f]{64})"),
    ("dashboard", "deploy/interna/wazuh/compose.yml", r"image:\s*[\"\x27]?(wazuh/wazuh-dashboard:4\.14\.7@sha256:[0-9a-f]{64})"),
    ("generator", "deploy/interna/wazuh/generate-indexer-certs.yml", r"image:\s*[\"\x27]?(wazuh/wazuh-certs-generator:0\.0\.4@sha256:[0-9a-f]{64})"),
]
for label, path, regex in targets:
    text = Path(path).read_text(encoding="utf-8")
    m = re.search(regex, text)
    print(f"{label}|{m.group(1) if m else 'MISSING'}")
' > "/tmp/conectaeduca-wazuh-pins-${STAMP}.txt"

PINFILE="/tmp/conectaeduca-wazuh-pins-${STAMP}.txt"
cat "$PINFILE"

while IFS='|' read -r label ref; do
  if [[ "$ref" == "MISSING" ]]; then
    fail "$label não está fixado por digest"
    continue
  fi

  ok "$label está fixado por digest"

  if docker buildx imagetools inspect "$ref" >/dev/null 2>&1; then
    ok "$label: digest resolvível no registry"
  else
    fail "$label: digest não resolvível no registry"
    continue
  fi

  if docker pull --platform "$TARGET_PLATFORM" "$ref" >/dev/null 2>&1; then
    ok "$label: pull exato funciona para $TARGET_PLATFORM"
  else
    fail "$label: pull exato falhou para $TARGET_PLATFORM"
  fi
done < "$PINFILE"

echo
echo "=== 5. COMPOSE DE HANDOFF ==="
if "${DC[@]}" config >/tmp/conectaeduca-wazuh-compose-${STAMP}.yml 2>&1; then
  ok "Compose base + handoff válido"
else
  fail "Compose base + handoff inválido"
  sed -n '1,160p' /tmp/conectaeduca-wazuh-compose-${STAMP}.yml
fi

CONFIG_JSON="/tmp/conectaeduca-wazuh-compose-${STAMP}.json"
if "${DC[@]}" config --format json > "$CONFIG_JSON" 2>/dev/null; then
  ok "Compose JSON gerado para inspeção"
else
  fail "não foi possível gerar Compose JSON"
fi

python3 - "$CONFIG_JSON" <<'PY'
import json, sys

p = sys.argv[1]
try:
    cfg = json.load(open(p, encoding="utf-8"))
except Exception:
    print("PARSE_ERROR")
    raise SystemExit(0)

for name, svc in cfg.get("services", {}).items():
    for port in svc.get("ports", []) or []:
        print(
            f"{name}|"
            f"{port.get('host_ip','')}|"
            f"{port.get('published','')}|"
            f"{port.get('target','')}|"
            f"{port.get('protocol','tcp')}"
        )
PY

PORTS="$(
  python3 - "$CONFIG_JSON" <<'PY'
import json, sys
cfg=json.load(open(sys.argv[1], encoding="utf-8"))
for name, svc in cfg.get("services", {}).items():
    for p in svc.get("ports", []) or []:
        print(f"{name}|{p.get('host_ip','')}|{p.get('published','')}|{p.get('target','')}|{p.get('protocol','tcp')}")
PY
)"

echo "$PORTS"

expected_1514='wazuh.manager|127.0.0.1|15114|1514|tcp'
expected_1515='wazuh.manager|127.0.0.1|15115|1515|tcp'
expected_dash='wazuh.dashboard|127.0.0.1|18445|5601|tcp'

grep -Fxq "$expected_1514" <<<"$PORTS" \
  && ok "Manager 1514 parametrizado" \
  || fail "binding 1514 do Manager divergente"

grep -Fxq "$expected_1515" <<<"$PORTS" \
  && ok "Manager 1515 parametrizado" \
  || fail "binding 1515 do Manager divergente"

grep -Fxq "$expected_dash" <<<"$PORTS" \
  && ok "Dashboard parametrizado" \
  || fail "binding do Dashboard divergente"

if grep -Eq '\|(9200|55000|514)\|' <<<"$PORTS"; then
  fail "Indexer API, Manager API ou syslog foram publicados no handoff"
else
  ok "9200, 55000 e 514 não são publicados no host"
fi

echo
echo "=== 6. RUNTIME LOCAL ==="
for f in \
  "$WAZUH_DIR/.runtime/manager.env" \
  "$WAZUH_DIR/.runtime/dashboard.env" \
  "$WAZUH_DIR/.runtime/internal_users.yml" \
  "$WAZUH_DIR/.runtime/wazuh.yml"
do
  if [[ -f "$f" ]]; then
    mode="$(stat -c '%a' "$f" 2>/dev/null || true)"
    echo "$(basename "$f") mode=$mode"
    [[ "$mode" == "600" ]] \
      && ok "$(basename "$f") protegido com modo 600" \
      || warn "$(basename "$f") existe, mas modo=$mode"
  else
    fail "runtime necessário ausente: ${f#$ROOT/}"
  fi
done

echo
echo "=== 7. PORTAS DE TESTE ==="
python3 - <<'PY'
import socket
ports=[15114,15115,18445]
bad=[]
for port in ports:
    s=socket.socket()
    try:
        s.bind(("127.0.0.1",port))
    except OSError:
        bad.append(port)
    finally:
        s.close()
print("livres=" + ",".join(map(str, sorted(set(ports)-set(bad)))))
print("ocupadas=" + ",".join(map(str,bad)))
raise SystemExit(1 if bad else 0)
PY
[[ $? -eq 0 ]] && ok "portas sintéticas livres" || fail "há porta sintética ocupada"

echo
echo "=== 8. VOLUMES DECLARADOS / SUBIDA ==="
DECLARED_VOLUMES="$("${DC[@]}" config --volumes 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"
echo "volumes_declarados=$DECLARED_VOLUMES"
(( DECLARED_VOLUMES >= 14 )) \
  && ok "stack declara ao menos 14 volumes persistentes" \
  || fail "quantidade de volumes persistentes menor que o baseline"

if "${DC[@]}" up -d; then
  ok "stack Wazuh iniciou com o perfil de handoff"
else
  fail "stack Wazuh não iniciou"
fi

MANAGER_ID="$("${DC[@]}" ps -q wazuh.manager 2>/dev/null || true)"
INDEXER_ID="$("${DC[@]}" ps -q wazuh.indexer 2>/dev/null || true)"
DASH_ID="$("${DC[@]}" ps -q wazuh.dashboard 2>/dev/null || true)"

wait_running() {
  local label="$1" cid="$2" max="${3:-180}" t=0 state=""
  while (( t <= max )); do
    state="$(docker inspect "$cid" --format '{{.State.Status}}' 2>/dev/null || true)"
    echo "wait label=$label t=${t}s state=$state"
    [[ "$state" == "running" ]] && return 0
    sleep 5
    t=$((t+5))
  done
  return 1
}

for pair in "manager:$MANAGER_ID" "indexer:$INDEXER_ID" "dashboard:$DASH_ID"; do
  label="${pair%%:*}"
  cid="${pair#*:}"
  if [[ -n "$cid" ]] && wait_running "$label" "$cid" 120; then
    ok "$label está running"
  else
    fail "$label não ficou running"
  fi
done

echo
echo "=== 9. FUNCIONALIDADE INTERNA ==="

wait_manager_ready() {
  local max="${1:-180}" t=0 status=""

  while (( t <= max )); do
    status="$(
      docker exec "$MANAGER_ID" sh -lc \
        '/var/ossec/bin/wazuh-control status 2>/dev/null' \
        2>/dev/null || true
    )"

    if grep -q "wazuh-analysisd is running" <<<"$status" \
       && grep -q "wazuh-remoted is running" <<<"$status"; then
      echo "manager_ready t=${t}s analysisd=running remoted=running"
      return 0
    fi

    echo "manager_wait t=${t}s"
    sleep 5
    t=$((t+5))
  done

  return 1
}

wait_indexer_ready() {
  local max="${1:-180}" t=0 health="" status=""

  while (( t <= max )); do
    health="$(
      docker exec "$DASH_ID" sh -lc \
        'curl -sk --connect-timeout 3 --max-time 5 \
        -u "$INDEXER_USERNAME:$INDEXER_PASSWORD" \
        https://wazuh.indexer:9200/_cluster/health' \
        2>/dev/null || true
    )"

    status="$(
      printf '%s' "$health" |
        python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("status",""))
except Exception:
    print("")'
    )"

    echo "indexer_wait t=${t}s status=${status:-unavailable}"

    if [[ "$status" == "green" || "$status" == "yellow" ]]; then
      INDEXER_HEALTH="$health"
      INDEXER_STATUS="$status"
      return 0
    fi

    sleep 5
    t=$((t+5))
  done

  INDEXER_HEALTH="$health"
  INDEXER_STATUS="$status"
  return 1
}

wait_manager_api() {
  local max="${1:-180}" t=0 token="" len=0

  while (( t <= max )); do
    token="$(
      docker exec "$DASH_ID" sh -lc \
        'curl -sk --connect-timeout 3 --max-time 5 \
        -u "$API_USERNAME:$API_PASSWORD" \
        -X POST \
        "https://wazuh.manager:55000/security/user/authenticate?raw=true"' \
        2>/dev/null || true
    )"

    len="${#token}"

    echo "manager_api_wait t=${t}s token_length=$len"

    if (( len > 20 )); then
      TOKEN_LEN="$len"
      return 0
    fi

    sleep 5
    t=$((t+5))
  done

  TOKEN_LEN="$len"
  return 1
}

wait_dashboard_ready() {
  local max="${1:-180}" t=0 code=""

  while (( t <= max )); do
    code="$(
      curl -sk \
        --connect-timeout 3 \
        --max-time 5 \
        -o /dev/null \
        -w '%{http_code}' \
        https://127.0.0.1:18445/ \
        2>/dev/null || true
    )"

    [[ -n "$code" ]] || code="000"

    echo "dashboard_wait t=${t}s http=$code"

    if [[ "$code" == "200" || "$code" == "302" ]]; then
      DASH_HTTP="$code"
      return 0
    fi

    sleep 5
    t=$((t+5))
  done

  DASH_HTTP="$code"
  return 1
}

if wait_manager_ready 180; then
  ok "Manager possui analysisd e remoted em execução"
else
  fail "processos essenciais do Manager não confirmados"
fi

echo
echo "=== 9A. FERRET DLP / DECODER JSON / REGRAS CUSTOMIZADAS ==="

if docker exec "$MANAGER_ID" test -f /var/ossec/etc/rules/conectaeduca_dlp_rules.xml 2>/dev/null; then
  ok "regra DLP customizada materializada em /var/ossec/etc/rules"
else
  fail "regra DLP customizada não foi materializada no Manager"
fi

run_dlp_logtest() {
  local label="$1"
  local expected_rule="$2"
  local event="$3"
  local output

  output="$(
    printf '%s\n' "$event" \
      | docker exec -i "$MANAGER_ID" /var/ossec/bin/wazuh-logtest 2>&1 \
      || true
  )"

  echo "--- logtest: $label ---"
  printf '%s\n' "$output" | tail -n 28

  if grep -Eq "id: ['\\\"]?$expected_rule['\\\"]?" <<<"$output"; then
    ok "$label classificado pela regra $expected_rule"
    return 0
  fi

  fail "$label não atingiu a regra esperada $expected_rule"
  return 1
}

DLP_FILE_ID='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
DLP_SCAN_ID='11111111-1111-4111-8111-111111111111'
DLP_TS='2026-08-21T22:00:00Z'

DLP_HIGH='{"schema_version":"1","event_type":"dlp_finding","source":"ferret-scan","source_version":"2.2.1","observed_at":"'"$DLP_TS"'","scan_id":"'"$DLP_SCAN_ID"'","finding_index":1,"file_id":"'"$DLP_FILE_ID"'","validator":"SECRETS","finding_type":"secret","confidence_level":"high","confidence":95,"line_number":1,"secret_type":"synthetic","detection_method":"pattern","environment_type":"test","sanitization_profile":"conectaeduca-allowlist-v1"}'
DLP_MEDIUM='{"schema_version":"1","event_type":"dlp_finding","source":"ferret-scan","source_version":"2.2.1","observed_at":"'"$DLP_TS"'","scan_id":"'"$DLP_SCAN_ID"'","finding_index":1,"file_id":"'"$DLP_FILE_ID"'","validator":"EMAIL","finding_type":"pii","confidence_level":"medium","confidence":70,"line_number":2,"secret_type":"","detection_method":"pattern","environment_type":"test","sanitization_profile":"conectaeduca-allowlist-v1"}'
DLP_LOW='{"schema_version":"1","event_type":"dlp_finding","source":"ferret-scan","source_version":"2.2.1","observed_at":"'"$DLP_TS"'","scan_id":"'"$DLP_SCAN_ID"'","finding_index":1,"file_id":"'"$DLP_FILE_ID"'","validator":"PERSON_NAME","finding_type":"pii","confidence_level":"low","confidence":40,"line_number":3,"secret_type":"","detection_method":"context","environment_type":"test","sanitization_profile":"conectaeduca-allowlist-v1"}'
DLP_SUMMARY_FINDINGS='{"schema_version":"1","event_type":"dlp_scan_summary","source":"ferret-scan","source_version":"2.2.1","observed_at":"'"$DLP_TS"'","scan_id":"'"$DLP_SCAN_ID"'","file_id":"'"$DLP_FILE_ID"'","files_processed":1,"files_skipped":0,"total_findings":1,"emitted_findings":1,"high":1,"medium":0,"low":0,"suppressed":0,"duration_seconds":0.01,"source_report_shape":"object","stats_complete":true,"sanitization_profile":"conectaeduca-allowlist-v1"}'

run_dlp_logtest "finding high" "110113" "$DLP_HIGH"
run_dlp_logtest "finding medium" "110112" "$DLP_MEDIUM"
run_dlp_logtest "finding low" "110111" "$DLP_LOW"
run_dlp_logtest "summary com findings" "110102" "$DLP_SUMMARY_FINDINGS"

UNRELATED='{"schema_version":"1","event_type":"dlp_finding","source":"outro-componente","confidence_level":"high"}'
UNRELATED_OUT="$(
  printf '%s\n' "$UNRELATED" \
    | docker exec -i "$MANAGER_ID" /var/ossec/bin/wazuh-logtest 2>&1 \
    || true
)"
if grep -Eq "id: ['\\\"]?1101(00|01|02|10|11|12|13)['\\\"]?" <<<"$UNRELATED_OUT"; then
  fail "evento JSON de outro componente atingiu regra DLP do ConectaEduca"
else
  ok "evento de outro componente não aciona regras Ferret DLP"
fi

INDEXER_HEALTH=""
INDEXER_STATUS=""

if wait_indexer_ready 180; then
  echo "indexer_status=$INDEXER_STATUS"
  ok "Indexer autenticado e funcional"
else
  echo "indexer_status=${INDEXER_STATUS:-}"
  fail "Indexer não respondeu com saúde green/yellow"
fi

TOKEN_LEN=0

if wait_manager_api 180; then
  echo "manager_api_token_length=$TOKEN_LEN"
  ok "Manager API autenticou usando credencial de runtime"
else
  echo "manager_api_token_length=$TOKEN_LEN"
  fail "Manager API não autenticou"
fi

DASH_HTTP="000"

if wait_dashboard_ready 180; then
  echo "dashboard_https=$DASH_HTTP"
  ok "Dashboard HTTPS acessível pelo binding de handoff"
else
  echo "dashboard_https=$DASH_HTTP"
  fail "Dashboard não respondeu no binding de handoff"
fi

echo
echo "=== 10. PORTAS EXTERNAS DO HANDOFF ==="
python3 - <<'PY'
import socket, sys
bad=[]
for port in (15114,15115):
    s=socket.socket()
    s.settimeout(2)
    try:
        s.connect(("127.0.0.1",port))
        print(f"tcp_{port}=open")
    except OSError:
        bad.append(port)
        print(f"tcp_{port}=closed")
    finally:
        s.close()
raise SystemExit(1 if bad else 0)
PY
[[ $? -eq 0 ]] \
  && ok "portas de agente/enrollment acessíveis no host" \
  || fail "porta de agente/enrollment não acessível"

MANAGER_PORTS="$(docker port "$MANAGER_ID" 2>/dev/null || true)"
INDEXER_PORTS="$(docker port "$INDEXER_ID" 2>/dev/null || true)"
DASH_PORTS="$(docker port "$DASH_ID" 2>/dev/null || true)"

echo "--- manager ---"
echo "$MANAGER_PORTS"
echo "--- indexer ---"
echo "$INDEXER_PORTS"
echo "--- dashboard ---"
echo "$DASH_PORTS"

grep -q '55000' <<<"$MANAGER_PORTS" \
  && fail "Manager API 55000 publicada no host" \
  || ok "Manager API 55000 permanece privada"

[[ -z "$INDEXER_PORTS" ]] \
  && ok "Indexer API permanece sem publicação no host" \
  || fail "Indexer possui publicação inesperada"

echo
echo "=== 11. RECURSOS ==="
docker stats --no-stream \
  --format '{{.Name}}\tCPU={{.CPUPerc}}\tMEM={{.MemUsage}}' \
  "$MANAGER_ID" "$INDEXER_ID" "$DASH_ID" 2>/dev/null || true

echo
echo "=== 12. VOLUMES / ENCERRAMENTO ==="
ACTIVE_VOLUMES="$(
  docker volume ls --format '{{.Name}}' \
    | grep '^conectaeduca-wazuh_' \
    | wc -l | tr -d ' '
)"
echo "volumes_ativos=$ACTIVE_VOLUMES"
(( ACTIVE_VOLUMES >= DECLARED_VOLUMES )) \
  && ok "volumes persistentes estão materializados" \
  || fail "nem todos os volumes declarados foram materializados"

if "${DC[@]}" down --remove-orphans; then
  ok "containers removidos preservando volumes"
else
  fail "falha ao encerrar stack"
fi

AFTER_VOLUMES="$(
  docker volume ls --format '{{.Name}}' \
    | grep '^conectaeduca-wazuh_' \
    | wc -l | tr -d ' '
)"
echo "volumes_apos_down=$AFTER_VOLUMES"
(( AFTER_VOLUMES >= DECLARED_VOLUMES )) \
  && ok "volumes persistem após remoção dos containers" \
  || fail "volumes persistentes foram perdidos"

echo
echo "=== 13. RETENÇÃO / BASELINE VERSIONADO ==="
[[ -f "$WAZUH_DIR/config/ism/conectaeduca-alertas-retencao-30d.json" ]] \
  && ok "política ISM 30d permanece versionada" \
  || fail "política ISM 30d ausente"

grep -RIn '<logall>yes</logall>\|<logall_json>yes</logall_json>' \
  "$WAZUH_DIR/config" 2>/dev/null | grep -q . \
  && fail "arquivamento completo parece habilitado" \
  || ok "nenhuma habilitação versionada de archives completos detectada"

echo
echo "=== 14. GIT FINAL ==="
git status -sb
git diff --check \
  && ok "git diff --check final" \
  || fail "git diff --check final"

rm -f "$PINFILE"

echo
echo "======================================================================"
echo " RESULTADO"
echo "======================================================================"
echo "Falhas: $FAIL"
echo "Advertências: $WARN"

if [[ "$FAIL" -eq 0 ]]; then
  echo "CHECKPOINT WAZUH / HANDOFF: APROVADO."
  echo "Imagens fixadas por digest, plataforma validada e perfil de VM testado."
  echo "Manager expõe apenas 1514/1515; Dashboard usa binding parametrizável."
  echo "Indexer API e Manager API permanecem privadas no host."
  echo "Regras Ferret DLP são validadas no decoder JSON com wazuh-logtest."
  echo "Volumes são preservados e o runtime sensível permanece fora do Git."
else
  echo "CHECKPOINT WAZUH / HANDOFF: REPROVADO."
fi

echo "Relatório: $REPORT"
echo "======================================================================"

[[ "$FAIL" -eq 0 ]]
