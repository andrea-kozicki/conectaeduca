#!/usr/bin/env bash
set -Eeuo pipefail

die() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 \
        || die "comando obrigatório não encontrado: $1"
}

for cmd in git docker tar gzip sha256sum find sort df; do
    need "$cmd"
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "execute dentro do repositório ConectaEduca"

cd "$ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
    die "working tree não está limpa; faça commit ou descarte as alterações antes do handoff"
fi

COMMIT="$(git rev-parse HEAD)"
COMMIT_SHORT="$(git rev-parse --short=12 HEAD)"
BRANCH="$(git branch --show-current)"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"

OUT="${1:-/var/tmp/conectaeduca-handoff-${TIMESTAMP}}"

[[ ! -e "$OUT" ]] || die "diretório de saída já existe: $OUT"

mkdir -p \
    "$OUT/staging/dmz/images" \
    "$OUT/staging/dmz/deploy" \
    "$OUT/staging/interna/images" \
    "$OUT/staging/interna/deploy" \
    "$OUT/packages"

# O docker save pode precisar de bastante espaço temporário.
FREE_KIB="$(df -Pk "$(dirname "$OUT")" | awk 'NR==2 {print $4}')"
MIN_KIB=$((20 * 1024 * 1024))

if (( FREE_KIB < MIN_KIB )); then
    die "menos de 20 GiB livres no filesystem de destino"
fi

DMZ_IMAGES=(
    "conectaeduca/php-fpm:dmz"
    "conectaeduca/nginx:dmz"
    "owasp/modsecurity-crs:4.25.1-nginx-lts"
)

INTERNA_IMAGES=(
    "mariadb:12.3.2-ubi10"
    "wazuh/wazuh-manager:4.14.7"
    "wazuh/wazuh-indexer:4.14.7"
    "wazuh/wazuh-dashboard:4.14.7"
    "wazuh/wazuh-certs-generator:0.0.4"
)

ALL_IMAGES=(
    "${DMZ_IMAGES[@]}"
    "${INTERNA_IMAGES[@]}"
)

printf '\n=== VALIDANDO IMAGENS ===\n'

for image in "${ALL_IMAGES[@]}"; do
    docker image inspect "$image" >/dev/null 2>&1 \
        || die "imagem ausente: $image"

    os="$(docker image inspect "$image" --format '{{.Os}}')"
    arch="$(docker image inspect "$image" --format '{{.Architecture}}')"

    printf '%-55s %s/%s\n' "$image" "$os" "$arch"

    [[ "$os" == "linux" && "$arch" == "amd64" ]] \
        || die "plataforma inesperada em $image: $os/$arch"
done

copy_tracked_files() {
    local destination="$1"
    shift

    while IFS= read -r -d '' file; do
        # Defesa adicional: mesmo sendo arquivos rastreados,
        # nenhum segredo/runtime deve entrar no handoff.
        case "$file" in
            */.runtime/*|*/.runtime|\
            *.key|*.pem|*.p12|*.pfx|*.jks|\
            *.env)
                printf 'IGNORADO por política: %s\n' "$file"
                continue
                ;;
        esac

        mkdir -p "$destination/$(dirname "$file")"
        cp -a "$file" "$destination/$file"
    done < <(git ls-files -z -- "$@")
}

write_image_manifest() {
    local output="$1"
    shift

    {
        printf 'ConectaEduca - Manifesto de imagens\n'
        printf '=================================\n'
        printf 'Gerado em: %s\n' "$(date --iso-8601=seconds)"
        printf 'Branch: %s\n' "$BRANCH"
        printf 'Commit: %s\n' "$COMMIT"
        printf 'Plataforma requerida: linux/amd64\n\n'

        for image in "$@"; do
            printf 'Imagem: %s\n' "$image"
            printf 'ID: %s\n' \
                "$(docker image inspect "$image" --format '{{.Id}}')"
            printf 'Plataforma: %s/%s\n' \
                "$(docker image inspect "$image" --format '{{.Os}}')" \
                "$(docker image inspect "$image" --format '{{.Architecture}}')"
            printf 'Criada: %s\n' \
                "$(docker image inspect "$image" --format '{{.Created}}')"
            printf 'RepoDigests: %s\n' \
                "$(docker image inspect "$image" --format '{{json .RepoDigests}}')"
            printf '\n'
        done
    } > "$output"
}

printf '\n=== COPIANDO ARQUIVOS VERSIONADOS ===\n'

copy_tracked_files \
    "$OUT/staging/dmz/deploy" \
    deploy/dmz

copy_tracked_files \
    "$OUT/staging/interna/deploy" \
    deploy/interna/mariadb \
    deploy/interna/wazuh

printf '\n=== GERANDO MANIFESTOS ===\n'

write_image_manifest \
    "$OUT/staging/dmz/MANIFESTO.txt" \
    "${DMZ_IMAGES[@]}"

write_image_manifest \
    "$OUT/staging/interna/MANIFESTO.txt" \
    "${INTERNA_IMAGES[@]}"

cat > "$OUT/staging/dmz/LEIA-ME.txt" <<EOF_DMZ
CONECTAEDUCA - HANDOFF DMZ

Branch: $BRANCH
Commit: $COMMIT
Plataforma: linux/amd64

1. Verifique os arquivos:
   sha256sum -c SHA256SUMS

2. Carregue as imagens:
   docker load -i images/dmz-images.tar.gz

3. Crie os arquivos de runtime/segredos no host de destino
   conforme a documentação do projeto.

Nenhuma credencial ou arquivo .runtime faz parte deste pacote.
EOF_DMZ

cat > "$OUT/staging/interna/LEIA-ME.txt" <<EOF_INTERNA
CONECTAEDUCA - HANDOFF VM INTERNA

Branch: $BRANCH
Commit: $COMMIT
Plataforma: linux/amd64

1. Verifique os arquivos:
   sha256sum -c SHA256SUMS

2. Carregue as imagens:
   docker load -i images/interna-images.tar.gz

3. Crie os arquivos de runtime/segredos no host de destino
   conforme a documentação do projeto.

Nenhuma credencial ou arquivo .runtime faz parte deste pacote.
EOF_INTERNA

printf '\n=== EXPORTANDO IMAGENS DA DMZ ===\n'

docker save "${DMZ_IMAGES[@]}" \
    | gzip -1 \
    > "$OUT/staging/dmz/images/dmz-images.tar.gz"

printf '\n=== EXPORTANDO IMAGENS DA VM INTERNA ===\n'

docker save "${INTERNA_IMAGES[@]}" \
    | gzip -1 \
    > "$OUT/staging/interna/images/interna-images.tar.gz"

printf '\n=== GERANDO HASHES INTERNOS ===\n'

(
    cd "$OUT/staging/dmz"
    find . -type f ! -name SHA256SUMS -print0 \
        | sort -z \
        | xargs -0 sha256sum \
        > SHA256SUMS
)

(
    cd "$OUT/staging/interna"
    find . -type f ! -name SHA256SUMS -print0 \
        | sort -z \
        | xargs -0 sha256sum \
        > SHA256SUMS
)

printf '\n=== GERANDO PACOTES FINAIS ===\n'

DMZ_PACKAGE="$OUT/packages/conectaeduca-handoff-dmz-${COMMIT_SHORT}.tar"
INTERNA_PACKAGE="$OUT/packages/conectaeduca-handoff-interna-${COMMIT_SHORT}.tar"

tar -C "$OUT/staging" -cf "$DMZ_PACKAGE" dmz
tar -C "$OUT/staging" -cf "$INTERNA_PACKAGE" interna

(
    cd "$OUT/packages"
    sha256sum \
        "$(basename "$DMZ_PACKAGE")" \
        "$(basename "$INTERNA_PACKAGE")" \
        > SHA256SUMS
)

printf '\n=== RESULTADO ===\n'
printf 'Branch:      %s\n' "$BRANCH"
printf 'Commit:      %s\n' "$COMMIT"
printf 'Plataforma:  linux/amd64\n'
printf 'Saída:       %s\n\n' "$OUT"

du -h "$OUT/packages/"*

printf '\nHANDOFF GERADO COM SUCESSO.\n'
printf 'Próxima etapa: validar SHA-256 e testar docker load dos pacotes.\n'
