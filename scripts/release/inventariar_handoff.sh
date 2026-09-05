#!/usr/bin/env bash
set -Eeuo pipefail

DMZ_BUNDLE="${1:-}"
INT_BUNDLE="${2:-}"
OUT="${3:-/dev/stdout}"

[[ -f "$DMZ_BUNDLE" ]] || { echo "ERRO: bundle DMZ ausente" >&2; exit 1; }
[[ -f "$INT_BUNDLE" ]] || { echo "ERRO: bundle interna ausente" >&2; exit 1; }

TMP="$(mktemp -d -t conectaeduca-inventory-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

tar -xzf "$DMZ_BUNDLE" -C "$TMP"
tar -xzf "$INT_BUNDLE" -C "$TMP"

DMZ_ROOT="$(find "$TMP" -maxdepth 1 -type d -name 'conectaeduca-dmz*' | head -n 1)"
INT_ROOT="$(find "$TMP" -maxdepth 1 -type d -name 'conectaeduca-interna*' | head -n 1)"

[[ -d "$DMZ_ROOT" ]] || { echo "ERRO: raiz DMZ não encontrada" >&2; exit 1; }
[[ -d "$INT_ROOT" ]] || { echo "ERRO: raiz interna não encontrada" >&2; exit 1; }

DMZ_IMAGES="$DMZ_ROOT/IMAGES.txt"
INT_IMAGES="$INT_ROOT/IMAGES.txt"

[[ -f "$DMZ_IMAGES" ]] || { echo "ERRO: IMAGES.txt DMZ ausente" >&2; exit 1; }
[[ -f "$INT_IMAGES" ]] || { echo "ERRO: IMAGES.txt interna ausente" >&2; exit 1; }

exec > >(tee "$OUT") 2>&1

ok=0
fail=0

check_image() {
    local zone="$1"
    local role="$2"
    local kind="$3"
    local file="$4"
    local needle="$5"

    local found
    found="$(grep -F "$needle" "$file" | head -n 1 || true)"

    if [[ -n "$found" ]]; then
        echo "[OK] zone=$zone role=$role kind=$kind image=$found"
        ok=$((ok + 1))
    else
        echo "[FALHA] zone=$zone role=$role kind=$kind esperado=$needle"
        fail=$((fail + 1))
    fi
}

check_absent_image() {
    local zone="$1"
    local label="$2"
    local file="$3"
    local needle="$4"

    if grep -Fiq "$needle" "$file"; then
        echo "[FALHA] zone=$zone proibido=$label pattern=$needle"
        fail=$((fail + 1))
    else
        echo "[OK] zone=$zone excluido=$label"
        ok=$((ok + 1))
    fi
}

check_path() {
    local label="$1"
    local path="$2"
    if [[ -e "$path" ]]; then
        echo "[OK] $label path=${path#"$TMP"/}"
        ok=$((ok + 1))
    else
        echo "[FALHA] $label path_ausente=${path#"$TMP"/}"
        fail=$((fail + 1))
    fi
}

echo "============================================================"
echo "CONECTAEDUCA - INVENTARIO COMPLETO DE COMPONENTES DO HANDOFF"
echo "============================================================"
echo "dmz_bundle=$(basename "$DMZ_BUNDLE")"
echo "interna_bundle=$(basename "$INT_BUNDLE")"

echo
echo "=== DMZ / CONTAINERS DE RUNTIME ==="
check_image DMZ php-fpm build "$DMZ_IMAGES" "conectaeduca/php-fpm:dmz"
check_image DMZ nginx build "$DMZ_IMAGES" "conectaeduca/nginx:dmz"
check_image DMZ waf build "$DMZ_IMAGES" "conectaeduca/waf:dmz"

echo
echo "=== REDE INTERNA / CONTAINERS DE RUNTIME ==="
check_image INTERNA mariadb pull "$INT_IMAGES" "mariadb:12.3.2-ubi10"
check_image INTERNA openbao pull "$INT_IMAGES" "openbao/openbao:2.6.1"
check_image INTERNA ferret pull "$INT_IMAGES" "public.ecr.aws/awslabs/ferret-scan:2.4.3"
check_image INTERNA wazuh-manager pull "$INT_IMAGES" "wazuh/wazuh-manager:4.14.7"
check_image INTERNA wazuh-indexer pull "$INT_IMAGES" "wazuh/wazuh-indexer:4.14.7"
check_image INTERNA wazuh-dashboard pull "$INT_IMAGES" "wazuh/wazuh-dashboard:4.14.7"
check_image INTERNA bacula-catalog pull "$INT_IMAGES" "postgres:17-bookworm"
check_image INTERNA bacula-storage build "$INT_IMAGES" "conectaeduca/bacula-storage:15.0.3"
check_image INTERNA bacula-director build "$INT_IMAGES" "conectaeduca/bacula-director:15.0.3"

echo
echo "=== REDE INTERNA / BOOTSTRAP ==="
check_image INTERNA wazuh-cert-generator bootstrap "$INT_IMAGES" "wazuh/wazuh-certs-generator:0.0.4"

echo
echo "=== COMPONENTES NATIVOS NAS VMs ==="
check_path "bacula-fd-dmz-nativo" \
    "$DMZ_ROOT/deploy/dmz/bacula-fd/bacula-fd.conf.example"
check_path "bacula-fd-interna-nativo" \
    "$INT_ROOT/deploy/interna/bacula/fd/bacula-fd.conf.example"
check_path "instalador-bacula-fd-ubuntu-dmz" \
    "$DMZ_ROOT/scripts/implantacao/preparar_bacula_fd_ubuntu.sh"
check_path "instalador-bacula-fd-ubuntu-interna" \
    "$INT_ROOT/scripts/implantacao/preparar_bacula_fd_ubuntu.sh"

echo
echo "=== EXCLUSOES OBRIGATORIAS ==="
check_absent_image DMZ mariadb "$DMZ_IMAGES" "mariadb:"
check_absent_image DMZ bacula-fd-container "$DMZ_IMAGES" "bacula-filedaemon"
check_absent_image INTERNA bacula-fd-container "$INT_IMAGES" "bacula-filedaemon"
check_absent_image DMZ mailpit "$DMZ_IMAGES" "mailpit"
check_absent_image INTERNA mailpit "$INT_IMAGES" "mailpit"
check_absent_image DMZ trivy "$DMZ_IMAGES" "trivy"
check_absent_image INTERNA trivy "$INT_IMAGES" "trivy"
check_absent_image DMZ twingate "$DMZ_IMAGES" "twingate"
check_absent_image INTERNA twingate "$INT_IMAGES" "twingate"

if find "$DMZ_ROOT" "$INT_ROOT" -type f -path '*/deploy/lab/*' | grep -q .; then
    echo "[FALHA] deploy/lab presente em handoff"
    fail=$((fail + 1))
else
    echo "[OK] deploy/lab excluido"
    ok=$((ok + 1))
fi

echo
echo "=== REFERENCIAS DE IMAGEM - DMZ ==="
cat "$DMZ_IMAGES"

echo
echo "=== REFERENCIAS DE IMAGEM - INTERNA ==="
cat "$INT_IMAGES"

echo
echo "=== IMAGENS LOCAIS / EVIDENCIA AUXILIAR ==="
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    while IFS= read -r img; do
        [[ -z "$img" || "$img" == \#* ]] && continue
        if docker image inspect "$img" >/dev/null 2>&1; then
            iid="$(docker image inspect "$img" --format '{{.Id}}' 2>/dev/null || true)"
            dig="$(docker image inspect "$img" --format '{{join .RepoDigests ","}}' 2>/dev/null || true)"
            echo "LOCAL_IMAGE=SIM ref=$img id=$iid digests=${dig:-SEM_REPODIGEST}"
        else
            echo "LOCAL_IMAGE=NAO ref=$img"
        fi
    done < <(cat "$DMZ_IMAGES" "$INT_IMAGES" | grep -v '^#' | sort -u)
else
    echo "DOCKER_LOCAL=INDISPONIVEL"
fi

echo
echo "=== RESUMO ==="
echo "CHECKS_OK=$ok"
echo "CHECKS_FALHA=$fail"
echo "RUNTIME_CONTAINERS_DMZ_ESPERADOS=3"
echo "RUNTIME_CONTAINERS_INTERNA_ESPERADOS=9"
echo "BOOTSTRAP_IMAGES_ESPERADAS=1"
echo "BACULA_FD_NATIVOS_ESPERADOS=2"

if [[ "$fail" -ne 0 ]]; then
    echo "INVENTARIO_FINAL=REPROVADO"
    exit 1
fi

echo "INVENTARIO_FINAL=APROVADO"
