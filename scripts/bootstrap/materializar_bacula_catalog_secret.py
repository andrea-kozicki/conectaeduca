#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import secrets
import stat
import tempfile
from pathlib import Path


def fail(msg: str) -> None:
    raise SystemExit(f"ERRO       {msg}")


def canonical_runtime_dir() -> Path:
    return Path(__file__).resolve().parents[2] / "deploy/interna/bacula/.runtime"


def validate_runtime_dir(runtime: Path) -> Path:
    expected = canonical_runtime_dir()

    if runtime != expected:
        fail("runtime-dir fora do caminho canônico recusado")

    if runtime.is_symlink():
        fail("runtime-dir canônico não pode ser symlink")

    return runtime


def atomic_write(path: Path, content: str, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(content)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp_name, path)
        path.chmod(mode)
    finally:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass


def read_env(path: Path) -> tuple[list[str], dict[str, str]]:
    if not path.is_file():
        return [], {}

    lines = path.read_text(encoding="utf-8").splitlines()
    values: dict[str, str] = {}

    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            fail(f"linha inválida em {path.name}")
        key, value = line.split("=", 1)
        if key in values:
            fail(f"variável duplicada em {path.name}: {key}")
        values[key] = value

    return lines, values


def validate_secret_file(path: Path) -> str:
    if not path.is_file():
        fail(f"arquivo de segredo ausente: {path}")

    mode = stat.S_IMODE(path.stat().st_mode)
    if mode != 0o600:
        fail(f"segredo com modo inesperado: {oct(mode)}")

    value = path.read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"[A-Fa-f0-9]{64}", value):
        fail("segredo do Catalog não possui formato token_hex(32)")
    return value


def materialize(runtime: Path) -> None:
    runtime = validate_runtime_dir(runtime)
    runtime.mkdir(parents=True, exist_ok=True)
    runtime.chmod(0o700)

    env_path = runtime / "catalog.env"
    secret_path = runtime / "catalog-postgres-password"

    lines, values = read_env(env_path)

    db = values.get("POSTGRES_DB", "bacula")
    user = values.get("POSTGRES_USER", "bacula")
    old_password = values.get("POSTGRES_PASSWORD", "")

    if not re.fullmatch(r"[A-Za-z0-9_.:-]+", db):
        fail("POSTGRES_DB inválido")
    if not re.fullmatch(r"[A-Za-z0-9_.:-]+", user):
        fail("POSTGRES_USER inválido")

    if secret_path.exists():
        secret_value = validate_secret_file(secret_path)
        if old_password and old_password != secret_value:
            fail("catalog.env e arquivo de segredo divergem; recusando migração")
    elif old_password:
        if not re.fullmatch(r"[A-Fa-f0-9]{64}", old_password):
            fail("POSTGRES_PASSWORD legado possui formato inesperado")
        atomic_write(secret_path, old_password + "\n", 0o600)
    else:
        atomic_write(secret_path, secrets.token_hex(32) + "\n", 0o600)

    kept: list[str] = []
    seen_db = False
    seen_user = False

    for raw in lines:
        stripped = raw.strip()
        if stripped.startswith("POSTGRES_PASSWORD="):
            continue
        if stripped.startswith("POSTGRES_DB="):
            kept.append(f"POSTGRES_DB={db}")
            seen_db = True
            continue
        if stripped.startswith("POSTGRES_USER="):
            kept.append(f"POSTGRES_USER={user}")
            seen_user = True
            continue
        kept.append(raw)

    if not seen_db:
        kept.append(f"POSTGRES_DB={db}")
    if not seen_user:
        kept.append(f"POSTGRES_USER={user}")

    atomic_write(env_path, "\n".join(kept).strip() + "\n", 0o600)

    _, final_values = read_env(env_path)
    if "POSTGRES_PASSWORD" in final_values:
        fail("POSTGRES_PASSWORD permaneceu em catalog.env")

    validate_secret_file(secret_path)

    print("PASS       segredo administrativo do Catalog materializado fora do env")
    print("PASS       catalog.env não contém POSTGRES_PASSWORD")
    print("PASS       catalog.env e segredo protegidos em 0600")
    print("PASS       nenhum valor de segredo foi exibido")


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Materializa o segredo do Bacula Catalog no runtime canônico."
    )
    ap.parse_args()
    materialize(canonical_runtime_dir())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
