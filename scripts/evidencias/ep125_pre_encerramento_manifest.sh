#!/usr/bin/env bash
# CE-EP125-PRESERVATION: read-only, no sudo, no secret contents, no uploads.
set -euo pipefail

expected_host='ep125-pucpr'
observed_host="$(hostname -s)"
printf '%s\n' '=== CE-EP125 | MANIFESTO SOMENTE LEITURA ==='
printf 'HOSTNAME_ESPERADO=%s\n' "$expected_host"
if [[ "$observed_host" != "$expected_host" ]]; then
    printf '%s\n' 'RESULTADO=HOST_INCORRETO; NENHUMA_COLETA_REALIZADA'
    exit 2
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
if ! git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' 'RESULTADO=REPOSITORIO_NAO_ENCONTRADO'
    exit 2
fi

paths=(
    'deploy/dmz/compose.ga08-dual-socket.candidate.yml'
    'deploy/dmz/compose.ga08-runtimefix.candidate.yml'
    'deploy/dmz/compose.ga08-socket.candidate.yml'
    'deploy/dmz/ga08/app-http.dual-socket.candidate.conf'
    'deploy/dmz/ga08/app-http.socket.candidate.conf'
    'deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf'
    'docs/release/GA08-17B-CHANGE-CONTROL-EP125-20261102.md'
    'scripts/ga08-32-bateria-integrada-ep125.py'
    'scripts/ga08-33-sockets-persistentes-e2e-ep125.py'
    'scripts/ga08-canario-fpm-offline-ep125.py'
    'scripts/ga08-change-control.py'
    'scripts/ga08-contexto-execucao-ep125.py'
    'scripts/ga08-e2e-pa02-ep125.py'
    'scripts/ga08-fpm-permission-triage-ep125.py'
    'scripts/ga08-implantacao-controlada-ep125.sh'
    'scripts/ga08-nginx-canario-ep125.py'
    'scripts/ga08-nginx-entrypoint-isolation-ep125.py'
    'scripts/ga08-nginx-runtime-paths-ep125.py'
    'scripts/ga08-nginx-tmpfs-diferencial-ep125.py'
    'scripts/ga08-preflight-env-runtime-ep125.py'
    'scripts/ga08-preparar-sockets-ep125.sh'
    'scripts/ga08-rollback-controlado-ep125.sh'
)

printf 'DATA=%s\n' "$(date -Is)"
printf 'GIT_HEAD=%s\n' "$(git -C "$repo_root" rev-parse HEAD)"
printf 'GIT_BRANCH=%s\n' "$(git -C "$repo_root" branch --show-current)"
printf 'GIT_ORIGIN_MAIN_LOCAL=%s\n' "$(git -C "$repo_root" rev-parse --verify refs/remotes/origin/main 2>/dev/null || printf 'INDISPONIVEL')"
printf '%s\n' '=== STATUS DOS CAMINHOS CANDIDATOS ==='
git -C "$repo_root" status --short --untracked-files=all -- "${paths[@]}"

found=0
missing=0
skipped=0
printf '%s\n' '=== METADADOS E HASHES (SEM CONTEUDO) ==='
for relative in "${paths[@]}"; do
    full_path="$repo_root/$relative"
    if [[ -L "$full_path" ]]; then
        printf 'SKIP_SYMLINK | %s\n' "$relative"
        skipped=$((skipped + 1))
    elif [[ -f "$full_path" ]]; then
        if [[ -r "$full_path" ]]; then
            digest="$(sha256sum -- "$full_path")"
            digest="${digest%% *}"
            permissions="$(stat -c '%a' -- "$full_path")"
            bytes="$(stat -c '%s' -- "$full_path")"
            printf 'PRESENTE | sha256=%s | mode=%s | bytes=%s | %s\n' "$digest" "$permissions" "$bytes" "$relative"
            found=$((found + 1))
        else
            printf 'SEM_PERMISSAO_LEITURA | %s\n' "$relative"
            skipped=$((skipped + 1))
        fi
    else
        printf 'AUSENTE | %s\n' "$relative"
        missing=$((missing + 1))
    fi
done

printf '%s\n' '=== RESUMO ==='
printf 'TOTAL_ESPERADO=%s\n' "${#paths[@]}"
printf 'PRESENTES=%s\n' "$found"
printf 'AUSENTES=%s\n' "$missing"
printf 'IGNORADOS=%s\n' "$skipped"
printf '%s\n' 'ALTERACOES_NO_RUNTIME=NAO'
printf '%s\n' 'PUBLICACAO_AUTOMATICA=NAO'
