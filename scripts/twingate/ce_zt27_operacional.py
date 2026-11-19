#!/usr/bin/env python3
"""CE-ZT27 — diagnóstico dirigido do Twingate em EP125/EP126/openSUSE.

Execução: python3 ce_zt27_operacional.py --role ep125|ep126|opensuse
Sem sudo, sem bibliotecas extras, sem alterar rede, Docker ou tenant.
Não exibe token, env, logs brutos ou configuração sensível.
"""
import argparse
import datetime as dt
import getpass
import json
import os
import re
import socket
import subprocess
import sys
from collections import Counter

EXPECTED_HOSTS = {
    "ep125": "ep125-pucpr",
    "ep126": "ep126-pucpr-br",
    "opensuse": "opensuse-andrea",
}
CONNECTORS = {
    "ep125": "conectaeduca-dmz-01",
    "ep126": "conectaeduca-twingate-connector",
}
CONTROLLER = "conectaeducalab.twingate.com"
ENDPOINTS = (
    ("CONTROLLER", CONTROLLER, "/api/v1/public_keys"),
    ("PUBNUB_PUBSUB", "pubsub.pubnub.com", "/time/0"),
    ("PUBNUB_H2", "h2.pubnubapi.com", "/time/0"),
    ("PUBNUB_PNDSN", "ps.pndsn.com", "/time/0"),
)
ERROR_PATTERNS = {
    "PUBNUB_TLS_IO": r"pubnub-lib.*TLS/SSL I/O operation failed",
    "PUBNUB_TRANSACTION": r"pubnub-lib.*Transaction failed",
    "AUTH_INVALID": r"invalid token|invalid credentials|unauthorized",
    "CONTROLLER_KEYS": r"failed to get public keys",
    "RELAY": r"failed to preconnect a relay listener|maintain_relay_connectivity",
    "DNS": r"no such host|could not resolve|temporary failure in name resolution",
}
CURL_ERRORS = {
    6: "DNS",
    7: "CONNECT",
    28: "TIMEOUT",
    35: "TLS_RESET_OU_NEGOCIACAO",
    51: "CERTIFICADO",
    52: "SEM_RESPOSTA",
    56: "CONEXAO_REDEFINIDA",
    60: "CERTIFICADO",
}


def call(argv, timeout=25):
    """Processo limitado, sem shell e sem interpolação de argumentos."""
    try:
        return subprocess.run(
            argv, capture_output=True, text=True, timeout=timeout, check=False
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def probe(label, domain, path, http1=False):
    url = "https://" + domain + path
    cmd = [
        "curl", "-q", "--noproxy", "*", "--ipv4",
        "--silent", "--show-error", "--output", "/dev/null",
        "--connect-timeout", "7", "--max-time", "15",
        "--write-out", "HTTP=%{http_code};TLS=%{ssl_verify_result};IP=%{remote_ip}",
    ]
    if http1:
        cmd.append("--http1.1")
    result = call(cmd + [url], timeout=20)
    if result is None:
        return {"label": label, "rc": -1, "http": "000", "tls": "?", "ip": "?",
                "ok": False, "erro": "CURL_INDISPONIVEL"}
    fields = dict(re.findall(r"(HTTP|TLS|IP)=([^;\s]+)", result.stdout))
    http = fields.get("HTTP", "000")
    tls = fields.get("TLS", "?")
    # Apenas o endpoint de tempo e Controller têm resposta 200 esperada.
    ok = result.returncode == 0 and http == "200" and tls == "0"
    error = "OK" if ok else CURL_ERRORS.get(result.returncode, "HTTP_NAO_200" if result.returncode == 0 else "CURL_ERRO")
    return {"label": label, "rc": result.returncode, "http": http,
            "tls": tls, "ip": fields.get("IP", "?"), "ok": ok, "erro": error}


def inspect_connector(name):
    p = call(["docker", "inspect", "--type", "container", name], timeout=15)
    if p is None or p.returncode != 0:
        return {"available": False}
    try:
        info = json.loads(p.stdout)[0]
    except (ValueError, KeyError, IndexError, TypeError):
        return {"available": False}
    state = info.get("State") or {}
    networks = (info.get("NetworkSettings") or {}).get("Networks") or {}
    configured = {}
    env_names = ("TWINGATE_NETWORK", "TWINGATE_ACCESS_TOKEN", "TWINGATE_REFRESH_TOKEN")
    for item in (info.get("Config") or {}).get("Env") or []:
        key, sep, value = item.partition("=")
        if sep and key in env_names:
            configured[key] = bool(value)
    return {
        "available": True, "running": bool(state.get("Running")),
        "health": (state.get("Health") or {}).get("Status", "NAO_INFORMADO"),
        "restarts": info.get("RestartCount", "NAO_INFORMADO"),
        "image": (info.get("Config") or {}).get("Image", "NAO_INFORMADA"),
        "networks": sorted(networks), "env": configured,
    }


def log_counts(name):
    p = call(["docker", "logs", "--since", "30m", "--tail", "800", name], timeout=15)
    if p is None or p.returncode != 0:
        return None
    lines = (p.stdout + "\n" + p.stderr).splitlines()
    counts = Counter()
    for line in lines:
        for label, pattern in ERROR_PATTERNS.items():
            if re.search(pattern, line, re.I):
                counts[label] += 1
    return {"lines": len(lines), "counts": dict(counts)}


def client_state():
    if call(["which", "twingate"], timeout=5) is None:
        return "INDETERMINADO"
    p = call(["twingate", "status"], timeout=10)
    if p is None or p.returncode != 0:
        return "INDISPONIVEL"
    value = p.stdout.strip().lower()
    if value == "online":
        return "ONLINE"
    if value == "offline":
        return "OFFLINE"
    return "OUTRO_ESTADO"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--role", required=True, choices=tuple(EXPECTED_HOSTS))
    args = parser.parse_args(argv)
    hostname = socket.gethostname().lower()
    expected = EXPECTED_HOSTS[args.role]
    if not hostname.startswith(expected):
        print("CE-ZT27_ABORTADO=HOST_NAO_CORRESPONDE")
        print("HOST_ATUAL=", hostname)
        print("PAPEL_SOLICITADO=", args.role)
        return 4

    print("=== CE-ZT27 — TWINGATE DIAGNOSTICO OPERACIONAL ===")
    print("WHOAMI=", getpass.getuser())
    print("DATE=", dt.datetime.now().astimezone().isoformat(timespec="seconds"))
    print("HOST=", hostname)
    print("ROLE=", args.role)
    print("MODO=SOMENTE_LEITURA")
    print("PROXY_ENV_PRESENTE=", any(bool(os.environ.get(k)) for k in
          ("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy")))

    if args.role == "opensuse":
        print("CLIENT_STATUS=", client_state())
        p = call(["twingate", "resources"], timeout=10)
        if p is None or p.returncode != 0:
            print("CLIENT_RESOURCES=INDISPONIVEL")
        elif "No resources currently available" in p.stdout:
            print("CLIENT_RESOURCES=NENHUM")
        else:
            print("CLIENT_RESOURCES=CONSULTA_RESPONDEU_REVISAR_NO_TERMINAL")
    else:
        name = CONNECTORS[args.role]
        info = inspect_connector(name)
        print("CONTAINER_ESPERADO=", name)
        print("CONTAINER_ENCONTRADO=", info["available"])
        if info["available"]:
            print("CONTAINER_RUNNING=", info["running"])
            print("CONTAINER_HEALTH=", info["health"])
            print("RESTART_COUNT=", info["restarts"])
            print("IMAGE=", info["image"])
            print("DOCKER_REDES=", ",".join(info["networks"]) or "NENHUMA")
            for k in ("TWINGATE_NETWORK", "TWINGATE_ACCESS_TOKEN", "TWINGATE_REFRESH_TOKEN"):
                print(k + "_PRESENTE=", info["env"].get(k, False))
            logs = log_counts(name)
            if logs is None:
                print("LOGS=INDISPONIVEIS")
            else:
                print("LOGS_30MIN_LINHAS=", logs["lines"])
                for label in ERROR_PATTERNS:
                    print("LOG_" + label + "=", logs["counts"].get(label, 0))

    print("\n=== TESTES HTTPS EXTERNOS ===")
    results = []
    for label, domain, path in ENDPOINTS:
        r = probe(label, domain, path)
        results.append(r)
        print(f"{label}: RC={r['rc']} HTTP={r['http']} TLS_VERIFY={r['tls']} "
              f"IP={r['ip']} RESULTADO={r['erro']}")
        if label in ("PUBNUB_PUBSUB", "PUBNUB_H2") and not r["ok"]:
            r1 = probe(label + "_HTTP1", domain, path, http1=True)
            print(f"{label}_HTTP1: RC={r1['rc']} HTTP={r1['http']} "
                  f"TLS_VERIFY={r1['tls']} RESULTADO={r1['erro']}")

    failed = [r["label"] for r in results if not r["ok"]]
    print("\n=== INTERPRETACAO ===")
    if failed:
        print("HTTPS_FALHAS=", ",".join(failed))
        print("CONCLUSAO=FALHA_HTTPS_HOST_NAO_RECRIAR_CONNECTORS")
        print("PROXIMO=VALIDAR_CAMINHO_DE_SAIDA_INSTITUCIONAL_COM_SUPORTE")
    else:
        print("HTTPS_FALHAS=NENHUMA_NOS_ENDPOINTS_TESTADOS")
        print("CONCLUSAO=HTTPS_BASICO_OK_CONNECTOR_E_RELAY_AINDA_EXIGEM_VALIDACAO")
    print("SEGREDOS_EXIBIDOS=NAO")
    print("ALTERACOES=NAO")
    print("CE-ZT27_CONCLUIDO")
    return 2 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
