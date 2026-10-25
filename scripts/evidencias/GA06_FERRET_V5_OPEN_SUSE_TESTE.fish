#!/usr/bin/env fish
# ConectaEduca GA-06 | Candidate v5: local openSUSE only, preserve v4.
# Apply v5 delta on a private copy; validate 26 Node regressions; build Go via
# the Podman command that already worked for the operator.
function ga06_v5_check
    set -l BASE "$HOME/GA06-Ferret-v4-KLgjXjKo/ferret-scan"
    set -l CACHE "$HOME/GA06-Ferret-v4-KLgjXjKo/build-local/cache"
    set -l REF a5156d1950df19276e6cfd8335603d73187a3841
    set -l ORIGINAL_V4 bb633e36f1d13b48a8bcbdf867f455bf47b5d37c19335cbf9ca7f616ebc266b6
    set -l PATCH_SHA 4036355c9d9ac0f4dc4f942689a0c14db6d39089
    set -l TEST_SHA 304469059e323b86ab8532877697f6b3e268e599
    set -l URL "https://raw.githubusercontent.com/andrea-kozicki/conectaeduca/fix/pa07-ferret-ui-fail-closed-review-20261025"

    if test (hostname -s) != opensuse-andrea; or test (id -u) -eq 0
        echo "ERRO: somente openSUSE pessoal como usuario comum"
        return 1
    end
    for cmd in git curl node sha256sum awk podman cp
        command -sq $cmd
        or begin
            echo "ERRO: falta dependencia $cmd"
            return 1
        end
    end
    if not test -f "$BASE/internal/web/assets/app.js"
        echo "ERRO: copia v4 anterior nao encontrada"
        return 1
    end
    if test (git -C "$BASE" rev-parse HEAD) != "$REF"
        echo "ERRO: commit original incorreto"
        return 1
    end
    printf '%s  %s\n' "$ORIGINAL_V4" "$BASE/internal/web/assets/app.js" | sha256sum -c -
    or return 1

    set -l WORK (mktemp -d "$HOME/GA06-Ferret-v5-XXXXXXXX")
    or return 1
    set -l SRC "$WORK/ferret-scan"
    set -l PATCH "$WORK/ferret_pa07_v5_on_v4.patch"
    set -l TEST "$WORK/ferret-pa07-v5.test.cjs"
    set -l FRAGMENT "$WORK/ferret-v5-test-fragment.js"
    echo "WORK=$WORK"
    echo "ETAPA=1_COPIA_PRIVADA_V4"
    cp -a "$BASE" "$SRC"
    or return 1
    mkdir -p "$WORK/out"
    or return 1

    echo "ETAPA=2_DOWNLOAD_CONFERENCIA"
    curl --proto '=https' --tlsv1.2 -fLsS --retry 2 \
        "$URL/deploy/interna/ferret/patches/ferret_pa07_v5_on_v4.patch" -o "$PATCH"
    or return 1
    curl --proto '=https' --tlsv1.2 -fLsS --retry 2 \
        "$URL/tests/js/ferret-pa07-v5.test.cjs" -o "$TEST"
    or return 1
    if test (git hash-object "$PATCH") != "$PATCH_SHA"
        echo "ERRO: patch v5 divergente"
        return 1
    end
    if test (git hash-object "$TEST") != "$TEST_SHA"
        echo "ERRO: testes v5 divergentes"
        return 1
    end

    echo "ETAPA=3_APLICACAO_DE_V5_SOBRE_COPIA"
    git -C "$SRC" apply --check "$PATCH"
    or return 1
    git -C "$SRC" apply "$PATCH"
    or return 1
    git -C "$SRC" diff --check
    or return 1
    node --check "$SRC/internal/web/assets/app.js"
    or return 1

    # Limit the mock to the tested functions; no server/network calls.
    awk '/^function filterResults\(filter\) \{/ {exit} {print}' \
        "$SRC/internal/web/assets/app.js" > "$FRAGMENT"
    or return 1
    awk '/^function exportResults\(\) \{/ {flag=1}
        flag && /^function showHelp\(\) \{/ {exit}
        flag {print}' "$SRC/internal/web/assets/app.js" >> "$FRAGMENT"
    or return 1
    node --check "$FRAGMENT"
    or return 1

    echo "ETAPA=4_TESTES_26_CASOS"
    env FERRET_APP_JS="$FRAGMENT" node --test "$TEST" \
        2>&1 | tee "$WORK/GA06_V5_TESTES.txt"
    if test $pipestatus[1] -ne 0
        echo "TESTES_V5=FALHA"
        echo "LOG=$WORK/GA06_V5_TESTES.txt"
        return 1
    end

    echo "ETAPA=5_BUILD_GO_LOCAL_SEM_DEPLOY"
    if not test -d "$CACHE"
        mkdir -p "$CACHE"
        or return 1
    end
    podman run --rm --pull=never \
        -v "$SRC:/src:ro" \
        -v "$WORK/out:/out:rw" \
        -v "$CACHE:/cache:rw" \
        -w /src \
        -e HOME=/cache \
        -e GOCACHE=/cache/build \
        -e GOPATH=/cache/go \
        -e GOMODCACHE=/cache/go/pkg/mod \
        -e GOTOOLCHAIN=local \
        -e CGO_ENABLED=0 \
        -e GOFLAGS=-mod=readonly \
        -e GOMAXPROCS=2 \
        docker.io/library/golang:1.26-bookworm \
        sh -ec 'go version; go build -p 2 -trimpath -buildvcs=false -o /out/ferret-scan-v5 ./cmd' \
        2>&1 | tee "$WORK/GA06_V5_BUILD_LOG.txt"
    if test $pipestatus[1] -ne 0; or not test -s "$WORK/out/ferret-scan-v5"
        echo "BUILD_V5=FALHA"
        echo "LOG=$WORK/GA06_V5_BUILD_LOG.txt"
        return 1
    end

    set -l BIN "$WORK/out/ferret-scan-v5"
    chmod 700 "$BIN"
    or return 1
    begin
        echo "GA06_V5=VALIDACAO_LOCAL_APROVADA"
        echo "PATCH_V4_PRESERVADO=SIM"
        echo "TESTES_NODE_V5=26_ESPERADOS_VER_LOG"
        echo "BUILD_GO_V5=PASS"
        echo "BINARIO=$BIN"
        sha256sum "$BIN"
        echo "DEPLOY_EP126=NAO_REALIZADO"
        echo "TESTE_FIREFOX_V5=PENDENTE"
        echo "WORK=$WORK"
    end | tee "$WORK/GA06_V5_RESULTADO.txt"
end

ga06_v5_check
set -l status $status
functions --erase ga06_v5_check
exit $status
