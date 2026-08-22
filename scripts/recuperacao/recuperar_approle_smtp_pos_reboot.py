#!/usr/bin/env python3
from __future__ import annotations

import base64
import json
import os
import re
import stat
import subprocess
import sys
import time
import http.client
from pathlib import Path
from typing import NoReturn

REPO = Path("/srv/www/htdocs/conectaeduca")
HCL = REPO / "deploy/interna/openbao/config/openbao.hcl"
COMPOSE = REPO / "deploy/interna/openbao/compose.yml"
POLICY_FILE = (
    REPO
    / "deploy/interna/openbao/policies/conectaeduca-smtp-read.hcl"
)

CUSTODY = (
    Path.home()
    / ".local/share/conectaeduca/openbao-custodia-lab"
)
SHARES = [
    CUSTODY / "unseal-share-1.txt",
    CUSTODY / "unseal-share-2.txt",
]

WORKLOAD = (
    Path.home()
    / ".local/share/conectaeduca/openbao-workload-smtp"
)
ROLE_FILE = WORKLOAD / "role-id"
SECRET_FILE = WORKLOAD / "secret-id"

BAO_HOST = "127.0.0.1"
BAO_PORT = 18200
ROLE = "conectaeduca-smtp"
POLICY = "conectaeduca-smtp-read"
SECRET_PATH = "secret/data/conectaeduca/smtp"

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
        token: str | None = None, expected=(200, 204)):
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

    # Recuperação LAB-only: transporte restrito a 127.0.0.1.
    # Antes de comunicação entre VMs, a arquitetura exige TLS.
    conn = http.client.HTTPConnection(
        BAO_HOST,
        BAO_PORT,
        timeout=10,
    )

    try:
        conn.request(
            method,
            f"/v1/{path}",
            body=data,
            headers=headers,
        )
        resp = conn.getresponse()
        raw = resp.read()
        code = resp.status
    finally:
        conn.close()

    if code not in expected:
        raise RuntimeError(f"HTTP {code} em {path}")

    if not raw:
        return {}

    return json.loads(raw)


def wait_health() -> dict:
    for _ in range(40):
        try:
            return api(
                "GET",
                "sys/health",
                expected=(200, 429, 472, 473, 501, 503),
            )
        except Exception:
            time.sleep(1)

    raise RuntimeError("OpenBao não respondeu dentro do tempo esperado")


def wait_active(timeout_seconds: int = 45) -> dict:
    """Espera o nó Raft local assumir estado ativo após o unseal."""
    deadline = time.monotonic() + timeout_seconds
    last = {}

    while time.monotonic() < deadline:
        try:
            code, raw = _health_raw()
            if raw:
                last = json.loads(raw)

            if (
                code == 200
                and last.get("initialized") is True
                and last.get("sealed") is False
                and last.get("standby") is False
            ):
                out("OK", "OpenBao Raft assumiu estado ativo")
                return last

        except Exception:
            pass

        time.sleep(1)

    raise RuntimeError(
        "OpenBao ficou unsealed, mas não assumiu estado ativo "
        f"dentro de {timeout_seconds}s; último estado={last!r}"
    )


def _health_raw():
    # Mesmo contrato LAB-only da função api(): loopback local.
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


def read_share(path: Path) -> str:
    if not path.is_file():
        raise RuntimeError(f"share ausente: {path}")

    value = path.read_text(encoding="utf-8").strip()
    if not value:
        raise RuntimeError(f"share vazia: {path}")

    return value


def unseal() -> None:
    health = wait_health()

    if not health.get("initialized"):
        raise RuntimeError("OpenBao não inicializado")

    if not health.get("sealed"):
        out("OK", "OpenBao já está unsealed")
        wait_active()
        return

    for path in SHARES:
        response = api(
            "POST",
            "sys/unseal",
            {"key": read_share(path)},
            expected=(200,),
        )

        if response.get("sealed") is False:
            break

    health = wait_health()

    if health.get("sealed"):
        raise RuntimeError("OpenBao continuou selado após o quorum")

    out("OK", "OpenBao unsealed com quorum local de laboratório")
    wait_active()


def patch_legacy_listener() -> None:
    global original_hcl

    original_hcl = HCL.read_text(encoding="utf-8")

    if "disable_unauthed_generate_root_endpoints" in original_hcl:
        raise RuntimeError(
            "HCL já contém configuração explícita de generate-root; "
            "revisão manual necessária"
        )

    marker = '  tls_disable     = true\n'
    if original_hcl.count(marker) != 1:
        raise RuntimeError(
            "não encontrei exatamente um marcador tls_disable esperado"
        )

    patched = original_hcl.replace(
        marker,
        marker
        + '  disable_unauthed_generate_root_endpoints = false\n',
        1,
    )

    HCL.write_text(patched, encoding="utf-8")
    out(
        "OK",
        "endpoint legado habilitado TEMPORARIAMENTE no listener local",
    )


def restore_hcl() -> None:
    if original_hcl:
        HCL.write_text(original_hcl, encoding="utf-8")
        out("OK", "HCL endurecido restaurado")


def recreate() -> None:
    compose_rel = str(COMPOSE.relative_to(REPO))

    run(
        "docker",
        "compose",
        "-f",
        compose_rel,
        "config",
    )

    run(
        "docker",
        "compose",
        "-f",
        compose_rel,
        "up",
        "-d",
        "--force-recreate",
    )

    wait_health()


def decode_root(encoded_token: str, otp: str) -> str:
    encoded = encoded_token.strip()

    if not encoded:
        raise RuntimeError("encoded_token vazio")

    # Base64 normalmente tem comprimento múltiplo de 4.
    # Acrescentamos somente o padding "=" eventualmente omitido,
    # sem alterar nem registrar o conteúdo sensível.
    padding = (-len(encoded)) % 4
    encoded_padded = encoded + ("=" * padding)

    try:
        raw = base64.b64decode(
            encoded_padded,
            validate=True,
        )
    except Exception as exc:
        raise RuntimeError(
            "encoded_token retornado pelo OpenBao não pôde ser "
            "decodificado como Base64 padrão "
            f"(comprimento={len(encoded)}, "
            f"resto_mod4={len(encoded) % 4}, "
            f"padding_adicionado={padding})"
        ) from exc

    otp_bytes = otp.encode("utf-8")

    if len(raw) != len(otp_bytes):
        raise RuntimeError(
            "comprimento do token codificado não corresponde ao OTP "
            f"(token_decodificado={len(raw)} bytes, "
            f"otp={len(otp_bytes)} bytes)"
        )

    decoded = bytes(
        value ^ otp_value
        for value, otp_value in zip(raw, otp_bytes)
    )

    try:
        return decoded.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise RuntimeError(
            "root token decodificado não é UTF-8 válido"
        ) from exc


def generate_temporary_root() -> str:
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
        raise RuntimeError(
            "generate-root não retornou OTP/nonce"
        )

    final = None

    for path in SHARES:
        final = api(
            "POST",
            "sys/generate-root/update",
            {
                "key": read_share(path),
                "nonce": nonce,
            },
            expected=(200,),
        )

        if final.get("complete"):
            break

    if not final or not final.get("complete"):
        raise RuntimeError(
            "quorum não completou a geração do root temporário"
        )

    encoded = str(final.get("encoded_token") or "")
    if not encoded:
        raise RuntimeError(
            "generate-root não retornou token codificado"
        )

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
        raise RuntimeError(
            "token recuperado não possui policy root"
        )

    out(
        "OK",
        "root temporário recuperado somente em memória",
    )

    return token


def atomic_credential(path: Path, value: str) -> None:
    WORKLOAD.mkdir(parents=True, exist_ok=True)
    # Diretório de RoleID/SecretID: 0700 é deliberadamente restritivo.
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


def configure_workload(token: str) -> None:
    policy_text = POLICY_FILE.read_text(encoding="utf-8")

    paths = re.findall(
        r'(?m)^\s*path\s+"([^"]+)"\s*\{',
        policy_text,
    )

    if paths != [SECRET_PATH]:
        raise RuntimeError(
            f"policy SMTP inesperada: paths={paths!r}"
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
            "policy SMTP deve ter exclusivamente capability read"
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

        # Laboratório: SecretID persistente para retomada.
        # O token emitido continua curto e de um único uso.
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
        raise RuntimeError(
            "AppRole perdeu bind_secret_id"
        )

    if not role_data.get("token_no_default_policy"):
        raise RuntimeError(
            "AppRole perdeu token_no_default_policy"
        )

    if int(role_data.get("secret_id_num_uses", -1)) != 0:
        raise RuntimeError(
            "SecretID não ficou reutilizável no laboratório"
        )

    if int(role_data.get("secret_id_ttl", -1)) != 0:
        raise RuntimeError(
            "SecretID recebeu TTL inesperado"
        )

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

    sid = str(
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

    if not role_id or not sid:
        raise RuntimeError(
            "não foi possível emitir a credencial AppRole de workload"
        )

    atomic_credential(ROLE_FILE, role_id)
    atomic_credential(SECRET_FILE, sid)

    role_id = ""
    sid = ""

    stored_role = ROLE_FILE.read_text(
        encoding="utf-8"
    ).strip()

    stored_sid = SECRET_FILE.read_text(
        encoding="utf-8"
    ).strip()

    # Prova leitura permitida com token de um único uso.
    login = api(
        "POST",
        "auth/approle/login",
        {
            "role_id": stored_role,
            "secret_id": stored_sid,
        },
        expected=(200,),
    )

    auth = login.get("auth") or {}
    app_token = str(auth.get("client_token") or "")
    policies = list(auth.get("policies") or [])

    if (
        not app_token
        or POLICY not in policies
        or "default" in policies
    ):
        raise RuntimeError(
            "login de workload retornou policies inesperadas"
        )

    allowed = api(
        "GET",
        SECRET_PATH,
        token=app_token,
        expected=(200,),
    )
    app_token = ""

    if not str(
        ((allowed.get("data") or {}).get("data") or {}).get(
            "password"
        )
        or ""
    ):
        raise RuntimeError(
            "workload não conseguiu ler o segredo SMTP"
        )

    # Prova deny fora do único path permitido.
    login = api(
        "POST",
        "auth/approle/login",
        {
            "role_id": stored_role,
            "secret_id": stored_sid,
        },
        expected=(200,),
    )

    deny_token = str(
        (login.get("auth") or {}).get("client_token")
        or ""
    )

    api(
        "GET",
        "secret/data/conectaeduca/outro-segredo",
        token=deny_token,
        expected=(403,),
    )

    deny_token = ""
    stored_role = ""
    stored_sid = ""

    out(
        "OK",
        "workload: read somente no SMTP e deny em path vizinho",
    )
    out(
        "OK",
        "RoleID/SecretID protegidos fora do Git para retomada do laboratório",
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
        die("repositório ConectaEduca não encontrado")

    for path in SHARES:
        if not path.is_file():
            die(f"share de custódia ausente: {path}")

    custody_mode = stat.S_IMODE(
        CUSTODY.stat().st_mode
    )

    if custody_mode & 0o077:
        die(
            "custódia com permissões excessivas: "
            f"mode={oct(custody_mode)}"
        )

    out(
        "INFO",
        "recuperação administrativa v2.2 de UMA VEZ; "
        "nenhum segredo será impresso",
    )

    patch_legacy_listener()

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
            "generate-root legado disponível apenas durante a recuperação",
        )

        root_token = generate_temporary_root()

        configure_workload(root_token)

        revoke_root(root_token)
        root_token = ""

        # Restaura o hardening antes da retomada normal.
        restore_hcl()

        recreate()
        unseal()

        # Depois de unsealed + hardening, o legado não pode responder 200.
        try:
            api(
                "GET",
                "sys/generate-root/attempt",
                expected=(200,),
            )
        except RuntimeError:
            out(
                "OK",
                "generate-root legado voltou a ficar desabilitado",
            )
        else:
            raise RuntimeError(
                "generate-root legado ainda responde "
                "após restauração do hardening"
            )

        run(
            "fish",
            "scripts/bootstrap/"
            "materializar_openbao_smtp_runtime.fish",
        )

        smtp_file = Path(
            "/dev/shm/conectaeduca-smtp-password"
        )

        if not smtp_file.is_file():
            raise RuntimeError(
                "segredo SMTP não foi materializado "
                "após a recuperação"
            )

        out(
            "OK",
            "retomada SMTP provada sem root token "
            "e sem reprovisionar OpenBao",
        )

        out(
            "SUCESSO",
            "credencial de workload pronta para "
            "os próximos reboots do laboratório",
        )

        return 0

    finally:
        # Best effort: um root temporário nunca deve ficar ativo.
        if root_token:
            try:
                revoke_root(root_token)
            except Exception:
                out(
                    "ALERTA",
                    "não foi possível confirmar a revogação "
                    "do root temporário; interrompa e investigue",
                )
            root_token = ""

        # O HCL versionado deve sempre terminar endurecido.
        if (
            original_hcl
            and HCL.read_text(encoding="utf-8")
            != original_hcl
        ):
            restore_hcl()

            try:
                recreate()
                out(
                    "INFO",
                    "OpenBao recriado com configuração "
                    "endurecida após interrupção",
                )
            except Exception:
                out(
                    "ALERTA",
                    "HCL foi restaurado, mas não foi possível "
                    "confirmar recriação do OpenBao",
                )


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        out(
            "FALHA",
            f"{type(exc).__name__}: {exc}",
        )
        raise SystemExit(1)
