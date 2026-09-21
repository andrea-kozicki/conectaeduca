#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEFAULT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
ROOT="${PROJECT_ROOT:-$DEFAULT_ROOT}"
RUNTIME="/dev/shm/conectaeduca-twingate.env"
CONTAINER="conectaeduca-twingate-connector"
EXPECTED_DIGEST="sha256:833e7a968f1b3a5ad79b88b04f82aad1bfc8621f61b6b35f01be2411d35beba9"
IMAGE_REF="twingate/connector@$EXPECTED_DIGEST"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HOME/Downloads/conectaeduca-checkpoint-twingate-operacional-$STAMP.txt"

mkdir -p "$HOME/Downloads"
exec > >(tee "$OUT") 2>&1

fail() {
    echo "FALHA: $*" >&2
    echo "CHECKPOINT_TWINGATE_OPERACIONAL=REPROVADO"
    echo "ARQUIVO_SAIDA=$OUT"
    exit 1
}

cd "$ROOT"

echo "=== Twingate operacional ==="
echo "data=$(date --iso-8601=seconds)"
echo "raiz_projeto=$ROOT"
ROOT_REAL="$(cd -- "$ROOT" && pwd -P)"
GIT_TOP=""
GIT_TOP_REAL=""
if command -v git >/dev/null 2>&1; then
    GIT_TOP="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$GIT_TOP" ]]; then
        GIT_TOP_REAL="$(cd -- "$GIT_TOP" && pwd -P)" || GIT_TOP_REAL=""
    fi
fi

SOURCE_MODE=""
if [[ -n "$GIT_TOP_REAL" && "$GIT_TOP_REAL" == "$ROOT_REAL" ]]; then
    SOURCE_MODE="git"
    echo "source=git"
    echo "branch=$(git -C "$ROOT" branch --show-current)"
    echo "head=$(git -C "$ROOT" rev-parse HEAD)"
elif [[ -f "$ROOT/RELEASE-METADATA.txt" ]] && grep -Eq '^git_commit=[0-9a-f]{40}

test -f "$RUNTIME" || fail "runtime efêmero ausente"
[[ "$(stat -c '%a' "$RUNTIME")" == "600" ]] || fail "runtime não está em 600"
echo "OK runtime=presente"
echo "OK runtime_mode=600"
echo "SEGREDOS_EXIBIDOS=NAO"

STATUS="$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || true)"
RESTARTING="$(docker inspect -f '{{.State.Restarting}}' "$CONTAINER" 2>/dev/null || true)"
[[ "$STATUS" == "running" ]] || fail "container status=$STATUS"
[[ "$RESTARTING" == "false" ]] || fail "container restarting=$RESTARTING"
echo "OK container_status=running"

LOCAL_DIGEST="$(docker image inspect "$IMAGE_REF" --format '{{index .RepoDigests 0}}' 2>/dev/null || true)"
[[ "$LOCAL_DIGEST" == "$IMAGE_REF" ]] || fail "digest local divergente"
LOCAL_IMAGE_ID="$(docker image inspect "$IMAGE_REF" --format '{{.Id}}' 2>/dev/null || true)"
CONTAINER_IMAGE_ID="$(docker inspect -f '{{.Image}}' "$CONTAINER" 2>/dev/null || true)"
[[ -n "$LOCAL_IMAGE_ID" && "$CONTAINER_IMAGE_ID" == "$LOCAL_IMAGE_ID" ]] \
    || fail "container não usa a imagem validada por digest"
echo "OK image_digest=$EXPECTED_DIGEST"

[[ "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$CONTAINER")" == "host" ]] || fail "network mode inesperado"
[[ "$(docker inspect -f '{{.HostConfig.Privileged}}' "$CONTAINER")" == "false" ]] || fail "container privilegiado"
[[ "$(docker inspect -f '{{.Config.User}}' "$CONTAINER")" == "nonroot" ]] || fail "usuário inesperado"

SECOPT="$(docker inspect -f '{{json .HostConfig.SecurityOpt}}' "$CONTAINER")"
grep -Fq 'no-new-privileges:true' <<<"$SECOPT" || fail "no-new-privileges ausente"

[[ -z "$(docker port "$CONTAINER" 2>/dev/null || true)" ]] || fail "porta publicada"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
chmod 600 "$TMP"
docker logs --tail 250 "$CONTAINER" >"$TMP" 2>&1 || true

if grep -Eqi 'Invalid token|failed to get an access token|Gone, code 410|authentication failed' "$TMP"; then
    fail "logs indicam falha de autenticação; detalhes omitidos"
fi

echo "OK auth_error_patterns=ausentes"
if [[ "$SOURCE_MODE" == "git" ]]; then
    git -C "$ROOT" diff --check
    echo "SOURCE_INTEGRITY=GIT_DIFF_OK"
else
    if [[ -f "$ROOT/RELEASE-METADATA.txt" ]] && grep -Eq '^git_commit=[0-9a-f]{40}

echo "CHECKPOINT_TWINGATE_OPERACIONAL=APROVADO_LOCALMENTE"
echo "ADMIN_CONSOLE_STATUS=VERIFICACAO_MANUAL_PENDENTE"
echo "RESOURCE_CRIADO=NAO"
echo "TOKENS_PERSISTIDOS_NO_GIT=NAO"
echo "SEGREDOS_EXIBIDOS=NAO"
echo "ARQUIVO_SAIDA=$OUT" "$ROOT/RELEASE-METADATA.txt"; then
    SOURCE_MODE="handoff"
    echo "source=handoff"
    echo "head=$(sed -n 's/^git_commit=//p' "$ROOT/RELEASE-METADATA.txt")"
else
    fail "origem sem Git e sem RELEASE-METADATA válido"
fi

test -f "$RUNTIME" || fail "runtime efêmero ausente"
[[ "$(stat -c '%a' "$RUNTIME")" == "600" ]] || fail "runtime não está em 600"
echo "OK runtime=presente"
echo "OK runtime_mode=600"
echo "SEGREDOS_EXIBIDOS=NAO"

STATUS="$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || true)"
RESTARTING="$(docker inspect -f '{{.State.Restarting}}' "$CONTAINER" 2>/dev/null || true)"
[[ "$STATUS" == "running" ]] || fail "container status=$STATUS"
[[ "$RESTARTING" == "false" ]] || fail "container restarting=$RESTARTING"
echo "OK container_status=running"

LOCAL_DIGEST="$(docker image inspect "$IMAGE_REF" --format '{{index .RepoDigests 0}}' 2>/dev/null || true)"
[[ "$LOCAL_DIGEST" == "$IMAGE_REF" ]] || fail "digest local divergente"
LOCAL_IMAGE_ID="$(docker image inspect "$IMAGE_REF" --format '{{.Id}}' 2>/dev/null || true)"
CONTAINER_IMAGE_ID="$(docker inspect -f '{{.Image}}' "$CONTAINER" 2>/dev/null || true)"
[[ -n "$LOCAL_IMAGE_ID" && "$CONTAINER_IMAGE_ID" == "$LOCAL_IMAGE_ID" ]] \
    || fail "container não usa a imagem validada por digest"
echo "OK image_digest=$EXPECTED_DIGEST"

[[ "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$CONTAINER")" == "host" ]] || fail "network mode inesperado"
[[ "$(docker inspect -f '{{.HostConfig.Privileged}}' "$CONTAINER")" == "false" ]] || fail "container privilegiado"
[[ "$(docker inspect -f '{{.Config.User}}' "$CONTAINER")" == "nonroot" ]] || fail "usuário inesperado"

SECOPT="$(docker inspect -f '{{json .HostConfig.SecurityOpt}}' "$CONTAINER")"
grep -Fq 'no-new-privileges:true' <<<"$SECOPT" || fail "no-new-privileges ausente"

[[ -z "$(docker port "$CONTAINER" 2>/dev/null || true)" ]] || fail "porta publicada"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
chmod 600 "$TMP"
docker logs --tail 250 "$CONTAINER" >"$TMP" 2>&1 || true

if grep -Eqi 'Invalid token|failed to get an access token|Gone, code 410|authentication failed' "$TMP"; then
    fail "logs indicam falha de autenticação; detalhes omitidos"
fi

echo "OK auth_error_patterns=ausentes"
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ROOT" diff --check
    echo "SOURCE_INTEGRITY=GIT_DIFF_OK"
else
    echo "SOURCE_INTEGRITY=HANDOFF_FREEZE_METADATA_OK"
fi

echo "CHECKPOINT_TWINGATE_OPERACIONAL=APROVADO_LOCALMENTE"
echo "ADMIN_CONSOLE_STATUS=VERIFICACAO_MANUAL_PENDENTE"
echo "RESOURCE_CRIADO=NAO"
echo "TOKENS_PERSISTIDOS_NO_GIT=NAO"
echo "SEGREDOS_EXIBIDOS=NAO"
echo "ARQUIVO_SAIDA=$OUT" "$ROOT/RELEASE-METADATA.txt"; then
        echo "SOURCE_INTEGRITY=HANDOFF_FREEZE_METADATA_OK"
    else
        fail "metadata handoff inválida no gate final"
    fi
fi

echo "CHECKPOINT_TWINGATE_OPERACIONAL=APROVADO_LOCALMENTE"
echo "ADMIN_CONSOLE_STATUS=VERIFICACAO_MANUAL_PENDENTE"
echo "RESOURCE_CRIADO=NAO"
echo "TOKENS_PERSISTIDOS_NO_GIT=NAO"
echo "SEGREDOS_EXIBIDOS=NAO"
echo "ARQUIVO_SAIDA=$OUT" "$ROOT/RELEASE-METADATA.txt"; then
    SOURCE_MODE="handoff"
    echo "source=handoff"
    echo "head=$(sed -n 's/^git_commit=//p' "$ROOT/RELEASE-METADATA.txt")"
else
    fail "origem sem Git e sem RELEASE-METADATA válido"
fi

test -f "$RUNTIME" || fail "runtime efêmero ausente"
[[ "$(stat -c '%a' "$RUNTIME")" == "600" ]] || fail "runtime não está em 600"
echo "OK runtime=presente"
echo "OK runtime_mode=600"
echo "SEGREDOS_EXIBIDOS=NAO"

STATUS="$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || true)"
RESTARTING="$(docker inspect -f '{{.State.Restarting}}' "$CONTAINER" 2>/dev/null || true)"
[[ "$STATUS" == "running" ]] || fail "container status=$STATUS"
[[ "$RESTARTING" == "false" ]] || fail "container restarting=$RESTARTING"
echo "OK container_status=running"

LOCAL_DIGEST="$(docker image inspect "$IMAGE_REF" --format '{{index .RepoDigests 0}}' 2>/dev/null || true)"
[[ "$LOCAL_DIGEST" == "$IMAGE_REF" ]] || fail "digest local divergente"
LOCAL_IMAGE_ID="$(docker image inspect "$IMAGE_REF" --format '{{.Id}}' 2>/dev/null || true)"
CONTAINER_IMAGE_ID="$(docker inspect -f '{{.Image}}' "$CONTAINER" 2>/dev/null || true)"
[[ -n "$LOCAL_IMAGE_ID" && "$CONTAINER_IMAGE_ID" == "$LOCAL_IMAGE_ID" ]] \
    || fail "container não usa a imagem validada por digest"
echo "OK image_digest=$EXPECTED_DIGEST"

[[ "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$CONTAINER")" == "host" ]] || fail "network mode inesperado"
[[ "$(docker inspect -f '{{.HostConfig.Privileged}}' "$CONTAINER")" == "false" ]] || fail "container privilegiado"
[[ "$(docker inspect -f '{{.Config.User}}' "$CONTAINER")" == "nonroot" ]] || fail "usuário inesperado"

SECOPT="$(docker inspect -f '{{json .HostConfig.SecurityOpt}}' "$CONTAINER")"
grep -Fq 'no-new-privileges:true' <<<"$SECOPT" || fail "no-new-privileges ausente"

[[ -z "$(docker port "$CONTAINER" 2>/dev/null || true)" ]] || fail "porta publicada"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
chmod 600 "$TMP"
docker logs --tail 250 "$CONTAINER" >"$TMP" 2>&1 || true

if grep -Eqi 'Invalid token|failed to get an access token|Gone, code 410|authentication failed' "$TMP"; then
    fail "logs indicam falha de autenticação; detalhes omitidos"
fi

echo "OK auth_error_patterns=ausentes"
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ROOT" diff --check
    echo "SOURCE_INTEGRITY=GIT_DIFF_OK"
else
    echo "SOURCE_INTEGRITY=HANDOFF_FREEZE_METADATA_OK"
fi

echo "CHECKPOINT_TWINGATE_OPERACIONAL=APROVADO_LOCALMENTE"
echo "ADMIN_CONSOLE_STATUS=VERIFICACAO_MANUAL_PENDENTE"
echo "RESOURCE_CRIADO=NAO"
echo "TOKENS_PERSISTIDOS_NO_GIT=NAO"
echo "SEGREDOS_EXIBIDOS=NAO"
echo "ARQUIVO_SAIDA=$OUT"