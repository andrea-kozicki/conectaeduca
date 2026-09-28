#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEFAULT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
ROOT="${PROJECT_ROOT:-$DEFAULT_ROOT}"

[[ -d "$ROOT/deploy/interna/ferret" ]] || {
  echo "ERRO: raiz ConectaEduca inválida: $ROOT" >&2
  exit 1
}

cd "$ROOT"

RUNTIME="$ROOT/deploy/interna/ferret/.runtime"
SANITIZER="$ROOT/scripts/dlp/sanitizar_ferret.py"
PENTEST_PRINCIPAL_UID_FILE="/etc/conectaeduca/pentest-principal.uid"

# ACL é requisito estrutural do runtime Ferret, mesmo antes de existir contrato
# de pentest: a normalização remove ACLs/default ACLs residuais de todos os
# diretórios protegidos. Falhe antes de qualquer mutação se o host não tiver o
# pacote `acl` (setfacl/getfacl), em vez de quebrar no meio da materialização.
for acl_tool in setfacl getfacl; do
  command -v "$acl_tool" >/dev/null 2>&1 || {
    echo "ERRO: $acl_tool ausente; instale o pacote host 'acl' antes de preparar o Ferret." >&2
    exit 1
  }
done
echo "ACL_TOOLING=PASS setfacl=$(command -v setfacl) getfacl=$(command -v getfacl)"

# PENTEST_DLP_DROPZONE_ACL_V1
# O runtime operacional continua pertencendo ao UID/GID 1000 usado pela imagem
# Ferret. Quando o contrato root-owned do principal de pentest existir, somente
# a drop-zone recebe ACL nominal: traverse no pai e write+execute na inbox.
# State/reports/events permanecem fora do alcance do principal de pentest.
PENTEST_UID=""
if sudo test -f "$PENTEST_PRINCIPAL_UID_FILE"; then
  contract_meta="$(sudo stat -c '%u:%a' "$PENTEST_PRINCIPAL_UID_FILE")"
  contract_owner="${contract_meta%%:*}"
  contract_mode="${contract_meta##*:}"
  [[ "$contract_owner" == "0" ]] || {
    echo "ERRO: contrato de pentest não pertence a root." >&2
    exit 1
  }
  (( (8#$contract_mode & 8#022) == 0 )) || {
    echo "ERRO: contrato de pentest é gravável por group/other." >&2
    exit 1
  }

  PENTEST_UID="$(sudo cat "$PENTEST_PRINCIPAL_UID_FILE")"
  [[ "$PENTEST_UID" =~ ^[0-9]+$ && "$PENTEST_UID" -ne 0 && "$PENTEST_UID" -ne 1000 ]] || {
    echo "ERRO: UID inválido no contrato de pentest: $PENTEST_PRINCIPAL_UID_FILE" >&2
    exit 1
  }
fi

ROOT_REAL="$(cd -- "$ROOT" && pwd -P)"
GIT_TOP=""
GIT_TOP_REAL=""
if command -v git >/dev/null 2>&1; then
  GIT_TOP="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$GIT_TOP" ]]; then
    GIT_TOP_REAL="$(cd -- "$GIT_TOP" && pwd -P)" || GIT_TOP_REAL=""
  fi
fi

if [[ -n "$GIT_TOP_REAL" && "$GIT_TOP_REAL" == "$ROOT_REAL" ]]; then
  git -C "$ROOT" check-ignore -q "deploy/interna/ferret/.runtime/prova-ignore" 2>/dev/null || {
    echo "ERRO: runtime Ferret não coberto pelo .gitignore." >&2
    exit 1
  }
else
  META="$ROOT/RELEASE-METADATA.txt"
  [[ -f "$META" ]] || {
    echo "ERRO: execução fora de Git exige RELEASE-METADATA.txt." >&2
    exit 1
  }
  grep -Fxq 'runtime_secrets_included=no' "$META" || {
    echo "ERRO: metadata não comprova exclusão de runtime secrets." >&2
    exit 1
  }
fi

[[ -f "$SANITIZER" ]] || {
  echo "ERRO: sanitizador ausente." >&2
  exit 1
}

chmod 0755 "$SANITIZER"

sudo install -d -o 1000 -g 1000 -m 0700 \
  "$RUNTIME" \
  "$RUNTIME/state" \
  "$RUNTIME/state/incoming" \
  "$RUNTIME/inbox" \
  "$RUNTIME/reports" \
  "$RUNTIME/reports/raw" \
  "$RUNTIME/events"

# Normaliza primeiro os diretórios protegidos. chmod em diretório com ACL altera
# a mask; por isso a ACL da drop-zone é reaplicada abaixo de forma idempotente.
for dir in \
  "$RUNTIME/state" \
  "$RUNTIME/state/incoming" \
  "$RUNTIME/reports" \
  "$RUNTIME/reports/raw" \
  "$RUNTIME/events"
do
  sudo chown 1000:1000 "$dir"
  sudo chmod 0700 "$dir"
  sudo setfacl -b "$dir"
  sudo setfacl -k "$dir" 2>/dev/null || true
done

sudo chown 1000:1000 "$RUNTIME" "$RUNTIME/inbox"
sudo chmod 0700 "$RUNTIME" "$RUNTIME/inbox"
sudo setfacl -b "$RUNTIME" "$RUNTIME/inbox"
sudo setfacl -k "$RUNTIME" "$RUNTIME/inbox" 2>/dev/null || true

if [[ -n "$PENTEST_UID" ]]; then
  # Pai: somente traverse. Inbox: write+execute sem listagem.
  sudo setfacl -m "u:${PENTEST_UID}:--x,m::--x" "$RUNTIME"
  sudo setfacl -m "u:${PENTEST_UID}:-wx,m::-wx" "$RUNTIME/inbox"
  sudo chmod +t "$RUNTIME/inbox"

  # Arquivos novos criados pelo pentester devem continuar legíveis pelo
  # runtime UID1000 do Ferret, sem abrir group/other.
  sudo setfacl -m \
    "d:u::rwx,d:u:1000:r--,d:g::---,d:m::r--,d:o::---" \
    "$RUNTIME/inbox"
fi

for dir in "$RUNTIME/state" "$RUNTIME/state/incoming" "$RUNTIME/reports" "$RUNTIME/reports/raw" "$RUNTIME/events"
do
  meta="$(sudo stat -c '%u:%g %a' "$dir")"
  [[ "$meta" == "1000:1000 700" ]] || {
    echo "ERRO: metadata protegida inesperada em $dir: $meta" >&2
    exit 1
  }
done

# Nenhum diretório protegido pode conservar default ACL herdável. A inbox é a
# única exceção, porque sua default ACL é deliberada para os artefatos novos.
for dir in "$RUNTIME" "$RUNTIME/state" "$RUNTIME/state/incoming" "$RUNTIME/reports" "$RUNTIME/reports/raw" "$RUNTIME/events"
do
  if sudo getfacl -cpn "$dir" | grep -q '^default:'; then
    echo "ERRO: default ACL inesperada em diretório protegido: $dir" >&2
    exit 1
  fi
done

if [[ -n "$PENTEST_UID" ]]; then
  sudo getfacl -cpn "$RUNTIME" | grep -Fxq "user:${PENTEST_UID}:--x" || {
    echo "ERRO: ACL traverse do principal não materializada no runtime." >&2
    exit 1
  }
  sudo getfacl -cpn "$RUNTIME/inbox" | grep -Fxq "user:${PENTEST_UID}:-wx" || {
    echo "ERRO: ACL write+execute do principal não materializada na inbox." >&2
    exit 1
  }
  sudo getfacl -cpn "$RUNTIME/inbox" | grep -Fxq "default:user:1000:r--" || {
    echo "ERRO: default ACL de leitura do UID1000 ausente na inbox." >&2
    exit 1
  }
  inbox_mode="$(sudo stat -c '%a' "$RUNTIME/inbox")"
  [[ "$inbox_mode" == 1* ]] || {
    echo "ERRO: sticky bit ausente na inbox: mode=$inbox_mode" >&2
    exit 1
  }
  echo "OK: runtime Ferret protegido; drop-zone do pentest materializada por ACL mínima."
else
  meta_runtime="$(sudo stat -c '%u:%g %a' "$RUNTIME")"
  meta_inbox="$(sudo stat -c '%u:%g %a' "$RUNTIME/inbox")"
  [[ "$meta_runtime" == "1000:1000 700" && "$meta_inbox" == "1000:1000 700" ]] || {
    echo "ERRO: metadata base inesperada sem contrato de pentest." >&2
    exit 1
  }
  echo "OK: runtime Ferret 1000:1000/0700; contrato de pentest ainda não materializado."
fi

echo "OK: sanitizador 0755."
