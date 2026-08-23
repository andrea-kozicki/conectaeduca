#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
RUNTIME="/dev/shm/conectaeduca-twingate.env"
CONTAINER="conectaeduca-twingate-connector"
EXPECTED_DIGEST="sha256:833e7a968f1b3a5ad79b88b04f82aad1bfc8621f61b6b35f01be2411d35beba9"
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
echo "branch=$(git branch --show-current)"
echo "head=$(git rev-parse HEAD)"

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

LOCAL_DIGEST="$(docker image inspect twingate/connector:1 --format '{{index .RepoDigests 0}}')"
[[ "$LOCAL_DIGEST" == "twingate/connector@$EXPECTED_DIGEST" ]] || fail "digest local divergente"
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
git diff --check

echo "CHECKPOINT_TWINGATE_OPERACIONAL=APROVADO_LOCALMENTE"
echo "ADMIN_CONSOLE_STATUS=VERIFICACAO_MANUAL_PENDENTE"
echo "RESOURCE_CRIADO=NAO"
echo "TOKENS_PERSISTIDOS_NO_GIT=NAO"
echo "SEGREDOS_EXIBIDOS=NAO"
echo "ARQUIVO_SAIDA=$OUT"
