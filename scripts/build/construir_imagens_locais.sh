#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.0.0"
TARGET="all"
PLAN_ONLY=0

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="${PROJECT_ROOT:-$(cd -- "$SCRIPT_DIR/../.." && pwd -P)}"

PASS=0
WARN=0
FAIL=0
INFO=0

usage() {
    cat <<'EOF'
Uso:
  construir_imagens_locais.sh [--alvo dmz|bacula|all] [--plan]

Opções:
  --alvo   conjunto de imagens (padrão: all)
  --plan   mostra a sequência sem executar docker build/tag/run
  -h       ajuda
EOF
}

while (($#)); do
    case "$1" in
        --alvo)
            [[ $# -ge 2 ]] || { usage >&2; exit 64; }
            TARGET="$2"
            shift 2
            ;;
        --plan)
            PLAN_ONLY=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERRO: argumento desconhecido: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

case "$TARGET" in
    dmz|bacula|all) ;;
    *)
        echo "ERRO: alvo inválido: $TARGET" >&2
        exit 64
        ;;
esac

[[ -d "$ROOT/.git" ]] || {
    echo "ERRO: build oficial exige checkout Git do ConectaEduca." >&2
    exit 1
}

for cmd in git sha256sum awk sed sort mktemp; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "ERRO: comando obrigatório ausente: $cmd" >&2
        exit 1
    }
done

cd "$ROOT"

COMMIT="$(git rev-parse HEAD)"
SHORT="$(git rev-parse --short=12 HEAD)"
BRANCH="$(git branch --show-current)"
STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
OUT_DIR="${CONECTAEDUCA_EVIDENCE_DIR:-/var/tmp}"
REPORT="$OUT_DIR/conectaeduca-build-imagens-${TARGET}-${SHORT}-${STAMP}-pid$$.txt"
MANIFEST="$OUT_DIR/conectaeduca-build-imagens-${TARGET}-${SHORT}-${STAMP}-pid$$.tsv"

mkdir -p "$OUT_DIR"
: >"$REPORT"
: >"$MANIFEST"
chmod 0644 "$REPORT" "$MANIFEST"

exec > >(tee -a "$REPORT") 2>&1

pass() { PASS=$((PASS + 1)); echo "[PASS] $*"; }
warn() { WARN=$((WARN + 1)); echo "[WARN] $*"; }
fail() { FAIL=$((FAIL + 1)); echo "[FAIL] $*"; }
info() { INFO=$((INFO + 1)); echo "[INFO] $*"; }

run() {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
    if (( PLAN_ONLY == 0 )); then
        "$@"
    fi
}

finish() {
    local rc=$?
    local final report_sha manifest_sha

    if (( rc != 0 && FAIL == 0 )); then
        FAIL=$((FAIL + 1))
    fi

    if (( FAIL > 0 )); then
        final="FAIL"
    elif (( WARN > 0 )); then
        final="WARN"
    else
        final="PASS"
    fi

    echo
    echo "=== SUMMARY ==="
    echo "PASS=$PASS"
    echo "WARN=$WARN"
    echo "FAIL=$FAIL"
    echo "INFO=$INFO"
    echo "PLAN_ONLY=$PLAN_ONLY"
    echo "FINAL=$final"
    echo "SOURCE_COMMIT=$COMMIT"
    echo "REPORT=$REPORT"
    echo "MANIFEST=$MANIFEST"

    report_sha="$(sha256sum "$REPORT" | awk '{print $1}')"
    manifest_sha="$(sha256sum "$MANIFEST" | awk '{print $1}')"
    echo "REPORT_SHA256=$report_sha"
    echo "MANIFEST_SHA256=$manifest_sha"

    exit "$rc"
}
trap finish EXIT

echo "=== CONECTAEDUCA — BUILD OFICIAL DE IMAGENS LOCAIS ==="
echo "VERSION=$VERSION"
echo "TARGET=$TARGET"
echo "PLAN_ONLY=$PLAN_ONLY"
echo "BRANCH=$BRANCH"
echo "SOURCE_COMMIT=$COMMIT"

git diff --check
pass "git diff --check."

if [[ -n "$(git status --porcelain=v1)" ]]; then
    fail "Working tree não está limpa; build oficial recusado."
    exit 1
fi
pass "Working tree limpa."

if (( PLAN_ONLY == 0 )); then
    command -v docker >/dev/null 2>&1 || {
        fail "Docker ausente."
        exit 1
    }
    docker info >/dev/null 2>&1 || {
        fail "Docker Engine indisponível."
        exit 1
    }
    pass "Docker Engine acessível."
else
    info "Modo plan: Docker não é requerido."
fi

printf 'image\timage_id\trevision\tbuild_policy\tpackage_manifest_sha256\n' >"$MANIFEST"

build_image() {
    local image="$1"
    local dockerfile="$2"
    local target_stage="${3:-}"
    shift 3 || true

    local args=(
        docker build
        --build-arg "CONECTAEDUCA_SOURCE_COMMIT=$COMMIT"
        -f "$dockerfile"
        -t "$image"
    )

    if [[ -n "$target_stage" ]]; then
        args+=(--target "$target_stage")
    fi

    while (($#)); do
        args+=("$1")
        shift
    done

    args+=(.)

    run "${args[@]}"

    if (( PLAN_ONLY == 1 )); then
        return 0
    fi

    local id revision policy alias manifest_tmp manifest_sha
    id="$(docker image inspect "$image" --format '{{.Id}}')"
    revision="$(docker image inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')"
    policy="$(docker image inspect "$image" --format '{{index .Config.Labels "io.conectaeduca.build-policy"}}')"

    [[ "$revision" == "$COMMIT" ]] || {
        fail "$image: label revision diverge do commit."
        return 1
    }

    [[ -n "$policy" && "$policy" != "<no value>" ]] || {
        fail "$image: build-policy ausente."
        return 1
    }

    alias="${image}-git-${SHORT}"
    run docker tag "$image" "$alias"

    manifest_tmp="$(mktemp)"
    if docker run --rm --entrypoint cat "$image" /usr/share/conectaeduca/build-packages.txt         >"$manifest_tmp" 2>/dev/null
    then
        manifest_sha="$(sha256sum "$manifest_tmp" | awk '{print $1}')"
    else
        manifest_sha="BASE_IMAGE_ONLY"
    fi
    rm -f "$manifest_tmp"

    printf '%s\t%s\t%s\t%s\t%s\n'         "$image" "$id" "$revision" "$policy" "$manifest_sha" >>"$MANIFEST"

    pass "$image construída e vinculada ao commit $SHORT."
    echo "IMAGE=$image"
    echo "IMAGE_ID=$id"
    echo "IMMUTABLE_ALIAS=$alias"
    echo "BUILD_POLICY=$policy"
    echo "PACKAGE_MANIFEST_SHA256=$manifest_sha"
}

if [[ "$TARGET" == "dmz" || "$TARGET" == "all" ]]; then
    build_image         "conectaeduca/php-fpm:dmz"         "deploy/dmz/php/Dockerfile"         ""

    build_image         "conectaeduca/nginx:dmz"         "deploy/dmz/nginx/Dockerfile"         ""

    build_image         "conectaeduca/waf:dmz"         "deploy/dmz/waf/Dockerfile"         ""
fi

if [[ "$TARGET" == "bacula" || "$TARGET" == "all" ]]; then
    build_image         "conectaeduca/bacula-director:15.0.3"         "deploy/interna/bacula/images/Dockerfile.vm"         "director"

    build_image         "conectaeduca/bacula-storage:15.0.3"         "deploy/interna/bacula/images/Dockerfile.vm"         "storage"

    if (( PLAN_ONLY == 0 )); then
        DIRECTOR_ID="$(docker image inspect conectaeduca/bacula-director:15.0.3 --format '{{.Id}}')"
    else
        DIRECTOR_ID="PLAN_ONLY"
    fi

    build_image         "conectaeduca/pgbouncer:1.24.1-tls-bridge"         "deploy/interna/bacula/pgbouncer/Dockerfile"         ""         --build-arg "BACULA_BASE_IMAGE=conectaeduca/bacula-director:15.0.3"         --build-arg "PGBOUNCER_UPSTREAM_VERSION=1.24.1"         --label "io.conectaeduca.parent-image-id=$DIRECTOR_ID"

    if (( PLAN_ONLY == 0 )); then
        PARENT_ID="$(docker image inspect             conectaeduca/pgbouncer:1.24.1-tls-bridge             --format '{{index .Config.Labels "io.conectaeduca.parent-image-id"}}')"

        [[ "$PARENT_ID" == "$DIRECTOR_ID" ]] || {
            fail "PgBouncer não registra o image ID do Director usado no build."
            exit 1
        }

        VERSION_OUT="$(docker run --rm --entrypoint pgbouncer             conectaeduca/pgbouncer:1.24.1-tls-bridge --version 2>&1 | head -n1)"
        echo "PGBOUNCER_VERSION_OUTPUT=$VERSION_OUT"
        grep -Eq '(^|[[:space:]])1\.24\.1([[:space:]]|$)' <<<"$VERSION_OUT" || {
            fail "PgBouncer construído não reporta 1.24.1."
            exit 1
        }

        pass "PgBouncer 1.24.1 e parent image ID comprovados."
    fi
fi

if (( PLAN_ONLY == 1 )); then
    pass "Plano de build gerado sem mutação Docker."
else
    pass "Manifesto de proveniência das imagens gerado."
fi
