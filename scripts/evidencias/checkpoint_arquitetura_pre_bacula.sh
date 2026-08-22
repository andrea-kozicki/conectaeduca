#!/usr/bin/env bash
set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 1

REPORT="/tmp/conectaeduca-checkpoint-arquitetura-pre-bacula-$(date +%Y%m%d-%H%M%S).txt"
OKS=0
WARN=0
FAIL=0

exec > >(tee "$REPORT") 2>&1

ok()   { printf 'OK       %s\n' "$*"; OKS=$((OKS+1)); }
warn() { printf 'AVISO    %s\n' "$*"; WARN=$((WARN+1)); }
fail() { printf 'FALHA    %s\n' "$*"; FAIL=$((FAIL+1)); }

echo "======================================================================"
echo " CONECTAEDUCA - CHECKPOINT ARQUITETURA PRÉ-BACULA"
echo " Versão: pre-bacula-arch-1.0"
echo " Data: $(date -Iseconds)"
echo "======================================================================"

echo
echo "=== 1. GIT ==="
if [[ "$(git branch --show-current)" == "feature/auth-local" ]]; then
  ok "branch feature/auth-local confirmada"
else
  fail "branch esperada feature/auth-local não está ativa"
fi

if git diff --check; then
  ok "git diff --check"
else
  fail "git diff --check encontrou problema"
fi

echo
echo "=== 2. DOCUMENTOS ==="
required=(
  deploy/ARQUITETURA-VMs.md
  deploy/interna/bacula/README.md
  deploy/interna/bacula/CAPACIDADE-180GB.md
  deploy/interna/bacula/MATRIZ-BACKUP.md
  deploy/interna/bacula/CONSISTENCIA.md
  deploy/interna/bacula/POLITICA-RPO-RTO-RETENCAO.md
  deploy/interna/bacula/ARQUITETURA-COMPONENTES.md
  deploy/interna/bacula/REDE-PFSENSE.md
  deploy/interna/bacula/IDENTIDADES-PRIVILEGIOS.md
  deploy/interna/bacula/CONTRATO-RESTORE.md
  deploy/interna/bacula/OBSERVABILIDADE-WAZUH.md
  deploy/interna/bacula/CONTRATO-CHECKPOINT.md
  deploy/interna/bacula/DECISOES-PRE-IMPLEMENTACAO.md
)

for f in "${required[@]}"; do
  [[ -f "$f" ]] && ok "$f" || fail "ausente: $f"
done

echo
echo "=== 3. CAPACIDADE / POSICIONAMENTO ==="
grep -Fq 'Ubuntu DMZ | 8 GiB | 180 GiB' deploy/ARQUITETURA-VMs.md \
  && ok "DMZ fixada em 8 GiB / 180 GiB" \
  || fail "dimensionamento da DMZ divergente"

grep -Fq 'Ubuntu Interna | 16 GiB | 180 GiB' deploy/ARQUITETURA-VMs.md \
  && ok "VM interna fixada em 16 GiB / 180 GiB" \
  || fail "dimensionamento da VM interna divergente"

grep -Fq 'Storage principal não fica na DMZ' deploy/interna/bacula/DECISOES-PRE-IMPLEMENTACAO.md \
  && ok "Storage Bacula explicitamente fora da DMZ" \
  || fail "posicionamento do Storage não está fechado"

grep -Fq 'PostgreSQL dedicado' deploy/interna/bacula/DECISOES-PRE-IMPLEMENTACAO.md \
  && ok "Catalog separado do MariaDB da aplicação" \
  || fail "Catalog dedicado não confirmado"

grep -Fq 'File Daemon será nativo' deploy/interna/bacula/DECISOES-PRE-IMPLEMENTACAO.md \
  && ok "File Daemon nativo definido para evitar bind amplo do host" \
  || fail "modelo do File Daemon não confirmado"

echo
echo "=== 4. ESCOPO / SEGREDOS ==="
grep -Fq '| OpenBao root token | NUNCA |' deploy/interna/bacula/MATRIZ-BACKUP.md \
  && ok "root token OpenBao excluído" \
  || fail "root token OpenBao não está explicitamente excluído"

grep -Fq '| unseal shares | NUNCA |' deploy/interna/bacula/MATRIZ-BACKUP.md \
  && ok "unseal shares excluídas" \
  || fail "unseal shares não estão explicitamente excluídas"

grep -Fq '| Ferret reports/raw | NÃO |' deploy/interna/bacula/MATRIZ-BACKUP.md \
  && ok "Ferret reports/raw fora do backup" \
  || fail "reports/raw do Ferret não está excluído"

grep -Fq '| Ferret inbox | NÃO |' deploy/interna/bacula/MATRIZ-BACKUP.md \
  && ok "Ferret inbox fora do backup" \
  || fail "inbox do Ferret não está excluída"

grep -Fq 'não copiar diretamente o volume `/var/lib/mysql`' deploy/interna/bacula/CONSISTENCIA.md \
  && ok "MariaDB protegido por dump, não por cópia crua" \
  || fail "contrato de consistência MariaDB divergente"

grep -Fq 'snapshot Raft consistente' deploy/interna/bacula/CONSISTENCIA.md \
  && ok "OpenBao protegido por snapshot Raft" \
  || fail "contrato de snapshot OpenBao divergente"

echo
echo "=== 5. REDE / SEGURANÇA ==="
for port in 9101 9102 9103; do
  grep -Fq "$port" deploy/interna/bacula/REDE-PFSENSE.md \
    && ok "porta Bacula $port documentada" \
    || fail "porta Bacula $port não documentada"
done

grep -Fq 'Interna(Director) -> DMZ(FD): TCP 9102' deploy/interna/bacula/REDE-PFSENSE.md \
  && ok "fluxo Director -> FD DMZ documentado" \
  || fail "fluxo Director -> FD DMZ ausente"

grep -Fq 'DMZ(FD) -> Interna(Storage): TCP 9103' deploy/interna/bacula/REDE-PFSENSE.md \
  && ok "fluxo FD DMZ -> Storage documentado" \
  || fail "fluxo FD DMZ -> Storage ausente"

grep -Fq 'TLS obrigatório' deploy/interna/bacula/ARQUITETURA-COMPONENTES.md \
  && ok "TLS definido como obrigatório" \
  || fail "TLS não está obrigatório"

mapfile -t BACULA_IMPL_FILES < <(
  find deploy/interna/bacula -type f \
    \( -name '*.yml' -o -name '*.yaml' -o -name 'Dockerfile*' -o -name '*.conf' \) \
    -print
)

if (( ${#BACULA_IMPL_FILES[@]} == 0 )); then
  ok "nenhum artefato operacional Bacula foi antecipado; proibições ficam apenas documentadas"
elif grep -InE 'network_mode:[[:space:]]*host|privileged:[[:space:]]*true|/var/run/docker\.sock' \
     "${BACULA_IMPL_FILES[@]}" >/dev/null; then
  fail "artefato operacional Bacula contém privilégio/rede proibido"
else
  ok "artefatos operacionais Bacula não dependem de host network, privileged ou Docker socket"
fi

echo
echo "=== 6. RESTORE / OBSERVABILIDADE ==="
grep -Fq 'SHA-256 pós-restore é idêntico' deploy/interna/bacula/CONTRATO-CHECKPOINT.md \
  && ok "restore por hash é critério obrigatório" \
  || fail "restore por hash não é critério"

grep -Fq 'MariaDB sintético restaura' deploy/interna/bacula/CONTRATO-CHECKPOINT.md \
  && ok "restore MariaDB sintético é obrigatório" \
  || fail "restore MariaDB não está no contrato"

grep -Fq '110200-110219' deploy/interna/bacula/OBSERVABILIDADE-WAZUH.md \
  && ok "faixa futura de regras Wazuh reservada" \
  || fail "faixa Wazuh Bacula não está reservada"

echo
echo "=== 7. LIMITAÇÃO DO LABORATÓRIO ==="
if grep -Fq 'não protege contra' deploy/ARQUITETURA-VMs.md \
   && grep -Fq 'perda total da VM ou do disco virtual' deploy/ARQUITETURA-VMs.md; then
  ok "risco residual de storage no mesmo disco está explicitamente documentado"
else
  fail "risco residual do storage local não foi documentado"
fi

if [[ -e deploy/interna/bacula/compose.yml ]]; then
  warn "compose Bacula já existe; esta fase deveria ser apenas arquitetura"
else
  ok "nenhum Compose Bacula foi antecipado antes do fechamento arquitetural"
fi

echo
echo "======================================================================"
echo " RESULTADO"
echo "======================================================================"
echo "Aprovações:   $OKS"
echo "Advertências: $WARN"
echo "Falhas:       $FAIL"

if (( FAIL > 0 )); then
  echo "CHECKPOINT ARQUITETURA PRÉ-BACULA: REPROVADO."
  echo "Relatório: $REPORT"
  exit 1
fi

if (( WARN > 0 )); then
  echo "CHECKPOINT ARQUITETURA PRÉ-BACULA: APROVADO COM ADVERTÊNCIAS."
else
  echo "CHECKPOINT ARQUITETURA PRÉ-BACULA: APROVADO."
fi

echo "Arquitetura pronta para iniciar a implementação do Bacula."
echo "Relatório: $REPORT"
