#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import stat
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import NoReturn

BAO_ADDR = os.environ.get(
    "CONECTAEDUCA_OPENBAO_ADDR",
    "http://127.0.0.1:18200",
).rstrip("/")

CRED_DIR = Path.home() / ".local/share/conectaeduca/openbao-workload-smtp"
ROLE_ID_FILE = CRED_DIR / "role-id"
SECRET_ID_FILE = CRED_DIR / "secret-id"

SECRET_PATH = "secret/data/conectaeduca/smtp"
OUT_FILE = Path("/dev/shm/conectaeduca-smtp-password")
EXPECTED_POLICY = "conectaeduca-smtp-read"


def fail(msg: str) -> NoReturn:
    print(f"FALHA       {msg}", file=sys.stderr)
    raise SystemExit(1)


def api(method: str, path: str, payload=None, token: str | None = None,
        expected=(200, 204)):
    body = None if payload is None else json.dumps(payload).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["X-Vault-Token"] = token

    req = urllib.request.Request(
        f"{BAO_ADDR}/v1/{path}",
        data=body,
        headers=headers,
        method=method,
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            raw = resp.read()
            code = resp.status
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        code = exc.code
    except Exception as exc:
        fail(f"OpenBao indisponível: {type(exc).__name__}")

    if code not in expected:
        fail(f"OpenBao retornou HTTP {code} em {path}")

    if not raw:
        return {}

    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        fail(f"resposta não JSON em {path}")


def read_credential(path: Path) -> str:
    if not path.is_file():
        fail(f"credencial de workload ausente: {path}")

    mode = stat.S_IMODE(path.stat().st_mode)
    if mode & 0o077:
        fail(f"credencial com permissões excessivas: {path} mode={oct(mode)}")

    value = path.read_text(encoding="utf-8").strip()
    if not value:
        fail(f"credencial vazia: {path}")
    return value


def atomic_secret(path: Path, value: str) -> None:
    fd, tmp_name = tempfile.mkstemp(
        prefix=".conectaeduca-smtp-",
        dir=str(path.parent),
    )

    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(value)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())

        os.replace(tmp_name, path)
        os.chmod(path, 0o600)
    finally:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass


health = api(
    "GET",
    "sys/health",
    expected=(200, 429, 472, 473, 501, 503),
)

if not health.get("initialized"):
    fail("OpenBao não está inicializado")

if health.get("sealed"):
    fail("OpenBao está selado; faça unseal antes da materialização")


role_id = read_credential(ROLE_ID_FILE)
secret_id = read_credential(SECRET_ID_FILE)

login = api(
    "POST",
    "auth/approle/login",
    {"role_id": role_id, "secret_id": secret_id},
    expected=(200,),
)

auth = login.get("auth") or {}
token = str(auth.get("client_token") or "")
policies = list(auth.get("policies") or [])

role_id = ""
secret_id = ""

if not token:
    fail("login AppRole não retornou token")

if EXPECTED_POLICY not in policies:
    fail("token AppRole não recebeu a policy SMTP esperada")

if "default" in policies:
    fail("token AppRole recebeu policy default inesperadamente")

# O token de workload é configurado para um único uso.
secret = api(
    "GET",
    SECRET_PATH,
    token=token,
    expected=(200,),
)
token = ""

password = str(
    ((secret.get("data") or {}).get("data") or {}).get("password") or ""
)

if not password:
    fail("segredo SMTP recuperado está vazio")

atomic_secret(OUT_FILE, password)
password = ""

mode = stat.S_IMODE(OUT_FILE.stat().st_mode)
if mode != 0o600:
    fail(f"segredo materializado com modo inesperado: {oct(mode)}")

print("OK          AppRole de workload autenticou com policy mínima")
print("OK          segredo SMTP rematerializado em /dev/shm sem exposição")
