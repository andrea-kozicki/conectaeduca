#!/usr/bin/env python3
"""EP125 GA08: compare private reconstructed Compose service hashes to runtime.

No deploy, rollback, file writes, secret reads, or raw Docker/config output.
For Compose 5.7.0 only. A matching hash is evidence of service-model
equivalence, NOT proof of effective application operation or recoverability.

Requires previously vetted files in ~/Downloads:
  ga08-private-interpolation-preflight-ep125.py
  ga08-private-context-compare-ep125.py (checked by the first script)
"""

from __future__ import annotations

import hashlib
import os
import re
import runpy
import socket
import stat
import subprocess
from pathlib import Path
from typing import Any

PEER = "ga08-private-interpolation-preflight-ep125.py"
PEER_SHA256 = "b5f860cf617f47739325feed9561e3b6cc480904a281b105c43f2a8c72aa929e"
EXPECTED_VERSION = "5.7.0"
SERVICES = ("php", "nginx", "waf")
BASE_DIR = Path("/opt/conectaeduca/deploy/dmz")
PROJECT = "conectaeduca-dmz"
HASH = re.compile(r"[0-9a-f]{64}\Z")
ENVFILE_KEY = re.compile(rb"(?m)^\s*(?:env_file|include|extends)\s*:")


class GuardError(Exception):
    pass


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise GuardError(reason)


def verified_peer(home: Path) -> dict[str, Any]:
    """Validate exact trusted library bytes before invoking their top level."""
    peer = home / "Downloads" / PEER
    fd = -1
    try:
        require(peer.is_absolute() and peer.resolve(strict=True) == peer,
                "biblioteca_caminho_inseguro")
        fd = os.open(peer, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        meta = os.fstat(fd)
        require(stat.S_ISREG(meta.st_mode) and meta.st_nlink == 1 and
                meta.st_uid in (0, os.getuid()) and
                not (stat.S_IMODE(meta.st_mode) & 0o022) and
                0 < meta.st_size <= 100_000, "biblioteca_permissoes_invalidas")
        with os.fdopen(fd, "rb") as stream:
            fd = -1
            content = stream.read(100_001)
        require(hashlib.sha256(content).hexdigest() == PEER_SHA256,
                "biblioteca_hash_divergente")
    except (OSError, ValueError, RuntimeError):
        raise GuardError("biblioteca_indisponivel") from None
    finally:
        if fd >= 0:
            os.close(fd)
    try:
        return runpy.run_path(str(peer), run_name="ce_interpolation_library")
    except Exception:
        raise GuardError("biblioteca_indisponivel") from None


def compose_version() -> str:
    try:
        p = subprocess.run(["docker", "compose", "version", "--short"],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           timeout=15, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise GuardError("compose_versao_indisponivel") from None
    require(p.returncode == 0 and p.stdout.strip() == EXPECTED_VERSION.encode(),
            "compose_versao_inesperada")
    return EXPECTED_VERSION


def check_no_service_env_files(paths: tuple[Path, ...]) -> None:
    """Do not let Compose hash evaluation open unexpected service env_files."""
    require(len(paths) == 14, "compose_fontes_invalidas")
    for item in paths:
        fd = -1
        try:
            require(item.is_file() and not item.is_symlink(),
                    "compose_fonte_insegura")
            fd = os.open(item, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
            meta = os.fstat(fd)
            require(stat.S_ISREG(meta.st_mode) and 0 < meta.st_size < 1_000_000,
                    "compose_fonte_insegura")
            with os.fdopen(fd, "rb") as stream:
                fd = -1
                data = stream.read(1_000_001)
            require(len(data) < 1_000_000 and not ENVFILE_KEY.search(data),
                    "compose_envfile_ou_inclusao_nao_aprovada")
        except (OSError, ValueError):
            raise GuardError("compose_fonte_indisponivel") from None
        finally:
            if fd >= 0:
                os.close(fd)


def service_hash(paths: tuple[Path, ...], env_refs: dict[str, str],
                 service: str) -> str | None:
    require(service in SERVICES and len(paths) == 14,
            "servico_ou_compose_invalido")
    env = os.environ.copy()
    env.update(env_refs)
    env.pop("COMPOSE_ENV_FILES", None)
    env["COMPOSE_DISABLE_ENV_FILE"] = "1"
    command = ["docker", "compose", "--project-directory", str(BASE_DIR),
               "-p", PROJECT]
    for source in paths:
        command.extend(["-f", str(source)])
    command.extend(["config", "--hash", service])
    try:
        proc = subprocess.run(command, cwd=BASE_DIR, env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              timeout=40, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    # Public evidence never includes this line: it may change in later CLI
    # versions and must match exactly one allowlisted hash in memory.
    try:
        raw = proc.stdout.decode("ascii").strip()
    except UnicodeError:
        return None
    match = re.fullmatch(r"(?:" + service + r"[\s:]+)?([0-9a-f]{64})", raw)
    return match.group(1) if match else None


def report(home: Path, peer: dict[str, Any]) -> list[dict[str, str]]:
    lib = peer["load_verified_library"](home)
    snapshots = lib["inspect_runtime"]()
    files = peer["approved_compose_paths"](snapshots, lib, home)
    check_no_service_env_files(files)
    active = lib["runtime_references"](snapshots)
    records = lib["records"](lib["private_root"](home))
    require(len(records) == 2 and
            {entry.name[5:13] for entry in records} == {"20261103", "20261104"},
            "contextos_inesperados")
    expected_hashes = {}
    for service in SERVICES:
        label = (snapshots[service].get("Config") or {}).get("Labels") or {}
        digest = label.get("com.docker.compose.config-hash")
        require(isinstance(digest, str) and HASH.fullmatch(digest),
                "label_hash_indisponivel")
        expected_hashes[service] = digest

    results = []
    for record in records:
        context = lib["read_private_json"](record / "runtime-refs.json")
        refs = lib["context_references"](context, record.name)
        manifest = lib["read_private_json"](record / "manifest.json")
        require(lib["manifest_class"](manifest, record.name) == "LEGADO_9_10",
                "manifesto_inesperado")
        require(lib["compare_references"](refs, active) == (15, 2, 0),
                "referencias_divergentes")
        effective = dict(refs)
        for key in peer["CONFIG_KEYS"]:
            current = active.get(key)
            require(isinstance(current, str) and
                    peer["secure_digest"](Path(refs[key]), limit=65_536,
                                          suffix=".conf") ==
                    peer["secure_digest"](Path(current), limit=65_536,
                                          suffix=".conf"),
                    "config_conteudo_divergente")
            effective[key] = current
        comparison = {}
        for service in SERVICES:
            calculated = service_hash(files, effective, service)
            comparison[service] = (
                "NAO_COMPROVADO" if calculated is None else
                "IGUAL" if calculated == expected_hashes[service] else
                "DIFERENTE"
            )
        results.append(comparison)
    return results


def main() -> int:
    print("=== CE-GA08 | PARIDADE HASH 14 VS RUNTIME | EP125 ===")
    try:
        require(socket.gethostname().split(".")[0] in
                ("ep125-pucpr", "ep125-pucpr-br") and
                os.geteuid() != 0, "host_ou_usuario_invalido")
        version = compose_version()
        results = report(Path.home(), verified_peer(Path.home()))
        print("COMPOSE_VERSAO=" + version)
        for index, result in enumerate(results, start=1):
            print("=== REGISTRO_" + f"{index:02d}" + " ===")
            for service in SERVICES:
                print(service.upper() + "_HASH=" + result[service])
        all_ok = all(value == "IGUAL" for result in results
                     for value in result.values())
        print("DIAGNOSTICO=" + ("PASS_HASH_RUNTIME" if all_ok else
                              "ANALISAR_DIVERGENCIAS_SEM_MUTACAO"))
        return 0 if all_ok else 3
    except GuardError as error:
        print("DIAGNOSTICO=FAIL_CLOSED")
        print("MOTIVO=" + str(error))
        return 3
    except Exception:
        print("DIAGNOSTICO=FAIL_CLOSED")
        print("MOTIVO=erro_inesperado")
        return 3
    finally:
        print("HASHES_E_VALORES_EXIBIDOS=NAO")
        print("SERVICOS_MODIFICADOS=NAO")
        print("ROLLBACK_HABILITADO=NAO")
        print("=== FIM ===")


if __name__ == "__main__":
    raise SystemExit(main())
