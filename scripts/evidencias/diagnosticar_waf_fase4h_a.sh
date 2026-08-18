#!/usr/bin/env bash
set -u
export LC_ALL=C
export LANG=C

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"
TARGET_IMAGE="${TARGET_IMAGE:-owasp/modsecurity-crs:4.25.1-nginx-lts}"
LAB_BACKEND_IMAGE="${LAB_BACKEND_IMAGE:-nginx:alpine}"
PROJECT="conectaeduca-waf-4h-a"
LAB_PORT="${LAB_PORT:-18080}"
STAMP="$(date +%Y%m%d-%H%M%S)"
LAB_DIR="/tmp/conectaeduca-waf-4h-a-${STAMP}"
REPORT="/tmp/conectaeduca-waf-fase4h-a-${STAMP}.txt"

FAIL=0
STARTED=0

ok(){ echo "OK       $*"; }
fail(){ echo "FALHA    $*"; FAIL=$((FAIL+1)); }
info(){ echo "INFO     $*"; }

cleanup() {
  set +e
  if [[ "$STARTED" -eq 1 && -f "$LAB_DIR/compose.yml" ]]; then
    docker compose -p "$PROJECT" -f "$LAB_DIR/compose.yml" down --remove-orphans >/dev/null 2>&1 || true
  fi
  rm -rf "$LAB_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

exec > >(tee "$REPORT") 2>&1

echo "======================================================================"
echo " CONECTAEDUCA - FASE 4H-A"
echo " Diagnóstico e smoke test do WAF ModSecurity + OWASP CRS — v2"
echo " Data: $(date --iso-8601=seconds)"
echo " Imagem alvo: $TARGET_IMAGE"
echo "======================================================================"

cd "$ROOT" || exit 1

echo
echo "=== 1. BRANCH / GIT ==="
git status -sb

BRANCH="$(git branch --show-current 2>/dev/null || true)"
echo "branch_atual=$BRANCH"

[[ "$BRANCH" == "feature/auth-local" ]] \
  && ok "branch feature/auth-local confirmada" \
  || fail "esta fase deve ser executada em feature/auth-local"

git diff --check \
  && ok "git diff --check" \
  || fail "git diff --check"

echo
echo "=== 2. PRÉ-REQUISITOS ==="
for cmd in docker curl python3 ss; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd disponível"
  else
    fail "$cmd ausente"
  fi
done

if docker info >/dev/null 2>&1; then
  ok "Docker Engine acessível"
else
  fail "Docker Engine indisponível para o usuário atual"
fi

if docker compose version >/dev/null 2>&1; then
  echo "docker_compose=$(docker compose version --short 2>/dev/null || docker compose version)"
  ok "Docker Compose acessível"
else
  fail "Docker Compose indisponível"
fi

echo
echo "=== 3. INVENTÁRIO DMZ EXISTENTE — SOMENTE LEITURA ==="
if [[ -d "$ROOT/deploy/dmz" ]]; then
  find "$ROOT/deploy/dmz" -maxdepth 3 -type f \
    \( -name '*.yml' -o -name '*.yaml' -o -name 'Dockerfile*' -o -name '*.conf' \) \
    -printf '%P\n' | sort
  ok "deploy/dmz encontrado"
else
  info "deploy/dmz não encontrado; integração será tratada na 4H-B"
fi

echo
echo "--- arquivos Compose candidatos ---"
find "$ROOT/deploy/dmz" -maxdepth 3 -type f \
  \( -iname 'compose*.yml' -o -iname 'compose*.yaml' -o -iname 'docker-compose*.yml' -o -iname 'docker-compose*.yaml' \) \
  -print 2>/dev/null || true

echo
echo "--- portas de containers ConectaEduca atualmente em execução ---"
docker ps \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}' |
  grep -Ei 'NAMES|conectaeduca|nginx|php' || true

echo
echo "=== 4. PORTA DO LABORATÓRIO ==="
if ss -H -ltn "( sport = :$LAB_PORT )" 2>/dev/null | grep -q .; then
  fail "porta TCP $LAB_PORT já está em uso"
else
  ok "porta TCP $LAB_PORT livre"
fi

echo
echo "=== 5. IMAGEM OFICIAL / TAG FIXA ==="
echo "target_image=$TARGET_IMAGE"

if docker manifest inspect "$TARGET_IMAGE" >/dev/null 2>&1; then
  ok "manifesto remoto da imagem alvo acessível"
else
  fail "não foi possível validar o manifesto de $TARGET_IMAGE"
fi

if docker pull "$TARGET_IMAGE"; then
  ok "imagem WAF obtida"
else
  fail "falha ao obter imagem WAF"
fi

IMAGE_ID="$(docker image inspect "$TARGET_IMAGE" --format '{{.Id}}' 2>/dev/null || true)"
IMAGE_DIGEST="$(docker image inspect "$TARGET_IMAGE" --format '{{join .RepoDigests "\n"}}' 2>/dev/null || true)"
echo "image_id=$IMAGE_ID"
echo "repo_digest=$IMAGE_DIGEST"

[[ -n "$IMAGE_ID" ]] \
  && ok "imagem WAF presente localmente" \
  || fail "imagem WAF não encontrada após pull"

echo
echo "=== 6. CRIAÇÃO DO LABORATÓRIO EFÊMERO ==="
mkdir -p "$LAB_DIR"

cat > "$LAB_DIR/compose.yml" <<YAML
name: ${PROJECT}

services:
  backend:
    image: ${LAB_BACKEND_IMAGE}
    restart: "no"
    networks:
      - waf-lab
    expose:
      - "80"

  waf:
    image: ${TARGET_IMAGE}
    restart: "no"
    depends_on:
      - backend
    environment:
      BACKEND: "http://backend:80"
      SERVER_NAME: "localhost"
      PORT: "8080"
      MODSEC_RULE_ENGINE: "On"
      MODSEC_AUDIT_ENGINE: "RelevantOnly"
      MODSEC_AUDIT_LOG: "/dev/stdout"
      MODSEC_AUDIT_LOG_FORMAT: "JSON"
      MODSEC_AUDIT_LOG_PARTS: "ABFHZ"
      BLOCKING_PARANOIA: "1"
      DETECTION_PARANOIA: "1"
      ANOMALY_INBOUND: "5"
      ANOMALY_OUTBOUND: "4"
      SERVER_TOKENS: "off"
    ports:
      - "127.0.0.1:${LAB_PORT}:8080"
    networks:
      - waf-lab

networks:
  waf-lab:
    internal: false
YAML

if docker compose -p "$PROJECT" -f "$LAB_DIR/compose.yml" config >/dev/null; then
  ok "Compose efêmero válido"
else
  fail "Compose efêmero inválido"
fi

echo
echo "=== 7. SUPERFÍCIE DECLARADA DO LAB ==="
CONFIG_JSON="$(
  docker compose -p "$PROJECT" -f "$LAB_DIR/compose.yml" config --format json 2>/dev/null || true
)"

if printf '%s' "$CONFIG_JSON" | python3 -c '
import json, sys
port=int(sys.argv[1])
c=json.load(sys.stdin)["services"]
assert not c["backend"].get("ports")
ports=c["waf"].get("ports", [])
assert len(ports)==1
p=ports[0]
assert p.get("host_ip")=="127.0.0.1"
assert int(p.get("published"))==port
assert int(p.get("target"))==8080
' "$LAB_PORT"
then
  ok "somente o WAF é publicado, em loopback"
else
  fail "superfície de rede do laboratório não corresponde ao esperado"
fi

echo
echo "=== 8. SUBIDA ==="
if docker compose -p "$PROJECT" -f "$LAB_DIR/compose.yml" up -d; then
  STARTED=1
  ok "WAF e backend iniciados"
else
  fail "falha ao iniciar laboratório"
fi

docker compose -p "$PROJECT" -f "$LAB_DIR/compose.yml" ps || true

echo
echo "=== 9. HEALTHCHECK / BACKEND ==="
HEALTH=""
for t in $(seq 0 30); do
  HEALTH="$(docker inspect "${PROJECT}-waf-1" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}sem-healthcheck{{end}}' 2>/dev/null || true)"
  echo "health_wait t=$((t*2))s status=${HEALTH:-desconhecido}"
  [[ "$HEALTH" == "healthy" ]] && break
  sleep 2
done

[[ "$HEALTH" == "healthy" ]] \
  && ok "healthcheck oficial do container ficou healthy" \
  || fail "WAF não ficou healthy no tempo esperado"

BENIGN_CODE="$(
  curl -sS --max-time 10 \
    -o /tmp/conectaeduca-waf-benign-${STAMP}.body \
    -w '%{http_code}' \
    "http://127.0.0.1:${LAB_PORT}/" \
    2>/dev/null || true
)"
echo "benign_http=$BENIGN_CODE"
[[ "$BENIGN_CODE" == "200" ]] \
  && ok "requisição benigna atravessou WAF e alcançou backend" \
  || fail "requisição benigna não retornou HTTP 200"

echo
echo "=== 10. TESTES DE BLOQUEIO OWASP CRS ==="

XSS_CODE="$(
  curl -sS --max-time 10 \
    -G \
    --data-urlencode 'q=<script>alert(1)</script>' \
    -o /dev/null \
    -w '%{http_code}' \
    "http://127.0.0.1:${LAB_PORT}/" \
    2>/dev/null || true
)"
echo "xss_http=$XSS_CODE"

[[ "$XSS_CODE" == "403" ]] \
  && ok "payload XSS sintético bloqueado" \
  || fail "payload XSS não foi bloqueado como esperado"

SQLI_CODE="$(
  curl -sS --max-time 10 \
    -G \
    --data-urlencode "id=1' OR '1'='1" \
    -o /dev/null \
    -w '%{http_code}' \
    "http://127.0.0.1:${LAB_PORT}/" \
    2>/dev/null || true
)"
echo "sqli_http=$SQLI_CODE"

[[ "$SQLI_CODE" == "403" ]] \
  && ok "payload SQLi sintético bloqueado" \
  || fail "payload SQLi não foi bloqueado como esperado"

TRAVERSAL_CODE="$(
  curl -sS --max-time 10 \
    -G \
    --data-urlencode 'file=../../../../etc/passwd' \
    -o /dev/null \
    -w '%{http_code}' \
    "http://127.0.0.1:${LAB_PORT}/" \
    2>/dev/null || true
)"
echo "traversal_http=$TRAVERSAL_CODE"

if [[ "$TRAVERSAL_CODE" == "403" ]]; then
  ok "payload traversal sintético bloqueado"
else
  info "payload traversal retornou HTTP $TRAVERSAL_CODE; não reprova 4H-A porque XSS/SQLi são as provas obrigatórias"
fi

echo
echo "=== 11. AUDIT LOG / PRIVACIDADE ==="
WAF_LOGS="$(docker logs "${PROJECT}-waf-1" 2>&1 || true)"

if printf '%s' "$WAF_LOGS" | grep -Eq '"message"|ModSecurity|modsecurity|id "[0-9]+'; then
  ok "WAF produziu evidência de auditoria para tráfego relevante"
else
  fail "não foi localizada evidência de auditoria do ModSecurity"
fi

if printf '%s' "$WAF_LOGS" | grep -Fq '"request_body"'; then
  fail "audit log aparenta conter campo explícito de request body"
else
  ok "não foi observado campo explícito request_body no audit log"
fi

echo "--- IDs de regras observados, sem imprimir transações completas ---"
printf '%s\n' "$WAF_LOGS" |
  grep -Eo 'id "[0-9]{6}"|ruleId["=: ]+[0-9]{6}' |
  sort -u |
  head -20 || true

echo
echo "=== 12. SUPERFÍCIE REAL ==="
docker ps \
  --filter "label=com.docker.compose.project=$PROJECT" \
  --format 'table {{.Names}}\t{{.Ports}}'

BACKEND_BINDINGS="$(docker port "${PROJECT}-backend-1" 2>/dev/null || true)"
if [[ -z "$BACKEND_BINDINGS" ]]; then
  ok "backend não possui porta publicada no host"
else
  printf '%s\n' "$BACKEND_BINDINGS"
  fail "backend foi publicado no host"
fi

WAF_BINDINGS="$(docker port "${PROJECT}-waf-1" 8080/tcp 2>/dev/null || true)"
echo "waf_bindings=$WAF_BINDINGS"

if printf '%s' "$WAF_BINDINGS" | grep -Fxq "127.0.0.1:${LAB_PORT}"; then
  ok "WAF publicado somente em 127.0.0.1:${LAB_PORT}"
else
  fail "binding real do WAF inesperado"
fi

echo
echo "=== 13. RECURSOS ==="
IDS="$(
  docker compose -p "$PROJECT" -f "$LAB_DIR/compose.yml" ps -q
)"
docker stats --no-stream \
  --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.BlockIO}}' \
  $IDS || true

echo
echo "=== 14. ENCERRAMENTO ==="
if docker compose -p "$PROJECT" -f "$LAB_DIR/compose.yml" down --remove-orphans; then
  STARTED=0
  ok "laboratório efêmero removido"
else
  fail "falha ao encerrar laboratório"
fi

RESIDUAL="$(
  docker ps -aq \
    --filter "label=com.docker.compose.project=$PROJECT" \
    2>/dev/null || true
)"

[[ -z "$RESIDUAL" ]] \
  && ok "nenhum container residual da 4H-A" \
  || fail "container residual encontrado"

echo
echo "=== 15. GIT FINAL ==="
cd "$ROOT"
git status -sb

if git diff --check; then
  ok "git diff --check final"
else
  fail "git diff --check final"
fi

echo
echo "======================================================================"
echo " RESULTADO"
echo "======================================================================"
echo "Falhas: $FAIL"

if [[ "$FAIL" -eq 0 ]]; then
  echo "FASE 4H-A: APROVADA."
  echo "Imagem oficial ModSecurity + OWASP CRS validada como reverse proxy WAF."
  echo "Requisição benigna passou; XSS e SQLi sintéticos foram bloqueados."
  echo "Backend permaneceu sem publicação direta."
else
  echo "FASE 4H-A: REPROVADA."
fi

echo "Relatório: $REPORT"
echo "======================================================================"

rm -f "/tmp/conectaeduca-waf-benign-${STAMP}.body" >/dev/null 2>&1 || true

[[ "$FAIL" -eq 0 ]]
