#!/usr/bin/env bash
set -euo pipefail
# SOMENTE LEITURA — nao executa docker load, pull, compose up ou sudo.
# Requer TAR local aprovado e imagem ja importada na engine institucional.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
IMAGE='localhost/conectaeduca/ferret-scan:2.4.3-pa07-v5-candidate'
BASE="$ROOT/deploy/interna/ferret/compose.yml"
OVERLAY="$ROOT/deploy/interna/ferret/pa07-v5/compose.pa07-v5.override.yml"
POLICY="$ROOT/scripts/evidencias/ga06_validar_politica_tar.py"
PROVENANCE="$ROOT/scripts/evidencias/ga06_validar_proveniencia_offline.py"

usage() {
  printf '%s\n' 'Uso: bash scripts/evidencias/ga06_preflight_tar_local.sh --archive /caminho/privado/arquivo.tar'
  printf '%s\n' 'Somente leitura; nao faz docker load nem implantacao.'
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage; exit 0; fi
if [[ "$#" -ne 2 || "$1" != "--archive" ]]; then usage >&2; exit 2; fi
ARCHIVE="$2"
if [[ ! -f "$ARCHIVE" || -L "$ARCHIVE" ]]; then
  echo 'GA06_PREFLIGHT=FAIL motivo=TAR_ausente_ou_symlink' >&2; exit 1
fi
for name in python3 docker; do
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "GA06_PREFLIGHT=FAIL motivo=dependencia_ausente_$name" >&2; exit 1
  fi
done
python3 "$POLICY" || { echo 'GA06_PREFLIGHT=FAIL motivo=politica' >&2; exit 1; }

# Diretório privado efemero: docker inspect pode incluir variaveis sensiveis.
umask 077
WORK="$(mktemp -d)"
chmod 0700 "$WORK"
cleanup() {
  if [[ -n "${WORK:-}" && -d "$WORK" ]]; then rm -rf -- "$WORK"; fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if ! docker image inspect "$IMAGE" > "$WORK/image.json" 2>/dev/null; then
  echo 'GA06_PREFLIGHT=FAIL motivo=imagem_local_ausente' >&2
  exit 1
fi
if ! python3 "$PROVENANCE" --archive "$ARCHIVE" --inspect-json "$WORK/image.json"; then
  echo 'GA06_PREFLIGHT=FAIL motivo=custodia_TAR_ou_Docker' >&2
  exit 1
fi

# Canonicaliza a configuracao SOMENTE em JSON privado; nao exibe variaveis.
if ! docker compose -f "$BASE" config --format json > "$WORK/base.json" 2>/dev/null; then
  echo 'GA06_PREFLIGHT=FAIL motivo=config_base_invalida' >&2; exit 1
fi
if ! docker compose -f "$BASE" -f "$OVERLAY" config --format json > "$WORK/candidate.json" 2>/dev/null; then
  echo 'GA06_PREFLIGHT=FAIL motivo=config_override_invalida' >&2; exit 1
fi
if ! python3 - "$WORK/base.json" "$WORK/candidate.json" "$IMAGE" <<'PY'
import json,sys
with open(sys.argv[1],encoding='utf-8') as f:
    base=json.load(f)
with open(sys.argv[2],encoding='utf-8') as f:
    candidate=json.load(f)
tag=sys.argv[3]
a=base.get('services',{}).get('ferret',{})
b=candidate.get('services',{}).get('ferret',{})
def require(ok):
    if not ok: raise SystemExit(2)
require(isinstance(a,dict) and isinstance(b,dict))
require(a.get('image','').startswith('public.ecr.aws/awslabs/ferret-scan:2.4.3@sha256:'))
require(b.get('image')==tag and b.get('pull_policy')=='never')
require(a.get('read_only') is True and b.get('read_only') is True)
require(sorted(a.get('cap_drop',[]))==['ALL'])
for cfg in (a,b):
    cfg.pop('image',None)
    cfg.pop('pull_policy',None)
require(a==b)
base['services']['ferret']=a
candidate['services']['ferret']=b
require(base==candidate)
PY
then
  echo 'GA06_PREFLIGHT=FAIL motivo=compose_divergente' >&2; exit 1
fi

echo 'GA06_PREFLIGHT=PASS'
echo 'GA06_TAR_INTEGRITY=PASS'
echo 'GA06_IMAGE_ID_AND_ROOTFS=PASS'
echo 'GA06_COMPOSE_ONLY_IMAGE_AND_PULL_POLICY_CHANGED=PASS'
echo 'GA06_INSTITUTIONAL_DEPLOY_APPROVAL=PENDENTE'
echo 'GA06_SERVICE_CHANGED=NAO'
