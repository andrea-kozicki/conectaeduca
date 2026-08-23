#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
export LANG=C

STRICT=0
ROOT="${PROJECT_ROOT:-}"

usage() {
    cat <<'EOF'
Uso:
  inventariar_segredos_runtime.sh [--estrito]

Este diagnóstico registra apenas nomes, existência, permissões, UID/GID,
tamanho e mounts. Ele não lê conteúdo de .runtime, RoleID, SecretID,
senhas, root token ou shares de unseal.
EOF
}

while (($#)); do
    case "$1" in
        --estrito) STRICT=1; shift ;;
        --ajuda|-h) usage; exit 0 ;;
        *) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 64 ;;
    esac
done

if [[ -z "$ROOT" ]]; then
    ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$ROOT" || ! -d "$ROOT/.git" ]]; then
    echo "ERRO: execute dentro do repositório ConectaEduca ou defina PROJECT_ROOT." >&2
    exit 1
fi

for cmd in git stat find sort python3; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "ERRO: comando obrigatório ausente: $cmd" >&2
        exit 1
    }
done

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${CONECTAEDUCA_OUTPUT_DIR:-$HOME/Downloads}"
OUT="$OUT_DIR/conectaeduca-inventario-segredos-runtime-$STAMP.txt"
BEFORE="$(mktemp -t conectaeduca-secrets-before.XXXXXX)"
AFTER="$(mktemp -t conectaeduca-secrets-after.XXXXXX)"
trap 'rm -f "$BEFORE" "$AFTER"' EXIT

cd "$ROOT"
git status --porcelain=v1 > "$BEFORE"
exec > >(tee "$OUT") 2>&1

WARN=0
FAIL=0

section() {
    printf '\n============================================================\n%s\n============================================================\n' "$1"
}
ok() { echo "OK|$*"; }
warn() { echo "WARN|$*"; WARN=$((WARN+1)); }
fail() { echo "FALHA|$*"; FAIL=$((FAIL+1)); }

file_meta() {
    local label="$1"
    local path="$2"

    if [[ ! -e "$path" ]]; then
        echo "SECRET_META=$label|state=ABSENT|content=NOT_READ"
        return 0
    fi

    local mode uid gid size ignored="NA"
    mode="$(stat -c '%a' "$path" 2>/dev/null || echo '?')"
    uid="$(stat -c '%u' "$path" 2>/dev/null || echo '?')"
    gid="$(stat -c '%g' "$path" 2>/dev/null || echo '?')"
    size="$(stat -c '%s' "$path" 2>/dev/null || echo '?')"

    if [[ "$path" == "$ROOT/"* ]]; then
        rel="${path#"$ROOT/"}"
        git check-ignore -q -- "$rel" 2>/dev/null && ignored="SIM" || ignored="NAO"
    fi

    echo "SECRET_META=$label|state=PRESENT|mode=$mode|uid=$uid|gid=$gid|bytes=$size|ignored=$ignored|content=NOT_READ"
}

section "CONECTAEDUCA - INVENTARIO DE SEGREDOS DE RUNTIME"
echo "data=$(date --iso-8601=seconds)"
echo "root=$ROOT"
echo "branch=$(git branch --show-current)"
echo "head=$(git rev-parse HEAD)"
echo "strict=$STRICT"
echo "saida=$OUT"
echo "GARANTIA=CONTEUDO_DE_SEGREDOS_NAO_LIDO"

section "1. ARTEFATOS EFEMEROS / APPROLE"
file_meta "openbao_root_token_temporario" "/dev/shm/conectaeduca-openbao-initial-root-token"
file_meta "smtp_password_shm" "/dev/shm/conectaeduca-smtp-password"
file_meta "smtp_role_id" "$ROOT/deploy/interna/openbao/.runtime/smtp/role-id"
file_meta "smtp_secret_id" "$ROOT/deploy/interna/openbao/.runtime/smtp/secret-id"
file_meta "bacula_snapshot_role_id" "$ROOT/deploy/interna/openbao/.runtime/bacula-snapshot/role-id"
file_meta "bacula_snapshot_secret_id" "$ROOT/deploy/interna/openbao/.runtime/bacula-snapshot/secret-id"

section "2. DIRETORIOS .runtime - METADADOS SOMENTE"
RUNTIME_DIRS=(
    deploy/dmz/.runtime
    deploy/interna/mariadb/.runtime
    deploy/interna/openbao/.runtime
    deploy/interna/ferret/.runtime
    deploy/interna/wazuh/.runtime
    deploy/interna/bacula/.runtime
)

for rel in "${RUNTIME_DIRS[@]}"; do
    dir="$ROOT/$rel"
    if [[ ! -d "$dir" ]]; then
        echo "RUNTIME_DIR=$rel|state=ABSENT"
        continue
    fi

    dmode="$(stat -c '%a' "$dir" 2>/dev/null || echo '?')"
    echo "RUNTIME_DIR=$rel|state=PRESENT|mode=$dmode"

    if [[ "$dmode" =~ ^[0-7]{3,4}$ ]]; then
        dperm=$((8#$dmode))
        if (( (dperm & 077) != 0 )); then
            fail "diretório runtime acessível por group/other: $rel mode=$dmode"
        fi
    else
        warn "não foi possível interpretar mode do diretório $rel"
    fi

    while IFS= read -r -d '' path; do
        file_rel="${path#"$ROOT/"}"
        mode="$(stat -c '%a' "$path" 2>/dev/null || echo '?')"
        uid="$(stat -c '%u' "$path" 2>/dev/null || echo '?')"
        gid="$(stat -c '%g' "$path" 2>/dev/null || echo '?')"
        size="$(stat -c '%s' "$path" 2>/dev/null || echo '?')"
        ignored="NAO"
        git check-ignore -q -- "$file_rel" 2>/dev/null && ignored="SIM"

        echo "RUNTIME_FILE=$file_rel|mode=$mode|uid=$uid|gid=$gid|bytes=$size|ignored=$ignored|content=NOT_READ"

        if [[ "$ignored" != "SIM" ]]; then
            fail "runtime não ignorado pelo Git: $file_rel"
        fi

        if [[ "$mode" =~ ^[0-7]{3,4}$ ]]; then
            # Proíbe qualquer permissão para group/other. 0400/0600 são o
            # caso comum; owner executable não é tratado como exposição.
            perm=$((8#$mode))
            if (( (perm & 077) != 0 )); then
                fail "runtime acessível por group/other: $file_rel mode=$mode"
            fi
        else
            warn "não foi possível interpretar mode de $file_rel"
        fi
    done < <(find "$dir" -type f -print0 2>/dev/null | sort -z)
done

section "3. ARQUIVOS SENSIVEIS RASTREADOS"
TRACKED_FILE="$(mktemp -t conectaeduca-tracked-sensitive.XXXXXX)"
trap 'rm -f "$BEFORE" "$AFTER" "$TRACKED_FILE"' EXIT

git ls-files \
    | grep -Ei '(^|/)\.runtime/|(^|/)\.env$|unseal-share|root-token|(^|/)(role-id|secret-id)$|\.(pem|key|p12|pfx|jks)$' \
    | grep -vE '\.example$|\.md$|(^|/)policies?/|checkpoint_|README' \
    > "$TRACKED_FILE" || true

if [[ -s "$TRACKED_FILE" ]]; then
    fail "há candidatos sensíveis rastreados"
    sed 's/^/TRACKED_SENSITIVE=/' "$TRACKED_FILE"
else
    ok "nenhum runtime/credencial/chave privada real rastreado"
fi

section "4. CONTAINERS - SEM ENVIRONMENT VALUES"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        state="$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || true)"
        image="$(docker inspect -f '{{.Config.Image}}' "$name" 2>/dev/null || true)"
        user="$(docker inspect -f '{{.Config.User}}' "$name" 2>/dev/null || true)"
        restart="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$name" 2>/dev/null || true)"
        echo "CONTAINER_META=name=$name|state=${state:-?}|image=${image:-?}|user=${user:-default}|restart=${restart:-?}"
        docker inspect "$name" \
            --format '{{range .Mounts}}{{println "type=" .Type "|dst=" .Destination "|rw=" .RW}}{{end}}' \
            2>/dev/null \
            | sed "s/^/CONTAINER_MOUNT=name=$name|/" || true
    done < <(
        docker ps -a --filter 'name=conectaeduca' --format '{{.Names}}' | sort -u
    )
    echo "CONTAINER_ENV_VALUES_READ=NAO"
else
    warn "Docker indisponível; inventário de mounts foi pulado"
fi

section "5. NOMES DE VARIAVEIS E PLACEHOLDERS VERSIONADOS"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import re, subprocess, sys

root = Path(sys.argv[1])
tracked = subprocess.check_output(["git", "-C", str(root), "ls-files"], text=True).splitlines()
prefixes = ("deploy/", "scripts/")
env_names = set()
placeholders = set()

for rel in tracked:
    if not rel.startswith(prefixes):
        continue
    path = root / rel
    if not path.is_file():
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    env_names.update(re.findall(r"\$\{([A-Z][A-Z0-9_]*)", text))
    placeholders.update(re.findall(r"__(?:RUNTIME_)?SECRET_[A-Z0-9_]+__", text))

print(f"ENV_VARIABLE_NAMES={len(env_names)}")
for name in sorted(env_names):
    print(f"ENV_NAME={name}")
print(f"SECRET_PLACEHOLDERS={len(placeholders)}")
for name in sorted(placeholders):
    print(f"PLACEHOLDER={name}")
PY
echo "VARIABLE_VALUES_READ=NAO"

section "6. PROVA DE NAO ALTERACAO"
git status --porcelain=v1 > "$AFTER"
if cmp -s "$BEFORE" "$AFTER"; then
    ok "status Git permaneceu idêntico"
    echo "GIT_MODIFICADO_PELO_SCRIPT=NAO"
else
    fail "status Git mudou durante o inventário"
    echo "GIT_MODIFICADO_PELO_SCRIPT=SIM"
fi
git diff --check

section "RESULTADO"
echo "SEGREDOS_LIDOS_PELO_SCRIPT=NAO"
echo "WARNINGS=$WARN"
echo "FALHAS=$FAIL"
echo "ARQUIVO_SAIDA=$OUT"

if (( FAIL > 0 )); then
    echo "INVENTARIO_SEGREDOS_RUNTIME=REPROVADO"
    exit 1
fi
if (( STRICT == 1 && WARN > 0 )); then
    echo "INVENTARIO_SEGREDOS_RUNTIME=APROVADO_COM_ADVERTENCIAS_ESTRICTO"
    exit 2
fi
echo "INVENTARIO_SEGREDOS_RUNTIME=APROVADO"
