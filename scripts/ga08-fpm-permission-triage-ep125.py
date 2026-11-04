#!/usr/bin/env python3
"""GA08.21: safe FPM permission triage, with production left untouched.

Default is PLAN ONLY. --run starts one disposable, network-isolated container
from the currently running PHP image, then destroys it. Does not copy or
mount secrets, persistent sockets, host /run, or the production Compose stack.
Only prints fixed vocabulary outcomes, never raw logs.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import secrets
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
CANARY = ROOT / "scripts/ga08-canario-fpm-offline-ep125.py"
PINNED_CANARY_BLOB = "b85dc4f17ce42534eac2f2d7f617600a605ea151"
PINNED_FPM_CONFIG_BLOB = "a1f3f8212f754f005473d8ad2d5d49bfcc5514a1"
CONFIG = ROOT / "deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf"

def git_blob(path: Path) -> str:
    b = path.read_bytes()
    return hashlib.sha1(b"blob " + str(len(b)).encode() + b"\0" + b).hexdigest()

def load_canary():
    if not CANARY.is_file() or CANARY.is_symlink():
        raise RuntimeError("CANARIO_BASE_AUSENTE")
    if git_blob(CANARY) != PINNED_CANARY_BLOB:
        raise RuntimeError("CANARIO_BASE_DIVERGENTE")
    if not CONFIG.is_file() or CONFIG.is_symlink():
        raise RuntimeError("FPM_CONFIG_AUSENTE")
    if git_blob(CONFIG) != PINNED_FPM_CONFIG_BLOB:
        raise RuntimeError("FPM_CONFIG_DIVERGENTE")
    spec = importlib.util.spec_from_file_location("ga08_canary_baseline", CANARY)
    if not spec or not spec.loader:
        raise RuntimeError("IMPORT_CODIGO")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

SHELL = r"""
if test "$(id -u)" = 82 && test "$(id -g)" = 82; then
  echo CE_DIAG_UID=82; else echo CE_DIAG_UID=OUTRO; fi
if test -r /usr/local/etc/php-fpm.d/zz-conectaeduca.conf; then
  echo CE_DIAG_CONF_READ=SIM; else echo CE_DIAG_CONF_READ=NAO; fi
if test -d /run/conectaeduca-fpm; then
  echo CE_DIAG_SOCKET_DIR_EXISTE=SIM; else echo CE_DIAG_SOCKET_DIR_EXISTE=NAO; fi
if test -w /run/conectaeduca-fpm; then
  echo CE_DIAG_SOCKET_DIR_RW=SIM; else echo CE_DIAG_SOCKET_DIR_RW=NAO; fi
exec php-fpm -F
"""

def diag_args(mod, name: str, image_id: str) -> list[str]:
    args = mod.canary_args(name, image_id)
    pos = args.index("--entrypoint")
    args[pos + 1] = "/bin/sh"
    if args[-2:] != [image_id, "-F"]:
        raise RuntimeError("CANARIO_ARGUMENTOS_DIVERGENTES")
    return args[:-1] + ["-c", SHELL]

def error_detail(log: str) -> tuple[str, str]:
    # Derive only fixed vocabulary from ephemeral process output.
    # The original log data must never leave this function.
    lower = log.lower()
    # Match the permission error line itself rather than scanning any unrelated
    # reference to a socket or config path elsewhere in the output.
    denied_lines = [
        line for line in lower.splitlines()
        if re.search(r"permission denied|operation not permitted|access denied", line)
    ]
    if not denied_lines:
        if re.search(r"no such file or directory", lower):
            return ("ARQUIVO_AUSENTE", "NAO_APLICAVEL")
        if re.search(r"address already in use|unable to bind", lower):
            return ("BIND_SOCKET", "NAO_APLICAVEL")
        return ("NAO_IDENTIFICADO", "NAO_APLICAVEL")
    targets = (
        ("/run/conectaeduca-fpm/php-fpm.sock", "SOCKET_UNIX"),
        ("/run/conectaeduca-fpm", "DIRETORIO_SOCKET"),
        ("/usr/local/var/run", "PID_FPM"),
        ("php-fpm.pid", "PID_FPM"),
        ("/proc/self/fd/2", "ERROR_LOG_STDERR"),
        ("error_log", "ERROR_LOG"),
        ("/usr/local/etc/php-fpm.d/", "CONFIG_FPM"),
        ("/var/www/conectaeduca/storage/", "STORAGE_APP"),
    )
    for line in denied_lines:
        for needle, label in targets:
            if needle in line:
                return ("PERMISSAO", label)
    return ("PERMISSAO", "ALVO_NAO_CLASSIFICADO")

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run", action="store_true")
    args = ap.parse_args()
    print("=== GA08.21 — TRIAGEM FPM PERMISSOES ISOLADA ===")
    if not args.run:
        print("MODO=PLANEJAMENTO")
        print("DOCKER_EXECUTADO=NAO")
        print("CUTOVER_EXECUTADO=NAO")
        return 0
    name = "ga08-fpm-triage-" + secrets.token_hex(6)
    created = False
    rc = 3
    mod = None
    try:
        mod = load_canary()
        image_id = mod.assert_preconditions()
        p = mod.docker(diag_args(mod, name, image_id), timeout=60)
        if p.returncode:
            raise RuntimeError("DOCKER_RUN_FALHOU")
        created = True
        state = {}
        for _ in range(12):
            time.sleep(2)
            d = mod.inspect(name)
            state = d.get("State") or {}
            if not state.get("Running"):
                break
            if (state.get("Health") or {}).get("Status") in ("healthy", "unhealthy"):
                break
        p = mod.docker(["logs", "--tail", "100", name], timeout=12)
        # Trusted echo markers; do not print any other log line.
        out = p.stdout + "\n" + p.stderr
        for marker in ("UID", "CONF_READ", "SOCKET_DIR_EXISTE", "SOCKET_DIR_RW"):
            m = re.search(r"^CE_DIAG_" + marker +
                          r"=(82|OUTRO|SIM|NAO)\s*$", out, re.M)
            print("GA08_" + marker + "=" + (m.group(1) if m else "INDETERMINADO"))
        category, target = error_detail(out)
        print("FPM_ERRO_CLASSE=" + category)
        print("FPM_ERRO_ALVO=" + target)
        print("FPM_RUNNING=" + ("SIM" if state.get("Running") else "NAO"))
        print("FPM_EXIT_CODE=" + str(state.get("ExitCode", "INDETERMINADO")))
        print("FPM_HEALTH=" + str((state.get("Health") or {}).get(
            "Status", "INDETERMINADO")).upper())
        rc = 0 if state.get("Running") and (
            state.get("Health") or {}).get("Status") == "healthy" else 1
        print("GA08_21=" + ("PASS" if rc == 0 else "FALHA_DIAGNOSTICADA"))
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as e:
        label = str(e)
        if not re.fullmatch(r"[A-Z0-9_]{1,80}", label):
            label = "INDETERMINADO"
        print("GA08_21=BLOCKED_" + label)
    finally:
        if mod is not None:
            p = mod.docker(["rm", "--force", name], timeout=30)
            print("CANARIO_REMOVIDO=" + ("SIM" if p.returncode == 0
                                       else "NAO_OU_INEXISTENTE"))
        print("SERVICOS_PRODUCAO_MODIFICADOS=NAO_POR_ESTE_SCRIPT")
        print("DOCKER_COMPOSE_EXECUTADO=NAO")
        print("CUTOVER_EXECUTADO=NAO")
        print("HOST_BIND_PERSISTENTE_TESTADO=NAO")
        print("LOGS_BRUTOS_EXIBIDOS=NAO")
    return rc

if __name__ == "__main__":
    sys.exit(main())
