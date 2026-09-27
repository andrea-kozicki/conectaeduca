#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
import stat
import tempfile
from pathlib import Path


def write_all(fd: int, data: bytes) -> None:
    view = memoryview(data)
    while view:
        written = os.write(fd, view)
        if written <= 0:
            raise OSError("short write while creating protected snapshot")
        view = view[written:]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Cria snapshot protegido e inode-safe de um artefato da inbox Ferret."
    )
    parser.add_argument("--inbox", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--staging", required=True)
    args = parser.parse_args()

    name = args.name
    if not name or name in {".", ".."} or os.path.basename(name) != name:
        raise SystemExit("nome de artefato inválido")

    if not hasattr(os, "O_NOFOLLOW"):
        raise SystemExit("O_NOFOLLOW indisponível; recusa fail-closed")

    inbox = Path(args.inbox)
    staging = Path(args.staging)
    euid = os.geteuid()

    staging_stat = staging.stat()
    if staging_stat.st_uid != euid or (staging_stat.st_mode & 0o077):
        raise SystemExit("staging inseguro: owner/mode divergente")

    dir_flags = os.O_RDONLY | os.O_CLOEXEC
    if hasattr(os, "O_DIRECTORY"):
        dir_flags |= os.O_DIRECTORY
    dir_fd = os.open(inbox, dir_flags)
    src_fd = -1
    dst_fd = -1
    dst_path: str | None = None
    try:
        inbox_stat = os.fstat(dir_fd)
        if inbox_stat.st_uid != euid:
            raise SystemExit("inbox não pertence ao runtime UID esperado")

        src_flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW
        if hasattr(os, "O_NONBLOCK"):
            src_flags |= os.O_NONBLOCK

        src_fd = os.open(name, src_flags, dir_fd=dir_fd)
        src_before = os.fstat(src_fd)
        if not stat.S_ISREG(src_before.st_mode):
            raise SystemExit("artefato recusado: não é arquivo regular")

        dst_fd, dst_path = tempfile.mkstemp(prefix=".snapshot-", dir=staging)
        os.fchmod(dst_fd, 0o400)

        digest = hashlib.sha256()
        while True:
            chunk = os.read(src_fd, 1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
            write_all(dst_fd, chunk)

        os.fsync(dst_fd)
        src_after = os.fstat(src_fd)
        dst_stat = os.fstat(dst_fd)

        source_changed = (
            src_before.st_dev != src_after.st_dev
            or src_before.st_ino != src_after.st_ino
            or src_before.st_size != src_after.st_size
            or src_before.st_mtime_ns != src_after.st_mtime_ns
            or src_before.st_ctime_ns != src_after.st_ctime_ns
        )
        if source_changed:
            raise SystemExit("artefato mudou durante o snapshot; recusa fail-closed")

        if not stat.S_ISREG(dst_stat.st_mode) or dst_stat.st_size != src_after.st_size:
            raise SystemExit("snapshot inconsistente; recusa fail-closed")

        print(f"{dst_path}\t{digest.hexdigest()}")
        dst_path = None
        return 0
    finally:
        if src_fd >= 0:
            os.close(src_fd)
        if dst_fd >= 0:
            os.close(dst_fd)
        os.close(dir_fd)
        if dst_path is not None:
            try:
                os.unlink(dst_path)
            except FileNotFoundError:
                pass


if __name__ == "__main__":
    raise SystemExit(main())
