#!/usr/bin/env python3
"""GA08.18F: Resolve somente referências de interpolação do Compose a partir
do runtime Docker da EP125; não lê arquivos de segredos e não executa cutover.
Execução: python3 scripts/ga08-preflight-env-runtime-ep125.py
"""
from __future__ import annotations
import json
import os
import re
import socket
import subprocess
import sys
from pathlib import Path

ROOT = Path("/opt/conectaeduca")
PREFLIGHT = ROOT / "scripts/ga08-implantacao-controlada-ep125.sh"
TARGETS = {
    "php": "conectaeduca-dmz-php-1",
    "waf": "conectaeduca-dmz-waf-1",
    "nginx": "conectaeduca-dmz-nginx-1",
}
GA08_VARS = (
    "CONECTAEDUCA_GA08_SOCKET_DIR",
    "CONECTAEDUCA_GA08_HTTP_SOCKET_DIR",
    "CONECTAEDUCA_GA08_NGINX_CONF",
    "CONECTAEDUCA_GA08_NGINX_HTTP_UNIX_CONF",
    "CONECTAEDUCA_GA08_FPM_CONF",
)
SECRET_MOUNTS = {
    "CONECTAEDUCA_DB_PASSWORD_FILE": ("php", "conectaeduca_db_password"),
    "CONECTAEDUCA_PRIVATE_KEY_FILE": ("php", "conectaeduca_private_key"),
    "CONECTAEDUCA_PUBLIC_KEY_FILE": ("php", "conectaeduca_public_key"),
    "CONECTAEDUCA_DB_TLS_CA_FILE": ("php", "conectaeduca_db_tls_ca"),
    "CONECTAEDUCA_WAF_TLS_CERT_FILE": ("waf", "waf_tls_cert"),
    "CONECTAEDUCA_WAF_TLS_KEY_FILE": ("waf", "waf_tls_key"),
}

def fail(reason: str) -> None:
    print("GA08_ENV_RUNTIME=BLOCKED_" + reason)
    print("GA08_CUTOVER=NAO_EXECUTADO")
    sys.exit(2)

def inspect(service: str) -> dict:
    try:
        p = subprocess.run(
            ["docker", "inspect", TARGETS[service]],
            text=True, capture_output=True, timeout=15, check=False
        )
        if p.returncode: fail("DOCKER_INSPECT_" + service.upper())
        d = json.loads(p.stdout)
        if len(d) != 1: fail("DOCKER_FORMATO_" + service.upper())
        item = d[0]
        labels = (item.get("Config") or {}).get("Labels") or {}
        state = item.get("State") or {}
        if labels.get("com.docker.compose.project") != "conectaeduca-dmz":
            fail("PROJETO_" + service.upper())
        if labels.get("com.docker.compose.service") != service:
            fail("SERVICO_" + service.upper())
        if not state.get("Running"):
            fail("CONTAINER_PARADO_" + service.upper())
        return item
    except (OSError, ValueError, TypeError, subprocess.TimeoutExpired):
        fail("INSPECT_INDISPONIVEL_" + service.upper())

def environment(container: dict) -> dict[str, str]:
    raw = ((container.get("Config") or {}).get("Env") or [])
    return dict(pair.split("=", 1) for pair in raw if "=" in pair)

def required_value(raw: str | None, name: str) -> str:
    if not isinstance(raw, str) or not raw.strip() or any(c in raw for c in "\n\r\x00"):
        fail("REFERENCIA_INDISPONIVEL_" + name)
    return raw

def mount_path(container: dict, destination: str, name: str) -> str:
    mounts = [
        m for m in container.get("Mounts", [])
        if m.get("Destination") == destination and m.get("Type") == "bind"
    ]
    if len(mounts) != 1: fail("MOUNT_" + name)
    path = required_value(mounts[0].get("Source"), name)
    if not Path(path).is_absolute(): fail("MOUNT_NAO_ABSOLUTO_" + name)
    return path

def published_bind(waf: dict) -> tuple[str, str, str]:
    portbinds = (waf.get("HostConfig") or {}).get("PortBindings") or {}
    def get(key: str, hostport: str) -> dict:
        matches = [
            p for p in portbinds.get(key) or []
            if str(p.get("HostPort", "")) == hostport
        ]
        if len(matches) != 1: fail("PORTA_PUBLICADA_" + hostport)
        return matches[0]
    http = get("8080/tcp", "80")
    https = get("8443/tcp", "443")
    a, b = http.get("HostIp") or "0.0.0.0", https.get("HostIp") or "0.0.0.0"
    if a != b: fail("BIND_HOST_INCONSISTENTE")
    return a, "80", "443"

def main() -> int:
    print("=== GA08.18F — RECUPERAR CONTEXTO SEM LER SEGREDOS ===")
    if socket.gethostname().split(".")[0] not in ("ep125-pucpr", "ep125-pucpr-br"):
        fail("HOST_INCORRETO")
    if os.geteuid() == 0: fail("USUARIO_ROOT")
    if not PREFLIGHT.is_file(): fail("PREFLIGHT_AUSENTE")
    for key in GA08_VARS:
        required_value(os.environ.get(key), key)
    obj = {service: inspect(service) for service in TARGETS}
    php_env = environment(obj["php"])
    env = os.environ.copy()

    for key, source in {
        "CONECTAEDUCA_DB_HOST": "DB_HOST",
        "CONECTAEDUCA_DB_PORT": "DB_PORT",
        "CONECTAEDUCA_APP_URL": "APP_URL",
    }.items():
        env[key] = required_value(php_env.get(source), key)

    for key, (service, name) in SECRET_MOUNTS.items():
        env[key] = mount_path(obj[service], "/run/secrets/" + name, key)

    ga = lambda obj: {
        str(x) for x in ((obj.get("HostConfig") or {}).get("GroupAdd") or [])
        if re.fullmatch(r"[0-9]+", str(x))
    }
    gids = ga(obj["waf"]) & ga(obj["php"])
    if len(gids) != 1: fail("GID_RUNTIME_AMBIGUO")
    env["CONECTAEDUCA_STACK_SECRET_GID"] = next(iter(gids))

    ip, http, https = published_bind(obj["waf"])
    env["CONECTAEDUCA_WAF_BIND_ADDRESS"] = ip
    env["CONECTAEDUCA_HTTP_PORT"] = http
    env["CONECTAEDUCA_HTTPS_PORT"] = https

    print("REFERENCIAS_RUNTIME=12/12")  # DB host/port, URL, 6 mounts, GID, bind, 2 ports = 12
    print("CONTEUDO_DE_SEGREDOS_LIDO=NAO")
    print("VALORES_DE_AMBIENTE_IMPRESSOS=NAO")
    print("ARQUIVO_ENV_CRIADO=NAO")
    try:
        result = subprocess.run(
            ["bash", str(PREFLIGHT)],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            timeout=120,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        fail("PREFLIGHT_INDISPONIVEL")

    # Somente marcadores aprovados; não imprimir stdout/stderr integral.
    allowed = {
        "GA08_PREFLIGHT", "GA08_APLICACAO", "GA08_ROLLBACK",
        "GA08_GATE", "GA08_MOTIVO", "GA08_G0_SNAPSHOT_AUTORIZACAO",
        "GA08_ROLLBACK_AUTOMATICO"
    }
    for line in (result.stdout + "\n" + result.stderr).splitlines():
        if "=" not in line: continue
        k, v = line.strip().split("=", 1)
        if k in allowed and re.fullmatch(r"[A-Z0-9_a-z-]{1,100}", v):
            print(k + "=" + v)
    if result.returncode:
        fail("PREFLIGHT_RC_" + str(result.returncode))
    print("GA08_18F=PASS")
    print("CUTOVER_EXECUTADO=NAO")
    return 0

if __name__ == "__main__":
    sys.exit(main())
