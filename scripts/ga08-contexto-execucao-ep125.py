#!/usr/bin/env python3
"""GA08.18G: preserve reference-only Docker Compose context for cutover/rollback.

Does NOT store secret file contents or inline secret values. The context holds
host paths to existing secret mounts, service URLs, bind/port and socket paths;
thus it is still private 0600 data. No services are modified in --prepare.
Execution remains blocked by the original ga08-change-control.py interlocks.
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
import runpy
import socket
import stat
import subprocess
import sys
from pathlib import Path

ROOT = Path("/opt/conectaeduca")
HELPER = ROOT / "scripts/ga08-preflight-env-runtime-ep125.py"
DRIVER = ROOT / "scripts/ga08-implantacao-controlada-ep125.sh"
ROLLBACK = ROOT / "scripts/ga08-rollback-controlado-ep125.sh"
CHANGE_ROOT = Path.home() / "ConectaEduca_Fase2_Evidencias/EP125/GA08"
CONTEXT_FILE = "runtime-refs.json"
APPROVAL_EXAMPLE = "approval-template.json"
CONTEXT_KEYS = {
    "CONECTAEDUCA_DB_HOST", "CONECTAEDUCA_DB_PORT",
    "CONECTAEDUCA_APP_URL", "CONECTAEDUCA_DB_PASSWORD_FILE",
    "CONECTAEDUCA_PRIVATE_KEY_FILE", "CONECTAEDUCA_PUBLIC_KEY_FILE",
    "CONECTAEDUCA_DB_TLS_CA_FILE", "CONECTAEDUCA_WAF_TLS_CERT_FILE",
    "CONECTAEDUCA_WAF_TLS_KEY_FILE", "CONECTAEDUCA_STACK_SECRET_GID",
    "CONECTAEDUCA_WAF_BIND_ADDRESS", "CONECTAEDUCA_HTTP_PORT",
    "CONECTAEDUCA_HTTPS_PORT", "CONECTAEDUCA_GA08_SOCKET_DIR",
    "CONECTAEDUCA_GA08_HTTP_SOCKET_DIR", "CONECTAEDUCA_GA08_NGINX_CONF",
    "CONECTAEDUCA_GA08_NGINX_HTTP_UNIX_CONF", "CONECTAEDUCA_GA08_FPM_CONF",
}
GA08_ONLY = {x for x in CONTEXT_KEYS if x.startswith("CONECTAEDUCA_GA08_")}
SECRET_PATH_KEYS = {
    "CONECTAEDUCA_DB_PASSWORD_FILE", "CONECTAEDUCA_PRIVATE_KEY_FILE",
    "CONECTAEDUCA_PUBLIC_KEY_FILE", "CONECTAEDUCA_DB_TLS_CA_FILE",
    "CONECTAEDUCA_WAF_TLS_CERT_FILE", "CONECTAEDUCA_WAF_TLS_KEY_FILE",
}
SAFE_MARKERS = {
    "GA08_PREFLIGHT", "GA08_APLICACAO", "GA08_ROLLBACK",
    "GA08_GATE", "GA08_MOTIVO", "GA08_G0_SNAPSHOT_AUTORIZACAO",
    "GA08_ROLLBACK_AUTOMATICO", "GA08_CUTOVER",
    "GA08_PA02", "GA08_E2E_WAF_CRS_TLS_SQL_RBAC",
    "GA08_RECUPERACAO_FUNCIONAL_E2E", "GA08_ROLLBACK_MANIFESTO_GUARDADO",
}
SAFE_PREFIXES = ("GA08_SERVICE_", "GA08_ROLLBACK_")

def stop(reason: str) -> None:
    print("GA08_CONTEXT=BLOCKED_" + reason)
    print("CONTINUAR_COM_CUTOVER=NAO")
    sys.exit(2)

def host() -> str:
    name = socket.gethostname().split(".")[0]
    if name not in ("ep125-pucpr", "ep125-pucpr-br"): stop("HOST")
    if os.geteuid() == 0: stop("NAO_USAR_ROOT")
    return name

def private_dir(change_id: str) -> Path:
    if not re.fullmatch(r"GA08-[0-9]{8}-[A-Z0-9_-]{3,32}", change_id):
        stop("CHANGE_ID")
    if not CHANGE_ROOT.is_dir():
        CHANGE_ROOT.mkdir(parents=True, mode=0o700)
    root = CHANGE_ROOT
    if root.is_symlink() or root.stat().st_uid != os.getuid():
        stop("DIRETORIO_RAIZ_INSEGURO")
    if stat.S_IMODE(root.stat().st_mode) & 0o022: stop("RAIZ_PERMISSOES")
    base = root / change_id
    if base.is_symlink(): stop("DIRETORIO_SYMLINK")
    base.mkdir(mode=0o700, exist_ok=True)
    st = base.stat()
    if st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) != 0o700:
        stop("DIRETORIO_PERMISSOES")
    return base

def checked_file(path: Path) -> bytes:
    if not path.is_file() or path.is_symlink(): stop("ARQUIVO_NAO_REGULAR")
    st = path.stat()
    if st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) != 0o600:
        stop("ARQUIVO_PERMISSOES")
    if st.st_size > 20000: stop("ARQUIVO_GRANDE")
    return path.read_bytes()

def secure_create(path: Path, data: bytes) -> bool:
    if path.exists() or path.is_symlink():
        if checked_file(path) != data: stop("CONTEXTO_EXISTENTE_DIVERGENTE")
        return False
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as output:
        output.write(data)
        output.flush()
        os.fsync(output.fileno())
    return True

def references(helper: dict) -> dict[str, str]:
    for k in GA08_ONLY:
        helper["required_value"](os.environ.get(k), k)
    data = {
        service: helper["inspect"](service)
        for service in ("php", "waf", "nginx")
    }
    php_env = helper["environment"](data["php"])
    result = {k: helper["required_value"](os.environ.get(k), k) for k in GA08_ONLY}
    for dest, source in {
        "CONECTAEDUCA_DB_HOST": "DB_HOST",
        "CONECTAEDUCA_DB_PORT": "DB_PORT",
        "CONECTAEDUCA_APP_URL": "APP_URL",
    }.items():
        result[dest] = helper["required_value"](php_env.get(source), dest)

    for key, (service, name) in helper["SECRET_MOUNTS"].items():
        result[key] = helper["mount_path"](
            data[service], "/run/secrets/" + name, key
        )

    def groups(container: dict) -> set[str]:
        return {
            str(x) for x in ((container.get("HostConfig") or {}).get("GroupAdd") or [])
            if re.fullmatch(r"[0-9]+", str(x))
        }
    gids = groups(data["php"]) & groups(data["waf"])
    if len(gids) != 1: stop("GID_AMBIGUO")
    result["CONECTAEDUCA_STACK_SECRET_GID"] = next(iter(gids))
    bind, http, https = helper["published_bind"](data["waf"])
    result.update({
        "CONECTAEDUCA_WAF_BIND_ADDRESS": bind,
        "CONECTAEDUCA_HTTP_PORT": http,
        "CONECTAEDUCA_HTTPS_PORT": https,
    })
    validate_references(result)
    return result

def validate_references(refs: dict) -> None:
    if set(refs) != CONTEXT_KEYS: stop("CHAVES_ENV_DIVERGENTES")
    for name, value in refs.items():
        if not isinstance(value, str) or not value or len(value) > 4096:
            stop("ENV_VALOR_INVALIDO_" + name)
        if any(x in value for x in "\n\r\x00"):
            stop("ENV_CONTROLE_INVALIDO_" + name)
    for name in GA08_ONLY | SECRET_PATH_KEYS:
        if not Path(refs[name]).is_absolute(): stop("CAMINHO_RELATIVO_" + name)

def read_context(path: Path, change_id: str) -> dict[str, str]:
    try:
        obj = json.loads(checked_file(path))
    except (UnicodeError, ValueError):
        stop("JSON_CONTEXTO_INVALIDO")
    if (not isinstance(obj, dict) or obj.get("format") != 1
        or obj.get("change_id") != change_id
        or obj.get("host") not in ("ep125-pucpr", "ep125-pucpr-br")
        or not isinstance(obj.get("references"), dict)):
        stop("IDENTIDADE_CONTEXTO")
    refs = obj["references"]
    validate_references(refs)
    return refs

def run_control(driver: Path, args: list[str], refs: dict, timeout: int) -> int:
    proc_env = os.environ.copy()
    proc_env.update(refs)
    try:
        p = subprocess.run(
            ["bash", str(driver)] + args,
            cwd=ROOT, env=proc_env, text=True, capture_output=True,
            timeout=timeout, check=False
        )
    except subprocess.TimeoutExpired:
        stop("TIMEOUT_ESTADO_INDETERMINADO")
    except OSError:
        stop("EXECUCAO_INDISPONIVEL")
    for line in (p.stdout + "\n" + p.stderr).splitlines():
        if "=" not in line: continue
        name, value = line.strip().split("=", 1)
        if (name in SAFE_MARKERS or name.startswith(SAFE_PREFIXES)) and re.fullmatch(
            r"[A-Za-z0-9_-]{1,110}", value
        ):
            print(name + "=" + value)
    return p.returncode

def template(change_id: str) -> bytes:
    obj = {
        "change_id": change_id,
        "snapshot_id": "ubuntu.33",
        "approver": "PREENCHER_OPERADORA",
        "snapshot_covers_all_ep125_disks": False,
        "snapshot_restore_confirmed_by_operator": False,
        "bind_mounts_verified_by_operator": False,
        "secrets_and_tls_recoverable": False,
        "operator_and_window_approved": False,
        "cross_vm_dependencies_checked": False,
        "socket_directories_clean": False,
        "cutover_approved": False,
        "rollback_approved": False,
    }
    return (json.dumps(obj, indent=2, ensure_ascii=False) + "\n").encode()

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--mode", required=True, choices=("prepare", "cutover", "rollback"))
    ap.add_argument("--change-id", required=True)
    ap.add_argument("--execute", action="store_true")
    ap.add_argument("--approval-file", default="")
    ap.add_argument("--ack", default="")
    args = ap.parse_args()
    name = host()
    os.umask(0o077)
    base = private_dir(args.change_id)
    context = base / CONTEXT_FILE
    if not HELPER.is_file() or not DRIVER.is_file() or not ROLLBACK.is_file():
        stop("HELPERS_AUSENTES")

    lockpath = base / "ga08-context.lock"
    if lockpath.is_symlink(): stop("LOCK_SYMLINK")
    fd = os.open(lockpath, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "r+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.mode == "prepare":
            if args.execute or args.ack or args.approval_file:
                stop("PREPARE_NAO_RECEBE_FLAGS_DE_CORTE")
            helper = runpy.run_path(str(HELPER))
            refs = references(helper)
            print("=== GA08.18G — CONTEXTO DE RETORNO ===")
            rc = run_control(DRIVER, [], refs, 120)
            if rc: stop("PREFLIGHT_RC_" + str(rc))
            obj = {
                "format": 1,
                "change_id": args.change_id,
                "host": name,
                "references": refs
            }
            raw = (json.dumps(obj, indent=2, sort_keys=True) + "\n").encode()
            secure_create(context, raw)
            sample = base / APPROVAL_EXAMPLE
            secure_create(sample, template(args.change_id))
            print("GA08_REFERENCIAS_PRIVADAS=18/18")
            print("GA08_CONTEXT_SHA256=" + hashlib.sha256(raw).hexdigest())
            print("GA08_CONTEXT=PASS")
            print("GA08_APROVACAO_TEMPLATE_CRIADO=SIM")
            print("GA08_SEGREDOS_CONTEUDO_COPIADO=NAO")
            print("GA08_SERVICOS_MODIFICADOS=NAO")
            return 0

        # Live mutations require all interlocks and local evidence separately.
        if not args.execute or not args.approval_file:
            stop("EXECUCAO_NAO_AUTORIZADA")
        if os.environ.get("GA08_ENABLE_LIVE_CHANGE") != "YES":
            stop("INTERLOCK_AUSENTE")
        expected = ("APLICAR_GA08_NA_EP125" if args.mode == "cutover"
                    else "RESTAURAR_BASELINE_EP125")
        if args.ack != expected: stop("CONFIRMACAO_DIVERGENTE")
        refs = read_context(context, args.change_id)
        if args.mode == "cutover":
            # Compare live baseline before any mutation; never rederive env during rollback.
            helper = runpy.run_path(str(HELPER))
            original_env = {k: os.environ.get(k) for k in GA08_ONLY}
            if any(original_env[k] != refs[k] for k in GA08_ONLY):
                stop("GA08_CAMINHOS_NAO_EXPORTADOS_OU_MUDARAM")
            current = references(helper)
            if current != refs: stop("RUNTIME_DRIFT")
        driver = DRIVER if args.mode == "cutover" else ROLLBACK
        cmd = [
            "--execute", "--change-id", args.change_id,
            "--approval-file", args.approval_file, "--ack", args.ack,
        ]
        print("GA08_ACAO=" + args.mode.upper())
        print("GA08_CONTEXT_CARREGADO=SIM")
        rc = run_control(driver, cmd, refs, 900)
        if rc:
            print("GA08_EXECUCAO=FALHOU_RC_" + str(rc))
            print("GA08_REEXECUTAR_SEM_DIAGNOSTICO=NAO")
            return rc
        print("GA08_EXECUCAO_SCRIPT=PASS")
        print("GA08_E2E_APLICACIONAL=AINDA_NAO_VALIDADO")
        return 0

if __name__ == "__main__":
    raise SystemExit(main())
