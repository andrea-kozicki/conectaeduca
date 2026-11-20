#!/usr/bin/env python3
"""GA08.31: Differential Nginx socket mount test without modifying the EP125 stack.

Based on GA08.30's proven broken canary: run two disposable containers:
A: omit ONLY /var/run tmpfs; B: replace ONLY /var/run tmpfs by canonical /run.
Both are no-network, non-root, read-only, no secrets/host socket binds,
using exact installed nginx image and candidate config from GA08.28.
A passed directory check alone may still fail nginx due to read-only PID path;
do not confuse that failure with failed socket mounts. Each canary removed.
"""
from __future__ import annotations

import argparse
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
P28 = ROOT / "scripts/ga08-nginx-canario-ep125.py"
P29 = ROOT / "scripts/ga08-nginx-entrypoint-isolation-ep125.py"
P30 = ROOT / "scripts/ga08-nginx-runtime-paths-ep125.py"
BLOBS = {
    P28: "c460306bab91c300d0878bc7c1c8a1cf5676a2a7",
    P29: "502c475c479aa35d6b4f983bcf4a183bb39b1176",
    P30: "dba304a9525cfe043ebd0cfd18230121b100d76c",
}
CHECKS = (
    "GA08_RUN_DIR",
    "GA08_RUN_WRITABLE",
    "GA08_VAR_RUN_DIR",
    "GA08_VAR_RUN_SYMLINK",
    "GA08_HTTP_DIR",
    "GA08_HTTP_DIR_WRITABLE",
    "GA08_HTTP_DIR_EXECUTABLE",
    "GA08_HTTP_MOUNT_PRESENTE",
    "GA08_FPM_DIR",
    "GA08_PID_DIR_WRITABLE",
    "GA08_CACHE_DIR_WRITABLE",
    "GA08_NGINX_CONF_TEST",
)

def alter(argv: list[str], variant: str) -> list[str]:
    if variant not in ("SEM_VAR_RUN", "RUN_CANONICO"):
        raise ValueError("VARIANTE_INVALIDA")
    a = list(argv)
    locations = [
        i + 1 for i, v in enumerate(a[:-1])
        if v == "--tmpfs" and a[i+1].startswith("/var/run:")
    ]
    if len(locations) != 1:
        raise ValueError("TMPFS_VAR_RUN_AMBIGUO")
    i = locations[0]
    if variant == "SEM_VAR_RUN":
        del a[i-1:i+1]
    else:
        a[i] = "/run:" + a[i].split(":", 1)[1]
    return a

def probe(name: str, variant: str, module: dict, differential: dict, shell: str, image: str) -> tuple[bool, bool]:
    command = module["args"](name, image)
    command = alter(command, variant)
    index = command.index(image)
    command[index:index] = ["--entrypoint", "/bin/sh"]
    command.extend(["-c", shell])
    created = False
    running = False
    directory_ready = False
    print("=== VARIANTE_" + variant + " ===", flush=True)
    try:
        start = module["call"](command, timeout=60)
        if start.returncode:
            print("CONTAINER_START=FAIL")
            return False, False
        created = True
        final = None
        for _ in range(12):
            time.sleep(2)
            final = module["inspect"](name)
            state = final.get("State") or {}
            health = (state.get("Health") or {}).get("Status", "none")
            if not state.get("Running") or health in ("healthy", "unhealthy"):
                break
        state = (final or {}).get("State") or {}
        running = bool(state.get("Running"))
        health = (state.get("Health") or {}).get("Status", "none")
        print("RUNNING=" + ("SIM" if running else "NAO"))
        print("HEALTH=" + (health.upper() if re.fullmatch(r"[a-z]+", health) else "INDETERMINADO"))
        code = state.get("ExitCode")
        print("EXIT_CODE=" + (str(code) if isinstance(code, int) else "INDETERMINADO"))
        result = module["call"](["docker", "logs", "--tail", "100", name], timeout=12)
        logs = result.stdout + "\n" + result.stderr
        found = {}
        valid = set(CHECKS)
        for line in logs.splitlines():
            m = re.fullmatch(r"(GA08_[A-Z0-9_]+)=(SIM|NAO|PASS|FAIL)", line.strip())
            if m and m.group(1) in valid:
                found[m.group(1)] = m.group(2)
        for key in CHECKS:
            print(key.replace("GA08_", "") + "=" + found.get(key, "NAO_OBSERVADO"))
        category, target = differential["category_and_target"](logs)
        print("ERRO_FATAL_CATEGORIA=" + category)
        print("ERRO_FATAL_ALVO=" + target)
        directory_ready = (
            found.get("GA08_HTTP_DIR") == "SIM"
            and found.get("GA08_HTTP_DIR_WRITABLE") == "SIM"
            and found.get("GA08_HTTP_DIR_EXECUTABLE") == "SIM"
            and found.get("GA08_HTTP_MOUNT_PRESENTE") == "SIM"
            and found.get("GA08_FPM_DIR") == "SIM"
        )
        print("DIRETORIOS_SOCKET_VISIVEIS=" + ("SIM" if directory_ready else "NAO"))
        healthy = running and health == "healthy"
        if healthy:
            p = module["call"]([
                "docker", "exec", name, "test", "-S",
                "/run/conectaeduca-http/nginx.sock"
            ], timeout=12)
            print("SOCKET_HTTP_PRESENTE=" + ("SIM" if p.returncode == 0 else "NAO"))
            healthy = p.returncode == 0
        else:
            print("SOCKET_HTTP_PRESENTE=NAO_VALIDADO")
        print("VARIANTE_RESULTADO=" + (
            "PASS_COMPLETO" if healthy and directory_ready else
            "DIRETORIOS_RECUPERADOS" if directory_ready else
            "MONTAGENS_AINDA_INCONSISTENTES"
        ))
        return directory_ready, healthy
    finally:
        if created:
            result = module["call"](["docker", "rm", "--force", name], timeout=30)
            print("CANARIO_REMOVIDO=" + ("SIM" if result.returncode == 0 else "NAO"))
        else:
            print("CANARIO_CRIADO=NAO")

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    opts = parser.parse_args()
    print("=== GA08.31 — DIFERENCIAL TMPFS /VAR/RUN E /RUN ===", flush=True)
    if not opts.run:
        print("MODO=PLANO")
        print("DOCKER_EXECUTADO=NAO")
        return 0
    if os.geteuid() == 0 or socket.gethostname().split(".")[0] not in (
        "ep125-pucpr", "ep125-pucpr-br"
    ):
        print("GA08_31=BLOCKED_IDENTIDADE")
        return 3
    try:
        if any(not p.is_file() or p.is_symlink() for p in BLOBS):
            raise RuntimeError("SCRIPT_DEPENDENCIA_AUSENTE")
        module = runpy.run_path(str(P28))
        if any(module["git_blob"](p) != expected for p, expected in BLOBS.items()):
            raise RuntimeError("SCRIPT_DEPENDENCIA_DIVERGENTE")
        differential = runpy.run_path(str(P29))
        reader = runpy.run_path(str(P30))
        image = module["preconditions"]()
        print("SCRIPTS_E_CANDIDATO=INTEGROS")
        print("NGINX_BASELINE=HEALTHY")
        outcomes = {}
        for variant in ("SEM_VAR_RUN", "RUN_CANONICO"):
            name = "ga08-nginx-tmpfs-" + secrets.token_hex(6)
            outcomes[variant] = probe(name, variant, module, differential, reader["SHELL_PROBE"], image)
        for variant, (dirs, healthy) in outcomes.items():
            print("RESULTADO_" + variant + "=" + (
                "PASS_COMPLETO" if dirs and healthy else
                "DIR_VISIVEL_NGINX_PENDENTE" if dirs else "DIR_OCULTO_OU_INACESSIVEL"
            ))
        if outcomes["RUN_CANONICO"] == (True, True):
            print("HIPOTESE_SOBREPOSICAO=REFORCADA")
        elif outcomes["RUN_CANONICO"][0] or outcomes["SEM_VAR_RUN"][0]:
            print("HIPOTESE_SOBREPOSICAO=PARCIAL")
        else:
            print("HIPOTESE_SOBREPOSICAO=NAO_COMPROVADA")
        print("GA08_31=DIAGNOSTICO_CONCLUIDO")
        return 0
    except (RuntimeError, ValueError, OSError, subprocess.TimeoutExpired) as error:
        reason = str(error)
        if not re.fullmatch(r"[A-Z0-9_]{1,100}", reason):
            reason = "ERRO_INDETERMINADO"
        print("GA08_31=BLOCKED_" + reason)
        return 3
    finally:
        print("MONTAGENS_HOST_TESTADAS=NAO")
        print("DOCKER_COMPOSE_EXECUTADO=NAO")
        print("SERVICOS_PRODUCAO_MODIFICADOS=NAO_POR_ESTE_SCRIPT")
        print("CUTOVER_EXECUTADO=NAO")

if __name__ == "__main__":
    sys.exit(main())
