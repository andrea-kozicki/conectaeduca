#!/usr/bin/env python3
"""GA08.26: bounded live AFTER-cutover WAF/Unix-sockets/PA-02 regression.

Default PLAN_ONLY. --verify reads Docker state, checks two sockets and performs
bounded HTTP GET, WAF negative XSS and host-to-container TCP connect attempts.
No sudo, no secret files, no docker compose/up/exec shell, no container writes,
no Docker network modifications. Intended only after separately approved cutover.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import socket
import subprocess
import sys
from pathlib import Path

PROJECT = "conectaeduca-dmz"
TARGETS = {
    "waf": "conectaeduca-dmz-waf-1",
    "nginx": "conectaeduca-dmz-nginx-1",
    "php": "conectaeduca-dmz-php-1",
}
EXPECTED_NET = {"waf": "waf_backend", "nginx": "waf_backend", "php": "php_egress"}
SOCKET_CHECKS = (
    ("WAF_HTTP_UNIX", "waf", "/run/conectaeduca-http/nginx.sock"),
    ("NGINX_HTTP_UNIX", "nginx", "/run/conectaeduca-http/nginx.sock"),
    ("NGINX_FPM_UNIX", "nginx", "/run/conectaeduca-fpm/php-fpm.sock"),
    ("PHP_FPM_UNIX", "php", "/run/conectaeduca-fpm/php-fpm.sock"),
)

def run(argv: list[str], timeout: int = 15) -> subprocess.CompletedProcess:
    return subprocess.run(argv, capture_output=True, text=True,
                          timeout=timeout, check=False)

def inspect(name: str) -> dict:
    p = run(["docker", "inspect", name])
    if p.returncode:
        raise RuntimeError("DOCKER_INSPECT_FALHOU")
    try:
        result = json.loads(p.stdout)
    except ValueError as e:
        raise RuntimeError("DOCKER_INSPECT_INVALIDO") from e
    if not isinstance(result, list) or len(result) != 1:
        raise RuntimeError("DOCKER_INSPECT_INVALIDO")
    return result[0]

def verify_baseline(items: dict[str, dict]) -> tuple[str, int, dict[str, str]]:
    aliases = {}
    for role, info in items.items():
        cfg, state = info.get("Config") or {}, info.get("State") or {}
        labels = cfg.get("Labels") or {}
        if (labels.get("com.docker.compose.project") != PROJECT or
                labels.get("com.docker.compose.service") != role):
            raise RuntimeError("COMPOSE_IDENTIDADE_DIVERGENTE")
        if (not state.get("Running") or
                (state.get("Health") or {}).get("Status") != "healthy"):
            raise RuntimeError("SERVICO_NAO_HEALTHY")
        networks = (info.get("NetworkSettings") or {}).get("Networks") or {}
        if len(networks) != 1:
            raise RuntimeError("TOPOLOGIA_NAO_ISOLADA")
        net, values = next(iter(networks.items()))
        if not net.endswith("_" + EXPECTED_NET[role]):
            raise RuntimeError("TOPOLOGIA_AINDA_BASELINE_OU_DIVERGENTE")
        ip = values.get("IPAddress", "")
        if not isinstance(ip, str) or not re.fullmatch(r"172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}", ip):
            raise RuntimeError("IP_CONTAINER_INVALIDO")
        aliases[role] = ip
        if role in ("nginx", "php"):
            bindings = (info.get("HostConfig") or {}).get("PortBindings") or {}
            if any(v for v in bindings.values()):
                raise RuntimeError("BACKEND_PORTA_PUBLICADA")
    # There must be no common network between nginx and php.
    if (set((items["nginx"].get("NetworkSettings") or {}).get("Networks") or {}) &
        set((items["php"].get("NetworkSettings") or {}).get("Networks") or {})):
        raise RuntimeError("BACKEND_REDE_COMPARTILHADA")
    ports = (items["waf"].get("HostConfig") or {}).get("PortBindings") or {}
    resolved = [
        (x.get("HostIp", ""), x.get("HostPort", ""))
        for entry in ports.values() for x in (entry or [])
        if x.get("HostPort") == "443"
    ]
    if not any(ip == "192.168.6.34" and port == "443" for ip, port in resolved):
        raise RuntimeError("BIND_WAF_443_DIVERGENTE")
    return "192.168.6.34", 443, aliases

def check_socket(role: str, path: str) -> bool:
    p = run(["docker", "exec", TARGETS[role], "test", "-S", path], timeout=12)
    return p.returncode == 0

def request(ip: str, port: int, path: str) -> tuple[str, int]:
    # Only fixed GET routes; no body, cookies, auth or redirect following.
    url = f"https://conectaeduca.local:{port}{path}"
    p = run(["curl", "--silent", "--insecure", "--noproxy", "*",
             "--connect-timeout", "4", "--max-time", "10",
             "--resolve", f"conectaeduca.local:{port}:{ip}",
             "--output", "/dev/null", "--write-out", "%{http_code}",
             url], timeout=13)
    code = p.stdout.strip()
    return code if re.fullmatch(r"[0-9]{3}", code) else "000", p.returncode

def reachable(ip: str, port: int) -> bool:
    try:
        with socket.create_connection((ip, port), timeout=2):
            return True
    except OSError:
        return False

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--verify", action="store_true")
    args = ap.parse_args()
    print("=== GA08.26 — REGRESSAO E2E POS-CUTOVER ===")
    if not args.verify:
        print("MODO=PLANO")
        print("REDE_DOCKER_USADA=NAO")
        print("SERVICOS_MODIFICADOS=NAO")
        return 0
    if os.geteuid() == 0 or socket.gethostname().split(".")[0] not in ("ep125-pucpr", "ep125-pucpr-br"):
        print("GA08_26=BLOCKED_IDENTIDADE")
        return 3
    failed = False
    try:
        items = {role: inspect(name) for role, name in TARGETS.items()}
        ip, port, aliases = verify_baseline(items)
        print("CONTAINERS_3_3_HEALTHY=PASS")
        print("REDE_WAF_NGINX_PHP_ISOLADA=PASS")
        print("BACKEND_HOST_PORT_PUBLISHED=NAO")
        for marker, role, loc in SOCKET_CHECKS:
            result = check_socket(role, loc)
            print(marker + "=" + ("PASS" if result else "FAIL"))
            failed |= not result
        for marker, uri in (
            ("HEALTHZ", "/healthz"),
            ("LOGIN", "/login.php"),
            ("CHAVE_PUBLICA", "/api/public_key.php"),
            ("WAF_XSS_CANARIO", "/?ga08_validation=%3Cscript%3Ealert%281%29%3C%2Fscript%3E"),
        ):
            code, rc = request(ip, port, uri)
            expected = "403" if marker == "WAF_XSS_CANARIO" else "200"
            verdict = code == expected and rc == 0
            print(f"{marker}_HTTP={code} CURL_RC={rc} RESULTADO=" +
                  ("PASS" if verdict else "FAIL"))
            failed |= not verdict
        for role, portno in (("nginx", 8080), ("php", 9000)):
            blocked = not reachable(aliases[role], portno)
            print(f"{role.upper()}_TCP_{portno}_HOST_NEGA=" +
                  ("PASS" if blocked else "FAIL"))
            failed |= not blocked
        print("GA08_26=" + ("FAIL" if failed else "PASS_RECORTE"))
        print("PA02_FECHADO=NAO_POR_ESTE_TESTE")
        return 1 if failed else 0
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        reason = str(error)
        if not re.fullmatch(r"[A-Z0-9_]{1,90}", reason):
            reason = "ERRO_DE_AMBIENTE"
        print("GA08_26=BLOCKED_" + reason)
        return 3
    finally:
        print("HOST_BIND_PERSISTENTE_VERIFICADO_POR_INSPECAO=NAO")
        print("LOGIN_MFA_SQL_TLS_CA_E2E=NAO_ABRANGIDOS")
        print("DOCKER_COMPOSE_EXECUTADO=NAO")
        print("CUTOVER_EXECUTADO=NAO")
        print("SERVICOS_MODIFICADOS=NAO_POR_ESTE_SCRIPT")

if __name__ == "__main__":
    sys.exit(main())
