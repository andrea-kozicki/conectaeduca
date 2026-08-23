#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/srv/www/htdocs/conectaeduca"
OUT="$HOME/Downloads/conectaeduca-checkpoint-openbao-bacula-readiness-$(date +%Y%m%d-%H%M%S).txt"
OPENBAO_CONTAINER="conectaeduca-openbao"
OPENBAO_API="http://127.0.0.1:18200/v1"
APPROLE_DIR="$ROOT/deploy/interna/openbao/.runtime/bacula-snapshot"
ROLE_FILE="$APPROLE_DIR/role-id"
SECRET_FILE="$APPROLE_DIR/secret-id"
POLICY_FILE="$ROOT/deploy/interna/openbao/policies/bacula-snapshot.hcl"

cd "$ROOT"
exec > >(tee "$OUT") 2>&1

pass=0
pending=0
fail=0
ok(){ echo "OK       $*"; pass=$((pass+1)); }
pend(){ echo "PENDENTE $*"; pending=$((pending+1)); }
bad(){ echo "FALHA    $*"; fail=$((fail+1)); }

echo "======================================================================"
echo " CHECKPOINT OPENBAO RAFT -> BACULA - READINESS 2.1"
echo "======================================================================"

[[ "$(git branch --show-current)" == "main" ]] && ok "branch main" || bad "branch inesperada; esperado main"
git diff --check >/dev/null && ok "git diff --check" || bad "git diff --check"

state="$(docker inspect -f '{{.State.Status}}' "$OPENBAO_CONTAINER" 2>/dev/null || true)"
[[ "$state" == "running" ]] && ok "OpenBao container running" || bad "OpenBao container não está running"

STATUS_JSON="$(
    docker exec \
        -e BAO_ADDR=http://127.0.0.1:8200 \
        "$OPENBAO_CONTAINER" \
        bao status -format=json \
        2>/dev/null || true
)"

if [[ -n "$STATUS_JSON" ]]; then
    if python3 - "$STATUS_JSON" <<'PY'
import json,sys
x=json.loads(sys.argv[1])
print("OPENBAO_STATUS=initialized=%s|sealed=%s|version=%s|storage_type=%s" % (
    x.get("initialized"),
    x.get("sealed"),
    x.get("version"),
    x.get("storage_type"),
))
raise SystemExit(
    0 if x.get("initialized") is True
    and x.get("sealed") is False
    and x.get("storage_type") == "raft"
    else 1
)
PY
    then
        ok "OpenBao initialized + unsealed + Raft"
    else
        bad "bao status não confirmou initialized/unsealed/raft"
    fi
else
    bad "bao status JSON indisponível"
fi

for item in \
    "director:conectaeduca-bacula-director" \
    "storage:conectaeduca-bacula-storage" \
    "catalog:conectaeduca-bacula-catalog"
do
    label="${item%%:*}"
    container="${item#*:}"
    s="$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || true)"
    [[ "$s" == "running" ]] && ok "Bacula $label running" || bad "Bacula $label não está running"
done

if [[ -s "$POLICY_FILE" ]]; then
    ok "policy bacula-snapshot existe"
    if grep -Eq 'path[[:space:]]+"sys/storage/raft/snapshot"' "$POLICY_FILE" \
       && grep -Eq '"read"' "$POLICY_FILE"; then
        ok "policy snapshot Raft é mínima"
    else
        pend "policy existe, mas contrato mínimo não foi confirmado"
    fi
else
    pend "policy bacula-snapshot ainda não está materializada"
fi

approle_ready=1
for f in "$ROLE_FILE" "$SECRET_FILE"; do
    if [[ -s "$f" ]]; then
        mode="$(stat -c '%a' "$f" 2>/dev/null || true)"
        ignored="NAO"
        git check-ignore -q "$f" 2>/dev/null && ignored="SIM"
        echo "APPROLE_FILE=$(basename "$f")|mode=$mode|ignored=$ignored|conteudo=OCULTO"
        [[ "$mode" == "600" && "$ignored" == "SIM" ]] || approle_ready=0
    else
        approle_ready=0
    fi
done

if (( approle_ready == 1 )); then
    ok "AppRole bacula-snapshot pronta, 0600 e ignorada"
else
    pend "AppRole bacula-snapshot ainda não está pronta"
fi

if (( approle_ready == 1 )); then
    set +e
    SNAP="$(
        python3 - "$OPENBAO_API" "$ROLE_FILE" "$SECRET_FILE" <<'PY'
import hashlib,json,os,pathlib,sys,tempfile,urllib.request

base=sys.argv[1].rstrip("/")
role=pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").strip()
secret=pathlib.Path(sys.argv[3]).read_text(encoding="utf-8").strip()

def req(method,path,payload=None,token=None,raw=False):
    data=None if payload is None else json.dumps(payload).encode()
    headers={"Content-Type":"application/json"}
    if token:
        headers["X-Vault-Token"]=token
    q=urllib.request.Request(base+path,data=data,headers=headers,method=method)
    with urllib.request.urlopen(q,timeout=15) as r:
        body=r.read()
        return r.status, body if raw else (json.loads(body) if body else {})

token=None
tmp=None
try:
    _,login=req("POST","/auth/approle/login",{"role_id":role,"secret_id":secret})
    token=login.get("auth",{}).get("client_token")
    if not token:
        raise RuntimeError("login AppRole sem token")
    code,blob=req("GET","/sys/storage/raft/snapshot",token=token,raw=True)
    if code != 200 or len(blob) < 128:
        raise RuntimeError("snapshot inválido")
    fd,tmp=tempfile.mkstemp(prefix="conectaeduca-raft-",suffix=".snap",dir="/dev/shm")
    os.close(fd)
    pathlib.Path(tmp).write_bytes(blob)
    print(f"SNAPSHOT_BYTES={len(blob)}")
    print(f"SNAPSHOT_SHA256={hashlib.sha256(blob).hexdigest()}")
    print("SNAPSHOT_TOKEN=OCULTO")
finally:
    if token:
        try:
            req("POST","/auth/token/revoke-self",{},token=token)
        except Exception:
            pass
    if tmp:
        pathlib.Path(tmp).unlink(missing_ok=True)
PY
    )"
    rc=$?
    set -e

    if [[ $rc -eq 0 ]]; then
        printf '%s\n' "$SNAP"
        ok "snapshot Raft via AppRole funcionou e temporário foi removido"
    else
        pend "AppRole existe, mas snapshot Raft ainda não passou"
    fi
else
    pend "snapshot não testado porque AppRole ainda não está pronta"
fi

if grep -RIlE \
    'openbao.*raft|raft.*openbao|openbao-raft\.snap|sys/storage/raft/snapshot' \
    deploy/interna/bacula scripts \
    --exclude='checkpoint_bacula_openbao_raft.sh' \
    --exclude='checkpoint_openbao_bacula_readiness.sh' \
    2>/dev/null | grep -q .
then
    ok "há gancho versionado Bacula/OpenBao Raft"
else
    pend "gancho Bacula/OpenBao Raft ainda não está versionado"
fi

echo "Aprovacoes=$pass"
echo "Pendencias=$pending"
echo "Falhas=$fail"

if (( fail > 0 )); then
    echo "OPENBAO_BACULA_READINESS=FALHA"
elif (( pending > 0 )); then
    echo "OPENBAO_BACULA_READINESS=PENDENTE"
else
    echo "OPENBAO_BACULA_READINESS=APROVADO"
fi

echo "ARQUIVO_SAIDA=$OUT"
if (( fail > 0 )); then
    exit 1
fi
exit 0
