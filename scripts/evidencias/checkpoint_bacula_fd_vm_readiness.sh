#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/srv/www/htdocs/conectaeduca"
OUT="$HOME/Downloads/conectaeduca-checkpoint-bacula-fd-vm-readiness-$(date +%Y%m%d-%H%M%S).txt"
cd "$ROOT"
exec > >(tee "$OUT") 2>&1

pass=0
pending=0
fail=0
ok(){ echo "OK       $*"; pass=$((pass+1)); }
pend(){ echo "PENDENTE $*"; pending=$((pending+1)); }
bad(){ echo "FALHA    $*"; fail=$((fail+1)); }

[[ "$(git branch --show-current)" == "main" ]] && ok "branch main" || bad "branch inesperada; esperado main"
git diff --check >/dev/null && ok "git diff --check" || bad "git diff --check"

for item in \
    "director:conectaeduca-bacula-director" \
    "storage:conectaeduca-bacula-storage" \
    "catalog:conectaeduca-bacula-catalog"
do
    label="${item%%:*}"
    container="${item#*:}"
    state="$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || true)"
    [[ "$state" == "running" ]] && ok "Bacula $label running" || bad "Bacula $label não está running"
done

required=(
    deploy/dmz/bacula-fd/bacula-fd.conf.example
    deploy/interna/bacula/fd/bacula-fd.conf.example
    deploy/interna/bacula/fd/director-clients-vm.conf.example
    deploy/interna/bacula/CONTRATO-FD-VM.md
    scripts/implantacao/preparar_bacula_fd_ubuntu.sh
)

for f in "${required[@]}"; do
    [[ -s "$f" ]] && ok "artefato FD: $f" || bad "artefato FD ausente: $f"
done

for cfg in \
    deploy/dmz/bacula-fd/bacula-fd.conf.example \
    deploy/interna/bacula/fd/bacula-fd.conf.example
do
    grep -q 'FDport = 9102' "$cfg" && ok "$cfg usa 9102" || bad "$cfg sem 9102"
    grep -q 'TLS Require = yes' "$cfg" && ok "$cfg exige TLS" || bad "$cfg não exige TLS"
    grep -q '__RUNTIME_SECRET_' "$cfg" && ok "$cfg usa placeholder runtime" || bad "$cfg não possui placeholder runtime"
done

if grep -q 'File Daemon definitivo é \*\*nativo no host Ubuntu\*\*' deploy/interna/bacula/CONTRATO-FD-VM.md; then
    ok "contrato define FD nativo"
else
    bad "contrato não define claramente FD nativo"
fi

if grep -q 'serviço NÃO será iniciado automaticamente' scripts/implantacao/preparar_bacula_fd_ubuntu.sh; then
    ok "instalador não inicia FD com placeholder"
else
    bad "proteção contra início com placeholder não confirmada"
fi

echo "Aprovacoes=$pass"
echo "Pendencias=$pending"
echo "Falhas=$fail"

if (( fail > 0 )); then
    echo "BACULA_FD_VM_READINESS=FALHA"
elif (( pending > 0 )); then
    echo "BACULA_FD_VM_READINESS=PENDENTE"
else
    echo "BACULA_FD_VM_READINESS=APROVADO"
fi

echo "FD_LAB=NAO_DEVE_ENTRAR_NO_HANDOFF_FINAL"
echo "ARQUIVO_SAIDA=$OUT"
if (( fail > 0 )); then
    exit 1
fi
exit 0
