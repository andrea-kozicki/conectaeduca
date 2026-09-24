#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import json
import socket
import subprocess
from pathlib import Path

HOST = socket.gethostname()
UTC = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%SZ")
HOME = Path.home()
REPORT = HOME / f"conectaeduca-gui01c-phpmyadmin-precheck-{HOST}-{UTC}.txt"

PROJECT = Path("/opt/conectaeduca")
EXPECTED_HOST = "ep126-pucpr"
MARIADB_PROJECT = "conectaeduca-mariadb"
MARIADB_SERVICE = "mariadb"
CANDIDATE_PORT = 9098

REPORT.write_text("", encoding="utf-8")


def w(line: str = "") -> None:
    with REPORT.open("a", encoding="utf-8") as fh:
        fh.write(line + "\n")
    print(line)


def section(title: str) -> None:
    w()
    w("=" * 88)
    w(title)
    w("=" * 88)


def run(cmd: list[str], timeout: int = 20) -> tuple[int, str, str]:
    try:
        p = subprocess.run(
            cmd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
        return p.returncode, p.stdout.rstrip(), p.stderr.rstrip()
    except FileNotFoundError:
        return 127, "", f"command not found: {cmd[0]}"
    except subprocess.TimeoutExpired:
        return 124, "", f"timeout after {timeout}s"


def docker_exec(container: str, shell: str, timeout: int = 20) -> tuple[int, str, str]:
    return run(["docker", "exec", container, "sh", "-lc", shell], timeout)


def find_mariadb_container() -> str | None:
    rc, out, _ = run([
        "docker", "ps",
        "--filter", f"label=com.docker.compose.project={MARIADB_PROJECT}",
        "--filter", f"label=com.docker.compose.service={MARIADB_SERVICE}",
        "--format", "{{.Names}}",
    ])
    names = [x.strip() for x in out.splitlines() if x.strip()] if rc == 0 else []
    return names[0] if len(names) == 1 else None


section("GUI-01C — PHPMYADMIN READ-ONLY PRECHECK")
w(f"host={HOST}")
w(f"utc={UTC}")
w("mode=READ_ONLY")
w("container_created=0")
w("network_changed=0")
w("database_mutation=0")
w("secret_value_printed=0")
w(f"REPORT={REPORT}")

section("1. HOST / REPOSITÓRIO")
w(f"HOST_EXPECTED={'PASS' if HOST == EXPECTED_HOST else 'WARN'} expected={EXPECTED_HOST} actual={HOST}")
if (PROJECT / ".git").is_dir():
    rc, out, _ = run(["git", "-C", str(PROJECT), "status", "--short"])
    w(f"GIT_REPOSITORY=PASS path={PROJECT}")
    w(f"GIT_CLEAN={'PASS' if rc == 0 and not out.strip() else 'WARN'}")
else:
    w(f"GIT_REPOSITORY=WARN path={PROJECT}")

section("2. MARIADB RUNTIME")
container = find_mariadb_container()
if not container:
    w("MARIADB_CONTAINER=BLOCK reason=not_unique_or_not_found")
    w("FINAL=BLOCK")
    raise SystemExit(2)

w(f"MARIADB_CONTAINER=PASS name={container}")
rc, raw, _ = run(["docker", "inspect", container])
if rc != 0:
    w("MARIADB_INSPECT=BLOCK")
    w("FINAL=BLOCK")
    raise SystemExit(2)

info = json.loads(raw)[0]
state = info.get("State", {}) or {}
health = (state.get("Health") or {}).get("Status")
w(f"MARIADB_RUNNING={'PASS' if state.get('Running') else 'BLOCK'}")
w(f"MARIADB_HEALTH={health or 'n/a'}")

networks = ((info.get("NetworkSettings") or {}).get("Networks") or {})
if networks:
    for name, data in sorted(networks.items()):
        ip = (data or {}).get("IPAddress") or ""
        w(f"MARIADB_NETWORK={name}|ipv4={ip or 'n/a'}")
else:
    w("MARIADB_NETWORK=BLOCK")

published = (info.get("NetworkSettings") or {}).get("Ports") or {}
for key, mappings in sorted(published.items()):
    if not mappings:
        continue
    for item in mappings:
        host_ip = (item or {}).get("HostIp") or ""
        host_port = (item or {}).get("HostPort") or ""
        w(f"MARIADB_PUBLISHED_PORT={key}|host_ip={host_ip}|host_port={host_port}")

section("3. IDENTIDADE HUMANA teste")
sql = r"""
set -eu
pw="$(cat /run/secrets/mariadb_root_password)"
export MYSQL_PWD="$pw"
mariadb --batch --skip-column-names -uroot -e "
SELECT User, Host
FROM mysql.user
WHERE User='teste'
ORDER BY Host;

SELECT GRANTEE, PRIVILEGE_TYPE
FROM information_schema.SCHEMA_PRIVILEGES
WHERE TABLE_SCHEMA='conectaeduca'
ORDER BY GRANTEE, PRIVILEGE_TYPE;

SELECT GRANTEE, PRIVILEGE_TYPE
FROM information_schema.USER_PRIVILEGES
WHERE PRIVILEGE_TYPE <> 'USAGE'
ORDER BY GRANTEE, PRIVILEGE_TYPE;
" mysql
unset MYSQL_PWD pw
"""
rc, out, _ = docker_exec(container, sql)
if rc != 0:
    w(f"TESTE_IDENTITY_QUERY=BLOCK rc={rc}")
else:
    lines = [x for x in out.splitlines() if x.strip()]
    w("TESTE_IDENTITY_QUERY=PASS")
    for line in lines:
        if "teste" in line or line.startswith("teste\t"):
            w(f"TESTE_DB_FACT={line}")

section("4. PORTA LOCAL CANDIDATA")
rc, ss, _ = run(["ss", "-ltn"])
busy = rc != 0 or f":{CANDIDATE_PORT} " in ss or f":{CANDIDATE_PORT}\n" in ss
w(f"LOOPBACK_PORT_{CANDIDATE_PORT}={'BLOCK_BUSY' if busy else 'PASS_FREE'}")
w(f"TARGET_BIND=127.0.0.1:{CANDIDATE_PORT}")

section("5. INVARIANTES PARA O APPLY")
for item in (
    "loopback_only=required",
    "no_docker_socket=required",
    "privileged=false",
    "read_only_rootfs=required_if_image_compatible",
    "cap_drop_all=required_if_image_compatible",
    "no_database_password_in_compose=required",
    "human_login=teste",
    "positive_test=SELECT_via_GUI",
    "negative_test=INSERT_UPDATE_DELETE_denied",
    "mariadb_container_recreate=forbidden",
):
    w(f"INVARIANT={item}")

section("6. RESULTADO")
network_ok = bool(networks)
port_ok = not busy
runtime_ok = bool(state.get("Running")) and health in (None, "healthy")
w(f"MARIADB_RUNTIME_READY={'YES' if runtime_ok else 'NO'}")
w(f"NETWORK_DISCOVERED={'YES' if network_ok else 'NO'}")
w(f"LOOPBACK_PORT_READY={'YES' if port_ok else 'NO'}")
w("PHPMYADMIN_IMAGE_PINNED=NO")
w("APPLY_AUTHORIZED=NO")
w("NEXT=review report, pin official image by digest, render compose, validate candidate, then controlled apply")
w(f"FINAL={'PASS_PRECHECK' if runtime_ok and network_ok and port_ok else 'BLOCK'}")
w(f"REPORT={REPORT}")
