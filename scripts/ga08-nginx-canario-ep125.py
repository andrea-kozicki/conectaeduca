#!/usr/bin/env python3
"""GA08.28: isolated rootless Nginx Unix-HTTP candidate canary for EP125.

Default is plan only. --run creates ONE ephemeral container with the SAME
installed Nginx image ID, exact candidate config, UID101/GID101, no network,
no secrets, no host socket/data bind, read-only rootfs and tmpfs runtime.
It verifies health, socket, nginx -t and prints sanitized error classes.
The canary is always removed. It DOES NOT test persistent host bind or E2E WAF.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import socket
import stat
import subprocess
import sys
import time

ROOT = Path("/opt/conectaeduca")
CONFIG = ROOT / "deploy/dmz/ga08/app-http.dual-socket.candidate.conf"
EXPECTED_BLOB = "d659dcabf1123c1b8b4b38bc4b381bf34a0d34f2"
NAME = "conectaeduca-dmz-nginx-1"
SOCKET = "/run/conectaeduca-http/nginx.sock"
SOCKET_PARENT = "/run/conectaeduca-http"
HEALTH_CMD = "nginx -t >/dev/null 2>&1 && test -S " + SOCKET

def call(args: list[str], timeout: int = 20) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)

def inspect(name: str) -> dict:
    result = call(["docker", "inspect", name])
    if result.returncode:
        raise RuntimeError("DOCKER_INSPECT_FALHOU")
    try:
        data = json.loads(result.stdout)
    except ValueError as error:
        raise RuntimeError("DOCKER_JSON_INVALIDO") from error
    if not isinstance(data, list) or len(data) != 1:
        raise RuntimeError("DOCKER_JSON_INVALIDO")
    return data[0]

def git_blob(path: Path) -> str:
    data = path.read_bytes()
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()

def preconditions() -> str:
    if os.geteuid() == 0 or socket.gethostname().split(".")[0] not in (
        "ep125-pucpr", "ep125-pucpr-br"
    ):
        raise RuntimeError("HOST_OU_IDENTIDADE_INVALIDOS")
    if CONFIG.is_symlink() or not CONFIG.is_file():
        raise RuntimeError("CONFIG_NAO_REGULAR")
    st = CONFIG.stat()
    if not stat.S_ISREG(st.st_mode) or not (stat.S_IMODE(st.st_mode) & stat.S_IROTH):
        raise RuntimeError("CONFIG_NAO_LEGIVEL_POR_101")
    if git_blob(CONFIG) != EXPECTED_BLOB:
        raise RuntimeError("CONFIG_BLOB_DIVERGENTE")
    image = inspect(NAME)
    labels = (image.get("Config") or {}).get("Labels") or {}
    state = image.get("State") or {}
    if (labels.get("com.docker.compose.project") != "conectaeduca-dmz"
            or labels.get("com.docker.compose.service") != "nginx"):
        raise RuntimeError("NGINX_NAO_EH_STACK")
    if not state.get("Running") or (state.get("Health") or {}).get("Status") != "healthy":
        raise RuntimeError("NGINX_PRODUCAO_NAO_HEALTHY")
    image_id = image.get("Image", "")
    if not isinstance(image_id, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", image_id):
        raise RuntimeError("IMAGE_ID_INVALIDO")
    return image_id

def args(name: str, image: str) -> list[str]:
    return [
        "docker", "run", "--detach", "--pull", "never", "--name", name,
        "--network", "none", "--read-only", "--user", "101:101",
        "--group-add", "82", "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges:true", "--pids-limit", "128",
        "--memory", "256m", "--restart", "no",
        "--mount", "type=bind,src=" + str(CONFIG) +
            ",dst=/etc/nginx/conf.d/default.conf,readonly",
        "--tmpfs", "/var/cache/nginx:rw,nosuid,nodev,noexec,size=16m,uid=101,gid=101,mode=0750",
        "--tmpfs", "/var/run:rw,nosuid,nodev,noexec,size=4m,uid=101,gid=101,mode=0750",
        "--tmpfs", SOCKET_PARENT + ":rw,nosuid,nodev,noexec,size=1m,uid=101,gid=101,mode=0700",
        "--tmpfs", "/run/conectaeduca-fpm:rw,nosuid,nodev,noexec,size=1m,uid=82,gid=82,mode=0770",
        "--health-cmd", HEALTH_CMD,
        "--health-interval", "2s", "--health-timeout", "2s",
        "--health-retries", "3", "--health-start-period", "3s",
        image,
    ]

def classify(logs: str) -> str:
    text = logs.lower()
    if "permission denied" in text or "operation not permitted" in text:
        return "PERMISSAO"
    if "read-only file system" in text:
        return "ROOTFS_RO"
    if "address already in use" in text:
        return "SOCKET_OCUPADO"
    if "no such file or directory" in text or "not found" in text:
        return "ARQUIVO_OU_DIRETORIO"
    if "[emerg]" in text or "invalid number" in text or "unknown directive" in text:
        return "CONFIGURACAO_NGINX"
    if "error" in text or "failed" in text:
        return "OUTRO_ERRO"
    return "SEM_ERRO_IDENTIFICADO"

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    opt = parser.parse_args()
    print("=== GA08.28 — CANARIO NGINX HTTP UNIX ISOLADO ===", flush=True)
    if not opt.run:
        print("MODO=PLANO")
        print("CONTEINER_CRIADO=NAO")
        return 0
    tempname = "ga08-nginx-canary-" + secrets.token_hex(6)
    created = False
    try:
        image_id = preconditions()
        response = call(args(tempname, image_id), timeout=60)
        if response.returncode:
            raise RuntimeError("DOCKER_RUN_FALHOU")
        created = True
        print("CONFIG_INTEGRIDADE=PASS")
        final = {}
        for _ in range(15):
            time.sleep(2)
            final = inspect(tempname)
            state = final.get("State") or {}
            health = (state.get("Health") or {}).get("Status", "none")
            if not state.get("Running") or health in ("healthy", "unhealthy"):
                break
        state = final.get("State") or {}
        running = bool(state.get("Running"))
        health = (state.get("Health") or {}).get("Status", "none")
        print("NGINX_RUNNING=" + ("SIM" if running else "NAO"))
        print("NGINX_HEALTH=" + health.upper())
        code = state.get("ExitCode", -1)
        print("NGINX_EXIT_CODE=" + (str(code) if isinstance(code, int) else "INDETERMINADO"))
        checks = (
            ("CONFIG_TEST", ["nginx", "-t"]),
            ("SOCKET_DIR_RW", ["test", "-w", SOCKET_PARENT]),
            ("SOCKET_UNIX_PRESENTE", ["test", "-S", SOCKET]),
        )
        results = {}
        if running:
            for key, command in checks:
                test = call(["docker", "exec", tempname, *command], timeout=15)
                results[key] = test.returncode == 0
                print(key + "=" + ("PASS" if results[key] else "FAIL"))
        else:
            for key, _ in checks:
                results[key] = False
                print(key + "=NAO_EXECUTADO")
        logs = call(["docker", "logs", "--tail", "60", tempname], timeout=12)
        category = classify(logs.stdout + "\n" + logs.stderr)
        print("LOG_CATEGORIA=" + category)
        success = (
            running and health == "healthy"
            and all(results.values())
        )
        print("GA08_28=" + ("PASS_SANDBOX" if success else "FALHA_DIAGNOSTICADA"))
        print("BIND_PERSISTENTE_HOST_TESTADO=NAO")
        return 0 if success else 1
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        reason = str(error)
        if not re.fullmatch(r"[A-Z0-9_]{1,90}", reason):
            reason = "ERRO_AMBIENTE"
        print("GA08_28=BLOCKED_" + reason)
        return 3
    finally:
        # Random tokenised name and --restart=no; cannot touch production service.
        if created:
            removed = call(["docker", "rm", "--force", tempname], timeout=30)
            print("CANARIO_REMOVIDO=" + ("SIM" if removed.returncode == 0 else "NAO"))
        else:
            print("CANARIO_CRIADO=NAO")
        print("DOCKER_COMPOSE_EXECUTADO=NAO")
        print("SERVICOS_PRODUCAO_MODIFICADOS=NAO_POR_ESTE_SCRIPT")
        print("CUTOVER_EXECUTADO=NAO")

if __name__ == "__main__":
    sys.exit(main())
