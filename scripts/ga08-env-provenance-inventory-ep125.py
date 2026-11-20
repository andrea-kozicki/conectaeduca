#!/usr/bin/env python3
"""Read-only, metadata-only discovery of possible EP125 DMZ launch scripts.

Never opens candidate files, .env files, container configuration or shell
history; never emits full paths or environment values. Not a recovery driver.
"""

from __future__ import annotations

import hashlib
import os
import re
import socket
import stat
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


REPO = Path("/opt/conectaeduca")
MAX_ENTRIES_PER_ROOT = 2500
MAX_DISPLAY = 35
RELEVANT = re.compile(
    r"ga08|pa05|dmz|deploy|compose|rollback|bootstrap|cutover|"
    r"conectaeduca|recovery|restore|env|stack", re.I,
)
SENSITIVE_NAME = re.compile(
    r"password|passwd|senha|token|secret|private|credential|api[_-]?key", re.I,
)


@dataclass(frozen=True)
class Candidate:
    root: str
    name: str
    kind: str
    modified_day: str
    opaque_id: str
    mtime: float


class InventoryError(Exception):
    pass


def roots(repo: Path, home: Path) -> tuple[tuple[str, Path, int], ...]:
    """Narrow, named roots; intentionally exclude $HOME and / as scan roots."""
    return (
        ("REPO_SCRIPTS", repo / "scripts", 2),
        ("DMZ_DEPLOY", repo / "deploy/dmz", 3),
        ("DOWNLOADS", home / "Downloads", 2),
        ("HOME_CE_CONFIG", home / ".config/conectaeduca", 3),
        ("HOME_BIN", home / "bin", 1),
        ("HOME_LOCAL_BIN", home / ".local/bin", 1),
        ("SYSTEMD_USER", home / ".config/systemd/user", 2),
        ("SYSTEMD_ETC", Path("/etc/systemd/system"), 2),
    )


def is_potential_env_name(name: str) -> bool:
    lower = name.lower()
    return lower == ".env" or lower.startswith(".env.") or lower.endswith(".env")


def candidate_kind(name: str, mode: int) -> str | None:
    lower = name.lower()
    if not RELEVANT.search(lower):
        return None
    if lower.endswith(".service"):
        return "SERVICE"
    if lower.endswith(".sh") or lower.endswith(".bash"):
        return "SHELL"
    if lower.endswith(".py"):
        return "PYTHON"
    if stat.S_IMODE(mode) & 0o111 and "." not in lower:
        return "EXEC"
    return None


def public_name(name: str) -> str:
    if SENSITIVE_NAME.search(name):
        return "REDACTED"
    sanitized = re.sub(r"[^A-Za-z0-9_.-]", "_", name)
    return sanitized[:85] + ("_TRUNCATED" if len(sanitized) > 85 else "")


def scan(root_tag: str, root: Path, depth_limit: int) -> tuple[list[Candidate], int, str]:
    """Inspect directory entries and stat metadata, never opening file data."""
    if root.is_symlink():
        return [], 0, "RAIZ_SYMLINK_IGNORADA"
    if not root.is_dir():
        return [], 0, "NAO_EXISTE"
    pending = [(root, 0)]
    seen = 0
    env_count = 0
    candidates: list[Candidate] = []
    while pending:
        folder, depth = pending.pop()
        try:
            with os.scandir(folder) as entries:
                for entry in entries:
                    seen += 1
                    if seen > MAX_ENTRIES_PER_ROOT:
                        raise InventoryError("limite_entradas_" + root_tag)
                    try:
                        if entry.is_symlink():
                            continue
                        if entry.is_dir(follow_symlinks=False):
                            if depth < depth_limit:
                                pending.append((Path(entry.path), depth + 1))
                            continue
                        if not entry.is_file(follow_symlinks=False):
                            continue
                        meta = entry.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    if is_potential_env_name(entry.name):
                        env_count += 1
                        continue  # .env names are never included in output
                    kind = candidate_kind(entry.name, meta.st_mode)
                    if not kind:
                        continue
                    path_id = hashlib.sha256(os.fsencode(entry.path)).hexdigest()[:12]
                    try:
                        day = datetime.fromtimestamp(meta.st_mtime).strftime("%Y-%m-%d")
                    except (OverflowError, OSError, ValueError):
                        day = "INDEFINIDA"
                    candidates.append(Candidate(
                        root_tag,
                        public_name(entry.name),
                        kind,
                        day,
                        path_id,
                        meta.st_mtime,
                    ))
        except PermissionError:
            return candidates, env_count, "ACESSO_PARCIAL"
        except OSError:
            return candidates, env_count, "LEITURA_DIRETORIO_FALHOU"
    return candidates, env_count, "COMPLETO"


def inventory(repo: Path, home: Path) -> tuple[list[Candidate], list[str], int]:
    found: list[Candidate] = []
    stats: list[str] = []
    env_total = 0
    for tag, root, depth in roots(repo, home):
        matches, env_count, status = scan(tag, root, depth)
        found.extend(matches)
        env_total += env_count
        stats.append(f"RAIZ_{tag}={status}|CANDIDATOS={len(matches)}")
    found.sort(key=lambda item: (-item.mtime, item.root, item.name))
    return found, stats, env_total


def main() -> int:
    if socket.gethostname().split(".")[0] not in ("ep125-pucpr", "ep125-pucpr-br"):
        print("INVENTARIO=FAIL_CLOSED|MOTIVO=host_nao_ep125")
        return 3
    if os.geteuid() == 0 or not REPO.is_dir():
        print("INVENTARIO=FAIL_CLOSED|MOTIVO=contexto_nao_aprovado")
        return 3
    try:
        candidates, status, env_count = inventory(REPO, Path.home())
    except InventoryError:
        print("INVENTARIO=FAIL_CLOSED|MOTIVO=limite_de_busca")
        print("SERVICOS_MODIFICADOS=NAO")
        return 3
    except (OSError, ValueError):
        print("INVENTARIO=FAIL_CLOSED|MOTIVO=erro_metadados")
        print("SERVICOS_MODIFICADOS=NAO")
        return 3
    print("=== CE-GA08 | PROVENIENCIA DE INICIALIZACAO | EP125 ===")
    for row in status:
        print(row)
    print("CANDIDATOS_TOTAL=" + str(len(candidates)))
    print("ARQUIVOS_ENV_POTENCIAIS=" + str(env_count))
    for index, item in enumerate(candidates[:MAX_DISPLAY], start=1):
        print(
            f"CANDIDATO_{index:02d}|ORIGEM={item.root}|TIPO={item.kind}"
            f"|NOME={item.name}|DATA={item.modified_day}|ID={item.opaque_id}"
        )
    print("CANDIDATOS_NAO_LISTADOS=" + str(max(0, len(candidates) - MAX_DISPLAY)))
    complete = not any("=ACESSO_PARCIAL" in row or
                       "=LEITURA_DIRETORIO_FALHOU" in row for row in status)
    print("INVENTARIO=" + ("PASS_METADATA" if complete else "PARCIAL"))
    print("CONTEUDOS_DE_ARQUIVOS_LIDOS=NAO")
    print("SHELL_HISTORY_LIDO=NAO")
    print("SEGREDOS_EXIBIDOS=NAO")
    print("SERVICOS_MODIFICADOS=NAO")
    print("=== FIM ===")
    return 0 if complete else 3


if __name__ == "__main__":
    raise SystemExit(main())
