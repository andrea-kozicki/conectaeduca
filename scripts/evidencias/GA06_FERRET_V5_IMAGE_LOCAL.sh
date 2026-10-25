#!/usr/bin/env bash
# GA-06 Ferret v5: local build + smoke only; no VMs, no push, no deploy.
set -Eeuo pipefail
umask 077

[[ "$(id -u)" -ne 0 && "$(hostname -s)" == "opensuse-andrea" ]] || { echo "Host inadequado"; exit 2; }
[[ "$(uname -m)" == "x86_64" ]] || { echo "Exige linux/amd64"; exit 2; }
for prog in git curl sha256sum awk podman python3 install; do
  command -v "$prog" >/dev/null || { echo "Falta $prog"; exit 2; }
done
podman info --format '{{.Host.Security.Rootless}}' | grep -Fxq true || { echo "Podman nao rootless"; exit 2; }

SRC="\${GA06_V5_SRC:-$HOME/GA06-Ferret-v5-jOvXM4fP/ferret-scan}"
PATCH="\${GA06_V5_PATCH:-$HOME/GA06-Ferret-v5-jOvXM4fP/ferret_pa07_v5_on_v4.patch}"
CACHE="\${GA06_GO_CACHE:-$HOME/GA06-Ferret-v4-KLgjXjKo/build-local/cache}"
COMMIT=a5156d1950df19276e6cfd8335603d73187a3841
PATCH_BLOB=4036355c9d9ac0f4dc4f942689a0c14db6d39089
DOCKERFILE_BLOB=aa9af3771b95cebbdec56fb6dd7deda0a0225aee
VERSION=2.4.3+ce.pa07.v5
IMAGE=localhost/conectaeduca/ferret-scan:2.4.3-pa07-v5-candidate

[[ -d "$SRC/.git" && -f "$PATCH" && -f "$SRC/LICENSE.txt" ]] || { echo "Fonte, patch ou LICENSE ausentes"; exit 2; }
[[ "$(git -C "$SRC" rev-parse HEAD)" == "$COMMIT" ]] || { echo "Upstream divergente"; exit 2; }
[[ "$(git hash-object "$PATCH")" == "$PATCH_BLOB" ]] || { echo "Delta v5 divergente"; exit 2; }
git -C "$SRC" apply -R --check "$PATCH" || { echo "Patch v5 nao aplicado na fonte"; exit 2; }
git -C "$SRC" diff --check || exit 2
[[ "$(git -C "$SRC" diff --name-only)" == "internal/web/assets/app.js" ]] || { echo "Mudanca inesperada no checkout"; exit 2; }
grep -Fq 'function renderScanCoverageStatus(verdict)' "$SRC/internal/web/assets/app.js" || { echo "UI v5 ausente"; exit 2; }
mkdir -p "$CACHE"

WORK="$(mktemp -d "$HOME/GA06-Ferret-v5-image-XXXXXXXX")"
CTX="$WORK/context"
mkdir -p "$CTX/etc" "$CTX/tmp" "$CTX/home/ferret/tmp" "$CTX/home/ferret/.ferret-scan" "$CTX/licenses"
CID=""
cleanup() { [[ -z "$CID" ]] || podman rm -f "$CID" >/dev/null 2>&1 || true; }
trap cleanup EXIT
echo "WORK=$WORK"

echo "ETAPA=1_PREPARAR_CONTEXT_SCRATCH"
curl --proto '=https' --tlsv1.2 -fLsS --retry 2 \
  'https://raw.githubusercontent.com/andrea-kozicki/conectaeduca/fix/pa07-ferret-ui-fail-closed-review-20261025/deploy/interna/ferret/pa07-v5/Containerfile' \
  -o "$WORK/Containerfile"
[[ "$(git hash-object "$WORK/Containerfile")" == "$DOCKERFILE_BLOB" ]] || { echo "Containerfile divergente"; exit 2; }
printf 'ferret:x:1000:1000:ferret:/home/ferret:/bin/sh\n' > "$CTX/etc/passwd"
printf 'ferret:x:1000:\n' > "$CTX/etc/group"
touch "$CTX/tmp/.keep" "$CTX/home/ferret/tmp/.keep" "$CTX/home/ferret/.ferret-scan/.keep"
chmod 1777 "$CTX/tmp"
chmod 0700 "$CTX/home/ferret/tmp" "$CTX/home/ferret/.ferret-scan"
install -m 0644 "$SRC/LICENSE.txt" "$CTX/licenses/LICENSE.txt"

echo "ETAPA=2_COMPILAR_BINARIO_AUDITAVEL"
podman run --rm --pull=never \
  -v "$SRC:/src:ro" -v "$CTX:/out:rw" -v "$CACHE:/cache:rw" \
  -w /src -e HOME=/cache -e GOCACHE=/cache/build \
  -e GOPATH=/cache/go -e GOMODCACHE=/cache/go/pkg/mod \
  -e GOTOOLCHAIN=local -e CGO_ENABLED=0 -e GOFLAGS=-mod=readonly -e GOMAXPROCS=2 \
  docker.io/library/golang:1.26-bookworm \
  sh -ec 'go version; go build -p 2 -trimpath -buildvcs=false -ldflags="-s -w -X github.com/awslabs/ferret-scan/v2/internal/version.Version=2.4.3+ce.pa07.v5 -X github.com/awslabs/ferret-scan/v2/internal/version.GitCommit=a5156d1950df19276e6cfd8335603d73187a3841+ce.pa07.v5 -X github.com/awslabs/ferret-scan/v2/internal/version.BuildDate=2026-10-25T00:00:00Z" -o /out/ferret-scan ./cmd' \
  > "$WORK/GO_BUILD.log" 2>&1 || { tail -n 35 "$WORK/GO_BUILD.log" >&2; exit 1; }
[[ -s "$CTX/ferret-scan" ]] || { echo "Binario nao gerado"; exit 1; }
chmod 0555 "$CTX/ferret-scan"

echo "ETAPA=3_IMAGEM_LOCAL_SCRATCH"
podman build --pull=never -f "$WORK/Containerfile" -t "$IMAGE" "$WORK" \
  > "$WORK/IMAGE_BUILD.log" 2>&1 || { tail -n 40 "$WORK/IMAGE_BUILD.log" >&2; exit 1; }
IMAGE_ID="$(podman image inspect "$IMAGE" --format '{{.Id}}')"
IMAGE_USER="$(podman image inspect "$IMAGE" --format '{{.Config.User}}')"
[[ "$IMAGE_USER" == "1000:1000" ]] || { echo "Usuario imagem incorreto: $IMAGE_USER"; exit 1; }

echo "ETAPA=4_SMOKE_ISOLADO_EM_LOOPBACK"
CID="$(podman run -d --rm \
  --read-only --cap-drop=ALL --security-opt=no-new-privileges \
  --tmpfs /home/ferret/tmp:rw,nosuid,nodev,noexec,size=256m,uid=1000,gid=1000,mode=0700 \
  -p 127.0.0.1::8080 "$IMAGE" --web --port 8080)" || { echo "Podman smoke falhou"; exit 1; }
PORT="$(podman port "$CID" 8080/tcp | awk -F: 'NR==1 {print $NF}')"
[[ "$PORT" =~ ^[0-9]+$ ]] || { echo "Porta smoke invalida"; exit 1; }
for i in $(seq 1 20); do
  curl -fsS --max-time 3 "http://127.0.0.1:\${PORT}/health" -o "$WORK/HEALTH.json" 2>/dev/null && break
  sleep 1
done
[[ -s "$WORK/HEALTH.json" ]] || { echo "Health nao respondeu"; podman logs "$CID" >&2 || true; exit 1; }
python3 - "$WORK/HEALTH.json" "$VERSION" <<'PY'
import json,sys
data=json.load(open(sys.argv[1],encoding='utf-8'))
assert data.get('status')=='healthy'
assert data.get('service')=='ferret-scan-web'
assert data.get('version')==sys.argv[2]
assert 'ce.pa07.v5' in data.get('build_info',{}).get('commit','')
print('HEALTH_SMOKE=PASS')
PY
curl -fsS --max-time 10 "http://127.0.0.1:\${PORT}/app.js" -o "$WORK/APP_JS_SERVIDO.js"
grep -Fq 'function renderScanCoverageStatus(verdict)' "$WORK/APP_JS_SERVIDO.js" || { echo "UI v5 ausente"; exit 1; }
grep -Fq 'Export blocked: scan coverage is incomplete' "$WORK/APP_JS_SERVIDO.js" || { echo "Export guard ausente"; exit 1; }
cleanup
CID=""

echo "ETAPA=5_ARCHIVE_LOCAL_SEM_TRANSFERENCIA"
ARCHIVE="$WORK/ferret-pa07-v5-candidate-docker-archive.tar"
podman save --format docker-archive -o "$ARCHIVE" "$IMAGE"
{
  echo "=== CONECTAEDUCA GA06 | CANDIDATO LOCAL ==="
  echo "HOST=$(hostname -s)"
  echo "UPSTREAM_COMMIT=$COMMIT"
  echo "PATCH_V5_SHA1=$PATCH_BLOB"
  echo "APP_JS_SHA256=$(sha256sum "$SRC/internal/web/assets/app.js" | awk '{print $1}')"
  echo "BINARIO_SHA256=$(sha256sum "$CTX/ferret-scan" | awk '{print $1}')"
  echo "IMAGEM_TAG=$IMAGE"
  echo "IMAGEM_ID=$IMAGE_ID"
  echo "IMAGEM_USUARIO=$IMAGE_USER"
  echo "ARQUIVO_TAR=$ARCHIVE"
  echo "ARQUIVO_TAR_SHA256=$(sha256sum "$ARCHIVE" | awk '{print $1}')"
  echo "HEALTH_SMOKE=PASS"
  echo "APP_JS_V5_SERVIDO=PASS"
  echo "FERRET_EXPECTED_VERSION_PARA_OPERACAO=$VERSION"
  echo "EP126_ALTERADA=NAO"
  echo "IMAGEM_PUBLICADA=NAO"
  echo "STATUS=PRONTO_PARA_REVISAO_CHANGE_CONTROL"
} | tee "$WORK/GA06_IMAGEM_RESULTADO.txt"
echo "IMPORTANTE: nao envie nem implante o archive na VM sem autorizacao."
