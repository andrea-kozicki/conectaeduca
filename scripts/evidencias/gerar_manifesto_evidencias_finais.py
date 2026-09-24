#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import re
from pathlib import Path

REQUIRED_DIRS = [
    "01-arquitetura-segmentacao",
    "02-aplicacao-waf-rbac",
    "03-dados-segredos-containers",
    "04-wazuh-fim",
    "05-dlp-privacidade",
    "06-bacula",
    "07-zero-sudo",
    "08-pentest-s01-s13",
    "09-twingate-comparativo",
]

EXCLUDED = {"SHA256SUMS", "MANIFESTO-EVIDENCIAS.txt"}

BLOCKED_PATHS = [
    re.compile(r"(^|/)\.env($|[.])", re.I),
    re.compile(r"secret[-_]?id", re.I),
    re.compile(r"role[-_]?id", re.I),
    re.compile(r"root[-_]?token", re.I),
    re.compile(r"unseal[-_]?share", re.I),
    re.compile(r"recovery[-_]?share", re.I),
    re.compile(r"private[-_]?key", re.I),
    re.compile(r"[.]key$", re.I),
    re.compile(r"[.]p12$", re.I),
    re.compile(r"[.]pfx$", re.I),
    re.compile(r"[.]kdbx$", re.I),
]


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Gera manifesto e SHA256SUMS das evidencias finais.")
    p.add_argument("root", nargs="?", default=str(Path.home() / "evidencias-finais"))
    return p.parse_args()


def main() -> int:
    root = Path(args().root).expanduser().resolve()
    if not root.is_dir():
        print(f"[FAIL] diretorio inexistente: {root}")
        return 2

    warns = 0
    fails = 0
    print("=== CONECTAEDUCA MANIFESTO EVIDENCIAS ===")
    print(f"root={root}")
    print("input_mutation=NO")

    for name in REQUIRED_DIRS:
        if (root / name).is_dir():
            print(f"[PASS] dir={name}")
        else:
            warns += 1
            print(f"[WARN] dir ausente={name}")

    files: list[Path] = []
    for path in sorted(root.rglob("*")):
        if path.name in EXCLUDED:
            continue
        if path.is_symlink():
            fails += 1
            print(f"[FAIL] symlink nao permitido: {path.relative_to(root)}")
        elif path.is_file():
            files.append(path)

    for path in files:
        rel = path.relative_to(root).as_posix()
        if any(rx.search(rel) for rx in BLOCKED_PATHS):
            fails += 1
            print(f"[FAIL] path sensivel: {rel}")

    rows: list[tuple[str, int, str]] = []
    total = 0
    for path in files:
        rel = path.relative_to(root).as_posix()
        size = path.stat().st_size
        total += size
        rows.append((digest(path), size, rel))

    if fails:
        print(f"FILES={len(rows)}")
        print(f"BYTES={total}")
        print(f"WARN={warns}")
        print(f"FAIL={fails}")
        print("MANIFEST_READY=NO")
        return 2

    sha = root / "SHA256SUMS"
    man = root / "MANIFESTO-EVIDENCIAS.txt"

    sha.write_text("".join(f"{h}  {rel}\n" for h, _, rel in rows), encoding="utf-8")
    lines = [
        "=== CONECTAEDUCA MANIFESTO DE EVIDENCIAS ===",
        f"generated_utc={dt.datetime.now(dt.timezone.utc).isoformat()}",
        f"files={len(rows)}",
        f"bytes={total}",
        f"warnings={warns}",
        "path_sanitization_gate=PASS",
        "",
        "sha256|bytes|path",
    ]
    lines.extend(f"{h}|{size}|{rel}" for h, size, rel in rows)
    lines.append("")
    man.write_text("\n".join(lines), encoding="utf-8")

    print(f"FILES={len(rows)}")
    print(f"BYTES={total}")
    print(f"WARN={warns}")
    print("FAIL=0")
    print("MANIFEST_READY=YES")
    print(f"SHA256SUMS={sha}")
    print(f"MANIFEST={man}")
    print("NOTE=revisao_humana_de_sanitizacao_continua_obrigatoria")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
