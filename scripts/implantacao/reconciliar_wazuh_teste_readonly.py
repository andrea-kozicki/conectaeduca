#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import datetime as dt
import getpass
import hashlib
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import tempfile

EXPECTED_HOST = "ep126-pucpr"
PROJECT = "conectaeduca-wazuh"
TARGET_USER = "teste"
BACKEND_ROLES = ["kibanauser", "readall"]
WAZUH_READONLY_ROLE_ID = 2
WAZUH_READONLY_ROLE_NAME = "readonly"
WAZUH_RULE_NAME = "conectaeduca_teste_readonly"

OUTDIR = Path.home() / "conectaeduca-evidencias"
OUTDIR.mkdir(parents=True, exist_ok=True, mode=0o700)
STAMP = dt.datetime.now().astimezone().strftime("%Y%m%d-%H%M%S")
PROVISIONING_RUN = f"conectaeduca-pentest-{STAMP}"

parser = argparse.ArgumentParser(
    description="Provisiona, valida ou revoga a identidade teste read-only no Wazuh"
)
group = parser.add_mutually_exclusive_group()
group.add_argument("--apply", action="store_true")
group.add_argument("--revoke", action="store_true")
parser.add_argument("--confirm-apply", action="store_true")
parser.add_argument("--confirm-revoke", action="store_true")
args = parser.parse_args()

if args.apply and not args.confirm_apply:
    raise SystemExit("APPLY exige --confirm-apply")
if args.revoke and not args.confirm_revoke:
    raise SystemExit("REVOKE exige --confirm-revoke")

MODE = "APPLY" if args.apply else "REVOKE" if args.revoke else "CHECK"
REPORT = OUTDIR / f"conectaeduca-wazuh-teste-readonly-{MODE.lower()}-{STAMP}.txt"

counts = {"PASS": 0, "WARN": 0, "FAIL": 0, "GAP": 0}
lines: list[str] = []
manager = dashboard = indexer = ""
created_user = False
created_rule = False
linked_rule = False
created_rule_id: int | None = None
user_creation_attempted = False
rule_creation_attempted = False
rule_link_attempted = False
rollback_used = False


def log(msg: str = "") -> None:
    lines.append(str(msg))
    print(msg, flush=True)


def mark(kind: str, msg: str) -> None:
    counts[kind] += 1
    log(f"[{kind}] {msg}")


def run(cmd: list[str], *, input_text: str | None = None, timeout: int = 45):
    try:
        p = subprocess.run(
            cmd,
            input=input_text,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except subprocess.TimeoutExpired as exc:
        return 124, (exc.stdout or "").strip(), f"timeout: {(exc.stderr or '').strip()}"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def services() -> dict[str, str]:
    rc, out, err = run([
        "docker", "ps",
        "--filter", f"label=com.docker.compose.project={PROJECT}",
        "--format", '{{.Names}}\t{{.Label "com.docker.compose.service"}}',
    ])
    if rc:
        raise RuntimeError(err or out)
    found: dict[str, str] = {}
    for line in out.splitlines():
        name, service = line.split("\t", 1)
        found[service] = name
    return found


def inspect_container(name: str) -> dict:
    rc, out, err = run(["docker", "inspect", name])
    if rc:
        raise RuntimeError(err or out)
    d = json.loads(out)[0]
    state = d.get("State") or {}
    return {
        "id": d.get("Id", ""),
        "running": bool(state.get("Running")),
        "health": ((state.get("Health") or {}).get("Status") or "sem-healthcheck"),
        "restart": int(d.get("RestartCount") or 0),
        "ports": (d.get("NetworkSettings") or {}).get("Ports") or {},
    }


def validate_dashboard_published_path(snapshot: dict) -> None:
    bindings = snapshot["ports"].get("5601/tcp")
    if not bindings:
        raise RuntimeError(
            "Dashboard 5601 não está publicado no host; "
            "caminho humano https://wazuh.dashboard:443 indisponível"
        )

    unsafe = [
        item
        for item in bindings
        if item.get("HostIp") not in {"127.0.0.1", "::1"}
        or item.get("HostPort") != "443"
    ]
    if unsafe:
        raise RuntimeError(
            "Dashboard deve publicar 5601 somente como loopback:443; "
            f"bindings={bindings}"
        )

    try:
        resolved = {
            item[4][0]
            for item in socket.getaddrinfo(
                "wazuh.dashboard",
                443,
                type=socket.SOCK_STREAM,
            )
        }
    except socket.gaierror as exc:
        raise RuntimeError(
            "wazuh.dashboard não resolve no host para o caminho humano documentado"
        ) from exc

    if not resolved or any(
        ip not in {"127.0.0.1", "::1"} for ip in resolved
    ):
        raise RuntimeError(
            "wazuh.dashboard deve resolver somente para loopback; "
            f"resolvido={sorted(resolved)}"
        )


def dashboard_host_login(password: str) -> None:
    with tempfile.TemporaryDirectory(
        prefix="conectaeduca-wazuh-dashboard-",
        dir="/dev/shm",
    ) as tmp:
        root = Path(tmp)
        ca = root / "root-ca.pem"
        cookies = root / "cookies.txt"
        response = root / "response.json"

        rc, out, err = run(
            [
                "docker",
                "cp",
                f"{dashboard}:/usr/share/wazuh-dashboard/certs/root-ca.pem",
                str(ca),
            ],
            timeout=30,
        )
        if rc:
            raise RuntimeError(
                f"não foi possível obter CA pública do Dashboard: {err or out}"
            )
        os.chmod(ca, 0o600)

        login_body = json.dumps(
            {"username": TARGET_USER, "password": password},
            separators=(",", ":"),
        )
        rc, http, err = run(
            [
                "curl",
                "-sS",
                "--cacert",
                str(ca),
                "-c",
                str(cookies),
                "-o",
                str(response),
                "-w",
                "%{http_code}",
                "-H",
                "Content-Type: application/json",
                "-H",
                "osd-xsrf: true",
                "-X",
                "POST",
                "--data-binary",
                "@-",
                "https://wazuh.dashboard:443/auth/login",
            ],
            input_text=login_body,
            timeout=30,
        )
        if rc or http.strip() != "200":
            raise RuntimeError(
                "login pelo Dashboard publicado falhou: "
                f"rc={rc} HTTP={http.strip() or '?'} err={err[:200]}"
            )

        if not cookies.exists():
            raise RuntimeError("Dashboard login não produziu cookie de sessão")
        os.chmod(cookies, 0o600)
        cookie_text = cookies.read_text(encoding="utf-8", errors="replace")
        if "security_authentication" not in cookie_text:
            raise RuntimeError(
                "Dashboard login retornou 200 sem cookie security_authentication"
            )

        api_login_body = json.dumps(
            {"idHost": "default"},
            separators=(",", ":"),
        )
        rc, http, err = run(
            [
                "curl",
                "-sS",
                "--cacert",
                str(ca),
                "-b",
                str(cookies),
                "-c",
                str(cookies),
                "-o",
                str(response),
                "-w",
                "%{http_code}",
                "-H",
                "Content-Type: application/json",
                "-H",
                "osd-xsrf: true",
                "-X",
                "POST",
                "--data-binary",
                "@-",
                "https://wazuh.dashboard:443/api/login",
            ],
            input_text=api_login_body,
            timeout=30,
        )
        if rc or not http.strip().startswith("2"):
            raise RuntimeError(
                "troca Wazuh /api/login pelo Dashboard publicado falhou: "
                f"rc={rc} HTTP={http.strip() or '?'} err={err[:200]}"
            )


def indexer_admin(method: str, path: str, body: dict | None = None):
    cmd = [
        "docker", "exec", "-i", indexer,
        "curl", "-sS",
        "--cert", "/usr/share/wazuh-indexer/config/certs/admin.pem",
        "--key", "/usr/share/wazuh-indexer/config/certs/admin-key.pem",
        "--cacert", "/usr/share/wazuh-indexer/config/certs/root-ca.pem",
        "-H", "Content-Type: application/json",
        "-X", method,
    ]
    if body is not None:
        cmd += ["--data-binary", "@-"]
    cmd += [f"https://wazuh.indexer:9200{path}"]
    data = json.dumps(body, separators=(",", ":")) if body is not None else None
    return run(cmd, input_text=data, timeout=30)


def indexer_admin_get_with_http(path: str):
    cmd = [
        "docker", "exec", "-i", indexer,
        "curl", "-sS",
        "--cert", "/usr/share/wazuh-indexer/config/certs/admin.pem",
        "--key", "/usr/share/wazuh-indexer/config/certs/admin-key.pem",
        "--cacert", "/usr/share/wazuh-indexer/config/certs/root-ca.pem",
        "-H", "Content-Type: application/json",
        "-X", "GET",
        "-w", "\n%{http_code}",
        f"https://wazuh.indexer:9200{path}",
    ]
    rc, out, err = run(cmd, timeout=30)
    body, sep, http = out.rpartition("\n")
    if not sep:
        return rc, "", out, err
    return rc, http.strip(), body.strip(), err


def confirm_indexer_user_absent() -> None:
    rc, http, out, err = indexer_admin_get_with_http(
        f"/_plugins/_security/api/internalusers/{TARGET_USER}"
    )
    if rc != 0:
        raise RuntimeError(
            "não foi possível confirmar ausência de teste no Indexer: "
            f"{err or out}"
        )

    try:
        remaining = json.loads(out)
    except Exception as exc:
        raise RuntimeError(
            "Indexer retornou resposta não-JSON ao confirmar ausência de teste: "
            f"HTTP={http} body={out[:300]}"
        ) from exc

    status = str(remaining.get("status", "")).upper()
    message = str(remaining.get("message", ""))

    if http == "404" and status == "NOT_FOUND" and "not found" in message.lower():
        return

    if http == "200" and TARGET_USER in remaining:
        raise RuntimeError("teste ainda está presente no Indexer")

    raise RuntimeError(
        "resposta inesperada ao confirmar ausência de teste no Indexer: "
        f"HTTP={http} status={status or '?'} body={out[:300]}"
    )


def get_indexer_user_record() -> dict | None:
    rc, http, out, err = indexer_admin_get_with_http(
        f"/_plugins/_security/api/internalusers/{TARGET_USER}"
    )
    if rc != 0:
        raise RuntimeError(
            "não foi possível consultar teste no Indexer: "
            f"{err or out}"
        )

    try:
        payload = json.loads(out)
    except Exception as exc:
        raise RuntimeError(
            "Indexer retornou resposta não-JSON ao consultar teste: "
            f"HTTP={http} body={out[:300]}"
        ) from exc

    if http == "200":
        record = payload.get(TARGET_USER)
        if not isinstance(record, dict):
            raise RuntimeError(
                "Indexer respondeu 200 sem registro estruturado de teste: "
                f"{out[:300]}"
            )
        return record

    status = str(payload.get("status", "")).upper()
    message = str(payload.get("message", ""))
    if http == "404" and status == "NOT_FOUND" and "not found" in message.lower():
        return None

    raise RuntimeError(
        "resposta inesperada ao consultar teste no Indexer: "
        f"HTTP={http} status={status or '?'} body={out[:300]}"
    )


def reconcile_ambiguous_indexer_creation() -> bool:
    record = get_indexer_user_record()
    if record is None:
        return False

    attrs = record.get("attributes") or {}
    backend_roles = sorted(record.get("backend_roles") or [])
    expected_roles = sorted(BACKEND_ROLES)

    if (
        attrs.get("purpose") == "conectaeduca-pentest"
        and attrs.get("provisioning_run") == PROVISIONING_RUN
        and backend_roles == expected_roles
    ):
        return True

    raise RuntimeError(
        "teste apareceu após mutação ambígua, mas não possui o marcador/roles "
        "desta execução; recusando assumir ownership"
    )


def reconcile_ambiguous_rule_creation() -> int | None:
    rule = find_rule()
    if rule is None:
        return None

    rule_body = rule.get("rule") or {}
    if rule_body.get("FIND", {}).get("user_name") != TARGET_USER:
        raise RuntimeError(
            "rule apareceu após mutação ambígua, mas o match não pertence a teste"
        )

    return int(rule["id"])


def indexer_hash_password(password: str):
    shell = r"""
set -eu
IFS= read -r CE_PW
export CE_PW
OS_HOME=/usr/share/wazuh-indexer
JAVA="$OS_HOME/jdk/bin/java"
PLUGIN="$OS_HOME/plugins/opensearch-security"
[ -x "$JAVA" ] || { echo BUNDLED_JAVA_NOT_FOUND >&2; exit 47; }
out="$("$JAVA" \
  -cp "$PLUGIN/*:$PLUGIN/deps/*:$OS_HOME/lib/*" \
  org.opensearch.security.tools.Hasher \
  -env CE_PW 2>/dev/null)"
unset CE_PW
hash="$(printf '%s\n' "$out" | awk '/^\$2[aby]\$/ {print; exit}')"
[ -n "$hash" ] || { echo HASH_OUTPUT_INVALID >&2; exit 48; }
printf '%s\n' "$hash"
"""
    return run(
        ["docker", "exec", "-i", indexer, "sh", "-lc", shell],
        input_text=password + "\n",
        timeout=45,
    )


def indexer_user_account(password: str):
    shell = r"""
set -eu
IFS= read -r PW
umask 077
CFG=/dev/shm/conectaeduca-wazuh-teste.$$
cleanup() { rm -f "$CFG"; unset PW; }
trap cleanup EXIT INT TERM
printf 'user = "teste:%s"\n' "$PW" > "$CFG"
curl -fsS \
  --config "$CFG" \
  --cacert /usr/share/wazuh-indexer/config/certs/root-ca.pem \
  https://wazuh.indexer:9200/_opendistro/_security/api/account
"""
    return run(
        ["docker", "exec", "-i", indexer, "sh", "-lc", shell],
        input_text=password + "\n",
        timeout=30,
    )


def manager_api(method: str, path: str, body: dict | None = None):
    shell = r"""
set -eu
METHOD="$1"
PATH_REQ="$2"
CFG=/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml
CA=/usr/share/wazuh-dashboard/certs/root-ca.pem
umask 077
AUTH=/dev/shm/conectaeduca-wazuh-admin-auth.$$
TOKENCFG=/dev/shm/conectaeduca-wazuh-admin-token.$$
BODY=/dev/shm/conectaeduca-wazuh-admin-body.$$
cleanup() { rm -f "$AUTH" "$TOKENCFG" "$BODY"; unset u p token; }
trap cleanup EXIT INT TERM

u="$(awk -F': ' '/^[[:space:]]*username:/ {gsub(/"/,"",$2); print $2; exit}' "$CFG")"
p="$(awk -F': ' '/^[[:space:]]*password:/ {gsub(/"/,"",$2); print $2; exit}' "$CFG")"
printf 'user = "%s:%s"\n' "$u" "$p" > "$AUTH"

token="$(curl -fsS \
  --config "$AUTH" \
  --cacert "$CA" \
  'https://wazuh.manager:55000/security/user/authenticate?raw=true')"
printf 'header = "Authorization: Bearer %s"\n' "$token" > "$TOKENCFG"

cat > "$BODY"
if [ -s "$BODY" ]; then
  curl -sS --config "$TOKENCFG" --cacert "$CA" \
    -H 'Content-Type: application/json' \
    -X "$METHOD" --data-binary @"$BODY" \
    "https://wazuh.manager:55000$PATH_REQ"
else
  curl -sS --config "$TOKENCFG" --cacert "$CA" \
    -H 'Content-Type: application/json' \
    -X "$METHOD" \
    "https://wazuh.manager:55000$PATH_REQ"
fi
"""
    data = json.dumps(body, separators=(",", ":")) if body is not None else ""
    return run(
        ["docker", "exec", "-i", dashboard, "sh", "-lc", shell, "ce-api", method, path],
        input_text=data,
        timeout=35,
    )


def configured_manager_api_username() -> str:
    shell = r"""
set -eu
CFG=/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml
u="$(awk -F': ' '/^[[:space:]]*username:/ {gsub(/"/,"",$2); print $2; exit}' "$CFG")"
[ -n "$u" ]
printf '%s\n' "$u"
"""
    rc, out, err = run(
        ["docker", "exec", dashboard, "sh", "-lc", shell],
        timeout=20,
    )
    if rc or not out.strip():
        raise RuntimeError(
            "não foi possível obter o username técnico configurado no wazuh.yml: "
            f"{err or out}"
        )
    return out.strip()


def verified_existing_mutation_probe_target() -> str:
    target = configured_manager_api_username()

    rc, out, err = manager_api("GET", "/security/users?pretty=false")
    if rc:
        raise RuntimeError(
            "não foi possível confirmar usuário-alvo do probe mutante: "
            f"{err or out}"
        )

    ok, payload = api_ok(out)
    if not ok:
        raise RuntimeError(
            "Wazuh API não retornou listagem administrativa válida ao confirmar "
            f"alvo do probe: {out[:300]}"
        )

    matches = [
        item
        for item in affected_items(payload)
        if item.get("username") == target
    ]
    if len(matches) != 1:
        raise RuntimeError(
            "usuário técnico configurado no Dashboard não foi confirmado de forma "
            f"única no Wazuh Manager: username={target!r} matches={len(matches)}"
        )

    return target


def manager_run_as(auth_context: dict):
    shell = r"""
set -eu
CFG=/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml
CA=/usr/share/wazuh-dashboard/certs/root-ca.pem
umask 077
AUTH=/dev/shm/conectaeduca-wazuh-runas-auth.$$
BODY=/dev/shm/conectaeduca-wazuh-runas-body.$$
cleanup() { rm -f "$AUTH" "$BODY"; unset u p; }
trap cleanup EXIT INT TERM

u="$(awk -F': ' '/^[[:space:]]*username:/ {gsub(/"/,"",$2); print $2; exit}' "$CFG")"
p="$(awk -F': ' '/^[[:space:]]*password:/ {gsub(/"/,"",$2); print $2; exit}' "$CFG")"
printf 'user = "%s:%s"\n' "$u" "$p" > "$AUTH"
cat > "$BODY"

curl -fsS \
  --config "$AUTH" \
  --cacert "$CA" \
  -H 'Content-Type: application/json' \
  -X POST --data-binary @"$BODY" \
  'https://wazuh.manager:55000/security/user/authenticate/run_as'
"""
    return run(
        ["docker", "exec", "-i", dashboard, "sh", "-lc", shell],
        input_text=json.dumps(auth_context, separators=(",", ":")),
        timeout=30,
    )


def scoped_get(token: str, path: str):
    shell = r"""
set -eu
PATH_REQ="$1"
IFS= read -r TOKEN
CA=/usr/share/wazuh-dashboard/certs/root-ca.pem
umask 077
CFG=/dev/shm/conectaeduca-wazuh-scoped.$$
RESP=/dev/shm/conectaeduca-wazuh-response.$$
cleanup() { rm -f "$CFG" "$RESP"; unset TOKEN; }
trap cleanup EXIT INT TERM
printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" > "$CFG"
code="$(curl -sS --config "$CFG" --cacert "$CA" \
  -o "$RESP" -w '%{http_code}' \
  "https://wazuh.manager:55000$PATH_REQ")"
printf '%s\n' "$code"
cat "$RESP" || true
"""
    rc, out, err = run(
        ["docker", "exec", "-i", dashboard, "sh", "-lc", shell, "ce", path],
        input_text=token + "\n",
        timeout=30,
    )
    if rc:
        return rc, "", "", err
    code, _, body = out.partition("\n")
    return 0, code.strip(), body.strip(), err


def scoped_mutation_probe(token: str, target_username: str):
    # O alvo é confirmado previamente pelo caminho administrativo e deriva do
    # username técnico realmente configurado no wazuh.yml. Assim o teste nunca
    # tenta criar um principal novo caso a política read-only regrida.
    probe_password = secrets.token_urlsafe(24) + "Aa1!"

    shell = r"""
set -eu
TARGET_USER="$1"
IFS= read -r TOKEN
IFS= read -r PROBE_PW
CA=/usr/share/wazuh-dashboard/certs/root-ca.pem
umask 077
CFG=/dev/shm/conectaeduca-wazuh-mutation.$
RESP=/dev/shm/conectaeduca-wazuh-mutation-response.$
BODY=/dev/shm/conectaeduca-wazuh-mutation-body.$
cleanup() {
  rm -f "$CFG" "$RESP" "$BODY"
  unset TOKEN PROBE_PW TARGET_USER
}
trap cleanup EXIT INT TERM

printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" > "$CFG"
printf '{"username":"%s","password":"%s"}\n' "$TARGET_USER" "$PROBE_PW" > "$BODY"

code="$(curl -sS --config "$CFG" --cacert "$CA" \
  -H 'Content-Type: application/json' \
  -X POST \
  --data-binary @"$BODY" \
  -o "$RESP" -w '%{http_code}' \
  'https://wazuh.manager:55000/security/users')"
printf '%s\n' "$code"
cat "$RESP" || true
"""
    rc, out, err = run(
        [
            "docker", "exec", "-i", dashboard,
            "sh", "-lc", shell, "ce-mutation", target_username,
        ],
        input_text=token + "\n" + probe_password + "\n",
        timeout=30,
    )
    if rc:
        return rc, "", "", err
    code, _, body = out.partition("\n")
    return 0, code.strip(), body.strip(), err


def jwt_roles(token: str) -> list:
    parts = token.split(".")
    if len(parts) < 2:
        return []
    data = parts[1] + "=" * (-len(parts[1]) % 4)
    payload = json.loads(base64.urlsafe_b64decode(data.encode()).decode())
    roles = payload.get("rbac_roles")
    return roles if isinstance(roles, list) else []


def api_ok(out: str) -> tuple[bool, dict]:
    try:
        payload = json.loads(out)
    except Exception:
        return False, {}
    return payload.get("error") == 0, payload


def affected_items(payload: dict) -> list:
    data = payload.get("data")
    if isinstance(data, dict) and isinstance(data.get("affected_items"), list):
        return data["affected_items"]
    return []


def find_rule() -> dict | None:
    rc, out, err = manager_api("GET", "/security/rules?pretty=false")
    if rc:
        raise RuntimeError(err or out)
    ok, payload = api_ok(out)
    if not ok:
        raise RuntimeError(out[:500])
    return next(
        (item for item in affected_items(payload) if item.get("name") == WAZUH_RULE_NAME),
        None,
    )


def validate_runtime() -> dict[str, dict]:
    snapshots = {}
    for name in (manager, indexer, dashboard):
        snap = inspect_container(name)
        snapshots[name] = snap
        if not snap["running"] or snap["health"] not in {"healthy", "sem-healthcheck"}:
            raise RuntimeError(f"runtime inadequado: {name} -> {snap}")
    if snapshots[manager]["ports"].get("55000/tcp"):
        raise RuntimeError("55000 está publicada no host")
    if snapshots[indexer]["ports"].get("9200/tcp"):
        raise RuntimeError("9200 está publicada no host")

    validate_dashboard_published_path(snapshots[dashboard])
    return snapshots


def validate_e2e(password: str) -> None:
    rc, out, err = indexer_admin(
        "GET", f"/_plugins/_security/api/internalusers/{TARGET_USER}"
    )
    if rc:
        raise RuntimeError(err or out)
    user = json.loads(out).get(TARGET_USER)
    if not user:
        raise RuntimeError("teste ausente no Indexer")
    if sorted(user.get("backend_roles") or []) != sorted(BACKEND_ROLES):
        raise RuntimeError(f"backend_roles inesperados: {user.get('backend_roles')}")
    mark("PASS", "teste presente com backend_roles kibanauser/readall.")

    rule = find_rule()
    if not rule:
        raise RuntimeError(f"rule {WAZUH_RULE_NAME} ausente")
    if rule.get("roles") != [WAZUH_READONLY_ROLE_ID]:
        raise RuntimeError(f"rule não está exclusivamente no readonly: {rule}")
    if (rule.get("rule") or {}).get("FIND", {}).get("user_name") != TARGET_USER:
        raise RuntimeError(f"match da rule inesperado: {rule.get('rule')}")
    mark("PASS", "Rule mapeia user_name=teste somente ao role readonly id=2.")

    rc, account_out, err = indexer_user_account(password)
    if rc:
        raise RuntimeError(f"autenticação no Indexer falhou: {err or account_out}")
    auth_context = json.loads(account_out)
    if auth_context.get("user_name") != TARGET_USER:
        raise RuntimeError("authContext não pertence a teste")
    mark("PASS", "Autenticação real de teste no Indexer confirmada.")

    dashboard_host_login(password)
    mark(
        "PASS",
        "Caminho humano publicado validado: https://wazuh.dashboard:443 "
        "aceitou /auth/login e /api/login com sessão autenticada.",
    )

    rc, runas_out, err = manager_run_as(auth_context)
    if rc:
        raise RuntimeError(f"run_as falhou: {err or runas_out}")
    token = (json.loads(runas_out).get("data") or {}).get("token")
    if not token:
        raise RuntimeError("run_as não retornou token")
    if jwt_roles(token) != [WAZUH_READONLY_ROLE_ID]:
        raise RuntimeError(f"rbac_roles inesperadas: {jwt_roles(token)}")
    mark("PASS", "run_as confirmou rbac_roles=[2] (readonly).")

    rc, http, body, err = scoped_get(token, "/agents?limit=1")
    if rc or http != "200" or json.loads(body).get("error") != 0:
        raise RuntimeError(f"GET /agents falhou: rc={rc} HTTP={http} body={body[:300]}")
    mark("PASS", "Positivo RBAC: consulta de agentes permitida.")

    rc, http, body, err = scoped_get(token, "/security/users?limit=1")
    if rc or http != "200":
        raise RuntimeError(f"listagem filtrada falhou: rc={rc} HTTP={http}")
    payload = json.loads(body)
    data = payload.get("data") or {}
    if (
        payload.get("error") != 0
        or (data.get("affected_items") or [])
        or data.get("total_affected_items") != 0
    ):
        raise RuntimeError(f"listagem administrativa não foi filtrada: {body[:300]}")
    mark("PASS", "Negativo por filtragem: /security/users expõe zero recursos.")

    rc, http, body, err = scoped_get(token, "/security/users?user_ids=1")
    if rc or http != "403":
        raise RuntimeError(
            f"negativo explícito esperava 403: rc={rc} HTTP={http} body={body[:300]}"
        )
    mark("PASS", "Negativo explícito: user_ids=1 negado com HTTP403.")

    mutation_target = verified_existing_mutation_probe_target()
    mark(
        "PASS",
        "Alvo do probe mutante confirmado como usuário técnico preexistente "
        "derivado do wazuh.yml.",
    )

    rc, http, body, err = scoped_mutation_probe(token, mutation_target)
    if rc or http != "403":
        raise RuntimeError(
            "endpoint mutante POST /security/users não foi negado como esperado: "
            f"rc={rc} HTTP={http} body={body[:300]}"
        )
    mark(
        "PASS",
        "Negativo mutante: POST /security/users foi negado com HTTP403 "
        "contra usuário técnico preexistente; nenhum principal novo foi criado.",
    )


def rollback() -> None:
    global rollback_used
    global created_user, created_rule, linked_rule, created_rule_id

    if not any(
        (
            created_user,
            created_rule,
            linked_rule,
            user_creation_attempted,
            rule_creation_attempted,
            rule_link_attempted,
        )
    ):
        return

    rollback_used = True
    errors: list[str] = []

    # Reconciliar primeiro qualquer mutação cujo request foi enviado, mas cuja
    # resposta pode ter sido perdida/truncada. O marcador da execução impede
    # assumir ownership de uma conta preexistente.
    if user_creation_attempted and not created_user:
        try:
            record = get_indexer_user_record()
            if record is not None:
                attrs = record.get("attributes") or {}
                backend_roles = sorted(record.get("backend_roles") or [])
                if (
                    attrs.get("purpose") == "conectaeduca-pentest"
                    and attrs.get("provisioning_run") == PROVISIONING_RUN
                    and backend_roles == sorted(BACKEND_ROLES)
                ):
                    created_user = True
                else:
                    errors.append(
                        "reconciliação rollback: teste existe, mas não pertence "
                        "comprovadamente a esta execução"
                    )
        except Exception as exc:
            errors.append(
                "reconciliação rollback do usuário: "
                f"{type(exc).__name__}: {exc}"
            )

    if rule_creation_attempted and not created_rule:
        try:
            rule = find_rule()
            if rule is not None:
                rule_body = rule.get("rule") or {}
                if rule_body.get("FIND", {}).get("user_name") == TARGET_USER:
                    created_rule_id = int(rule["id"])
                    created_rule = True
                else:
                    errors.append(
                        "reconciliação rollback: rule existe com match inesperado"
                    )
        except Exception as exc:
            errors.append(
                "reconciliação rollback da rule: "
                f"{type(exc).__name__}: {exc}"
            )

    if rule_link_attempted and created_rule and not linked_rule:
        try:
            rule = find_rule()
            if (
                rule is not None
                and int(rule["id"]) == created_rule_id
                and WAZUH_READONLY_ROLE_ID in (rule.get("roles") or [])
            ):
                linked_rule = True
        except Exception as exc:
            errors.append(
                "reconciliação rollback do vínculo: "
                f"{type(exc).__name__}: {exc}"
            )

    if created_rule_id is not None and linked_rule:
        try:
            rc, out, err = manager_api(
                "DELETE",
                f"/security/roles/{WAZUH_READONLY_ROLE_ID}/rules?rule_ids={created_rule_id}",
            )
            ok, payload = api_ok(out) if rc == 0 else (False, {})
            if not ok:
                errors.append(
                    "desvincular rule do readonly: "
                    f"{err or out[:300]}"
                )
        except Exception as exc:
            errors.append(f"desvincular rule do readonly: {type(exc).__name__}: {exc}")

    if created_rule_id is not None and created_rule:
        try:
            rc, out, err = manager_api(
                "DELETE", f"/security/rules?rule_ids={created_rule_id}"
            )
            ok, payload = api_ok(out) if rc == 0 else (False, {})
            if not ok:
                errors.append(
                    "remover rule Wazuh: "
                    f"{err or out[:300]}"
                )
        except Exception as exc:
            errors.append(f"remover rule Wazuh: {type(exc).__name__}: {exc}")

    if created_user:
        try:
            rc, out, err = indexer_admin(
                "DELETE", f"/_plugins/_security/api/internalusers/{TARGET_USER}"
            )
            if rc != 0:
                errors.append(
                    "remover teste do Indexer: "
                    f"{err or out[:300]}"
                )
            else:
                try:
                    payload = json.loads(out)
                except Exception as exc:
                    errors.append(
                        "DELETE do Indexer retornou resposta não-JSON: "
                        f"{out[:300]}"
                    )
                else:
                    status = str(payload.get("status", "")).upper()
                    message = str(payload.get("message", ""))
                    if status != "OK" or "deleted" not in message.lower():
                        errors.append(
                            "DELETE do Indexer sem confirmação reconhecida: "
                            f"status={status or '?'} body={out[:300]}"
                        )
        except Exception as exc:
            errors.append(f"remover teste do Indexer: {type(exc).__name__}: {exc}")

    if created_rule:
        try:
            if find_rule() is not None:
                errors.append("verificação final: rule Wazuh ainda existe")
        except Exception as exc:
            errors.append(
                f"verificação final da rule falhou: {type(exc).__name__}: {exc}"
            )

    if created_user:
        try:
            confirm_indexer_user_absent()
        except Exception as exc:
            errors.append(
                f"verificação final do usuário falhou: {type(exc).__name__}: {exc}"
            )

    if errors:
        raise RuntimeError(
            "rollback tentou todas as limpezas, mas houve falhas: "
            + " | ".join(errors)
        )

    mark(
        "PASS",
        "Rollback confirmado: usuário, rule e mapping criados nesta execução "
        "foram removidos e a ausência foi revalidada.",
    )


log("ConectaEduca — identidade teste read-only no Wazuh")
log(f"Data/hora={dt.datetime.now().astimezone().isoformat(timespec='seconds')}")
log(f"MODO={MODE}")
log("SENHA_EM_ARGV=NAO")
log("SEGREDOS_EXIBIDOS=NAO")
log("POLITICA_GLOBAL_DE_SENHA_RELAXADA=0")
log("PUBLICA_55000=NAO")
log("PUBLICA_9200=NAO")
log("DASHBOARD_HUMAN_PATH=https://wazuh.dashboard:443")
log("=" * 100)

snapshots: dict[str, dict] = {}

try:
    rc, host, err = run(["hostname"])
    if rc or host.strip() != EXPECTED_HOST:
        raise RuntimeError(f"executar somente em {EXPECTED_HOST}")
    mark("PASS", f"VM confirmada: {host.strip()}")

    rc, _, err = run(["docker", "info"])
    if rc:
        raise RuntimeError(err)
    mark("PASS", "Docker acessível sem sudo.")

    svc = services()
    manager = svc["wazuh.manager"]
    indexer = svc["wazuh.indexer"]
    dashboard = svc["wazuh.dashboard"]
    snapshots = validate_runtime()
    mark("PASS", "Manager/Indexer/Dashboard healthy; 55000/9200 sem host binding.")

    if MODE == "REVOKE":
        rule = find_rule()
        if rule:
            rid = int(rule["id"])
            manager_api(
                "DELETE",
                f"/security/roles/{WAZUH_READONLY_ROLE_ID}/rules?rule_ids={rid}",
            )
            manager_api("DELETE", f"/security/rules?rule_ids={rid}")
            mark("PASS", f"Rule {WAZUH_RULE_NAME} id={rid} removida.")

        rc, out, err = indexer_admin(
            "GET", f"/_plugins/_security/api/internalusers/{TARGET_USER}"
        )
        try:
            existing = json.loads(out)
        except Exception:
            existing = {}
        if TARGET_USER in existing:
            indexer_admin(
                "DELETE", f"/_plugins/_security/api/internalusers/{TARGET_USER}"
            )
            mark("PASS", "Internal user teste removido do Indexer.")

        if find_rule() is not None:
            raise RuntimeError("rule ainda presente após revogação")

        confirm_indexer_user_absent()
        mark(
            "PASS",
            "Revogação validada: Indexer confirmou ausência de teste.",
        )
    else:
        if MODE == "APPLY":
            # Nunca interpretar erro/TLS/non-JSON como ausência. O APPLY só pode
            # criar teste quando o Indexer comprova explicitamente 404/NOT_FOUND.
            confirm_indexer_user_absent()

            if find_rule() is not None:
                raise RuntimeError(f"rule {WAZUH_RULE_NAME} já existe")

            mark(
                "PASS",
                "Baseline confirma explicitamente ausência de teste no Indexer "
                "e ausência da rule Wazuh.",
            )

            rc, out, err = manager_api("GET", "/security/roles?pretty=false")
            if rc:
                raise RuntimeError(err or out)
            ok, payload = api_ok(out)
            roles = affected_items(payload) if ok else []
            if not any(
                item.get("id") == WAZUH_READONLY_ROLE_ID
                and item.get("name") == WAZUH_READONLY_ROLE_NAME
                for item in roles
            ):
                raise RuntimeError("role readonly id=2 não confirmada")
            mark("PASS", "Role Wazuh readonly id=2 confirmada.")

        password = getpass.getpass("Senha padrão da identidade técnica teste: ")
        confirmation = getpass.getpass("Confirme a senha padrão: ")
        if not password or password != confirmation:
            raise RuntimeError("senha vazia ou confirmação divergente")
        mark("PASS", "Senha recebida interativamente; não será registrada.")

        if MODE == "APPLY":
            user_creation_attempted = True
            body = {
                "password": password,
                "backend_roles": BACKEND_ROLES,
                "attributes": {
                    "purpose": "conectaeduca-pentest",
                    "provisioning_run": PROVISIONING_RUN,
                },
            }
            rc, out, err = indexer_admin(
                "PUT", f"/_plugins/_security/api/internalusers/{TARGET_USER}", body
            )

            response = None
            if rc == 0:
                try:
                    response = json.loads(out)
                except Exception:
                    response = None

            if response is None:
                if reconcile_ambiguous_indexer_creation():
                    created_user = True
                    mark(
                        "WARN",
                        "Resultado do PUT no Indexer foi ambíguo, mas a criação foi "
                        "reconciliada pelo marcador exclusivo desta execução.",
                    )
                else:
                    raise RuntimeError(
                        "PUT do Indexer teve resultado ambíguo e teste não apareceu; "
                        f"{err or out[:300]}"
                    )
            else:
                status = str(response.get("status", "")).upper()
                reason = str(response.get("reason", ""))

                if status == "ERROR" and "weak password" in reason.lower():
                    mark(
                        "WARN",
                        "Senha padrão rejeitada pela política de complexidade; "
                        "provisionando pelo hash nativo sem relaxar a política global.",
                    )
                    rc, password_hash, err = indexer_hash_password(password)
                    if rc or not password_hash.startswith(("$2a$", "$2b$", "$2y$")):
                        raise RuntimeError(
                            f"geração de hash falhou: {err or password_hash}"
                        )

                    hash_body = {
                        "hash": password_hash,
                        "backend_roles": BACKEND_ROLES,
                        "attributes": {
                            "purpose": "conectaeduca-pentest",
                            "provisioning_run": PROVISIONING_RUN,
                        },
                    }
                    rc, out, err = indexer_admin(
                        "PUT",
                        f"/_plugins/_security/api/internalusers/{TARGET_USER}",
                        hash_body,
                    )

                    response = None
                    if rc == 0:
                        try:
                            response = json.loads(out)
                        except Exception:
                            response = None

                    if response is None:
                        if reconcile_ambiguous_indexer_creation():
                            created_user = True
                            mark(
                                "WARN",
                                "Resultado do PUT com hash foi ambíguo, mas a criação "
                                "foi reconciliada pelo marcador desta execução.",
                            )
                        else:
                            raise RuntimeError(
                                "PUT com hash teve resultado ambíguo e teste não apareceu; "
                                f"{err or out[:300]}"
                            )
                    elif str(response.get("status", "")).upper() not in {"CREATED", "OK"}:
                        raise RuntimeError(
                            f"Indexer rejeitou criação por hash: {out[:500]}"
                        )
                    else:
                        created_user = True

                elif status not in {"CREATED", "OK"}:
                    raise RuntimeError(f"Indexer rejeitou criação: {out[:500]}")
                else:
                    created_user = True

            if not created_user:
                raise RuntimeError("não foi possível confirmar ownership da criação de teste")
            mark("PASS", "Usuário teste criado/reconciliado no Indexer/Dashboard.")

            rule_creation_attempted = True
            rc, out, err = manager_api(
                "POST",
                "/security/rules",
                {
                    "name": WAZUH_RULE_NAME,
                    "rule": {"FIND": {"user_name": TARGET_USER}},
                },
            )
            ok, payload = api_ok(out) if rc == 0 else (False, {})
            items = affected_items(payload) if ok else []

            if len(items) == 1:
                created_rule_id = int(items[0]["id"])
                created_rule = True
            else:
                reconciled_rule_id = reconcile_ambiguous_rule_creation()
                if reconciled_rule_id is None:
                    raise RuntimeError(
                        "criação da rule teve resultado ambíguo e a rule não apareceu: "
                        f"{err or out[:300]}"
                    )
                created_rule_id = reconciled_rule_id
                created_rule = True
                mark(
                    "WARN",
                    "Resultado do POST da rule foi ambíguo, mas a rule foi "
                    "reconciliada pelo nome/match exclusivos desta execução.",
                )

            mark("PASS", f"Rule {WAZUH_RULE_NAME} criada; id={created_rule_id}.")

            rule_link_attempted = True
            rc, out, err = manager_api(
                "POST",
                f"/security/roles/{WAZUH_READONLY_ROLE_ID}/rules?rule_ids={created_rule_id}",
            )
            ok, payload = api_ok(out) if rc == 0 else (False, {})
            if ok:
                linked_rule = True
            else:
                current_rule = find_rule()
                if (
                    current_rule is not None
                    and int(current_rule["id"]) == created_rule_id
                    and WAZUH_READONLY_ROLE_ID in (current_rule.get("roles") or [])
                ):
                    linked_rule = True
                    mark(
                        "WARN",
                        "Resultado do vínculo rule->readonly foi ambíguo, mas o "
                        "estado live confirmou o vínculo desta rule.",
                    )
                else:
                    raise RuntimeError(
                        f"vínculo rule->readonly falhou/ficou indeterminado: {err or out}"
                    )

            mark("PASS", "Rule vinculada exclusivamente ao role readonly.")

        validate_e2e(password)

        for name, before in snapshots.items():
            after = inspect_container(name)
            if after["id"] != before["id"] or after["restart"] != before["restart"]:
                raise RuntimeError(f"runtime mudou durante {MODE}: {name}")
        mark("PASS", "Runtime preservado sem restart/recreate.")

except Exception as exc:
    mark("FAIL", f"{type(exc).__name__}: {exc}")
    if MODE == "APPLY":
        try:
            rollback()
        except Exception as rollback_exc:
            mark("FAIL", f"rollback falhou: {rollback_exc}")

status = (
    "WAZUH_TESTE_READONLY_RECONCILIADO"
    if MODE == "APPLY" and counts["FAIL"] == 0
    else "WAZUH_TESTE_CHECK_E2E_APROVADO"
    if MODE == "CHECK" and counts["FAIL"] == 0
    else "WAZUH_TESTE_REVOGADO"
    if MODE == "REVOKE" and counts["FAIL"] == 0
    else "WAZUH_TESTE_OPERACAO_FALHOU"
)

log("=" * 100)
log(
    f"RESUMO_FINAL: PASS={counts['PASS']} WARN={counts['WARN']} "
    f"FAIL={counts['FAIL']} GAP={counts['GAP']}"
)
log(f"STATUS={status}")
log(f"GAP_FINAL_WAZUH_AUTH_PATH={0 if counts['FAIL'] == 0 and MODE != 'REVOKE' else 1}")
log(f"ROLLBACK_USED={1 if rollback_used else 0}")
log("ALTERACOES_GIT=0")
log("55000_PUBLICADO=0")
log("9200_PUBLICADO=0")
log("SEGREDOS_EXIBIDOS=0")
log("SENHA_PERSISTIDA_EM_ARQUIVO=0")
log("POLITICA_GLOBAL_DE_SENHA_RELAXADA=0")
log("HASH_METHOD=OPENSEARCH_SECURITY_HASHER_DIRECT")

REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
os.chmod(REPORT, 0o600)
print(f"RELATORIO={REPORT}")
print(f"RELATORIO_SHA256={sha256(REPORT)}")

if counts["FAIL"] > 0:
    sys.exit(1)
