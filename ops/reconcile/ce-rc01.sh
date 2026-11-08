#!/usr/bin/env bash
# CE-RC01 — Reconciliação GitHub x VM: coleta somente leitura.
# Proibido por projeto: sudo, git fetch/pull/reset, docker compose config, env e segredos.
set -Eeuo pipefail
umask 077
export LC_ALL=C
# Evitar locks/atualizacoes opcionais do indice Git durante coleta.
export GIT_OPTIONAL_LOCKS=0
vm="${1:-}"
case "$vm" in
  EP125) expected="ep125-pucpr"; paths=(deploy/dmz public scripts/implantacao/vms) ;;
  EP126) expected="ep126-pucpr-br"; paths=(deploy/interna scripts/implantacao scripts/observabilidade) ;;
  *) printf 'USO=bash ce-rc01.sh EP125|EP126\n' >&2; exit 2 ;;
esac
root="/opt/conectaeduca"
actual="$(hostname -s)"
if [[ "$actual" != "$expected" ]]; then
  printf 'ABORTADO_HOST_DIVERGENTE esperado=%s atual=%s\n' "$expected" "$actual" >&2
  exit 3
fi
printf '=== CE-RC01 | %s | GitHub x VM | SOMENTE_LEITURA ===\n' "$vm"
whoami
date -Is
printf 'HOST=%s\nREPO_LOCAL=%s\n' "$actual" "$root"
printf 'GITHUB_REPO=andrea-kozicki/conectaeduca\n'
printf 'BASELINE_MAIN_VERIFICADA_2026-11-08=b74ea581a0814d86a99b6b455d5569f12fa967e5\n'
printf 'NOTA=SHA_REMOTE_ESTATICA; nao representa necessariamente HEAD atual no momento da execucao\n'

printf '\n=== A. ESTADO DO GIT LOCAL ===\n'
if ! command -v git >/dev/null 2>&1 || ! git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'GIT_LOCAL=INDISPONIVEL_OU_SEM_CHECKOUT\n'
else
  top="$(git -C "$root" rev-parse --show-toplevel)"
  if [[ "$top" != "$root" ]]; then
    printf 'ABORTADO_REPO_DIFERENTE=%s\n' "$top" >&2
    exit 4
  fi
  printf 'BRANCH=%s\n' "$(git -C "$root" branch --show-current)"
  printf 'HEAD_LOCAL=%s\n' "$(git -C "$root" rev-parse HEAD)"
  printf 'ORIGIN_MAIN_LOCAL_CACHE=%s\n' "$(git -C "$root" rev-parse --verify refs/remotes/origin/main 2>/dev/null || printf INDISPONIVEL)"
  if output="$(git -C "$root" status --porcelain=v1 --untracked-files=no 2>/dev/null)"; then
    if [[ -z "$output" ]]; then
      printf 'DIRTY_TRACKED_COUNT=0\n'
    else
      printf 'DIRTY_TRACKED_COUNT=%s\n' "$(printf '%s\n' "$output" | wc -l | tr -d ' ')"
    fi
  else
    printf 'GIT_STATUS=INACESSIVEL\n'
  fi
  printf 'ALTERACOES_TRACKED_NAS_AREAS_VM:\n'
  count=0
  while IFS= read -r -d '' p; do
    count=$((count+1))
    case "$p" in
      *.env|*.env.*|*secret*|*token*|*.pem|*.key|*.p12|*.pfx|*.crt|*connector.conf)
        printf 'ALTERADO_%03d=CAMINHO_RESERVADO\n' "$count" ;;
      *)
        printf 'ALTERADO_%03d=%s\n' "$count" "$p" ;;
    esac
  done < <(git -C "$root" diff --name-only -z HEAD -- "${paths[@]}" 2>/dev/null)
  printf 'ALTERACOES_AREAS_TOTAL=%s\n' "$count"
  # Detectar overlays e arquivos locais nao rastreados sem expor seus nomes.
  # Arquivos ignorados por .gitignore continuam fora desta contagem.
  untracked_count="$(git -C "$root" ls-files --others --exclude-standard -z -- "${paths[@]}" | tr -cd '\000' | wc -c | tr -d ' ')"
  printf 'UNTRACKED_AREAS_TOTAL=%s\n' "$untracked_count"
  for p in "${paths[@]}"; do
    n="$(git -C "$root" ls-files -- "$p" | wc -l | tr -d ' ')"
    printf 'ARQUIVOS_RASTREADOS[%s]=%s\n' "$p" "$n"
  done
fi

printf '\n=== B. CONNECTOR NATIVO ===\n'
if command -v systemctl >/dev/null 2>&1; then
  systemctl show twingate-connector -p LoadState -p ActiveState -p SubState -p UnitFileState -p NRestarts --no-pager 2>/dev/null || printf 'SYSTEMD=INACESSIVEL\n'
fi
if command -v twingate-connector >/dev/null 2>&1; then
  twingate-connector -V 2>/dev/null | head -n 1 || true
else
  printf 'BINARIO_TWINGATE=NÃO_ENCONTRADO_NO_PATH\n'
fi
printf 'SEGREDOS_CONNECTOR=NÃO_CONSULTADOS\n'

printf '\n=== C. CONTAINERS EM EXECUCAO (SEM ENV/INSPECT) ===\n'
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  docker ps --format 'CONTAINER={{.Names}} IMAGEM={{.Image}} STATUS={{.Status}}' |
    grep -Ei 'waf|nginx|app|php|wazuh|ferret|bacula|bacularis|openbao|maria|mongo|twingate' ||
    printf 'CONTAINERS_RELEVANTES=NENHUM_NA_LISTA\n'
else
  printf 'DOCKER=SEM_PERMISSAO_OU_INDISPONIVEL\n'
fi
printf '\nSEGREDOS_LIDOS=NAO\n'
printf 'GIT_REMOTO_MODIFICADO=NAO\n'
printf 'RUNTIME_MODIFICADO=NAO\n'
printf 'CE-RC01_CONCLUIDO\n'
