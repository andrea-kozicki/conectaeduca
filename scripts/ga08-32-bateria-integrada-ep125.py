#!/usr/bin/env python3
"""GA08.32 — PA02 correction candidate integrated read-only/isolated QA.

ONE invocation evaluates:
  1) baseline WAF, Nginx, PHP health and routes (3 HTTP200, XSS HTTP403);
  2) integrity and permission of candidate files and script dependencies;
  3) Docker Compose 10 baseline + 2 socket candidate overlays + one
     GA08 canonical /run runtime-fix overlay, with no unrelated config drift;
  4) candidate PA02 isolation/security contract using the existing G0 driver;
  5) corrected Nginx running in one networkless ephemeral container with
     the exact installed image/UID101/read-only rootfs/tmpfs/Unix listener;
  6) Docker's real RO host bind of BOTH persistent Unix socket directories,
     checked in a second networkless ephemeral container AS UID101/GID101+82.

No Docker Compose up/down, no writes to host socket bind sources, no secrets
access, no changes to production. Uses read-only ephemeral mounts only.
NEVER prints Docker config, mounts contents, secrets or raw logs.
Fix must be separately approved with a NEW change ID before cutover.
"""
from __future__ import annotations

import argparse
import copy
import json
import os
from pathlib import Path
import re
import runpy
import secrets
import socket
import stat
import subprocess
import sys
import time

ROOT = Path("/opt/conectaeduca")
ROOT_PRIVATE = (
    Path.home() / "ConectaEduca_Fase2_Evidencias" / "EP125" / "GA08"
    / "GA08-20261104-EP125-PERM-FIX01"
)
SOURCES = {
    "deploy/dmz/compose.ga08-runtimefix.candidate.yml":
        "ff87d5e5fe1dfc43d30a908e5fb01e3e1574ecc3",  # pinned source; update if reviewed blob differs
    "scripts/ga08-nginx-canario-ep125.py":
        "c460306bab91c300d0878bc7c1c8a1cf5676a2a7",
    "scripts/ga08-nginx-entrypoint-isolation-ep125.py":
        "502c475c479aa35d6b4f983bcf4a183bb39b1176",
    "scripts/ga08-nginx-tmpfs-diferencial-ep125.py":
        "aa243b4c8f35a155f1c836fc4e16ca9dbc9da252",
    "scripts/ga08-change-control.py":
        "e5b6d75b7b7c4e876fc3d87abe1db7e88f1988c2",
}
BASE_COUNT = 10
OLD_CANDIDATES = (
    "compose.ga08-socket.candidate.yml",
    "compose.ga08-dual-socket.candidate.yml",
)
NEW_OVERLAY = "compose.ga08-runtimefix.candidate.yml"
EXPECTED_DIR = {
    "CONECTAEDUCA_GA08_SOCKET_DIR": ("/var/lib/conectaeduca-ga08/fpm", 82, 82, 0o770),
    "CONECTAEDUCA_GA08_HTTP_SOCKET_DIR": ("/var/lib/conectaeduca-ga08/http", 101, 101, 0o700),
}
PUBLIC_CFG = (
    "deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf",
    "deploy/dmz/ga08/app-http.socket.candidate.conf",
    "deploy/dmz/ga08/app-http.dual-socket.candidate.conf",
)

def result(name: str, ok: bool) -> None:
    print(name + "=" + ("PASS" if ok else "FAIL"), flush=True)

def only_public(s: str, limit: int = 95) -> str:
    return s if re.fullmatch(r"[A-Z0-9_-]{1," + str(limit) + r"}", s) else "INDETERMINADO"

def load_private_context() -> dict[str, str]:
    f = ROOT_PRIVATE / "runtime-refs.json"
    if f.is_symlink() or not f.is_file():
        raise RuntimeError("CONTEXTO_INVALIDO")
    st = f.stat()
    if st.st_uid != os.geteuid() or stat.S_IMODE(st.st_mode) != 0o600:
        raise RuntimeError("CONTEXTO_ACL")
    obj = json.loads(f.read_text(encoding="utf-8"))
    if obj.get("change_id") != ROOT_PRIVATE.name or obj.get("format") != 1:
        raise RuntimeError("CONTEXTO_IDENTIDADE")
    refs = obj.get("references")
    if not isinstance(refs, dict) or len(refs) != 18:
        raise RuntimeError("CONTEXTO_REFERENCIAS")
    for key, (path, _, _, _) in EXPECTED_DIR.items():
        if refs.get(key) != path:
            raise RuntimeError("CONTEXTO_SOCKET_PATH")
    return refs

def checked_dir(path: str, uid: int, gid: int, mode: int) -> bool:
    p = Path(path)
    if p.is_symlink() or not p.is_dir():
        return False
    st = p.stat()
    return (st.st_uid, st.st_gid, stat.S_IMODE(st.st_mode)) == (uid, gid, mode)

def composed(driver: dict, sequence: list[Path]) -> dict:
    # Inputs are absolute trusted repo files, and all sensitive substitutions
    # come solely from the private refs in subprocess environment.
    return driver["get_config"](sequence)

def validate_compose(driver: dict) -> dict:
    old = driver["files"](BASE_COUNT) + [
        ROOT / "deploy/dmz" / f for f in OLD_CANDIDATES
    ]
    new = old + [ROOT / "deploy/dmz" / NEW_OVERLAY]
    before = composed(driver, old)
    after = composed(driver, new)
    if set(before.get("services", {})) != set(after.get("services", {})):
        raise RuntimeError("COMPOSE_SERVICOS_DIVERGENTES")
    before_clean = copy.deepcopy(before)
    after_clean = copy.deepcopy(after)
    old_nginx = before_clean["services"]["nginx"]
    new_nginx = after_clean["services"]["nginx"]
    old_tmp = old_nginx.pop("tmpfs", None)
    new_tmp = new_nginx.pop("tmpfs", None)
    if before_clean != after_clean:
        raise RuntimeError("COMPOSE_MUDANCA_FORA_TMPFS")
    if not isinstance(old_tmp, list) or not isinstance(new_tmp, list):
        raise RuntimeError("COMPOSE_TMPFS_FORMATO")
    if not any(str(s).startswith("/var/run:") for s in old_tmp):
        raise RuntimeError("COMPOSE_ORIGINAL_INESPERADO")
    if any(str(s).startswith("/var/run:") for s in new_tmp):
        raise RuntimeError("COMPOSE_VAR_RUN_NAO_REMOVIDO")
    if sum(str(s).startswith("/run:") for s in new_tmp) != 1:
        raise RuntimeError("COMPOSE_RUN_NAO_CANONICO")
    if sum(str(s).startswith("/var/cache/nginx:") for s in new_tmp) != 1:
        raise RuntimeError("COMPOSE_CACHE_NGINX_DIVERGENTE")
    if len(new_tmp) != 2:
        raise RuntimeError("COMPOSE_TMPFS_EXTRA")
    if not after["services"]["nginx"].get("read_only"):
        raise RuntimeError("COMPOSE_ROOTFS_RW")
    driver["check_candidate"](driver["get_config"](driver["files"](BASE_COUNT)), after)
    print("COMPOSE_DIFF=APENAS_TMPFS_NGINX")
    print("COMPOSE_RUN_CANONICO=PASS")
    print("COMPOSE_SEGREGACAO=PASS")
    return after

def curl_code(path: str) -> tuple[int, str]:
    cmd = [
        "curl", "--silent", "--insecure", "--noproxy", "*",
        "--connect-timeout", "3", "--max-time", "10",
        "--output", "/dev/null", "--write-out", "%{http_code}",
        "https://192.168.6.34/" + path,
    ]
    p = subprocess.run(cmd, text=True, capture_output=True, timeout=13)
    code = p.stdout.strip()
    return p.returncode, code if re.fullmatch(r"[0-9]{3}", code) else "000"

def smoke() -> bool:
    all_good = True
    paths = (
        ("HEALTHZ", "healthz", "200"),
        ("LOGIN", "login.php", "200"),
        ("PUBLIC_KEY", "api/public_key.php", "200"),
        ("CRS_XSS", "?ga08_validation=%3Cscript%3Ealert%281%29%3C%2Fscript%3E", "403"),
    )
    for marker, path, expected in paths:
        try:
            rc, code = curl_code(path)
        except (OSError, subprocess.TimeoutExpired):
            rc, code = 99, "000"
        good = rc == 0 and code == expected
        print(f"WAF_{marker}_HTTP={code} RC={rc} RESULTADO=" + ("PASS" if good else "FAIL"))
        all_good &= good
    return all_good

def create_and_check_canary(module: dict, diff: dict, fix: dict, image_id: str) -> bool:
    name = "ga08-batch-fixed-" + secrets.token_hex(6)
    created = False
    try:
        argv = fix["alter"](module["args"](name, image_id), "RUN_CANONICO")
        position = argv.index(image_id)
        argv[position:position] = ["--entrypoint", "nginx"]
        argv += ["-g", "daemon off;"]
        start = module["call"](argv, timeout=65)
        if start.returncode:
            raise RuntimeError("CANARIO_NGINX_DOCKER_RUN")
        created = True
        current = None
        for _ in range(13):
            time.sleep(2)
            current = module["inspect"](name)
            state = current.get("State") or {}
            status = (state.get("Health") or {}).get("Status", "none")
            if not state.get("Running") or status in ("healthy", "unhealthy"):
                break
        state = (current or {}).get("State") or {}
        running = bool(state.get("Running"))
        health = (state.get("Health") or {}).get("Status") == "healthy"
        print("CANARIO_NGINX_RUNNING=" + ("SIM" if running else "NAO"))
        print("CANARIO_NGINX_HEALTHY=" + ("SIM" if health else "NAO"))
        tests = {
            "NGINX_TEST": ["nginx", "-t"],
            "DIR_HTTP_RW": ["test", "-w", "/run/conectaeduca-http"],
            "SOCKET_HTTP": ["test", "-S", "/run/conectaeduca-http/nginx.sock"],
            "DIR_FPM": ["test", "-d", "/run/conectaeduca-fpm"],
            "DIR_FPM_ACCESS": ["test", "-x", "/run/conectaeduca-fpm"],
        }
        valid = running and health
        for marker, sub in tests.items():
            okay = False
            if running:
                cmd = module["call"](["docker", "exec", name, *sub], timeout=15)
                okay = cmd.returncode == 0
            result("CANARIO_" + marker, okay)
            valid &= okay
        p = module["call"](["docker", "logs", "--tail", "80", name], timeout=12)
        category, target = diff["category_and_target"](p.stdout + "\n" + p.stderr)
        print("CANARIO_ERRO_CATEGORIA=" + category)
        print("CANARIO_ERRO_ALVO=" + target)
        return valid
    finally:
        if created:
            p = module["call"](["docker", "rm", "--force", name], timeout=35)
            result("CANARIO_ISOLADO_REMOVIDO", p.returncode == 0)
        else:
            print("CANARIO_ISOLADO_CRIADO=NAO")

def real_host_bind_ro(module: dict, diff: dict, fix: dict, image_id: str) -> bool:
    name = "ga08-batch-bind-ro-" + secrets.token_hex(6)
    created = False
    try:
        argv = fix["alter"](module["args"](name, image_id), "RUN_CANONICO")
        for path, _, _, _ in EXPECTED_DIR.values():
            if not Path(path).is_dir():
                raise RuntimeError("BIND_HOST_INEXISTENTE")
        # The original two transient tmpfs child mounts are replaced by RO
        # host sources. Never open/modify either host socket directory.
        for mount in ("/run/conectaeduca-http:", "/run/conectaeduca-fpm:"):
            loc = [
                i for i in range(len(argv)-1)
                if argv[i] == "--tmpfs" and argv[i+1].startswith(mount)
            ]
            if len(loc) != 1:
                raise RuntimeError("BIND_RO_FLAG_AMBIGUA")
            del argv[loc[0]:loc[0]+2]
        insert = argv.index(image_id)
        additions = []
        for parent, host in (
            ("/run/conectaeduca-http", "/var/lib/conectaeduca-ga08/http"),
            ("/run/conectaeduca-fpm", "/var/lib/conectaeduca-ga08/fpm"),
        ):
            additions.extend([
                "--mount",
                f"type=bind,src={host},dst={parent},readonly",
            ])
        additions.extend(["--entrypoint", "/bin/sh"])
        argv[insert:insert] = additions
        # Read-only shell checks; no Nginx start, no socket creation.
        argv.extend(["-c", "\n".join([
            "for path in /run/conectaeduca-http /run/conectaeduca-fpm; do",
            '  if test -d "$path" && test -x "$path"; then echo "CHECK_"$(basename "$path")"=PASS"; else echo "CHECK_"$(basename "$path")"=FAIL"; fi',
            "done",
            "for path in /run/conectaeduca-http /run/conectaeduca-fpm; do",
            '  if grep -Fq " $path " /proc/self/mountinfo; then echo "MOUNT_"$(basename "$path")"=PASS"; else echo "MOUNT_"$(basename "$path")"=FAIL"; fi',
            "done",
        ])])
        start = module["call"](argv, timeout=65)
        if start.returncode:
            raise RuntimeError("CANARIO_BIND_RO_DOCKER_RUN")
        created = True
        for _ in range(15):
            time.sleep(0.4)
            current = module["inspect"](name)
            state = current.get("State") or {}
            if not state.get("Running"):
                break
        p = module["call"](["docker", "logs", "--tail", "20", name], timeout=12)
        found = {}
        for line in p.stdout.splitlines():
            m = re.fullmatch(r"(CHECK|MOUNT)_(conectaeduca-http|conectaeduca-fpm)=(PASS|FAIL)", line.strip())
            if m:
                found[m.group(1) + "_" + m.group(2)] = m.group(3)
        markers = (
            "CHECK_conectaeduca-http",
            "CHECK_conectaeduca-fpm",
            "MOUNT_conectaeduca-http",
            "MOUNT_conectaeduca-fpm",
        )
        for marker in markers:
            print("BIND_RO_" + marker.upper().replace("-", "_") + "=" +
                  found.get(marker, "NAO_OBSERVADO"))
        return all(found.get(marker) == "PASS" for marker in markers)
    finally:
        if created:
            p = module["call"](["docker", "rm", "--force", name], timeout=35)
            result("CANARIO_BIND_RO_REMOVIDO", p.returncode == 0)
        else:
            print("CANARIO_BIND_RO_CRIADO=NAO")

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run", action="store_true")
    args = ap.parse_args()
    print("=== GA08.32 — BATERIA INTEGRADA PA02 ===", flush=True)
    if not args.run:
        print("MODO=PLANEJAMENTO")
        print("DOCKER_EXECUTADO=NAO")
        return 0
    if os.geteuid() == 0 or socket.gethostname().split(".")[0] not in (
        "ep125-pucpr", "ep125-pucpr-br"
    ):
        print("GA08_32=BLOCKED_IDENTIDADE")
        return 3
    try:
        initial_env = os.environ.copy()
        if os.environ.get("GA08_ENABLE_LIVE_CHANGE") == "YES":
            raise RuntimeError("INTERLOCK_LIVE_ATIVO")
        probe = runpy.run_path(str(ROOT / "scripts/ga08-nginx-canario-ep125.py"))
        for rel, expected in SOURCES.items():
            path = ROOT / rel
            if path.is_symlink() or not path.is_file() or probe["git_blob"](path) != expected:
                raise RuntimeError("SOURCE_BLOB_DIVERGENTE")
        for path in PUBLIC_CFG:
            p = ROOT / path
            if not p.is_file() or p.is_symlink() or not (stat.S_IMODE(p.stat().st_mode) & stat.S_IROTH):
                raise RuntimeError("CONFIG_NAO_LEGIVEL_UID_CONTAINER")
        print("FONTE_FIX_E_CONFIG=INTEGRA")
        refs = load_private_context()
        driver = runpy.run_path(str(ROOT / "scripts/ga08-change-control.py"))
        base = driver["current_baseline"]()
        result("BASELINE_3_SERVICOS_HEALTHY", len(base) == 3)
        for key, (path, uid, gid, mode) in EXPECTED_DIR.items():
            result("HOST_SOCKET_DIR_" + ("HTTP" if "HTTP" in key else "FPM"),
                   checked_dir(path, uid, gid, mode))
        # No secrets read; all Compose interpolation happens in subprocess env.
        os.environ.update(refs)
        try:
            validate_compose(driver)
        finally:
            os.environ.clear()
            os.environ.update(initial_env)
        baseline_smoke = smoke()
        result("BASELINE_WAF_SMOKE_4", baseline_smoke)
        diff = runpy.run_path(str(ROOT / "scripts/ga08-nginx-entrypoint-isolation-ep125.py"))
        fix = runpy.run_path(str(ROOT / "scripts/ga08-nginx-tmpfs-diferencial-ep125.py"))
        image = probe["preconditions"]()
        canary = create_and_check_canary(probe, diff, fix, image)
        result("CANDIDATO_NGINX_SANDBOX", canary)
        # All mounts in this test are read-only. It cannot create sockets on host.
        bind_ro = real_host_bind_ro(probe, diff, fix, image)
        result("BIND_HOST_REAL_LEITURA", bind_ro)
        passed = baseline_smoke and canary and bind_ro and all(
            checked_dir(path, uid, gid, mode) for path, uid, gid, mode in EXPECTED_DIR.values()
        )
        print("GA08_32=" + ("PASS_BATERIA_NAO_PRODUCAO" if passed else "FAIL_VER_MARCADORES"))
        print("BIND_HOST_RW_E2E_TESTADO=NAO")
        print("PA02_FECHADO=NAO")
        return 0 if passed else 1
    except (RuntimeError, ValueError, OSError, subprocess.TimeoutExpired) as error:
        reason = str(error)
        if not re.fullmatch(r"[A-Z0-9_]{1,100}", reason):
            reason = "ERRO_INDETERMINADO"
        print("GA08_32=BLOCKED_" + reason)
        return 3
    finally:
        print("CONTEINERES_PRODUCAO_MODIFICADOS=NAO_POR_ESTE_SCRIPT")
        print("COMPOSE_UP_EXECUTADO=NAO")
        print("CUTOVER_EXECUTADO=NAO")
        print("NAO_REUTILIZAR_CHANGE_ID_ANTIGO=SIM")

if __name__ == "__main__":
    sys.exit(main())
