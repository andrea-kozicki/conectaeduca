#!/usr/bin/env python3
"""CE-PA02-RW01: verificar escrita/limpeza no bind HTTP sem tocar na producao.

Um unico container descartavel, sem rede/secrets, user 101:101.
Nao executa Docker Compose nem altera o socket real do host.
"""
from __future__ import annotations
import datetime as dt
import json
import os
from pathlib import Path
import secrets
import socket
import stat
import subprocess
import sys

BIND = Path("/var/lib/conectaeduca-ga08/http")
PROJECT = "conectaeduca-dmz"
SERVICE = "nginx"
EXPECTED_PARENT = (101, 101, 0o700)

def checked(args: list[str], timeout: int = 25) -> str:
    try:
        p = subprocess.run(args, capture_output=True, text=True,
                           timeout=timeout, check=False)
    except (subprocess.TimeoutExpired, OSError):
        raise RuntimeError("DOCKER_NAO_RESPONDE")
    if p.returncode:
        raise RuntimeError("COMANDO_FALHOU")
    return p.stdout.strip()

def main() -> None:
    print("=== CE-PA02-RW01 — BIND HTTP ISOLADO ===", flush=True)
    print("DATA=" + dt.datetime.now().astimezone().isoformat(timespec="seconds"))
    if sys.argv[1:]:
        raise RuntimeError("SEM_ARGUMENTOS")
    if os.geteuid() == 0 or checked(["whoami"]) != "andrea.kiew":
        raise RuntimeError("USUARIO_NAO_AUTORIZADO")
    if socket.gethostname().split(".")[0] not in ("ep125-pucpr", "ep125-pucpr-br"):
        raise RuntimeError("HOST_NAO_EP125")
    if BIND.is_symlink() or not BIND.is_dir():
        raise RuntimeError("DIR_HTTP_INEXISTENTE")
    st = BIND.stat()
    if (st.st_uid, st.st_gid, stat.S_IMODE(st.st_mode)) != EXPECTED_PARENT:
        raise RuntimeError("DIR_HTTP_PERMISSOES_DIVERGENTES")
    print("BIND_HTTP_PERMISSOES=PASS")

    ids = checked(["docker", "ps", "-q",
        "--filter", "label=com.docker.compose.project=" + PROJECT,
        "--filter", "label=com.docker.compose.service=" + SERVICE]).splitlines()
    if len(ids) != 1:
        raise RuntimeError("NGINX_CONTÊINER_NAO_UNICO")
    data = json.loads(checked(["docker", "inspect", ids[0]]))[0]
    labels = data.get("Config", {}).get("Labels", {})
    if labels.get("com.docker.compose.project") != PROJECT or labels.get(
            "com.docker.compose.service") != SERVICE:
        raise RuntimeError("NGINX_LABELS_DIVERGENTES")
    if (data.get("State", {}).get("Health", {}).get("Status") != "healthy" or
        data.get("State", {}).get("Running") is not True):
        raise RuntimeError("NGINX_BASELINE_NAO_HEALTHY")
    image_id = data.get("Image", "")
    if not image_id.startswith("sha256:") or len(image_id) != 71:
        raise RuntimeError("NGINX_IMAGE_ID_INVALIDO")
    print("NGINX_BASELINE=HEALTHY")

    # UID 101 do container cria e remove somente seu nome aleatorio.
    # Nao le nem remove outras entradas; o socket de producao nao e tocado.
    name = "ga08-rw01-" + secrets.token_hex(8)
    target = "/ga08-http/" + name
    result = subprocess.run([
        "docker", "run", "--rm", "--pull", "never",
        "--network", "none", "--read-only",
        "--user", "101:101", "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges:true",
        "--pids-limit", "32",
        "--mount", "type=bind,src=" + str(BIND) + ",dst=/ga08-http",
        "--entrypoint", "/bin/sh", image_id,
        "-ec", "mkdir -m 0700 -- \"$1\"; rmdir -- \"$1\"", "sh", target,
    ], capture_output=True, text=True, timeout=35, check=False)
    if result.returncode:
        raise RuntimeError("BIND_HTTP_RW_OU_CLEANUP_NAO_CONFIRMADO")
    print("BIND_HTTP_RW=PASS")
    print("BIND_HTTP_LIMPEZA=PASS")
    print("CONTEINER_CANARIO=DESCARTADO")
    print("NGINX_PRODUCAO_ALTERADO=NAO")
    print("PHP_PA05_ALTERADO=NAO")
    print("DOCKER_COMPOSE_EXECUTADO=NAO")
    print("CE-PA02-RW01_CONCLUIDO")

if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, json.JSONDecodeError, subprocess.TimeoutExpired, OSError) as exc:
        print("CE-PA02-RW01_ABORTADO=" + (
            str(exc) if isinstance(exc, RuntimeError)
            else type(exc).__name__), file=sys.stderr)
        sys.exit(1)
