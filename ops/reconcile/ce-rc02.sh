#!/usr/bin/env bash
# CE-RC02 — classificacao local segura; nenhuma alteracao em VM, Git ou Docker.
set -Eeuo pipefail
umask 077
export LC_ALL=C
export GIT_OPTIONAL_LOCKS=0

case "$(hostname -s)" in
  ep125-pucpr) vm=EP125 ;;
  ep126-pucpr-br) vm=EP126 ;;
  *) printf 'ABORTADO_HOST_FORA_DO_ESCOPO\n' >&2; exit 3 ;;
esac

root=/opt/conectaeduca
if [[ "$(git -C "$root" rev-parse --show-toplevel 2>/dev/null || true)" != "$root" ]]; then
  printf 'ABORTADO_SEM_REPOSITORIO\n' >&2
  exit 4
fi

printf '=== CE-RC02 | %s | CLASSIFICACAO_READ_ONLY ===\n' "$vm"
whoami
date -Is

python3 - "$root" "$vm" <<'PY'
import collections
import subprocess
import sys

root, vm = sys.argv[1:3]
scopes = (
    ["deploy/dmz", "public", "scripts/implantacao/vms"]
    if vm == "EP125" else
    ["deploy/interna", "scripts/implantacao", "scripts/observabilidade"]
)

def git_paths(*args):
    result = subprocess.run(
        ["git", "-C", root, *args],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    return [s.decode("utf-8", "surrogateescape")
            for s in result.stdout.split(b"\0") if s]

def category(path):
    if path.startswith("deploy/interna/wazuh/config/rules/"):
        return "WAZUH_REGRAS"
    if path.startswith("deploy/interna/"):
        return "EP126_DEPLOY"
    if path.startswith("deploy/dmz/"):
        return "EP125_DEPLOY"
    if path.startswith("scripts/"):
        return "SCRIPTS"
    if path.startswith("src/"):
        return "CODIGO_APLICACAO"
    if path.startswith("public/"):
        return "PUBLIC_WEB"
    if path.startswith("docs/"):
        return "DOCUMENTACAO"
    if path.startswith(".github/"):
        return "CI"
    return "OUTROS"

tracked = git_paths("-c", "diff.external=", "diff", "--no-ext-diff", "--name-only", "-z", "HEAD")
untracked = git_paths("ls-files", "--others", "--exclude-standard", "-z", "--", *scopes)

print("=== GIT TRACKED: CLASSIFICACAO SEM CONTEUDO ===")
print("TRACKED_MODIFICADOS_TOTAL=" + str(len(tracked)))
for group, count in sorted(collections.Counter(map(category, tracked)).items()):
    print(f"TRACKED_CATEGORIA[{group}]={count}")

dlp_path = "deploy/interna/wazuh/config/rules/conectaeduca_dlp_rules.xml"
print("WAZUH_DLP_RULE_MODIFICADA=" + ("SIM" if dlp_path in tracked else "NAO"))
print("OUTROS_TRACKED_NAO_WAZUH_DLP=" +
      str(sum(p != dlp_path for p in tracked)))

print("=== GIT UNTRACKED: CATEGORIAS SEM NOMES ===")
print("UNTRACKED_NAO_IGNORADOS_TOTAL=" + str(len(untracked)))
for group, count in sorted(collections.Counter(map(category, untracked)).items()):
    print(f"UNTRACKED_CATEGORIA[{group}]={count}")
print("ARQUIVOS_IGNORADOS=NAO_INVENTARIADOS")
print("ARQUIVOS_NOMES_PRIVADOS=NAO_EXIBIDOS")
print("ARQUIVOS_CONTEUDO=NAO_EXIBIDO")
PY

if [[ "$vm" == EP126 ]]; then
  printf '=== OPENBAO: ESTADO DOCKER SEM ENV OU LOGS ===\n'
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    docker inspect --format 'OPENBAO_STATE={{.State.Status}} OPENBAO_HEALTH={{if .State.Health}}{{.State.Health.Status}}{{else}}SEM_HEALTHCHECK{{end}} OPENBAO_RESTARTS={{.RestartCount}}' conectaeduca-openbao 2>/dev/null || printf 'OPENBAO_INSPECAO_INDISPONIVEL\n'
  else
    printf 'DOCKER_INDISPONIVEL_OU_SEM_PERMISSAO\n'
  fi
fi

printf 'CE-RC02_CONCLUIDO\n'
