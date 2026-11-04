#!/usr/bin/env python3
"""GA08.20: investigate the PHP-FPM Unix socket in a disposable canary.

Default mode does nothing. --run creates ONLY one ephemeral Docker container,
with network=none, no secrets, no Compose and no host socket mounts. The PHP
image is addressed by its exact currently running image ID; the candidate FPM
configuration is bind-mounted read-only. This is NOT a replacement for a test
of the real host bind mount or for an end-to-end application test.

Usage on EP125, outside a cutover window:
    python3 scripts/ga08-canario-fpm-offline-ep125.py
    python3 scripts/ga08-canario-fpm-offline-ep125.py --run
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
FPM_CONFIG = ROOT / "deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf"
PHP_NAME = "conectaeduca-dmz-php-1"
SOCKET = "/run/conectaeduca-fpm/php-fpm.sock"

def docker(args: list[str], *, timeout: int = 20) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["docker", *args], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=timeout, check=False
    )

def inspect(name: str) -> dict:
    p = docker(["inspect", name])
    if p.returncode:
        raise RuntimeError("DOCKER_INSPECT")
    try:
        data = json.loads(p.stdout)
        if not isinstance(data, list) or len(data) != 1:
            raise ValueError
        return data[0]
    except (ValueError, TypeError, KeyError) as e:
        raise RuntimeError("DOCKER_INSPECT_JSON") from e

def classify(log: str) -> str:
    if re.search(r"permission denied|operation not permitted|access denied", log, re.I):
        return "PERMISSAO"
    if re.search(r"address already in use|already being used", log, re.I):
        return "SOCKET_OCUPADO"
    if re.search(r"no such file or directory|not found", log, re.I):
        return "ARQUIVO_OU_DIRETORIO"
    if re.search(r"failed to open configuration|configuration file.*failed", log, re.I):
        return "CONFIGURACAO"
    if re.search(r"unable to bind|bind\(\) failed|listen\(\)", log, re.I):
        return "LISTENER"
    if re.search(r"ready to handle connections|fpm is running", log, re.I):
        return "FPM_INICIOU"
    return "SEM_CLASSIFICACAO"

def assert_preconditions() -> str:
    if socket.gethostname().split(".")[0] not in ("ep125-pucpr", "ep125-pucpr-br"):
        raise RuntimeError("HOST_FORA_EP125")
    if os.geteuid() == 0:
        raise RuntimeError("ROOT_NAO_PERMITIDO")
    if not FPM_CONFIG.is_file() or FPM_CONFIG.is_symlink():
        raise RuntimeError("FPM_CANDIDATO_AUSENTE")
    if "listen = " + SOCKET not in FPM_CONFIG.read_text(encoding="utf-8"):
        raise RuntimeError("FPM_LISTENER_DIVERGENTE")
    container = inspect(PHP_NAME)
    labels = ((container.get("Config") or {}).get("Labels") or {})
    state = container.get("State") or {}
    if (labels.get("com.docker.compose.project") != "conectaeduca-dmz"
            or labels.get("com.docker.compose.service") != "php"):
        raise RuntimeError("PHP_NAO_E_DA_STACK")
    if not state.get("Running") or ((state.get("Health") or {}).get("Status")) != "healthy":
        raise RuntimeError("BASELINE_PHP_NAO_HEALTHY")
    image_id = container.get("Image")
    if not isinstance(image_id, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", image_id):
        raise RuntimeError("IMAGEM_INVALIDA")
    user = str((container.get("Config") or {}).get("User", ""))
    if user not in ("www-data", "82", "82:82"):
        raise RuntimeError("PHP_USER_INESPERADO")
    return image_id

def canary_args(name: str, image_id: str) -> list[str]:
    # Docker tmpfs simulates uid/gid and read-only rootfs; does NOT prove
    # owner/mode of the persistent bind directory on the EP125 host.
    tmpfs = [
        "/run/conectaeduca-fpm:rw,nosuid,nodev,noexec,size=1m,uid=82,gid=82,mode=0770",
        "/tmp:rw,nosuid,nodev,noexec,size=64m,uid=82,gid=82,mode=1770",
        "/var/www/conectaeduca/storage/logs:rw,nosuid,nodev,noexec,size=32m,uid=82,gid=82,mode=0770",
        "/var/www/conectaeduca/storage/keys:rw,nosuid,nodev,noexec,size=4m,uid=82,gid=82,mode=0770",
    ]
    args = [
        "run", "--detach", "--pull", "never", "--name", name,
        "--network", "none", "--read-only",
        "--user", "82:82", "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges:true",
        "--pids-limit", "128", "--memory", "384m",
        "--restart", "no",
        "--mount", "type=bind,src=" + str(FPM_CONFIG.resolve())
        + ",dst=/usr/local/etc/php-fpm.d/zz-conectaeduca.conf,readonly",
        "--entrypoint", "php-fpm",
    ]
    for entry in tmpfs:
        args.extend(["--tmpfs", entry])
    return [*args, image_id, "-F"]

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true",
                        help="start and remove one network-isolated ephemeral PHP canary")
    opts = parser.parse_args()
    print("=== GA08.20 — CANARIO PHP-FPM SEM REDE/SEGREDOS ===")
    if not opts.run:
        print("MODO=PLANEJAMENTO")
        print("DOCKER_EXECUTADO=NAO")
        print("CUTOVER_EXECUTADO=NAO")
        print("USE_RUN_APENAS_NA_EP125=SIM")
        return 0
    name = "ga08-fpm-canary-" + secrets.token_hex(5)
    created = False
    outcome = 3
    try:
        image_id = assert_preconditions()
        start = docker(canary_args(name, image_id), timeout=60)
        if start.returncode:
            raise RuntimeError("DOCKER_RUN_REJEITADO")
        created = True
        health = "INDETERMINADO"
        running = False
        for _ in range(12):
            time.sleep(2)
            data = inspect(name)
            state = data.get("State") or {}
            running = bool(state.get("Running"))
            health = str((state.get("Health") or {}).get("Status", "INDETERMINADO"))
            if not running or health in ("healthy", "unhealthy"):
                break
        print("CANARIO_RUNNING=" + ("SIM" if running else "NAO"))
        print("CANARIO_HEALTH=" + health.upper())
        if running:
            test_cfg = docker(["exec", name, "php-fpm", "-t"], timeout=15)
            test_sock = docker(["exec", name, "test", "-S", SOCKET], timeout=15)
            print("FPM_CONFIG=" + ("PASS" if test_cfg.returncode == 0 else "FAIL"))
            print("SOCKET_UNIX_PRESENTE=" +
                  ("SIM" if test_sock.returncode == 0 else "NAO"))
        else:
            print("FPM_CONFIG=NAO_EXECUTADO")
            print("SOCKET_UNIX_PRESENTE=NAO_AVALIADO")
        p = docker(["logs", "--tail", "80", name], timeout=12)
        # Deliberately print only a category, never raw container log data.
        print("FPM_LOG_CATEGORIA=" + classify(p.stdout + "\n" + p.stderr))
        outcome = 0 if running and health == "healthy" and (
            test_cfg.returncode == 0 and test_sock.returncode == 0
        ) else 1
        print("GA08_CANARIO=" + ("PASS" if outcome == 0 else "FAIL"))
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
        reason = str(exc)
        if not re.fullmatch(r"[A-Z0-9_]{1,100}", reason):
            reason = "INDETERMINADO"
        print("GA08_CANARIO=BLOCKED_" + reason)
    finally:
        if created:
            removal = docker(["rm", "--force", name], timeout=30)
            print("CANARIO_REMOVIDO=" + ("SIM" if removal.returncode == 0 else "NAO"))
        else:
            print("CANARIO_CRIADO=NAO")
        print("DOCKER_COMPOSE_EXECUTADO=NAO")
        print("SERVICOS_PRODUCAO_MODIFICADOS=NAO_POR_ESTE_SCRIPT")
        print("CUTOVER_EXECUTADO=NAO")
        print("TESTE_BIND_PERSISTENTE=NAO_ABRANGIDO")
    return outcome

if __name__ == "__main__":
    sys.exit(main())
