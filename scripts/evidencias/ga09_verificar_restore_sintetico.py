#!/usr/bin/env python3
"""GA-09: verifica SHA-256 de duas arvores de arquivos FICTICIOS.

Somente leitura; NAO executa Bacula, bconsole, Docker, restauracao,
agendamento ou comando privilegiado. Nao imprime nomes nem bytes dos arquivos.
O retorno PASS comprova apenas igualdade dos conteudos lidos nas duas arvores
no instante do ensaio, nao a origem Bacula nem RPO/RTO.
"""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import stat
import sys

MAX_FILES = 64
MAX_FILE_BYTES = 8 * 1024 * 1024
MAX_TOTAL_BYTES = 32 * 1024 * 1024
CHUNK = 128 * 1024


class IntegrityError(Exception):
    """Falha fechada, com motivo sem nomes ou conteudos de arquivos."""


def _files_in_tree(root: Path) -> tuple[dict[str, tuple[str, int]], set[str], int]:
    """Inventaria somente arquivos regulares e diretorios, sem seguir links."""
    if root.is_symlink() or not root.is_dir():
        raise IntegrityError("raiz_ausente_ou_link")
    result: dict[str, tuple[str, int]] = {}
    directories: set[str] = set()
    total = 0
    pending = [(root, Path("."))]

    while pending:
        current, relative_dir = pending.pop()
        try:
            with os.scandir(current) as iterator:
                items = list(iterator)
        except OSError as exc:
            raise IntegrityError("diretorio_inacessivel") from exc

        for item in items:
            relative = relative_dir / item.name
            rel = relative.as_posix()
            try:
                metadata = item.stat(follow_symlinks=False)
            except OSError as exc:
                raise IntegrityError("entrada_inacessivel") from exc
            if stat.S_ISLNK(metadata.st_mode):
                raise IntegrityError("link_simbolico_proibido")
            if stat.S_ISDIR(metadata.st_mode):
                directories.add(rel)
                pending.append((Path(item.path), relative))
                continue
            if not stat.S_ISREG(metadata.st_mode):
                raise IntegrityError("tipo_nao_regular")
            if metadata.st_nlink != 1:
                raise IntegrityError("hardlink_proibido")
            if metadata.st_size > MAX_FILE_BYTES:
                raise IntegrityError("arquivo_maior_que_limite")
            if len(result) >= MAX_FILES:
                raise IntegrityError("quantidade_maior_que_limite")
            total += metadata.st_size
            if total > MAX_TOTAL_BYTES:
                raise IntegrityError("volume_maior_que_limite")
            result[rel] = (_hash_checked(Path(item.path), metadata), metadata.st_size)

    if not result:
        raise IntegrityError("sem_arquivos_para_comparar")
    return result, directories, total


def _hash_checked(path: Path, expected: os.stat_result) -> str:
    """Abre sem seguir symlink e confere metadata antes/depois do hash."""
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    try:
        fd = os.open(path, flags)
    except OSError as exc:
        raise IntegrityError("arquivo_inacessivel") from exc
    digest = hashlib.sha256()
    try:
        with os.fdopen(fd, "rb", closefd=True) as stream:
            before = os.fstat(stream.fileno())
            if not stat.S_ISREG(before.st_mode):
                raise IntegrityError("arquivo_troca_de_tipo")
            if (before.st_dev, before.st_ino) != (expected.st_dev, expected.st_ino):
                raise IntegrityError("arquivo_substituido")
            if before.st_nlink != 1 or before.st_size > MAX_FILE_BYTES:
                raise IntegrityError("arquivo_inseguro")
            count = 0
            while True:
                part = stream.read(CHUNK)
                if not part:
                    break
                count += len(part)
                if count > MAX_FILE_BYTES:
                    raise IntegrityError("arquivo_cresceu_mais_que_limite")
                digest.update(part)
            after = os.fstat(stream.fileno())
            signature = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
            if signature(before) != signature(after) or signature(before) != signature(expected):
                raise IntegrityError("arquivo_alterado_durante_leitura")
            if count != after.st_size:
                raise IntegrityError("leitura_incompleta")
    except OSError as exc:
        raise IntegrityError("erro_leitura") from exc
    return digest.hexdigest()


def verify(source: Path, restored: Path) -> tuple[int, int]:
    """Compara caminhos relativos, diretorios, tamanhos e SHA-256."""
    if source.is_symlink() or restored.is_symlink():
        raise IntegrityError("raiz_link")
    try:
        a, b = source.resolve(strict=True), restored.resolve(strict=True)
    except OSError as exc:
        raise IntegrityError("raiz_inacessivel") from exc
    if a == b or a in b.parents or b in a.parents:
        raise IntegrityError("raizes_iguais_ou_aninhadas")

    originals, orig_dirs, total = _files_in_tree(a)
    recovered, restored_dirs, _ = _files_in_tree(b)
    if orig_dirs != restored_dirs:
        raise IntegrityError("estrutura_diretorios_divergente")
    if originals.keys() != recovered.keys():
        raise IntegrityError("inventario_arquivos_divergente")
    for path, original in originals.items():
        if original != recovered[path]:
            raise IntegrityError("conteudo_ou_tamanho_divergente")

    # Releitura para identificar alteracoes comuns durante a verificacao.
    check_again, new_dirs, _ = _files_in_tree(a)
    if new_dirs != orig_dirs or check_again != originals:
        raise IntegrityError("origem_alterada_durante_ensaio")
    return len(originals), total


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Compara apenas duas arvores sintéticas por SHA-256. Nunca executa restore."
    )
    parser.add_argument("--synthetic", action="store_true", help="confirma uso de arquivos ficticios")
    parser.add_argument("--source", type=Path, required=True, help="diretorio fonte FICTICIO")
    parser.add_argument("--restored", type=Path, required=True, help="diretorio restaurado ISOLADO")
    args = parser.parse_args(argv)
    if not args.synthetic:
        print("GA09_RESTORE_VERIFY=FAIL reason=confirmacao_sintetica_ausente", file=sys.stderr)
        return 2
    try:
        count, size = verify(args.source, args.restored)
    except (IntegrityError, OSError) as exc:
        reason = str(exc) if isinstance(exc, IntegrityError) else "erro_de_io"
        print(f"GA09_RESTORE_VERIFY=FAIL reason={reason}", file=sys.stderr)
        return 1
    print(f"GA09_RESTORE_VERIFY=PASS algorithm=SHA256 files={count} bytes={size}")
    print("GA09_BACULA_RESTORE_EXECUTED=NAO")
    print("GA09_OPERATIONAL_RECOVERY_PROVEN=NAO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
