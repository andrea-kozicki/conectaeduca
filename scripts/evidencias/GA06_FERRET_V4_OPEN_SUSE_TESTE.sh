#!/usr/bin/env bash
# ConectaEduca GA-06 | Ferret Scan UI v4 | validacao local isolada
# NAO usar em EP125/EP126. Nao faz deploy, docker, sudo ou altera servicos.
set -Eeuo pipefail
umask 077

if [[ "$(id -u)" -eq 0 ]]; then
  echo "ERRO: executar como usuario comum, nunca como root."
  exit 2
fi
host="$(hostname -s | tr '[:upper:]' '[:lower:]')"
if [[ "$host" == "ep125-pucpr" || "$host" == "ep126-pucpr" ]]; then
  echo "ERRO: host do laboratorio detectado; nao execute nas VMs."
  exit 2
fi
if ! grep -qi 'opensuse' /etc/os-release; then
  echo "ERRO: este roteiro foi preparado para o openSUSE pessoal."
  exit 2
fi

for prog in git curl node sha256sum awk; do
  if ! command -v "$prog" >/dev/null 2>&1; then
    echo "ERRO: dependencia ausente: $prog (nao instalar automaticamente)."
    exit 2
  fi
done

WORK="$(mktemp -d "$HOME/GA06-Ferret-v4-XXXXXXXX")"
SRC="$WORK/ferret-scan"
PATCH="$WORK/ferret_pa07_v4.patch"
TESTS="$WORK/ferret-pa07-v4.test.cjs"
RESULT="$WORK/GA06_RESULTADO.txt"
RAW="https://raw.githubusercontent.com/andrea-kozicki/conectaeduca/fix/pa07-ferret-ui-fail-closed-review-20261025"
UPSTREAM_COMMIT="a5156d1950df19276e6cfd8335603d73187a3841"
PATCH_BLOB="4e6ca69bb28d980a38482bea12ea42ffeae3a834"
TESTS_BLOB="c7ae9842b0208e18b2d01e52a07629406e7d70ab"

on_err() {
  printf 'RESULTADO=FALHA_EM_ETAPA_LOCAL\nPASTA=%s\n' "$WORK" >&2
}
trap on_err ERR

echo "=== GA-06 | FERRET v4 | openSUSE ==="
echo "HOST=$host"
echo "PASTA=$WORK"
echo "ETAPA=1/5_CLONE_OFICIAL"
git clone --quiet --depth 1 --branch v2.4.3 \
  https://github.com/awslabs/ferret-scan.git "$SRC"

got_commit="$(git -C "$SRC" rev-parse HEAD)"
[[ "$got_commit" == "$UPSTREAM_COMMIT" ]] || {
  echo "ERRO: checkout oficial difere do commit esperado: $got_commit" >&2
  exit 1
}

echo "ETAPA=2/5_DOWNLOAD_PATCH_TESTES"
curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
  --connect-timeout 10 --max-time 90 --retry 2 \
  "$RAW/deploy/interna/ferret/patches/ferret_pa07_v4.patch" -o "$PATCH"
curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
  --connect-timeout 10 --max-time 90 --retry 2 \
  "$RAW/tests/js/ferret-pa07-v4.test.cjs" -o "$TESTS"

got_patch="$(git hash-object "$PATCH")"
got_tests="$(git hash-object "$TESTS")"
[[ "$got_patch" == "$PATCH_BLOB" ]] || { echo "ERRO: patch divergente."; exit 1; }
[[ "$got_tests" == "$TESTS_BLOB" ]] || { echo "ERRO: arquivo de testes divergente."; exit 1; }

echo "ETAPA=3/5_APLICACAO_ISOLADA"
git -C "$SRC" apply --check "$PATCH"
git -C "$SRC" apply "$PATCH"
git -C "$SRC" diff --check
node --check "$SRC/internal/web/assets/app.js"
echo "PATCH_APLICADO_ISOLADAMENTE=SIM"

# Recorte de funções relevantes. Nao substitui testes no navegador completo.
awk '/^function filterResults\(filter\) \{/ {exit} {print}' \
  "$SRC/internal/web/assets/app.js" > "$WORK/ferret-app-fragment.js"
node --check "$WORK/ferret-app-fragment.js"

echo "ETAPA=4/5_REGRESSAO_NODE"
FERRET_APP_JS="$WORK/ferret-app-fragment.js" \
  node --test "$TESTS" > "$WORK/GA06_TESTES_NODE.txt" 2>&1 || {
    tail -n 55 "$WORK/GA06_TESTES_NODE.txt"
    echo "ERRO: regressao Node falhou. Sem build nem deploy."
    exit 1
  }
tail -n 12 "$WORK/GA06_TESTES_NODE.txt"

echo "ETAPA=5/5_BUILD_GO_OPCIONAL"
BUILD="NAO_EXECUTADO"
if command -v go >/dev/null 2>&1; then
  go_version="$(GOTOOLCHAIN=local go version 2>/dev/null || true)"
  go_minor="$(printf '%s\n' "$go_version" | sed -nE 's/.*go1\.([0-9]+).*/\1/p')"
  if [[ "$go_minor" =~ ^[0-9]+$ ]] && (( 10#$go_minor >= 26 )); then
    echo "GO_VERSION=$go_version"
    if (cd "$SRC" && GOTOOLCHAIN=local go build -trimpath -o "$WORK/ferret-scan-v4" ./cmd) \
         > "$WORK/GA06_BUILD_GO.txt" 2>&1; then
      BUILD="PASS"
    else
      BUILD="FALHA"
      tail -n 30 "$WORK/GA06_BUILD_GO.txt" >&2
      # Testes JS continuam validos; build nao sera considerado aprovado.
    fi
  else
    BUILD="PULADO_GO_1_26_OU_SUPERIOR_NAO_DISPONIVEL"
  fi
else
  BUILD="PULADO_GO_AUSENTE"
fi

patch_sha="$(sha256sum "$PATCH" | awk '{print $1}')"
js_sha="$(sha256sum "$SRC/internal/web/assets/app.js" | awk '{print $1}')"
{
  echo "=== CONECTAEDUCA | GA-06 | FERRET v4 ==="
  echo "HOST=$host"
  echo "VERSAO_BASE=v2.4.3"
  echo "UPSTREAM_COMMIT=$got_commit"
  echo "PATCH_BLOB_SHA1=$got_patch"
  echo "TEST_BLOB_SHA1=$got_tests"
  echo "PATCH_SHA256=$patch_sha"
  echo "APP_JS_PATCHED_SHA256=$js_sha"
  echo "PATCH_APLICAVEL=SIM"
  echo "NODE_SYNTAX=PASS"
  echo "TESTES_NODE=20_ESPERADOS_VER_LOG"
  echo "BUILD_GO=$BUILD"
  echo "DEPLOY_EP126=NAO_REALIZADO"
  echo "TESTE_NAVEGADOR_REAL=NAO_EXECUTADO"
  echo "WORK=$WORK"
  echo "RESULTADO=VALIDACAO_OFFLINE_CONCLUIDA"
} | tee "$RESULT"

echo "=== CUSTODIA LOCAL ==="
sha256sum "$RESULT" "$WORK/GA06_TESTES_NODE.txt"
echo "ARQUIVOS_PARA_ENVIAR=GA06_RESULTADO.txt e GA06_TESTES_NODE.txt"
echo "CONFERIR_SE_HOUVE_20_PASS_E_0_FAIL=SIM"
if [[ "$BUILD" == "PASS" ]]; then
  echo "BINARIO_ISOLADO=$WORK/ferret-scan-v4"
  echo "Para uma futura homologacao local: \"$WORK/ferret-scan-v4\" --web --bind 127.0.0.1 --port 18089"
  echo "O servidor NAO foi iniciado por este script."
fi
