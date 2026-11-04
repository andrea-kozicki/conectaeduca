#!/usr/bin/env python3
"""GA08.29: differential rootless nginx canary that bypasses ONLY image entrypoint.

GA08.28 baseline already failed in an isolated disposable container.
With --run GA08.29 starts one disposable container from the SAME running image
and the same RO/tmpfs/no-network/no-secrets flags as GA08.28, but uses
--entrypoint nginx -g "daemon off;". It tests whether fatal failure comes
from entrypoint vs core Nginx/socket. This is NOT production, no persistent
host socket bind, no Compose, no cutover and never edits source files.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import runpy
import secrets
import socket
import subprocess
import sys
import time

ROOT = Path("/opt/conectaeduca")
CANARY = ROOT / "scripts/ga08-nginx-canario-ep125.py"
CANARY_GIT_BLOB = "c460306bab91c300d0878bc7c1c8a1cf5676a2a7"
HTTP_SOCKET = "/run/conectaeduca-http/nginx.sock"

def category_and_target(logs: str) -> tuple[str, str]:
    # Prioritize fatal Nginx records over informational Docker entrypoint
    # warnings such as "can not modify read-only default.conf".
    lines = logs.splitlines()[:100]
    fatal = [s for s in lines if re.search(r"nginx: \[(?:emerg|alert|crit)\]", s, re.I)]
    errors = [s for s in lines if re.search(r"permission denied|read-only file system|not found|no such file|failed|error", s, re.I)]
    candidates = fatal or errors
    if not candidates:
        return "SEM_ERRO_IDENTIFICADO", "NAO_APLICAVEL"
    # Use newest actionable line; never print its contents or raw paths.
    s = candidates[-1].lower()
    if "permission denied" in s or "operation not permitted" in s:
        code = "PERMISSAO"
    elif "read-only file system" in s:
        code = "ROOTFS_RO"
    elif "address already in use" in s:
        code = "SOCKET_OCUPADO"
    elif "no such file" in s or "not found" in s:
        code = "ARQUIVO_AUSENTE"
    elif "nginx: [emerg]" in s:
        code = "NGINX_EMERG"
    else:
        code = "OUTRO_ERRO"
    if "/run/conectaeduca-http/nginx.sock" in s:
        where = "SOCKET_HTTP"
    elif "/run/conectaeduca-http" in s:
        where = "DIRETORIO_HTTP"
    elif "/run/conectaeduca-fpm" in s:
        where = "SOCKET_FPM"
    elif "/var/cache/nginx" in s:
        where = "CACHE_NGINX"
    elif "/var/run" in s or "/run/nginx.pid" in s or "nginx.pid" in s:
        where = "PID_NGINX"
    elif "/etc/nginx" in s:
        where = "CONFIG_NGINX"
    elif "/var/log/nginx" in s:
        where = "LOG_NGINX"
    elif "/docker-entrypoint" in s:
        where = "ENTRYPOINT"
    else:
        where = "OUTRO_ALVO"
    return code, where

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run", action="store_true")
    opts = ap.parse_args()
    print("=== GA08.29 — NGINX DIRETO SEM ENTRYPOINT ===", flush=True)
    if not opts.run:
        print("MODO=PLANO")
        print("DOCKER_EXECUTADO=NAO")
        return 0
    if os.geteuid() == 0 or socket.gethostname().split(".")[0] not in ("ep125-pucpr", "ep125-pucpr-br"):
        print("GA08_29=BLOCKED_IDENTIDADE")
        return 3
    name = "ga08-nginx-direct-" + secrets.token_hex(6)
    created = False
    can = None
    try:
        # Enforce exact input script that the operator already used for GA08.28
        # and exact candidate Git blob through its preconditions.
        if not CANARY.is_file() or CANARY.is_symlink():
            raise RuntimeError("CANARIO_BASE_AUSENTE")
        can = runpy.run_path(str(CANARY))
        if can["git_blob"](CANARY) != CANARY_GIT_BLOB:
            raise RuntimeError("CANARIO_BASE_DIVERGENTE")
        image_id = can["preconditions"]()
        argv = can["args"](name, image_id)
        index = argv.index(image_id)
        argv[index:index] = ["--entrypoint", "nginx"]
        argv.extend(["-g", "daemon off;"])
        started = can["call"](argv, timeout=60)
        if started.returncode:
            raise RuntimeError("DOCKER_RUN_RECUSADO")
        created = True
        print("IMAGE_ORIGINAL=PASS")
        print("CONFIG_CANDIDATA_INTEGRIDADE=PASS")
        print("ENTRYPOINT_BYPASS=SIM")
        last = None
        for _ in range(12):
            time.sleep(2)
            last = can["inspect"](name)
            state = last.get("State") or {}
            status = (state.get("Health") or {}).get("Status", "none")
            if not state.get("Running") or status in ("healthy", "unhealthy"):
                break
        state = last.get("State") or {}
        running = bool(state.get("Running"))
        health = str((state.get("Health") or {}).get("Status", "none")).upper()
        code = state.get("ExitCode")
        print("NGINX_DIRETO_RUNNING=" + ("SIM" if running else "NAO"))
        print("NGINX_DIRETO_HEALTH=" + (health if re.fullmatch(r"[A-Z]+", health) else "INDETERMINADO"))
        print("NGINX_DIRETO_EXIT_CODE=" + (str(code) if isinstance(code, int) else "INDETERMINADO"))
        checks = (
            ("NGINX_CONFIG_TEST", ["nginx", "-t"]),
            ("HTTP_SOCKET_DIR_RW", ["test", "-w", "/run/conectaeduca-http"]),
            ("HTTP_SOCKET_PRESENTE", ["test", "-S", HTTP_SOCKET]),
        )
        results = []
        for label, argv in checks:
            if not running:
                print(label + "=NAO_EXECUTADO")
                results.append(False)
            else:
                p = can["call"](["docker", "exec", name, *argv], timeout=15)
                pass_ = p.returncode == 0
                print(label + "=" + ("PASS" if pass_ else "FAIL"))
                results.append(pass_)
        logs = can["call"](["docker", "logs", "--tail", "80", name], timeout=12)
        cat, target = category_and_target(logs.stdout + "\n" + logs.stderr)
        print("ERRO_FATAL_CATEGORIA=" + cat)
        print("ERRO_FATAL_ALVO=" + target)
        good = running and health == "HEALTHY" and all(results)
        if good:
            print("CAUSA_ENTRYPOINT=HIPOTESE_REFORCADA")
        else:
            print("CAUSA_ENTRYPOINT=NAO_ISOLADA")
        print("GA08_29=" + ("PASS_SANDBOX" if good else "FALHA_DIAGNOSTICADA"))
        return 0 if good else 1
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        reason = str(error)
        if not re.fullmatch(r"[A-Z0-9_]{1,100}", reason):
            reason = "ERRO_NAO_CLASSIFICADO"
        print("GA08_29=BLOCKED_" + reason)
        return 3
    finally:
        if created and can is not None:
            result = can["call"](["docker", "rm", "--force", name], timeout=30)
            print("CANARIO_REMOVIDO=" + ("SIM" if result.returncode == 0 else "NAO"))
        else:
            print("CANARIO_CRIADO=NAO")
        print("CONFIGURACAO_ALTERADA=NAO")
        print("BIND_HOST_PERSISTENTE_TESTADO=NAO")
        print("SERVICOS_PRODUCAO_MODIFICADOS=NAO")
        print("CUTOVER_EXECUTADO=NAO")

if __name__ == "__main__":
    sys.exit(main())
