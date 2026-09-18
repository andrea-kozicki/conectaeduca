#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEFAULT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
ROOT="${PROJECT_ROOT:-$DEFAULT_ROOT}"
COMPOSE="$ROOT/deploy/interna/twingate/compose.yml"
RUNTIME="/dev/shm/conectaeduca-twingate.env"
EXPECTED_DIGEST="sha256:833e7a968f1b3a5ad79b88b04f82aad1bfc8621f61b6b35f01be2411d35beba9"
IMAGE_REF="twingate/connector@$EXPECTED_DIGEST"

fail() {
    echo "FALHA: $*" >&2
    exit 1
}

cd "$ROOT"
echo "=== Twingate readiness ==="
echo "raiz_projeto=$ROOT"

test -f "$COMPOSE" || fail "compose ausente"
grep -Fq "$EXPECTED_DIGEST" "$COMPOSE" || fail "digest inesperado"
grep -Eq '^[[:space:]]*network_mode:[[:space:]]*host[[:space:]]*$' "$COMPOSE" || fail "network_mode host ausente"
grep -Fq 'no-new-privileges:true' "$COMPOSE" || fail "no-new-privileges ausente"

if grep -Eq '^[[:space:]]*(ports|volumes|devices|cap_add|privileged):' "$COMPOSE"; then
    fail "compose contém expansão de superfície não aprovada"
fi

LOCAL_DIGEST="$(docker image inspect "$IMAGE_REF" --format '{{index .RepoDigests 0}}' 2>/dev/null || true)"
[[ "$LOCAL_DIGEST" == "twingate/connector@$EXPECTED_DIGEST" ]] || fail "digest local divergente"

ARCH="$(docker image inspect "$IMAGE_REF" --format '{{.Architecture}}')"
OS_NAME="$(docker image inspect "$IMAGE_REF" --format '{{.Os}}')"
IMAGE_USER="$(docker image inspect "$IMAGE_REF" --format '{{.Config.User}}')"

[[ "$ARCH" == "amd64" ]] || fail "arquitetura inesperada"
[[ "$OS_NAME" == "linux" ]] || fail "SO inesperado"
[[ "$IMAGE_USER" == "nonroot" ]] || fail "usuário default inesperado"

echo "OK image_digest=$EXPECTED_DIGEST"
echo "OK platform=$OS_NAME/$ARCH"
echo "OK image_user=$IMAGE_USER"

if [[ -f "$RUNTIME" ]]; then
    MODE="$(stat -c '%a' "$RUNTIME")"
    [[ "$MODE" == "600" ]] || fail "runtime modo=$MODE"
    echo "OK runtime=presente"
    echo "OK runtime_mode=600"
else
    echo "INFO runtime=ausente"
fi

if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ROOT" diff --check
    echo "SOURCE_INTEGRITY=GIT_DIFF_OK"
elif [[ -f "$ROOT/RELEASE-METADATA.txt" ]] \
     && grep -Eq '^git_commit=[0-9a-f]{40}$' "$ROOT/RELEASE-METADATA.txt"; then
    echo "SOURCE_INTEGRITY=HANDOFF_FREEZE_METADATA_OK"
else
    fail "origem sem Git e sem RELEASE-METADATA válido"
fi
echo "CHECKPOINT_TWINGATE_READINESS=APROVADO"