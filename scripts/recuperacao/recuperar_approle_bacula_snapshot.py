#!/usr/bin/env python3
from __future__ import annotations

import base64
import http.client
import json
import os
import re
import stat
import subprocess
import time
from pathlib import Path
from typing import NoReturn

REPO = Path("/srv/www/htdocs/conectaeduca")
HCL = REPO / "deploy/interna/openbao/config/openbao.hcl"
COMPOSE = REPO / "deploy/interna/openbao/compose.yml"
POLICY_FILE = REPO / "deploy/interna/openbao/policies/bacula-snapshot.hcl"

CUSTODY = Path.home() / ".local/share/conectaeduca/openbao-custodia-lab"
SHARES = [
    CUSTODY / "unseal-share-1.txt",
    CUSTODY / "unseal-share-2.txt",
]

WORKLOAD = REPO / "deploy/interna/openbao/.runtime/bacula-snapshot"
ROLE_FILE = WORKLOAD / "role-id"
SECRET_FILE = WORKLOAD / "secret-id"

BAO_HOST = "127.0.0.1"
BAO_PORT = 18200
ROLE = "bacula-snapshot"
POLICY = "bacula-snapshot"
SNAPSHOT_PATH = "sys/storage/raft/snapshot"

root_token = ""
original_hcl = ""


def out(kind: str, msg: str) -> None:
    print(f"{kind:<11} {msg}", flush=True)


def die(msg: str) -> NoReturn:
    raise RuntimeError(msg)


def run(*args: str) -> None:
    subprocess.run(
        args,
        cwd=REPO,
        check=True,
        stdout=subprocess.DEVNULL,
    )


def api(method: str, path: str, payload=None,
        token: str | None = None,
        expected=(200, 204),
        raw: bool = False):
    if (
        not path
        or path.startswith("/")
        or "://" in path
        or ".." in path.split("/")
    ):
        raise RuntimeError(f"path OpenBao inválido: {path!r}")

    data = None if payload is None else json.dumps(payload).encode()
    headers = {"Content-Type": "application/json"}

    if token:
        headers["X-Vault-Token"] = token

    conn = http.client.HTTPConnection(
        BAO_HOST,
        BAO_PORT,
        timeout=20,
    )

    try:
        conn.request(
            method,
            f"/v1/{path}",
            body=data,
            headers=headers,
        )
        resp = conn.getresponse()
        body = resp.read()
        code = resp.status
    finally:
        conn.close()

    if code not in expected:
        raise RuntimeError(f"HTTP {code} em {path}")

    if raw:
        return body

    if not body:
        return {}

    return json.loads(body)


def health_raw():
    conn = http.client.HTTPConnection(
        BAO_HOST,
        BAO_PORT,
        timeout=5,
    )
    try:
        conn.request("GET", "/v1/sys/health")
        resp = conn.getresponse()
        return resp.status, resp.read()
    finally:
        conn.close()


def wait_health() -> dict:
    for _ in range(45):
        try:
            return api(
                "GET",
                "sys/health",
                expected=(200, 429, 472, 473, 501, 503),
            )
        except Exception:
            time.sleep(1)

    raise RuntimeError("OpenBao não respondeu dentro do tempo esperado")


def wait_active(timeout_seconds: int = 50) -> dict:
    deadline = time.monotonic() + timeout_seconds
    last = {}

    while time.monotonic() < deadline:
        try:
            code, body = health_raw()
            if body:
                last = json.loads(body)

            if (
                code == 200
                and last.get("initialized") is True
                and last.get("sealed") is False
                and last.get("standby") is False
            ):
                out("OK", "OpenBao Raft ativo")
                return last
        except Exception:
            pass

        time.sleep(1)

    raise RuntimeError(
        "OpenBao não assumiu estado ativo; "
        f"último estado={last!r}"
    )


def read_share(path: Path) -> str:
    if not path.is_file():
        raise RuntimeError("share de custódia ausente")

    value = path.read_text(encoding="utf-8").strip()

    if not value:
        raise RuntimeError("share de custódia vazia")

    return value


def unseal() -> None:
    health = wait_health()

    if not health.get("initialized"):
        raise RuntimeError("OpenBao não inicializado")

    if not health.get("sealed"):
        out("OK", "OpenBao já estava unsealed")
        wait_active()
        return

    for path in SHARES:
        result = api(
            "POST",
            "sys/unseal",
            {"key": read_share(path)},
            expected=(200,),
        )
        if result.get("sealed") is False:
            break

    health = wait_health()

    if health.get("sealed"):
        raise RuntimeError("OpenBao permaneceu selado após quorum")

    out("OK", "OpenBao unsealed com quorum local")
    wait_active()


def patch_listener() -> None:
    global original_hcl

    original_hcl = HCL.read_text(encoding="utf-8")

    if "disable_unauthed_generate_root_endpoints" in original_hcl:
        raise RuntimeError(
            "HCL já possui configuração explícita de generate-root"
        )

    marker = '  tls_disable     = true\n'

    if original_hcl.count(marker) != 1:
        raise RuntimeError("marcador tls_disable inesperado")

    patched = original_hcl.replace(
        marker,
        marker + (
            "  disable_unauthed_generate_root_endpoints = false\n"
        ),
        1,
    )

    HCL.write_text(patched, encoding="utf-8")
    out(
        "OK",
        "generate-root legado habilitado temporariamente no listener local",
    )


def restore_hcl() -> None:
    if original_hcl:
        HCL.write_text(original_hcl, encoding="utf-8")
        out("OK", "HCL endurecido restaurado")


def recreate() -> None:
    rel = str(COMPOSE.relative_to(REPO))

    run(
        "docker",
        "compose",
        "-f",
        rel,
        "config",
    )

    run(
        "docker",
        "compose",
        "-f",
        rel,
        "up",
        "-d",
        "--force-recreate",
    )

    wait_health()


def decode_root(encoded_token: str, otp: str) -> str:
    encoded = encoded_token.strip()

    padding = (-len(encoded)) % 4

    try:
        raw = base64.b64decode(
            encoded + ("=" * padding),
            validate=True,
        )
    except Exception as exc:
        raise RuntimeError(
            "encoded_token inválido"
        ) from exc

    otp_bytes = otp.encode("utf-8")

    if len(raw) != len(otp_bytes):
        raise RuntimeError("comprimento encoded_token/OTP divergente")

    decoded = bytes(
        a ^ b for a, b in zip(raw, otp_bytes)
    )

    try:
        return decoded.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise RuntimeError(
            "root token recuperado não é UTF-8 válido"
        ) from exc


def generate_root() -> str:
    try:
        status = api(
            "GET",
            "sys/generate-root/attempt",
            expected=(200,),
        )

        if status.get("started"):
            api(
                "DELETE",
                "sys/generate-root/attempt",
                expected=(200, 204),
            )
    except RuntimeError:
        pass

    init = api(
        "POST",
        "sys/generate-root/attempt",
        {},
        expected=(200,),
    )

    otp = str(init.get("otp") or "")
    nonce = str(init.get("nonce") or "")

    if not otp or not nonce:
        raise RuntimeError("generate-root não retornou OTP/nonce")

    final = None

    for share in SHARES:
        final = api(
            "POST",
            "sys/generate-root/update",
            {
                "key": read_share(share),
                "nonce": nonce,
            },
            expected=(200,),
        )

        if final.get("complete"):
            break

    if not final or not final.get("complete"):
        raise RuntimeError("quorum generate-root não completou")

    encoded = str(final.get("encoded_token") or "")

    if not encoded:
        raise RuntimeError("generate-root sem encoded_token")

    token = decode_root(encoded, otp)

    otp = ""
    encoded = ""

    lookup = api(
        "GET",
        "auth/token/lookup-self",
        token=token,
        expected=(200,),
    )

    policies = (
        (lookup.get("data") or {}).get("policies")
        or []
    )

    if "root" not in policies:
        raise RuntimeError("token recuperado não possui policy root")

    out("OK", "root temporário recuperado somente em memória")
    return token


def atomic_credential(path: Path, value: str) -> None:
    WORKLOAD.mkdir(parents=True, exist_ok=True)
    # Diretorio de credenciais: 0700 e intencional para restringir acesso ao owner.
    os.chmod(WORKLOAD, 0o700)  # nosemgrep: python.lang.security.audit.insecure-file-permissions.insecure-file-permissions

    tmp = path.with_name(
        f".{path.name}.{os.getpid()}.tmp"
    )

    fd = os.open(
        tmp,
        os.O_WRONLY | os.O_CREAT | os.O_TRUNC,
        0o600,
    )

    try:
        os.write(fd, (value + "\n").encode())
        os.fsync(fd)
    finally:
        os.close(fd)

    os.replace(tmp, path)
    os.chmod(path, 0o600)


def configure_approle(token: str) -> None:
    policy_text = POLICY_FILE.read_text(encoding="utf-8")

    paths = re.findall(
        r'(?m)^\s*path\s+"([^"]+)"\s*\{',
        policy_text,
    )

    if paths != [SNAPSHOT_PATH]:
        raise RuntimeError(
            f"policy bacula-snapshot inesperada: paths={paths!r}"
        )

    caps = re.findall(
        r'(?m)^\s*capabilities\s*=\s*\[([^\]]+)\]',
        policy_text,
    )

    parsed_caps = (
        re.findall(r'"([^"]+)"', caps[0])
        if len(caps) == 1
        else []
    )

    if parsed_caps != ["read"]:
        raise RuntimeError(
            "policy bacula-snapshot deve ter somente read"
        )

    auths = api(
        "GET",
        "sys/auth",
        token=token,
        expected=(200,),
    )

    if "approle/" not in auths:
        api(
            "POST",
            "sys/auth/approle",
            {
                "type": "approle",
                "description": "AppRole workloads ConectaEduca",
            },
            token=token,
            expected=(200, 204),
        )

    api(
        "PUT",
        f"sys/policies/acl/{POLICY}",
        {"policy": policy_text},
        token=token,
        expected=(200, 204),
    )

    role_payload = {
        "bind_secret_id": True,
        "token_policies": [POLICY],
        "token_no_default_policy": True,
        "token_ttl": "5m",
        "token_max_ttl": "10m",
        "token_num_uses": 1,
        "secret_id_ttl": "0",
        "secret_id_num_uses": 0,
    }

    api(
        "POST",
        f"auth/approle/role/{ROLE}",
        role_payload,
        token=token,
        expected=(200, 204),
    )

    role_data = (
        api(
            "GET",
            f"auth/approle/role/{ROLE}",
            token=token,
            expected=(200,),
        ).get("data")
        or {}
    )

    if not role_data.get("bind_secret_id"):
        raise RuntimeError("AppRole perdeu bind_secret_id")

    if not role_data.get("token_no_default_policy"):
        raise RuntimeError("AppRole recebeu default policy")

    if int(role_data.get("token_num_uses", -1)) != 1:
        raise RuntimeError("token_num_uses não ficou em 1")

    if int(role_data.get("secret_id_num_uses", -1)) != 0:
        raise RuntimeError("SecretID não ficou reutilizável")

    if int(role_data.get("secret_id_ttl", -1)) != 0:
        raise RuntimeError("SecretID recebeu TTL inesperado")

    role_id = str(
        (
            api(
                "GET",
                f"auth/approle/role/{ROLE}/role-id",
                token=token,
                expected=(200,),
            ).get("data")
            or {}
        ).get("role_id")
        or ""
    )

    secret_id = str(
        (
            api(
                "POST",
                f"auth/approle/role/{ROLE}/secret-id",
                {},
                token=token,
                expected=(200, 204),
            ).get("data")
            or {}
        ).get("secret_id")
        or ""
    )

    if not role_id or not secret_id:
        raise RuntimeError("RoleID/SecretID não foram obtidos")

    atomic_credential(ROLE_FILE, role_id)
    atomic_credential(SECRET_FILE, secret_id)

    role_id = ""
    secret_id = ""

    out(
        "OK",
        "AppRole bacula-snapshot criada; credenciais em .runtime 0600",
    )


def prove_snapshot() -> None:
    role_id = ROLE_FILE.read_text(
        encoding="utf-8"
    ).strip()
    secret_id = SECRET_FILE.read_text(
        encoding="utf-8"
    ).strip()

    login = api(
        "POST",
        "auth/approle/login",
        {
            "role_id": role_id,
            "secret_id": secret_id,
        },
        expected=(200,),
    )

    role_id = ""
    secret_id = ""

    auth = login.get("auth") or {}
    token = str(auth.get("client_token") or "")
    policies = list(auth.get("policies") or [])

    if (
        not token
        or POLICY not in policies
        or "default" in policies
    ):
        raise RuntimeError("token AppRole retornou policies inesperadas")

    blob = api(
        "GET",
        SNAPSHOT_PATH,
        token=token,
        expected=(200,),
        raw=True,
    )

    if len(blob) < 128:
        raise RuntimeError("snapshot Raft inválido")

    token = ""

    out(
        "OK",
        f"snapshot Raft provado via AppRole; bytes={len(blob)}",
    )
    out(
        "OK",
        "token AppRole de um uso expirou após o snapshot",
    )


def revoke_root(token: str) -> None:
    api(
        "POST",
        "auth/token/revoke-self",
        {},
        token=token,
        expected=(200, 204),
    )
    out("OK", "root temporário revogado")


def main() -> int:
    global root_token

    if not (REPO / ".git").is_dir():
        die("repositório ConectaEduca ausente")

    for share in SHARES:
        if not share.is_file():
            die("share necessária de custódia ausente")

    custody_mode = stat.S_IMODE(CUSTODY.stat().st_mode)

    if custody_mode & 0o077:
        die("custódia com permissões excessivas")

    out(
        "INFO",
        "recuperação única bacula-snapshot; nenhum segredo será impresso",
    )

    patch_listener()

    try:
        recreate()
        unseal()

        api(
            "GET",
            "sys/generate-root/attempt",
            expected=(200,),
        )

        out(
            "OK",
            "generate-root disponível apenas durante recuperação",
        )

        root_token = generate_root()

        configure_approle(root_token)
        prove_snapshot()

        revoke_root(root_token)
        root_token = ""

        restore_hcl()
        recreate()
        unseal()

        try:
            api(
                "GET",
                "sys/generate-root/attempt",
                expected=(200,),
            )
        except RuntimeError:
            out(
                "OK",
                "generate-root voltou a ficar desabilitado",
            )
        else:
            raise RuntimeError(
                "generate-root permaneceu acessível após hardening"
            )

        out(
            "SUCESSO",
            "AppRole bacula-snapshot pronta sem root persistente",
        )

        return 0

    finally:
        if root_token:
            try:
                revoke_root(root_token)
            except Exception:
                out(
                    "ALERTA",
                    "não foi possível confirmar revogação do root temporário",
                )
            root_token = ""

        if (
            original_hcl
            and HCL.read_text(encoding="utf-8")
            != original_hcl
        ):
            restore_hcl()

            try:
                recreate()
                unseal()
                out(
                    "INFO",
                    "OpenBao restaurado com HCL endurecido após interrupção",
                )
            except Exception:
                out(
                    "ALERTA",
                    "HCL restaurado, mas estado final requer investigação",
                )


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        out("FALHA", f"{type(exc).__name__}: {exc}")
        raise SystemExit(1)
