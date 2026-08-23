#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
COMPOSE="$ROOT/deploy/interna/twingate/compose.yml"
RUNTIME="/dev/shm/conectaeduca-twingate.env"
EXPECTED_DIGEST="sha256:833e7a968f1b3a5ad79b88b04f82aad1bfc8621f61b6b35f01be2411d35beba9"

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

LOCAL_DIGEST="$(docker image inspect twingate/connector:1 --format '{{index .RepoDigests 0}}' 2>/dev/null || true)"
[[ "$LOCAL_DIGEST" == "twingate/connector@$EXPECTED_DIGEST" ]] || fail "digest local divergente"

ARCH="$(docker image inspect twingate/connector:1 --format '{{.Architecture}}')"
OS_NAME="$(docker image inspect twingate/connector:1 --format '{{.Os}}')"
IMAGE_USER="$(docker image inspect twingate/connector:1 --format '{{.Config.User}}')"

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

git diff --check
echo "CHECKPOINT_TWINGATE_READINESS=APROVADO"
