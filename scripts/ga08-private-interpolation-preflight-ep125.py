#!/usr/bin/env python3
"""EP125 GA08/PA05: interpolate Compose 11/14 using protected references.

Read-only, opt-in diagnostic. Does not render Compose config, environment,
JSON data, paths, digests, or subprocess diagnostics in public output.
Service env-file resolution is deliberately disabled, so PASS is only an
interpolation syntax gate; it is NOT effective-config parity or rollback.

Requires an exact, reviewed copy of ga08-private-context-compare-ep125.py in
~/Downloads. No files, containers, or private records are changed.
"""

from __future__ import annotations

import hashlib
import os
import runpy
import socket
import stat
import subprocess
from pathlib import Path
from typing import Any

REPO = Path("/opt/conectaeduca")
DMZ = REPO / "deploy/dmz"
LIB_NAME = "ga08-private-context-compare-ep125.py"
LIB_SHA256 = "965f964b4dd4a4dc8e3d4236fdee21788b4f6f6c1e7d152bc2b44b632a880294"
PROJECT = "conectaeduca-dmz"
CONFIG_KEYS = (
    "CONECTAEDUCA_GA08_FPM_CONF",
    "CONECTAEDUCA_GA08_NGINX_HTTP_UNIX_CONF",
)
GA08_SHA256 = {
    "compose.ga08-socket.candidate.yml":
        "5e6ce7dbab62b104a1448a84e23690c86d07ceccbbf36bfad9b8b91fb344dadc",
    "compose.ga08-dual-socket.candidate.yml":
        "fbf5c3aac42e02c40d09cf2fc0e19ccf634570a0d2049b2fbbceb4e49d191d51",
    "compose.ga08-runtimefix.candidate.yml":
        "9fb109e9b2da4b397c43c541d7120a68b682cc745eb6b3298061d5927e3aeb84",
}


class PreflightError(Exception):
    pass


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise PreflightError(reason)


def secure_digest(path: Path, *, limit: int, suffix: str | None) -> str:
    """Refuse symlinks and writable, unbounded or multi-linked source files."""
    fd = -1
    try:
        require(path.is_absolute() and path.resolve(strict=True) == path,
                "fonte_caminho_inseguro")
        if suffix is not None:
            require(path.suffix == suffix, "fonte_extensao_invalida")
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        info = os.fstat(fd)
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
                "fonte_nao_regular")
        require(info.st_uid in (0, os.getuid()) and
                not (stat.S_IMODE(info.st_mode) & 0o022),
                "fonte_permissao_insegura")
        require(0 < info.st_size <= limit, "fonte_tamanho_invalido")
        with os.fdopen(fd, "rb") as stream:
            fd = -1
            data = stream.read(limit + 1)
        require(len(data) <= limit, "fonte_tamanho_invalido")
        return hashlib.sha256(data).hexdigest()
    except (OSError, RuntimeError, ValueError):
        raise PreflightError("fonte_indisponivel") from None
    finally:
        if fd >= 0:
            os.close(fd)


def load_verified_library(home: Path) -> dict[str, Any]:
    path = home / "Downloads" / LIB_NAME
    require(secure_digest(path, limit=100_000, suffix=".py") == LIB_SHA256,
            "comparador_hash_divergente")
    try:
        return runpy.run_path(str(path), run_name="ce_private_compare_library")
    except Exception:
        raise PreflightError("comparador_indisponivel") from None


def approved_compose_paths(snapshot: dict[str, Any], lib: dict[str, Any],
                           home: Path) -> tuple[Path, ...]:
    files = ((snapshot["php"].get("Config") or {}).get("Labels") or {}).get(
        "com.docker.compose.project.config_files", "")
    require(isinstance(files, str), "compose_label_invalido")
    for service in ("nginx", "waf"):
        other = ((snapshot[service].get("Config") or {}).get("Labels") or {}).get(
            "com.docker.compose.project.config_files")
        require(other == files, "compose_labels_divergentes")
    paths = tuple(Path(item) for item in files.split(","))
    require(len(paths) == 14 and all(path.is_absolute() for path in paths),
            "compose_fontes_invalidas")
    require(tuple(path.name for path in paths) == lib["COMPOSE_ORDER"],
            "compose_ordem_divergente")
    expected_base = tuple(DMZ / name for name in lib["COMPOSE_ORDER"][:10])
    expected_pa05 = home / ".config/conectaeduca/pa05/compose.pa05-10328ab6.yml"
    require(paths[:11] == expected_base + (expected_pa05,),
            "compose_base_divergente")
    for index, path in enumerate(paths):
        require(path.is_file() and not path.is_symlink() and
                path.resolve(strict=True) == path, "compose_fonte_insegura")
        if index >= 11:
            require(path.is_relative_to(home) or path.parent == DMZ,
                    "compose_ga08_origem_invalida")
            require(secure_digest(path, limit=1_000_000, suffix=".yml") ==
                    GA08_SHA256[path.name], "compose_ga08_hash_divergente")
    return paths


def compose_interpolation(paths: tuple[Path, ...], refs: dict[str, str],
                          count: int) -> bool:
    """A config-only call, without printing captured output or env values."""
    require(count in (11, 14) and len(paths) == 14,
            "compose_quantidade_invalida")
    environment = os.environ.copy()
    environment.update(refs)
    environment.pop("COMPOSE_ENV_FILES", None)
    environment["COMPOSE_DISABLE_ENV_FILE"] = "1"
    cmd = ["docker", "compose", "--project-directory", str(DMZ), "-p", PROJECT]
    for path in paths[:count]:
        cmd.extend(["-f", str(path)])
    cmd.extend(["config", "--no-env-resolution", "--quiet"])
    try:
        result = subprocess.run(cmd, cwd=DMZ, env=environment,
                                stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=40,
                                check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise PreflightError("compose_indisponivel") from None
    return result.returncode == 0


def analyze(home: Path, lib: dict[str, Any]) -> list[tuple[bool, bool]]:
    snapshots = lib["inspect_runtime"]()
    sources = approved_compose_paths(snapshots, lib, home)
    live = lib["runtime_references"](snapshots)
    records = lib["records"](lib["private_root"](home))
    require(len(records) == 2 and
            {entry.name[5:13] for entry in records} == {"20261103", "20261104"},
            "contextos_esperados_ausentes")
    results = []
    for directory in records:
        ctx = lib["read_private_json"](directory / "runtime-refs.json")
        refs = lib["context_references"](ctx, directory.name)
        manifest = lib["read_private_json"](directory / "manifest.json")
        require(lib["manifest_class"](manifest, directory.name) == "LEGADO_9_10",
                "manifesto_inesperado")
        match, mismatch, unknown = lib["compare_references"](refs, live)
        require((match, mismatch, unknown) == (15, 2, 0),
                "referencias_runtime_divergentes")
        effective = dict(refs)
        for key in CONFIG_KEYS:
            current = live.get(key)
            require(isinstance(current, str) and
                    secure_digest(Path(refs[key]), limit=65_536, suffix=".conf") ==
                    secure_digest(Path(current), limit=65_536, suffix=".conf"),
                    "config_conteudo_divergente")
            effective[key] = current
        # The early Nginx reference is intentionally shadowed by later overlay;
        # do not infer that the old mount is present in the running container.
        results.append((compose_interpolation(sources, effective, 11),
                        compose_interpolation(sources, effective, 14)))
    return results


def main() -> int:
    print("=== CE-GA08 | INTERPOLACAO PRIVADA 11/14 | EP125 ===")
    try:
        require(socket.gethostname().split(".")[0] in
                ("ep125-pucpr", "ep125-pucpr-br"), "host_nao_ep125")
        require(os.geteuid() != 0 and REPO.is_dir(), "host_ou_usuario_invalido")
        results = analyze(Path.home(), load_verified_library(Path.home()))
        for index, (baseline, active) in enumerate(results, start=1):
            print("=== REGISTRO_" + f"{index:02d}" + " ===")
            print("COMPOSE11_INTERPOLACAO=" + ("PASS" if baseline else "FALHOU"))
            print("COMPOSE14_INTERPOLACAO=" + ("PASS" if active else "FALHOU"))
        print("DIAGNOSTICO=" + (
            "PASS_INTERPOLACAO_LIMITADA" if all(all(item) for item in results)
            else "FALHA_INTERPOLACAO_LIMITADA"))
        return 0 if all(all(item) for item in results) else 3
    except (PreflightError, KeyError, TypeError, ValueError) as error:
        print("DIAGNOSTICO=FAIL_CLOSED")
        print("MOTIVO=" + str(error) if isinstance(error, PreflightError)
              else "MOTIVO=estrutura_inesperada")
        return 3
    except Exception:
        print("DIAGNOSTICO=FAIL_CLOSED")
        print("MOTIVO=erro_inesperado")
        return 3
    finally:
        print("CONFIG_EFETIVA_COMPLETA=NAO_COMPROVADA")
        print("CAMINHOS_VALORES_HASHES_EXIBIDOS=NAO")
        print("SERVICOS_MODIFICADOS=NAO")
        print("ROLLBACK_HABILITADO=NAO")
        print("=== FIM ===")


if __name__ == "__main__":
    raise SystemExit(main())
