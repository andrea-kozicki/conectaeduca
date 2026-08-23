#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
export LANG=C

TARGET="all"
SCANNER="auto"
STRICT=0
INCLUDE_LAB=0
ROOT="${PROJECT_ROOT:-}"
TRIVY_CACHE_DIR="${CONECTAEDUCA_TRIVY_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/conectaeduca/trivy}"

usage() {
    cat <<'EOF'
Uso:
  inventariar_cve_containers.sh [opções]

Opções:
  --alvo all|dmz|interna   restringe a descoberta de imagens (padrão: all)
  --scanner auto|trivy|snyk|nenhum
                           scanner de vulnerabilidades (padrão: auto)
  --incluir-lab            inclui manifests com nome .lab./lab
  --estrito                erro de scanner torna o exit code não zero
  --ajuda                   mostra esta ajuda

O script é somente-leitura em relação ao repositório e às imagens do projeto:
não executa docker pull, docker build, docker compose up/down nem altera arquivos
versionados.
EOF
}

while (($#)); do
    case "$1" in
        --alvo)
            [[ $# -ge 2 ]] || { echo "ERRO: --alvo exige valor" >&2; exit 64; }
            TARGET="$2"; shift 2 ;;
        --scanner)
            [[ $# -ge 2 ]] || { echo "ERRO: --scanner exige valor" >&2; exit 64; }
            SCANNER="$2"; shift 2 ;;
        --incluir-lab)
            INCLUDE_LAB=1; shift ;;
        --estrito)
            STRICT=1; shift ;;
        --ajuda|-h)
            usage; exit 0 ;;
        *)
            echo "ERRO: opção desconhecida: $1" >&2
            usage >&2
            exit 64 ;;
    esac
done

case "$TARGET" in all|dmz|interna) ;; *) echo "ERRO: alvo inválido: $TARGET" >&2; exit 64 ;; esac
case "$SCANNER" in auto|trivy|snyk|nenhum) ;; *) echo "ERRO: scanner inválido: $SCANNER" >&2; exit 64 ;; esac

if [[ -z "$ROOT" ]]; then
    ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$ROOT" || ! -d "$ROOT/.git" ]]; then
    echo "ERRO: execute dentro do repositório ConectaEduca ou defina PROJECT_ROOT." >&2
    exit 1
fi

for cmd in git docker python3 find sort sha256sum stat id awk sed; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "ERRO: comando obrigatório ausente: $cmd" >&2
        exit 1
    }
done

docker info >/dev/null 2>&1 || {
    echo "ERRO: Docker Engine indisponível." >&2
    exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${CONECTAEDUCA_OUTPUT_DIR:-$HOME/Downloads}"
WORK_DIR="$OUT_DIR/conectaeduca-cve-reports-$STAMP"
OUT="$OUT_DIR/conectaeduca-inventario-cve-containers-$STAMP.txt"
INDEX="$WORK_DIR/images.tsv"
BEFORE="$WORK_DIR/git-before.txt"
AFTER="$WORK_DIR/git-after.txt"
mkdir -p "$WORK_DIR"
chmod 700 "$WORK_DIR"
: > "$INDEX"

cd "$ROOT"
git status --porcelain=v1 > "$BEFORE"
exec > >(tee "$OUT") 2>&1

section() {
    printf '\n============================================================\n%s\n============================================================\n' "$1"
}
warn() { echo "ADVERTENCIA: $*" >&2; }

section "CONECTAEDUCA - INVENTARIO REUTILIZAVEL DE CVEs"
echo "data=$(date --iso-8601=seconds)"
echo "root=$ROOT"
echo "branch=$(git branch --show-current)"
echo "head=$(git rev-parse HEAD)"
echo "alvo=$TARGET"
echo "scanner_solicitado=$SCANNER"
echo "include_lab=$INCLUDE_LAB"
echo "saida=$OUT"
echo "reports=$WORK_DIR"

section "1. DESCOBERTA DECLARATIVA DE IMAGENS"

MANIFEST_LIST="$WORK_DIR/manifests.txt"
IMAGE_LIST="$WORK_DIR/images.txt"

python3 - "$ROOT" "$TARGET" "$INCLUDE_LAB" "$MANIFEST_LIST" "$IMAGE_LIST" <<'PY'
from pathlib import Path
import os, re, sys

root = Path(sys.argv[1])
target = sys.argv[2]
include_lab = sys.argv[3] == "1"
manifest_out = Path(sys.argv[4])
image_out = Path(sys.argv[5])

bases = []
if target in {"all", "dmz"}:
    bases.append(root / "deploy" / "dmz")
if target in {"all", "interna"}:
    bases.append(root / "deploy" / "interna")

files = []
for base in bases:
    if not base.exists():
        continue
    for pat in ("compose*.yml", "compose*.yaml", "*.compose.yml", "*.compose.yaml"):
        files.extend(base.rglob(pat))

# Bootstrap Wazuh usa manifesto próprio fora do padrão compose*.yml.
if target in {"all", "interna"}:
    certgen = root / "deploy" / "interna" / "wazuh" / "generate-indexer-certs.yml"
    if certgen.exists():
        files.append(certgen)

def is_lab(path: Path) -> bool:
    rel = str(path.relative_to(root)).lower()
    name = path.name.lower()
    # No Bacula, compose.yml é o laboratório histórico; compose.vm.yml é a
    # variante final sem File Daemon containerizado.
    bacula_lab_compose = (
        rel == "deploy/interna/bacula/compose.yml"
        and (root / "deploy/interna/bacula/compose.vm.yml").exists()
    )
    return (
        "/lab/" in rel
        or ".lab." in name
        or name.startswith("compose.lab")
        or "filedaemon-lab" in rel
        or bacula_lab_compose
    )

def resolve_expr(value: str):
    value = value.strip().strip('"').strip("'")
    # ${VAR:-default} / ${VAR-default}
    m = re.fullmatch(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?:(:-|-)(.*))?\}", value)
    if m:
        var, _, default = m.groups()
        current = os.environ.get(var, "")
        if current:
            return current
        return (default or "").strip()
    return value

images = set()
kept_files = []
for path in sorted(set(files)):
    if not include_lab and is_lab(path):
        continue
    kept_files.append(path)
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    for raw in text.splitlines():
        m = re.match(r"^\s*image\s*:\s*(.*?)\s*$", raw)
        if not m:
            continue
        value = m.group(1)
        if " #" in value:
            value = value.split(" #", 1)[0].rstrip()
        value = resolve_expr(value)
        if not value or "$" in value:
            continue
        low = value.lower()
        if not include_lab and any(x in low for x in ("mailpit", "filedaemon-lab")):
            continue
        images.add(value)

manifest_out.write_text(
    "".join(str(p.relative_to(root)) + "\n" for p in kept_files),
    encoding="utf-8",
)
image_out.write_text(
    "".join(x + "\n" for x in sorted(images)),
    encoding="utf-8",
)
PY

if [[ ! -s "$IMAGE_LIST" ]]; then
    echo "ERRO: nenhuma referência image: foi descoberta nos manifests selecionados." >&2
    exit 1
fi

echo "manifests_considerados=$(wc -l < "$MANIFEST_LIST")"
echo "imagens_declaradas=$(wc -l < "$IMAGE_LIST")"
sed 's/^/IMAGE_DECLARADA=/' "$IMAGE_LIST"

section "2. ESCOLHA DO SCANNER"

SCANNER_EFFECTIVE="nenhum"
TRIVY_MODE=""
TRIVY_CONTAINER_USED=0

if [[ "$SCANNER" == "auto" || "$SCANNER" == "trivy" ]]; then
    if command -v trivy >/dev/null 2>&1; then
        SCANNER_EFFECTIVE="trivy"
        TRIVY_MODE="local"
    elif docker image inspect aquasec/trivy:0.73.0 >/dev/null 2>&1; then
        SCANNER_EFFECTIVE="trivy"
        TRIVY_MODE="container"
        mkdir -p "$TRIVY_CACHE_DIR"
        chmod 700 "$TRIVY_CACHE_DIR"
    elif [[ "$SCANNER" == "trivy" ]]; then
        echo "ERRO: Trivy não está instalado e aquasec/trivy:0.73.0 não está localmente disponível." >&2
        exit 1
    fi
fi

if [[ "$SCANNER_EFFECTIVE" == "nenhum" && ( "$SCANNER" == "auto" || "$SCANNER" == "snyk" ) ]]; then
    if command -v snyk >/dev/null 2>&1; then
        SCANNER_EFFECTIVE="snyk"
    elif [[ "$SCANNER" == "snyk" ]]; then
        echo "ERRO: Snyk CLI não está disponível." >&2
        exit 1
    fi
fi

if [[ "$SCANNER" == "nenhum" ]]; then
    SCANNER_EFFECTIVE="nenhum"
fi

echo "scanner_efetivo=$SCANNER_EFFECTIVE"
[[ -z "$TRIVY_MODE" ]] || echo "trivy_mode=$TRIVY_MODE"
[[ "$TRIVY_MODE" != "container" ]] || echo "trivy_cache_dir=$TRIVY_CACHE_DIR"

trivy_container() {
    TRIVY_CONTAINER_USED=1
    local socket_gid
    socket_gid="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo 0)"
    docker run --rm \
        --user "$(id -u):$(id -g)" \
        --group-add "$socket_gid" \
        -e HOME=/tmp \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$WORK_DIR:/reports" \
        -v "$TRIVY_CACHE_DIR:/trivy-cache" \
        aquasec/trivy:0.73.0 \
        --cache-dir /trivy-cache \
        "$@"
}

section "3. METADADOS E SCAN POR IMAGEM"

SCAN_FAILURES=0
LOCAL_MISSING=0
ANALYZED=0

while IFS= read -r image; do
    [[ -n "$image" ]] || continue
    key="$(printf '%s' "$image" | sha256sum | awk '{print substr($1,1,16)}')"
    status="LOCAL_OK"
    scan_status="NAO_EXECUTADO"
    scanner_rc=0

    if docker image inspect "$image" >/dev/null 2>&1; then
        image_id="$(docker image inspect --format '{{.Id}}' "$image")"
        size="$(docker image inspect --format '{{.Size}}' "$image")"
        user="$(docker image inspect --format '{{.Config.User}}' "$image")"
        created="$(docker image inspect --format '{{.Created}}' "$image")"
        digests="$(docker image inspect --format '{{range .RepoDigests}}{{printf "%s;" .}}{{end}}' "$image" 2>/dev/null || true)"
        [[ -n "$user" ]] || user="<vazio>=root"
        echo "IMAGE=$image"
        echo "  local=SIM"
        echo "  id=$image_id"
        echo "  created=$created"
        echo "  size_bytes=$size"
        echo "  default_user=$user"
        echo "  repodigests=${digests:-SEM_REPODIGEST_LOCAL}"
        ANALYZED=$((ANALYZED + 1))
    else
        status="AUSENTE_LOCALMENTE"
        image_id=""
        size="0"
        user=""
        digests=""
        LOCAL_MISSING=$((LOCAL_MISSING + 1))
        echo "IMAGE=$image"
        echo "  local=NAO"
    fi

    if [[ "$status" == "LOCAL_OK" && "$SCANNER_EFFECTIVE" != "nenhum" ]]; then
        json="$WORK_DIR/$key.json"
        err="$WORK_DIR/$key.err"
        set +e
        if [[ "$SCANNER_EFFECTIVE" == "trivy" ]]; then
            if [[ "$TRIVY_MODE" == "local" ]]; then
                trivy image --quiet --timeout 20m --scanners vuln --format json --output "$json" --exit-code 0 "$image" 2>"$err"
                scanner_rc=$?
            else
                trivy_container image --quiet --timeout 20m --scanners vuln --format json --output "/reports/$key.json" --exit-code 0 "$image" 2>"$err"
                scanner_rc=$?
            fi
        else
            snyk container test "$image" --platform=linux/amd64 --json >"$json" 2>"$err"
            scanner_rc=$?
        fi
        set -e

        if [[ "$SCANNER_EFFECTIVE" == "snyk" && "$scanner_rc" -le 1 && -s "$json" ]]; then
            scan_status="OK"
        elif [[ "$SCANNER_EFFECTIVE" == "trivy" && "$scanner_rc" -eq 0 && -s "$json" ]]; then
            scan_status="OK"
        else
            scan_status="ERRO"
            SCAN_FAILURES=$((SCAN_FAILURES + 1))
            warn "scanner falhou para $image (rc=$scanner_rc)"
        fi
    elif [[ "$status" != "LOCAL_OK" ]]; then
        scan_status="PULADO_IMAGEM_AUSENTE"
    else
        scan_status="PULADO_SEM_SCANNER"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$key" "$image" "$status" "$scan_status" "$scanner_rc" \
        "$user" "$size" "$image_id" "${digests:-}" >> "$INDEX"
done < "$IMAGE_LIST"

section "4. RESUMO NORMALIZADO"

python3 - "$WORK_DIR" "$INDEX" "$SCANNER_EFFECTIVE" <<'PY'
from collections import Counter, defaultdict
from pathlib import Path
import csv, json, sys

root = Path(sys.argv[1])
index = Path(sys.argv[2])
scanner = sys.argv[3]

SEV = ("CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN")
global_unique = defaultdict(set)
global_fixable = defaultdict(set)

def parse_trivy(data):
    vulns = []
    for result in data.get("Results") or []:
        vulns.extend(result.get("Vulnerabilities") or [])
    for v in vulns:
        yield (
            (v.get("Severity") or "UNKNOWN").upper(),
            v.get("VulnerabilityID") or "UNKNOWN",
            bool(str(v.get("FixedVersion") or "").strip()),
        )

def parse_snyk(data):
    if isinstance(data, list):
        items = []
        for obj in data:
            items.extend(obj.get("vulnerabilities") or [])
    else:
        items = data.get("vulnerabilities") or []
    for v in items:
        fixed = bool(v.get("isUpgradable") or v.get("isPatchable") or v.get("fixedIn"))
        yield (
            str(v.get("severity") or "unknown").upper(),
            str(v.get("id") or "UNKNOWN"),
            fixed,
        )

print("IMAGE|LOCAL|SCAN|CRITICAL|HIGH|MEDIUM|LOW|UNIQUE_IDS|FIXABLE_UNIQUE")
with index.open(encoding="utf-8", newline="") as f:
    for row in csv.reader(f, delimiter="\t"):
        key, image, local, scan, rc, user, size, image_id, digests = row
        counts = Counter()
        unique = defaultdict(set)
        fix = defaultdict(set)
        if scan == "OK":
            path = root / f"{key}.json"
            data = json.loads(path.read_text(encoding="utf-8"))
            parser = parse_trivy if scanner == "trivy" else parse_snyk
            for severity, vid, fixable in parser(data):
                if severity not in SEV:
                    severity = "UNKNOWN"
                counts[severity] += 1
                unique[severity].add(vid)
                global_unique[severity].add(vid)
                if fixable:
                    fix[severity].add(vid)
                    global_fixable[severity].add(vid)
        unique_total = len(set().union(*unique.values())) if unique else 0
        fix_total = len(set().union(*fix.values())) if fix else 0
        print(
            f"{image}|{local}|{scan}|{counts['CRITICAL']}|{counts['HIGH']}|"
            f"{counts['MEDIUM']}|{counts['LOW']}|{unique_total}|{fix_total}"
        )

print()
for sev in SEV:
    print(f"GLOBAL_{sev}_UNIQUE={len(global_unique[sev])}")
    print(f"GLOBAL_{sev}_FIXABLE_UNIQUE={len(global_fixable[sev])}")
PY

section "5. PROVA DE NAO ALTERACAO"

git status --porcelain=v1 > "$AFTER"
if cmp -s "$BEFORE" "$AFTER"; then
    echo "REPOSITORIO_ALTERADO_PELO_SCRIPT=NAO"
else
    echo "REPOSITORIO_ALTERADO_PELO_SCRIPT=SIM"
    warn "o status do Git mudou durante a execução"
fi

git diff --check
echo "IMAGENS_PUXADAS_PELO_SCRIPT=NAO"
echo "IMAGENS_REBUILDADAS_PELO_SCRIPT=NAO"
echo "CONTAINERS_DO_PROJETO_INICIADOS_OU_PARADOS=NAO"
if (( TRIVY_CONTAINER_USED == 1 )); then
    echo "TRIVY_CONTAINER_EFEMERO_EXECUTADO=SIM"
else
    echo "TRIVY_CONTAINER_EFEMERO_EXECUTADO=NAO"
fi

section "RESULTADO"
echo "IMAGENS_DECLARADAS=$(wc -l < "$IMAGE_LIST")"
echo "IMAGENS_LOCAIS_ANALISADAS=$ANALYZED"
echo "IMAGENS_AUSENTES_LOCALMENTE=$LOCAL_MISSING"
echo "SCAN_FAILURES=$SCAN_FAILURES"
echo "SCANNER_EFETIVO=$SCANNER_EFFECTIVE"
echo "ARQUIVO_SAIDA=$OUT"
echo "RELATORIOS_BRUTOS=$WORK_DIR"

if (( STRICT == 1 && SCAN_FAILURES > 0 )); then
    echo "INVENTARIO_CVE=REPROVADO_ERRO_SCANNER"
    exit 2
fi

echo "INVENTARIO_CVE=CONCLUIDO"
