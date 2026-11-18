#!/usr/bin/env bash
# CE-EP126-PRESERVATION: inventario somente leitura; nenhum sudo, deploy ou upload.
set -euo pipefail

printf '%s\n' '=== CONECTAEDUCA | EP126 | INVENTARIO PRE-ENCERRAMENTO ==='

# O hostname completo pode conter identificadores institucionais; nao o imprimir.
host_short="$(hostname -s)"
if [[ "$host_short" != ep126-* ]]; then
    printf '%s\n' 'RESULTADO=FORA_DA_EP126; NENHUMA_COLETA_REALIZADA'
    exit 2
fi

if [[ "$#" -ne 2 || "${1:-}" != '--repo' || "${2:-}" != '/opt/conectaeduca' ]]; then
    printf '%s\n' 'USO: bash ep126_pre_encerramento_manifest.sh --repo /opt/conectaeduca'
    printf '%s\n' 'RESULTADO=REPOSITORIO_NAO_CONFIRMADO'
    exit 2
fi

repo='/opt/conectaeduca'
git_top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -L "$repo" || "$git_top" != "$repo" ]]; then
    printf '%s\n' 'RESULTADO=REPOSITORIO_INDISPONIVEL_OU_LINK_SIMBOLICO'
    exit 2
fi

paths=(
    'scripts/bootstrap/subir_ferret.fish'
    'scripts/dlp/processar_inbox_ferret.fish'
    'scripts/dlp/processar_inbox_ferret.sh'
    'deploy/interna/ferret/pa07-v5/90-ga06-ferret-v5-healthcheck.conf'
    'deploy/interna/ferret/pa07-v5/GA06_CANDIDATE_PROVENANCE.json'
    'deploy/interna/ferret/pa07-v5/compose.pa07-v5.override.yml'
    'scripts/evidencias/ga06_preflight_tar_local.sh'
    'scripts/evidencias/ga06_validar_politica_tar.py'
    'scripts/evidencias/ga06_validar_proveniencia_offline.py'
)

printf '%s\n' 'HOST_ROLE=EP126'
printf 'DATA=%s\n' "$(date -Is)"
printf 'GIT_HEAD_LOCAL=%s\n' "$(git -C "$repo" rev-parse HEAD)"
printf 'GIT_BRANCH_LOCAL=%s\n' "$(git -C "$repo" branch --show-current)"
printf 'ORIGIN_MAIN_EM_CACHE=%s\n' "$(git -C "$repo" rev-parse --verify refs/remotes/origin/main 2>/dev/null || printf 'INDETERMINADO')"
printf '%s\n' 'OBSERVACAO=origin/main_em_cache_pode_estar_desatualizada; git_fetch_nao_executado'

printf '%s\n' '=== STATUS GIT APENAS DOS CAMINHOS CONHECIDOS ==='
git -C "$repo" status --short --untracked-files=all -- "${paths[@]}"

found=0
missing=0
skipped=0
printf '%s\n' '=== HASHES E METADADOS, SEM CONTEUDO ==='
for relative in "${paths[@]}"; do
    target="$repo/$relative"
    if [[ -L "$target" ]]; then
        printf 'IGNORADO_LINK_SIMBOLICO | %s\n' "$relative"
        skipped=$((skipped + 1))
    elif [[ -f "$target" && -r "$target" ]]; then
        sha="$(sha256sum -- "$target")"
        sha="${sha%% *}"
        mode="$(stat -c '%a' -- "$target")"
        bytes="$(stat -c '%s' -- "$target")"
        if git -C "$repo" ls-files --error-unmatch -- "$relative" >/dev/null 2>&1; then
            versionado='SIM'
        else
            versionado='NAO'
        fi
        printf 'PRESENTE | sha256=%s | mode=%s | bytes=%s | git_local=%s | %s\n' \
            "$sha" "$mode" "$bytes" "$versionado" "$relative"
        found=$((found + 1))
    elif [[ -e "$target" ]]; then
        printf 'IGNORADO_SEM_LEITURA | %s\n' "$relative"
        skipped=$((skipped + 1))
    else
        printf 'AUSENTE | %s\n' "$relative"
        missing=$((missing + 1))
    fi
done

# Este arquivo apresentou marcadores sensiveis em triagem anterior.
# Nao reproduzir conteudo, tamanho ou hash automaticamente.
if [[ -L "$repo/RELEASE-METADATA.txt" ]]; then
    printf '%s\n' 'RELEASE_METADATA=LINK_SIMBOLICO_NAO_INSPECIONADO'
elif [[ -e "$repo/RELEASE-METADATA.txt" ]]; then
    printf '%s\n' 'RELEASE_METADATA=PRESENTE_RESTRITO_A_TRIAGEM_PRIVADA'
else
    printf '%s\n' 'RELEASE_METADATA=AUSENTE'
fi

printf 'ARQUIVOS_ESPERADOS=%s\n' "${#paths[@]}"
printf 'PRESENTES=%s\n' "$found"
printf 'AUSENTES=%s\n' "$missing"
printf 'IGNORADOS=%s\n' "$skipped"
printf '%s\n' 'ALTERACOES_NO_RUNTIME=NAO'
printf '%s\n' 'EXPORTACAO_AUTOMATICA=NAO'
printf '%s\n' 'EQUIVALENCIA_COM_MAIN_REMOTA=NAO_ATESTADA'
