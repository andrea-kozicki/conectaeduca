#!/usr/bin/env bash
# GA-06 Ferret v5: retomar APENAS smoke e export local; nao recompila.
set -Eeuo pipefail
umask 077
[[ "$(id -u)" -ne 0 && "$(hostname -s)" == "opensuse-andrea" ]] || { echo "ERRO: somente usuario comum no openSUSE pessoal"; exit 2; }
for c in podman curl python3 sha256sum grep awk; do command -v "$c" >/dev/null || exit 2; done
podman info --format '{{.Host.Security.Rootless}}' | grep -Fxq true || { echo "ERRO: Podman nao rootless"; exit 2; }
WORK="${1:-$HOME/GA06-Ferret-v5-image-9oIUg369}"
IMAGE="localhost/conectaeduca/ferret-scan:2.4.3-pa07-v5-candidate"
VERSION="2.4.3+ce.pa07.v5"
[[ -s "$WORK/context/ferret-scan" && -f "$WORK/IMAGE_BUILD.log" ]] || { echo "ERRO: diretorio do build anterior nao encontrado"; exit 2; }
podman image exists "$IMAGE" || { echo "ERRO: imagem candidata nao existe"; exit 2; }
IMAGE_ID="$(podman image inspect "$IMAGE" --format '{{.Id}}')"
USER="$(podman image inspect "$IMAGE" --format '{{.Config.User}}')"
[[ "$USER" == "1000:1000" ]] || { echo "ERRO: usuario da imagem inesperado: $USER"; exit 2; }
CID=""
cleanup() { if [[ -n "$CID" ]]; then podman rm -f "$CID" >/dev/null 2>&1 || true; fi; }
trap cleanup EXIT
echo "WORK=$WORK"
echo "ETAPA=4_SMOKE_COM_TMPFS_ROOTLESS_COMPATIVEL"
# A opcao uid=1000 nao funciona neste Podman --tmpfs.
# Apenas neste smoke isolado, usar modo 1777 sticky (um unico usuario).
# A configuracao mais estrita da EP126 (0700/uid1000) permanece SEM TESTAR.
CID="$(podman run -d --rm --read-only --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --tmpfs /home/ferret/tmp:rw,nosuid,nodev,noexec,size=256m,mode=1777 \
  -p 127.0.0.1::8080 "$IMAGE" --web --port 8080)" || {
  echo "ERRO: container de smoke nao iniciou"; exit 1;
}
PORT="$(podman port "$CID" 8080/tcp | awk -F: 'NR==1 {print $NF}')"
[[ "$PORT" =~ ^[0-9]+$ ]] || { echo "ERRO: porta local invalida"; exit 1; }
for i in $(seq 1 20); do
  curl -fsS --max-time 3 "http://127.0.0.1:$PORT/health" -o "$WORK/HEALTH.json" 2>/dev/null && break
  sleep 1
done
[[ -s "$WORK/HEALTH.json" ]] || { podman logs --tail 40 "$CID" >&2 || true; echo "HEALTH=FALHA"; exit 1; }
python3 - "$WORK/HEALTH.json" "$VERSION" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f: o=json.load(f)
assert o.get("status")=="healthy"
assert o.get("service")=="ferret-scan-web"
assert o.get("version")==sys.argv[2]
assert "ce.pa07.v5" in o.get("build_info",{}).get("commit","")
print("HEALTH_SMOKE=PASS")
PY
curl -fsS --max-time 10 "http://127.0.0.1:$PORT/app.js" -o "$WORK/APP_JS_SERVIDO.js"
grep -Fq "function renderScanCoverageStatus(verdict)" "$WORK/APP_JS_SERVIDO.js" || exit 1
grep -Fq "Export blocked: scan coverage is incomplete" "$WORK/APP_JS_SERVIDO.js" || exit 1
echo "APP_JS_V5_SERVIDO=PASS"
# Upload ficticio confirma que UID 1000 consegue usar a pasta temporaria.
printf 'ConectaEduca GA06 smoke v5: teste ficticio sem segredos.\n' > "$WORK/GA06_SMOKE_LOCAL.txt"
curl -fsS --max-time 50 \
  -F "files=@$WORK/GA06_SMOKE_LOCAL.txt;type=text/plain" \
  -F "confidence=all" -F "checks=all" \
  -F "verbose=false" -F "recursive=false" \
  "http://127.0.0.1:$PORT/scan" -o "$WORK/SCAN_SMOKE.json" || {
  podman logs --tail 40 "$CID" >&2 || true; echo "POST_SCAN=FALHA"; exit 1;
}
python3 - "$WORK/SCAN_SMOKE.json" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f: o=json.load(f)
assert o.get("success") is True
assert isinstance(o.get("results"),list)
assert o.get("incomplete") is not True
print("UPLOAD_SINTETICO=PASS")
PY
cleanup
CID=""
echo "ETAPA=5_EXPORTAR_IMAGEM_LOCAL"
ARCHIVE="$WORK/ferret-pa07-v5-candidate-docker-archive.tar"
podman save --format docker-archive -o "$ARCHIVE" "$IMAGE"
{
  echo "HOST=$(hostname -s)"
  echo "IMAGEM_ID=$IMAGE_ID"
  echo "IMAGEM_USUARIO=$USER"
  echo "BINARIO_SHA256=$(sha256sum "$WORK/context/ferret-scan" | awk '{print $1}')"
  echo "TAR_PATH=$ARCHIVE"
  echo "TAR_SHA256=$(sha256sum "$ARCHIVE" | awk '{print $1}')"
  echo "HEALTH_SMOKE=PASS"
  echo "APP_JS_V5_SERVIDO=PASS"
  echo "UPLOAD_SINTETICO=PASS"
  echo "TMPFS_LOCAL=1777_STICKY"
  echo "TMPFS_EP126_0700_UID1000=PENDENTE"
  echo "DEPLOY_EP126=NAO_REALIZADO"
  echo "IMAGE_PUSH=NAO_REALIZADO"
  echo "STATUS=PRONTO_PARA_REVISAO_CHANGE_CONTROL"
} | tee "$WORK/GA06_IMAGEM_RESULTADO.txt"
