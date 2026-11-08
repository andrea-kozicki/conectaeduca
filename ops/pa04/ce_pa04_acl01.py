#!/usr/bin/env python3
"""CE-PA04-ACL01 — configurar OpenBao KV v2 e AppRole read-only, sem expor credenciais.

Nao grava, imprime ou envia tokens ao GitHub/Chat. Opera unicamente no localhost EP126.
Nao cria SecretID, nao cria segredos, nao altera mounts/policies/roles preexistentes.
"""
from __future__ import annotations

import datetime as dt
import getpass
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:18200/v1/"
ROOT = "/opt/conectaeduca"
HEAD = "04f88d275064a005d0ffcd4f9372a371c28c32d5"
MOUNT = "ce-app/"
AUTH_MOUNT = "ce-approle/"
POLICY_NAME = "ce-app-runtime-read-v1"
ROLE_NAME = "ce-app-runtime-read"
EXACT_SECRET_PATH = "ce-app/data/runtime/app"
POLICY = (
    '# CE/PA-04 — acesso da aplicacao somente a uma chave KV v2.\n'
    'path "ce-app/data/runtime/app" {\n'
    '  capabilities = ["read"]\n'
    '}\n'
)
ROLE = {
    "bind_secret_id": True,
    "secret_id_num_uses": 1,
    "secret_id_ttl": "10m",
    "token_policies": [POLICY_NAME],
    "token_no_default_policy": True,
    "token_ttl": "15m",
    "token_max_ttl": "1h",
    "token_type": "service",
}
HTTP = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def abort(reason: str) -> None:
    print("CE-PA04-ACL01_ABORTADO=" + reason, file=sys.stderr, flush=True)
    raise SystemExit(1)


def request(method: str, path: str, token: str | None = None,
            payload: dict | None = None) -> tuple[int, dict]:
    headers = {"Accept": "application/json"}
    if token is not None:
        headers["X-Vault-Token"] = token
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    try:
        with HTTP.open(req, timeout=8) as response:
            raw = response.read(1024 * 1024)
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        # Nao exibir corpo: algumas APIs podem revelar dados em mensagens de erro.
        exc.close()
        return exc.code, {}
    except (OSError, ValueError):
        abort("API_LOCAL_INDISPONIVEL_OU_RESPOSTA_INVALIDA")


def expected(method: str, path: str, token: str,
             payload: dict | None = None, ok: tuple[int, ...] = (200, 204)) -> dict:
    status, result = request(method, path, token, payload)
    if status not in ok:
        abort("API_" + path.replace("/", "_") + "_HTTP_" + str(status))
    return result


def data_of(body: dict) -> dict:
    value = body.get("data", {})
    return value if isinstance(value, dict) else {}


def verify_existing_role(token: str) -> None:
    r = data_of(expected("GET", "auth/ce-approle/role/" + ROLE_NAME, token))
    policies = r.get("token_policies", r.get("policies", []))
    if isinstance(policies, str):
        policies = [part.strip() for part in policies.split(",") if part.strip()]
    if not (
        r.get("bind_secret_id") is True
        and r.get("token_no_default_policy") is True
        and r.get("secret_id_num_uses") == 1
        and sorted(policies) == [POLICY_NAME]
        and str(r.get("token_type", "service")) in ("service", "default-service")
    ):
        abort("APPROLE_EXISTENTE_DIVERGENTE")
    print("APPROLE_RESTRITA=CONFIRMADA")


def main() -> None:
    print("=== CE-PA04-ACL01 — OPENBAO MENOR PRIVILEGIO ===", flush=True)
    print("USUARIO=" + subprocess.check_output(["whoami"], text=True).strip())
    print("DATA=" + dt.datetime.now().astimezone().isoformat(timespec="seconds"))
    if sys.argv[1:] != ["--apply"]:
        abort("EXIGE_--apply")
    if os.geteuid() == 0:
        abort("NAO_EXECUTAR_COM_ROOT")
    if subprocess.check_output(["whoami"], text=True).strip() != "andrea.kiew":
        abort("USUARIO_INCORRETO")
    if socket.gethostname().split(".")[0] != "ep126-pucpr-br":
        abort("HOST_INCORRETO")
    try:
        got_head = subprocess.check_output(
            ["git", "-C", ROOT, "rev-parse", "HEAD"], text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except subprocess.CalledProcessError:
        abort("GIT_NAO_VERIFICAVEL")
    if got_head != HEAD:
        abort("HEAD_DIVERGENTE")

    status, body = request("GET", "sys/health")
    if status != 200 or body.get("sealed") is not False or body.get("initialized") is not True:
        abort("COFRE_NAO_ATIVO_OU_SELADO")
    print("OPENBAO=ATIVO_NAO_SELADO")

    if not sys.stdin.isatty():
        abort("TOKEN_EXIGE_TERMINAL_INTERATIVO")
    token = getpass.getpass("Token administrativo OpenBao (oculto; nao enviar ao chat): ").strip()
    if not token:
        abort("TOKEN_NAO_INFORMADO")
    # A credencial permanece somente na memoria deste processo.
    expected("GET", "auth/token/lookup-self", token)
    mounts = data_of(expected("GET", "sys/mounts", token))
    methods = data_of(expected("GET", "sys/auth", token))
    m = mounts.get(MOUNT)
    a = methods.get(AUTH_MOUNT)
    if m is not None and (m.get("type") != "kv" or str((m.get("options") or {}).get("version")) != "2"):
        abort("MOUNT_CE_APP_EXISTENTE_DIVERGENTE")
    if a is not None and a.get("type") != "approle":
        abort("AUTH_CE_APP_EXISTENTE_DIVERGENTE")

    status, old_policy = request("GET", "sys/policies/acl/" + POLICY_NAME, token)
    if status == 200:
        value = old_policy.get("policy", data_of(old_policy).get("policy"))
        if not isinstance(value, str) or value.strip() != POLICY.strip():
            abort("POLITICA_EXISTENTE_DIVERGENTE")
    elif status != 404:
        abort("CONSULTA_POLITICA_HTTP_" + str(status))

    old_role = 404
    if a is not None:
        old_role, _ = request("GET", "auth/ce-approle/role/" + ROLE_NAME, token)
        if old_role not in (200, 404):
            abort("CONSULTA_ROLE_HTTP_" + str(old_role))
        if old_role == 200:
            verify_existing_role(token)
    print("COLISOES_PREEXISTENTES=NAO")

    if m is None:
        expected("POST", "sys/mounts/ce-app", token, {
            "type": "kv",
            "description": "ConectaEduca PA-04 — segredos de runtime isolados",
            "options": {"version": "2"},
        })
        print("KV2_CE_APP=CRIADO")
    else:
        print("KV2_CE_APP=EXISTENTE_VALIDO")

    if a is None:
        expected("POST", "sys/auth/ce-approle", token, {
            "type": "approle",
            "description": "ConectaEduca PA-04 — acesso de servico restrito",
        })
        print("AUTH_APPROLE=CRIADO")
    else:
        print("AUTH_APPROLE=EXISTENTE_VALIDO")

    if status == 404:
        expected("POST", "sys/policies/acl/" + POLICY_NAME, token,
                 {"policy": POLICY})
        print("POLITICA_READONLY=CRIADA")
    else:
        print("POLITICA_READONLY=EXISTENTE_VALIDA")

    if old_role == 404:
        expected("POST", "auth/ce-approle/role/" + ROLE_NAME, token, ROLE)
        print("APPROLE=CRIADA")
    else:
        print("APPROLE=EXISTENTE_VALIDA")
    verify_existing_role(token)

    print("CAPACIDADE=READ_UNICO_CAMINHO_KV2")
    print("CAMINHO=" + EXACT_SECRET_PATH)
    print("TOKEN_PADRAO=DESABILITADO")
    print("SECRET_ID_OBRIGATORIO=SIM")
    print("SECRET_ID_GERADO=NAO")
    print("SEGREDOS_CRIADOS_OU_LIDOS=NAO")
    print("INTEGRACAO_APP=AINDA_NAO_REALIZADA")
    print("SERVICOS_REINICIADOS=NAO")
    print("CE-PA04-ACL01_CONCLUIDO")


if __name__ == "__main__":
    main()
