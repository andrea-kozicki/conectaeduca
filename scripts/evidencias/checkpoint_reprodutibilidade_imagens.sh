#!/usr/bin/env bash
set -u
export LC_ALL=C
export LANG=C

ROOT="${PROJECT_ROOT:-/srv/www/htdocs/conectaeduca}"
TARGET_PLATFORM="${TARGET_PLATFORM:-linux/amd64}"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="/tmp/conectaeduca-checkpoint-reprodutibilidade-${STAMP}.txt"

FAIL=0
WARN=0
TMP_IMAGES=()
PIN_FILE="/tmp/conectaeduca-pinned-refs.$$"

ok(){ echo "OK       $*"; }
fail(){ echo "FALHA    $*"; FAIL=$((FAIL+1)); }
warn(){ echo "ATENÇÃO  $*"; WARN=$((WARN+1)); }
info(){ echo "INFO     $*"; }

cleanup() {
  set +e
  for image in "${TMP_IMAGES[@]}"; do
    docker image rm -f "$image" >/dev/null 2>&1 || true
  done
  rm -f "$PIN_FILE"
}
trap cleanup EXIT INT TERM

exec > >(tee "$REPORT") 2>&1

echo "======================================================================"
echo " CONECTAEDUCA - CHECKPOINT DE REPRODUTIBILIDADE DAS IMAGENS"
echo " Plataforma alvo: $TARGET_PLATFORM"
echo " Data: $(date --iso-8601=seconds)"
echo "======================================================================"

cd "$ROOT" || exit 1

echo
echo "=== 1. GIT / DOCKER ==="
git status -sb

BRANCH="$(git branch --show-current 2>/dev/null || true)"
[[ "$BRANCH" == "feature/auth-local" ]] \
  && ok "branch feature/auth-local confirmada" \
  || fail "branch deve ser feature/auth-local"

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
echo "=== 2. REFERÊNCIAS FIXADAS ==="

python3 - <<'PY' > "$PIN_FILE"
from pathlib import Path
import re

targets = [
    ("nginx", "deploy/dmz/nginx/Dockerfile", r"FROM\s+(nginx:stable-alpine@sha256:[0-9a-f]{64})"),
    ("php", "deploy/dmz/php/Dockerfile", r"FROM\s+(php:8\.5-fpm-bookworm@sha256:[0-9a-f]{64})"),
    ("composer", "deploy/dmz/php/Dockerfile", r"FROM\s+(composer:2@sha256:[0-9a-f]{64})"),
    ("waf", "deploy/dmz/compose.waf.yml", r"image:\s*[\"']?(owasp/modsecurity-crs:4\.25\.1-nginx-lts@sha256:[0-9a-f]{64})"),
    ("mariadb", "deploy/interna/mariadb/compose.yml", r"image:\s*[\"']?(mariadb:12\.3\.2-ubi10@sha256:[0-9a-f]{64})"),
]

for label, path, pattern in targets:
    text = Path(path).read_text(encoding="utf-8")
    m = re.search(pattern, text)
    print(f"{label}|{m.group(1) if m else 'MISSING'}")
PY

cat "$PIN_FILE"

while IFS='|' read -r label ref; do
  if [[ "$ref" == "MISSING" || ! "$ref" =~ @sha256:[0-9a-f]{64}$ ]]; then
    fail "$label não está fixada por digest"
  else
    ok "$label possui referência canônica com digest"
  fi
done < "$PIN_FILE"

[[ -f deploy/IMAGENS-VALIDADAS.md ]] \
  && ok "inventário de imagens validadas presente" \
  || fail "deploy/IMAGENS-VALIDADAS.md ausente"

echo
echo "=== 3. REGISTRY / PLATAFORMA DO DIGEST ==="
while IFS='|' read -r label ref; do
  [[ "$ref" == "MISSING" ]] && continue

  if docker buildx imagetools inspect "$ref" >/dev/null 2>&1; then
    ok "$label: digest ainda resolvível no registry"
  else
    fail "$label: digest não pôde ser resolvido no registry"
    continue
  fi

  if docker pull --platform "$TARGET_PLATFORM" "$ref" >/dev/null 2>&1; then
    ok "$label: pull exato funciona para $TARGET_PLATFORM"
  else
    fail "$label: pull exato falhou para $TARGET_PLATFORM"
  fi
done < "$PIN_FILE"

echo
echo "=== 4. BUILD SEM CACHE ==="
NGINX_TEST="conectaeduca/nginx:repro-${STAMP}"
PHP_TEST="conectaeduca/php-fpm:repro-${STAMP}"
TMP_IMAGES+=("$NGINX_TEST" "$PHP_TEST")

if docker build \
  --no-cache \
  --platform "$TARGET_PLATFORM" \
  -f deploy/dmz/nginx/Dockerfile \
  -t "$NGINX_TEST" \
  .; then
  ok "Nginx reconstrói sem cache usando base fixada"
else
  fail "build Nginx sem cache falhou"
fi

if docker build \
  --no-cache \
  --platform "$TARGET_PLATFORM" \
  -f deploy/dmz/php/Dockerfile \
  -t "$PHP_TEST" \
  .; then
  ok "PHP-FPM reconstrói sem cache usando PHP/Composer fixados"
else
  fail "build PHP-FPM sem cache falhou"
fi

echo
echo "=== 5. INSPEÇÃO DAS IMAGENS CONSTRUÍDAS ==="
for image in "$NGINX_TEST" "$PHP_TEST"; do
  if docker image inspect "$image" >/dev/null 2>&1; then
    size="$(docker image inspect "$image" --format '{{.Size}}' 2>/dev/null || true)"
    arch="$(docker image inspect "$image" --format '{{.Architecture}}' 2>/dev/null || true)"
    os="$(docker image inspect "$image" --format '{{.Os}}' 2>/dev/null || true)"
    echo "$image os=$os arch=$arch size_bytes=$size"

    [[ "$os/$arch" == "$TARGET_PLATFORM" ]] \
      && ok "$image corresponde à plataforma alvo" \
      || fail "$image diverge da plataforma alvo"
  else
    fail "$image não existe após build"
  fi
done

echo
echo "=== 6. REGRESSÃO DE PORTABILIDADE / INTEGRAÇÃO ==="
PORT_REPORT="/tmp/conectaeduca-portabilidade-aninhada-${STAMP}.txt"

if bash scripts/evidencias/checkpoint_portabilidade_containers.sh \
    > "$PORT_REPORT" 2>&1; then
  ok "checkpoint completo de portabilidade continua aprovado"
else
  fail "checkpoint completo de portabilidade reprovou após pinagem"
fi

echo "--- resumo do checkpoint de portabilidade ---"
grep -E \
  '^(Falhas:|Advertências:|CHECKPOINT DE PORTABILIDADE|OK       .*fixada por digest|ATENÇÃO  .*digest)' \
  "$PORT_REPORT" 2>/dev/null || true

echo
echo "=== 7. OBSERVAÇÃO SOBRE REPRODUTIBILIDADE TOTAL ==="
if grep -Eq 'apt-get[[:space:]]+update|apt-get[[:space:]]+install' deploy/dmz/php/Dockerfile; then
  warn "Dockerfile PHP ainda consulta repositórios Debian durante o build"
  info "digest fixa a base, mas pacotes apt podem variar no futuro"
  info "handoff final poderá exportar as imagens finais validadas para evitar rebuild na VM"
else
  ok "Dockerfile PHP não possui dependências apt dinâmicas"
fi

[[ -f composer.lock ]] \
  && ok "composer.lock presente para dependências PHP" \
  || fail "composer.lock ausente"

echo
echo "=== 8. GIT FINAL ==="
git status -sb
git diff --check \
  && ok "git diff --check final" \
  || fail "git diff --check final"

echo
echo "======================================================================"
echo " RESULTADO"
echo "======================================================================"
echo "Falhas: $FAIL"
echo "Advertências: $WARN"

if [[ "$FAIL" -eq 0 ]]; then
  echo "CHECKPOINT DE REPRODUTIBILIDADE: APROVADO."
  echo "As cinco imagens/base images estão fixadas por digest e resolvem em $TARGET_PLATFORM."
  echo "Nginx e PHP-FPM reconstruíram sem cache e a regressão de portabilidade passou."
  echo "A advertência apt, se presente, será tratada no handoff final das imagens construídas."
else
  echo "CHECKPOINT DE REPRODUTIBILIDADE: REPROVADO."
fi

echo "Relatório: $REPORT"
echo "Relatório de portabilidade aninhado: $PORT_REPORT"
echo "======================================================================"

[[ "$FAIL" -eq 0 ]]
