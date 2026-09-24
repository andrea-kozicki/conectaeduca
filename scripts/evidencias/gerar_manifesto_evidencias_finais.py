#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import os
import re
import sys
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

EXCLUDED_OUTPUTS = {"SHA256SUMS", "MANIFESTO-EVIDENCIAS.txt"}

BLOCKED_NAME_PATTERNS = [
    re.compile(r"(^|/)\.env($|[.])", re.IGNORECASE),
    re.compile(r"secret[-_]?id", re.IGNORECASE),
    re.compile(r"role[-_]?id", re.IGNORECASE),
    re.compile(r"root[-_]?token", re.IGNORECASE),
    re.compile(r"unseal[-_]?share", re.IGNORECASE),
    re.compile(r"recovery[-_]?share", re.IGNORECASE),
    re.compile(r"private[-_]?key", re.IGNORECASE),
]

PRIVATE_KEY_MARKERS = [
    bytes.fromhex("2d2d2d2d2d424547494e2050524956415445204b45592d2d2d2d2d"),
    bytes.fromhex("2d2d2d2d2d424547494e205253412050524956415445204b45592d2d2d2d2d"),
    bytes.fromhex("2d2d2d2d2d424547494e2045432050524956415445204b45592d2d2d2d2d"),
    bytes.fromhex("2d2d2d2d2d424547494e204f50454e5353482050524956415445204b45592d2d2d2d2d"),
]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Gera manifesto e SHA256SUMS de evidencias finais sanitizadas."
    )
    p.add_argument(
        "root",
        nargs="?",
        default=str(Path.home() / "evidencias-finais"),
        help="Diretorio raiz das evidencias finais.",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).expanduser().resolve()

    if not root.is_dir():
        print(f"[FAIL] diretorio inexistente: {root}")
        return 2

    print("=== CONECTAEDUCA MANIFESTO EVIDENCIAS FINAIS ===")
    print(f"root={root}")
    print("mode=READ_ONLY_INPUTS_WRITE_MANIFEST_ONLY")

    warns = 0
    fails = 0

    for name in REQUIRED_DIRS:
        p = root / name
        if p.is_dir():
            print(f"[PASS] dir={name}")
        else:
            warns += 1
            print(f"[WARN] dir ausente={name}")

    files: list[Path] = []
    for path in sorted(root.rglob("*")):
        if path.name in EXCLUDED_OUTPUTS:
            continue
        if path.is_symlink():
            fails += 1
            print(f"[FAIL] symlink nao permitido: {path.relative_to(root)}")
            continue
        if path.is_file():
            files.append(path)

    blocked_paths: list[str] = []
    private_key_files: list[str] = []

    for path in files:
        rel = path.relative_to(root).as_posix()
        if any(rx.search(rel) for rx in BLOCKED_NAME_PATTERNS):
            blocked_paths.append(rel)

        try:
            with path.open("rb") as fh:
                head = fh.read(1024 * 1024)
            if any(marker in head for marker in PRIVATE_KEY_MARKERS):
                private_key_files.append(rel)
        except OSError as exc:
            fails += 1
            print(f"[FAIL] leitura falhou: {rel}: {exc}")

    for rel in blocked_paths:
        fails += 1
        print(f"[FAIL] nome de arquivo/path sensivel: {rel}")

    for rel in private_key_files:
        fails += 1
        print(f"[FAIL] material de chave privada detectado: {rel}")

    manifest_rows: list[tuple[str, int, str]] = []
    total_bytes = 0

    for path in files:
        rel = path.relative_to(root).as_posix()
        digest = sha256_file(path)
        size = path.stat().st_size
        total_bytes += size
        manifest_rows.append((digest, size, rel))

    if fails:
        print(f"FILES={len(files)}")
        print(f"BYTES={total_bytes}")
        print(f"WARN={warns}")
        print(f"FAIL={fails}")
        print("MANIFEST_READY=NO")
        print("OUTPUT_WRITTEN=NO")
        return 2

    sha_path = root / "SHA256SUMS"
    manifest_path = root / "MANIFESTO-EVIDENCIAS.txt"

    sha_text = "".join(f"{digest}  {rel}\n" for digest, _, rel in manifest_rows)
    sha_path.write_text(sha_text, encoding="utf-8")

    utc = dt.datetime.now(dt.timezone.utc).isoformat()
    manifest_lines = [
        "=== CONECTAEDUCA MANIFESTO DE EVIDENCIAS ===",
        f"generated_utc={utc}",
        f"root_name={root.name}",
        f"files={len(manifest_rows)}",
        f"bytes={total_bytes}",
        f"warnings={warns}",
        "sanitization_filename_gate=PASS",
        "private_key_marker_gate=PASS",
        "",
        "sha256|bytes|path",
    ]
    manifest_lines.extend(
        f"{digest}|{size}|{rel}" for digest, size, rel in manifest_rows
    )
    manifest_lines.append("")
    manifest_path.write_text("\n".join(manifest_lines), encoding="utf-8")

    print(f"FILES={len(manifest_rows)}")
    print(f"BYTES={total_bytes}")
    print(f"WARN={warns}")
    print("FAIL=0")
    print("MANIFEST_READY=YES")
    print(f"SHA256SUMS={sha_path}")
    print(f"MANIFEST={manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
