#!/usr/bin/env python3
from __future__ import annotations

import getpass
import http.client
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import time
from urllib.parse import urlsplit

BASE = os.environ.get("CONECTAEDUCA_OPENBAO_ADDR", "http://127.0.0.1:18200").rstrip("/")
REPO = Path(__file__).resolve().parents[2]
POLICY_FILE = REPO / "deploy/interna/openbao/policies/conectaeduca-smtp-read.hcl"
CUSTODY_DIR = Path.home() / ".local/share/conectaeduca/openbao-custodia-lab"
ROOT_TOKEN_FILE = Path("/dev/shm/conectaeduca-openbao-initial-root-token")
SMTP_MATERIALIZED_FILE = Path("/dev/shm/conectaeduca-smtp-password")
RUNTIME_DIR = REPO / "deploy/dmz/.runtime"
RUNTIME_ENV = RUNTIME_DIR / "smtp-google.env"
CONTAINER = "conectaeduca-openbao"

ROLE = "conectaeduca-smtp"
POLICY = "conectaeduca-smtp-read"
SECRET_PATH = "secret/data/conectaeduca/smtp"

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class BaoError(RuntimeError):
    pass


def out(level: str, msg: str) -> None:
    print(f"{level:<11} {msg}", flush=True)


def _openbao_endpoint() -> tuple[str, str, int]:
    parsed = urlsplit(BASE)

    if parsed.scheme not in {"http", "https"}:
        raise BaoError("CONECTAEDUCA_OPENBAO_ADDR deve usar somente http ou https")
    if not parsed.hostname:
        raise BaoError("CONECTAEDUCA_OPENBAO_ADDR não contém hostname válido")
    if parsed.username is not None or parsed.password is not None:
        raise BaoError("credenciais não podem ser embutidas na URL do OpenBao")
    if parsed.query or parsed.fragment:
        raise BaoError("query/fragment não são permitidos na URL base do OpenBao")
    if parsed.path not in {"", "/"}:
        raise BaoError("a URL base do OpenBao não deve conter caminho adicional")

    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    return parsed.scheme, parsed.hostname, port


BAO_SCHEME, BAO_HOST, BAO_PORT = _openbao_endpoint()


def api(method: str, path: str, data=None, token: str | None = None,
        expected=(200, 204)) -> dict:
    method = method.upper()
    safe_path = path.lstrip("/")

    if method not in {"GET", "POST", "LIST"}:
        raise BaoError(f"método HTTP não permitido no cliente OpenBao: {method}")
    if (
        not safe_path
        or not re.fullmatch(r"[A-Za-z0-9._/-]+", safe_path)
        or ".." in safe_path.split("/")
    ):
        raise BaoError("caminho inválido para a API do OpenBao")

    body = None
    headers = {"Accept": "application/json"}
    if data is not None:
        body = json.dumps(data).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if token:
        headers["X-Vault-Token"] = token

    connection_class = (
        http.client.HTTPSConnection
        if BAO_SCHEME == "https"
        else http.client.HTTPConnection
    )
    connection = connection_class(BAO_HOST, BAO_PORT, timeout=10)

    try:
        connection.request(method, f"/v1/{safe_path}", body=body, headers=headers)
        response = connection.getresponse()
        raw = response.read()
        code = response.status
    except (OSError, http.client.HTTPException) as exc:
        raise BaoError(f"OpenBao inacessível em {BASE}") from exc
    finally:
        connection.close()

    if code not in expected:
        detail = ""
        try:
            payload = json.loads(raw.decode("utf-8", "replace"))
            detail = "; ".join(payload.get("errors", []))
        except Exception:
            detail = "resposta de erro não-JSON"
        suffix = f": {detail}" if detail else ""
        raise BaoError(f"{method} {path}: HTTP {code}{suffix}")

    if not raw:
        return {}
    try:
        return json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        return {}


def wait_api(seconds: int = 30) -> None:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            api("GET", "sys/init")
            return
        except Exception:
            time.sleep(1)
    raise BaoError(f"OpenBao não respondeu em {BASE} após {seconds}s")


def atomic_secret_file(path: Path, value: str, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(value)
            if not value.endswith("\n"):
                handle.write("\n")
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        try:
            tmp.unlink()
        except FileNotFoundError:
            pass


def read_secret_file(path: Path) -> str:
    return path.read_text(encoding="utf-8").strip()


def initialize_if_needed() -> tuple[str, list[str], bool]:
    status = api("GET", "sys/init")
    initialized = bool(status.get("initialized"))

    if not initialized:
        result = api(
            "POST",
            "sys/init",
            {"secret_shares": 3, "secret_threshold": 2},
            expected=(200,),
        )
        shares = result.get("keys_base64") or result.get("keys") or []
        root_token = str(result.get("root_token", ""))
        if len(shares) != 3 or not root_token:
            raise BaoError("resposta de inicialização não contém 3 shares e root token")

        CUSTODY_DIR.mkdir(parents=True, exist_ok=True)
        os.chmod(CUSTODY_DIR, 0o700)  # nosemgrep: python.lang.security.audit.insecure-file-permissions.insecure-file-permissions

        for idx, share in enumerate(shares, start=1):
            atomic_secret_file(CUSTODY_DIR / f"unseal-share-{idx}.txt", str(share), 0o400)

        readme = CUSTODY_DIR / "LEIA-ME.txt"
        readme.write_text(
            "ConectaEduca / OpenBao - custódia temporária do laboratório\n"
            "=========================================================\n"
            "Foram geradas 3 shares Shamir; 2 são necessárias para unseal.\n"
            "Distribua as shares por custódias distintas/offline e remova esta\n"
            "cópia agregada do notebook depois de confirmar a custódia.\n"
            "Nunca coloque estas shares no Git, chat, relatório ou evidência.\n",
            encoding="utf-8",
        )
        os.chmod(readme, 0o600)

        atomic_secret_file(ROOT_TOKEN_FILE, root_token, 0o600)
        out("OK", "OpenBao inicializado com Shamir: 3 shares, threshold 2")
        out("OK", "shares gravadas em custódia temporária fora do repositório")
        return root_token, [str(s) for s in shares], True

    # Retomada segura de uma execução interrompida.
    if not ROOT_TOKEN_FILE.is_file():
        raise BaoError(
            "OpenBao já está inicializado, mas o root token inicial temporário não existe. "
            "Não tente reinicializar. Use as shares de custódia para um procedimento "
            "controlado de generate-root."
        )

    root_token = read_secret_file(ROOT_TOKEN_FILE)
    shares = []
    for idx in (1, 2, 3):
        p = CUSTODY_DIR / f"unseal-share-{idx}.txt"
        if p.is_file():
            shares.append(read_secret_file(p))
    if len(shares) < 2:
        raise BaoError("faltam pelo menos 2 shares de custódia para retomar o unseal")
    out("INFO", "retomando configuração de OpenBao já inicializado")
    return root_token, shares, False


def ensure_unsealed(shares: list[str]) -> None:
    status = api("GET", "sys/seal-status")
    if not status.get("sealed"):
        out("OK", "OpenBao já está unsealed")
        return

    for share in shares[:2]:
        status = api("POST", "sys/unseal", {"key": share}, expected=(200,))
        if not status.get("sealed"):
            break

    status = api("GET", "sys/seal-status")
    if status.get("sealed"):
        raise BaoError("OpenBao permaneceu sealed após o threshold esperado")
    out("OK", "OpenBao unsealed com threshold Shamir sem expor shares")


def ensure_audit(root_token: str) -> None:
    # O audit device é declarativo no HCL. SIGHUP força reconciliação da config.
    subprocess.run(
        ["docker", "kill", "--signal=SIGHUP", CONTAINER],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    time.sleep(1)
    audits = api("GET", "sys/audit", token=root_token, expected=(200,))
    if not any(
        isinstance(v, dict)
        and v.get("type") == "file"
        and (v.get("options") or {}).get("file_path") in {"stdout", "/dev/stdout"}
        for v in audits.values()
    ):
        raise BaoError("audit device declarativo para stdout não foi materializado")
    out("OK", "auditoria OpenBao para stdout está habilitada sem log_raw")


def ensure_kv_v2(root_token: str) -> None:
    mounts = api("GET", "sys/mounts", token=root_token, expected=(200,))
    secret = mounts.get("secret/")
    if secret is None:
        api(
            "POST",
            "sys/mounts/secret",
            {"type": "kv", "options": {"version": "2"}},
            token=root_token,
            expected=(200, 204),
        )
    else:
        version = str((secret.get("options") or {}).get("version", "1"))
        if secret.get("type") != "kv":
            raise BaoError("mount secret/ existe, mas não é KV")
        if version != "2":
            api(
                "POST",
                "sys/mounts/secret/tune",
                {"options": {"version": "2"}},
                token=root_token,
                expected=(200, 204),
            )

    mounts = api("GET", "sys/mounts", token=root_token, expected=(200,))
    secret = mounts.get("secret/") or {}
    if secret.get("type") != "kv" or str((secret.get("options") or {}).get("version")) != "2":
        raise BaoError("secret/ não ficou configurado como KV v2")
    out("OK", "KV v2 habilitado em secret/")


def ensure_policy(root_token: str) -> str:
    policy_text = POLICY_FILE.read_text(encoding="utf-8")

    # Valida semanticamente o artefato versionado ANTES de enviá-lo.
    # Não dependemos da formatação/serialização retornada pela API.
    stanzas = re.findall(
        r'path\s+"([^"]+)"\s*\{(.*?)\}',
        policy_text,
        flags=re.DOTALL,
    )
    if len(stanzas) != 1:
        raise BaoError(
            f"policy SMTP versionada deve conter exatamente 1 path; encontrados={len(stanzas)}"
        )

    path_name, body = stanzas[0]
    if path_name != "secret/data/conectaeduca/smtp":
        raise BaoError("policy SMTP versionada aponta para path inesperado")

    cap_match = re.search(
        r'capabilities\s*=\s*\[(.*?)\]',
        body,
        flags=re.DOTALL,
    )
    if cap_match is None:
        raise BaoError("policy SMTP versionada não declara capabilities")

    capabilities = re.findall(r'"([^"]+)"', cap_match.group(1))
    if capabilities != ["read"]:
        raise BaoError(
            "policy SMTP versionada deve possuir exclusivamente a capability read"
        )

    api(
        "POST",
        f"sys/policies/acl/{POLICY}",
        {"policy": policy_text},
        token=root_token,
        expected=(200, 204),
    )

    # Confirma que a policy está registrada sem depender do formato retornado
    # pelo endpoint de leitura (que varia entre implementações/versões).
    listed = api("LIST", "sys/policies/acl", token=root_token, expected=(200,))
    keys = listed.get("keys") or ((listed.get("data") or {}).get("keys")) or []
    if POLICY not in keys:
        raise BaoError("policy SMTP foi enviada, mas não aparece na listagem de ACL policies")

    out(
        "OK",
        "policy SMTP versionada: 1 path, somente read e registrada no OpenBao",
    )
    return policy_text


def cleanup_stale_smtp_approle_tokens(root_token: str) -> None:
    """Revoga tokens AppRole SMTP deixados por bootstrap interrompido."""
    accessors = api(
        "LIST",
        "auth/token/accessors",
        token=root_token,
        expected=(200,),
    )
    keys = (
        accessors.get("keys")
        or ((accessors.get("data") or {}).get("keys"))
        or []
    )

    revoked = 0
    for accessor in keys:
        try:
            lookup = api(
                "POST",
                "auth/token/lookup-accessor",
                {"accessor": accessor},
                token=root_token,
                expected=(200,),
            )
        except BaoError:
            continue

        data = lookup.get("data") or {}
        policies = data.get("policies") or []
        path = str(data.get("path") or "")

        if path == "auth/approle/login" and POLICY in policies:
            api(
                "POST",
                "auth/token/revoke-accessor",
                {"accessor": accessor},
                token=root_token,
                expected=(200, 204),
            )
            revoked += 1

    if revoked:
        out(
            "OK",
            f"tokens AppRole SMTP residuais de tentativa anterior revogados: {revoked}",
        )
    else:
        out("OK", "nenhum token AppRole SMTP residual encontrado")


def ensure_approle(root_token: str) -> None:
    auths = api("GET", "sys/auth", token=root_token, expected=(200,))
    if "approle/" not in auths:
        api(
            "POST",
            "sys/auth/approle",
            {"type": "approle"},
            token=root_token,
            expected=(200, 204),
        )

    api(
        "POST",
        f"auth/approle/role/{ROLE}",
        {
            "bind_secret_id": True,
            "token_policies": [POLICY],
            "token_no_default_policy": True,
            "token_ttl": "15m",
            "token_max_ttl": "30m",
            "token_num_uses": 1,
            "secret_id_ttl": "10m",
            "secret_id_num_uses": 1,
        },
        token=root_token,
        expected=(200, 204),
    )
    role = api("GET", f"auth/approle/role/{ROLE}", token=root_token, expected=(200,))
    data = role.get("data") or {}
    policies = data.get("token_policies") or data.get("policies") or []
    if POLICY not in policies or not data.get("bind_secret_id", False):
        raise BaoError("AppRole não recebeu policy/bind_secret_id esperados")
    if not data.get("token_no_default_policy", False):
        raise BaoError("AppRole SMTP ainda receberia a policy default")
    out(
        "OK",
        "AppRole SMTP configurado sem default policy, SecretID obrigatório e TTL curto",
    )


def store_and_materialize(root_token: str, email: str, app_password: str, recipient: str) -> None:
    if app_password:
        api(
            "POST",
            SECRET_PATH,
            {"data": {"password": app_password}},
            token=root_token,
            expected=(200, 204),
        )
        out("OK", "App Password armazenado no KV v2 sem exposição no relatório")
    else:
        try:
            existing = api(
                "GET",
                SECRET_PATH,
                token=root_token,
                expected=(200,),
            )
        except BaoError as exc:
            raise BaoError(
                "nenhuma senha de app foi informada e não existe segredo SMTP "
                "reutilizável no OpenBao"
            ) from exc

        app_password = str(
            ((existing.get("data") or {}).get("data") or {}).get("password") or ""
        )
        if not app_password:
            raise BaoError("segredo SMTP existente no OpenBao está vazio")
        out(
            "OK",
            "App Password já existente no KV v2 será reutilizado sem exposição",
        )

    role_id = (api(
        "GET",
        f"auth/approle/role/{ROLE}/role-id",
        token=root_token,
        expected=(200,),
    ).get("data") or {}).get("role_id")
    secret_id = (api(
        "POST",
        f"auth/approle/role/{ROLE}/secret-id",
        {},
        token=root_token,
        expected=(200, 204),
    ).get("data") or {}).get("secret_id")

    if not role_id or not secret_id:
        raise BaoError("não foi possível obter RoleID/SecretID efêmeros")

    login = api(
        "POST",
        "auth/approle/login",
        {"role_id": role_id, "secret_id": secret_id},
        expected=(200,),
    )
    app_token = (login.get("auth") or {}).get("client_token")
    policies = (login.get("auth") or {}).get("policies") or []
    if not app_token or POLICY not in policies:
        raise BaoError("login AppRole não retornou token com policy mínima")

    try:
        # Prova as permissões EFETIVAS do token, em vez de confiar apenas
        # no texto da policy.
        allowed_path = "secret/data/conectaeduca/smtp"
        denied_paths = [
            "secret/data/conectaeduca/outro-segredo",
            "secret/metadata/conectaeduca/smtp",
        ]

        caps_allowed = api(
            "POST",
            "sys/capabilities",
            {"token": app_token, "paths": [allowed_path]},
            token=root_token,
            expected=(200,),
        )
        allowed = (
            caps_allowed.get(allowed_path)
            or caps_allowed.get("capabilities")
            or ((caps_allowed.get("data") or {}).get(allowed_path))
            or ((caps_allowed.get("data") or {}).get("capabilities"))
            or []
        )
        if sorted(allowed) != ["read"]:
            raise BaoError(
                f"AppRole deveria ter somente read no segredo SMTP; capabilities={allowed!r}"
            )

        for denied_path in denied_paths:
            caps_denied = api(
                "POST",
                "sys/capabilities",
                {"token": app_token, "paths": [denied_path]},
                token=root_token,
                expected=(200,),
            )
            denied = (
                caps_denied.get(denied_path)
                or caps_denied.get("capabilities")
                or ((caps_denied.get("data") or {}).get(denied_path))
                or ((caps_denied.get("data") or {}).get("capabilities"))
                or []
            )
            if denied != ["deny"]:
                raise BaoError(
                    f"AppRole possui capability inesperada fora do path SMTP: "
                    f"{denied_path} -> {denied!r}"
                )

        out(
            "OK",
            "capabilities efetivas confirmadas: read no SMTP e deny em paths vizinhos",
        )

        secret = api("GET", SECRET_PATH, token=app_token, expected=(200,))
        recovered = ((secret.get("data") or {}).get("data") or {}).get("password")
        if recovered != app_password:
            raise BaoError("AppRole leu um valor diferente do segredo provisionado")

        atomic_secret_file(SMTP_MATERIALIZED_FILE, recovered, 0o600)
        st_mode = stat.S_IMODE(SMTP_MATERIALIZED_FILE.stat().st_mode)
        if st_mode != 0o600:
            raise BaoError(f"arquivo materializado ficou com modo {oct(st_mode)}")
        out("OK", "AppRole de leitura recuperou o segredo e materializou em RAM (/dev/shm)")
    finally:
        try:
            api(
                "POST",
                "auth/token/revoke",
                {"token": app_token},
                token=root_token,
                expected=(200, 204),
            )
            out(
                "OK",
                "token AppRole de uso único revogado/confirmado pelo bootstrap",
            )
        except Exception:
            out("ADVERTENCIA", "não foi possível confirmar a revogação do token AppRole")

    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(RUNTIME_DIR, 0o700)  # nosemgrep: python.lang.security.audit.insecure-file-permissions.insecure-file-permissions
    env_text = "\n".join([
        "CONECTAEDUCA_SMTP_HOST=smtp.gmail.com",
        "CONECTAEDUCA_SMTP_PORT=587",
        f"CONECTAEDUCA_SMTP_USERNAME={email}",
        f"CONECTAEDUCA_SMTP_PASSWORD_FILE={SMTP_MATERIALIZED_FILE}",
        "CONECTAEDUCA_SMTP_ENCRYPTION=tls",
        f"CONECTAEDUCA_SMTP_FROM_ADDRESS={email}",
        "CONECTAEDUCA_SMTP_FROM_NAME=ConectaEduca",
        f"SMTP_REAL_CHECKPOINT_TO={recipient}",
        "",
    ])
    atomic_secret_file(RUNTIME_ENV, env_text, 0o600)
    out("OK", "runtime SMTP não secreto preparado fora do Git")


def revoke_root(root_token: str) -> None:
    api("POST", "auth/token/revoke-self", {}, token=root_token, expected=(200, 204))
    try:
        ROOT_TOKEN_FILE.unlink()
    except FileNotFoundError:
        pass
    out("OK", "root token inicial revogado e removido da RAM")


def main() -> int:
    print("=" * 70)
    print(" CONECTAEDUCA - OPENBAO OPERACIONAL + SMTP GOOGLE")
    print(" Shamir + KV v2 + AppRole mínimo + materialização efêmera")
    print("=" * 70)

    wait_api()

    email = input("Conta Google/Gmail de testes (e-mail completo): ").strip()
    if not EMAIL_RE.match(email):
        raise BaoError("endereço de e-mail inválido")

    recipient = input(
        "Caixa real de destino [Enter = mesma conta]: "
    ).strip() or email
    if not EMAIL_RE.match(recipient):
        raise BaoError("endereço de destino inválido")

    app_password = getpass.getpass(
        "Senha de app do Google "
        "(16 caracteres; Enter = reutilizar a já guardada no OpenBao): "
    ).replace(" ", "").strip()
    if app_password and len(app_password) != 16:
        raise BaoError("a senha de app deve ter 16 caracteres após remover espaços")

    root_token = ""
    new_init = False
    try:
        root_token, shares, new_init = initialize_if_needed()
        ensure_unsealed(shares)
        ensure_audit(root_token)
        ensure_kv_v2(root_token)
        ensure_policy(root_token)
        cleanup_stale_smtp_approle_tokens(root_token)
        ensure_approle(root_token)
        store_and_materialize(root_token, email, app_password, recipient)
        revoke_root(root_token)

        # Apaga referências sensíveis em memória o quanto antes.
        app_password = ""
        root_token = ""

        print()
        print("=" * 70)
        print(" RESULTADO")
        print("=" * 70)
        out("OK", "OpenBao operacional para o caso de uso SMTP")
        out("OK", "nenhum root token, AppRole token ou App Password foi impresso")
        out("INFO", f"custódia temporária das shares: {CUSTODY_DIR}")
        out("INFO", "distribua as 3 shares por custódias distintas/offline e remova a cópia agregada")
        out("INFO", f"segredo SMTP materializado em RAM: {SMTP_MATERIALIZED_FILE}")
        out("INFO", f"configuração runtime ignorada pelo Git: {RUNTIME_ENV}")
        return 0
    except Exception as exc:
        out("FALHA", "operacionalização não foi concluída")
        out("INFO", f"classe={exc.__class__.__name__}")
        out("INFO", f"mensagem={exc}")
        if ROOT_TOKEN_FILE.is_file():
            out(
                "ATENCAO",
                f"root token inicial foi preservado temporariamente em {ROOT_TOKEN_FILE} "
                "para permitir retomada; não copie nem versione esse arquivo",
            )
        return 1
    finally:
        app_password = ""
        root_token = ""


if __name__ == "__main__":
    sys.exit(main())
