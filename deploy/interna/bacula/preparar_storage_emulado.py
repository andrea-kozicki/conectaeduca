#!/usr/bin/env python3
"""
ConectaEduca — Bacula — migração/ativação fail-closed do Storage emulado.

Objetivo:
- impedir que um redeploy troque /backup para um bind vazio;
- preservar o named volume legado como rollback;
- quiescer Director/Storage antes da cópia;
- copiar e validar por fingerprint nomes/metadados/conteúdo;
- ativar o bind somente após igualdade criptográfica;
- restaurar o runtime legado automaticamente se a ativação falhar;
- persistir o target ativo para os redeploys canônicos posteriores;
- restaurar/remover o env-file persistido quando houver rollback;
- permitir timeouts configuráveis de fingerprint e cópia para mídias grandes/lentas;
- validar espaço livre antes de qualquer parada/cópia de mídia;
- proteger somente os ancestrais de TARGET criados pela própria migração;\n- rejeitar symlinks, ancestrais não-root/graváveis e races em toda a cadeia;\n- exigir barreira root:root 0700 no parent final do TARGET;\n- não converter job agendado pós-restart em rollback; rollback só muta Storage com quiescência comprovada;\n- reconciliar env-file com o mount /backup realmente ativo após qualquer falha;\n- quiescer o scheduler (`disable job all`) antes do gate No Jobs final do APPLY;\n- repetir capacity gate sobre source quiescente e quiescer scheduler também antes de rollback;\n- restaurar scheduling automaticamente se qualquer gate pós-disable falhar antes do stop do Director;\n- validar capacidade novamente imediatamente antes de toda cópia, já com Director/Storage parados;\n- aplicar o timeout dentro do sudo para encerrar o cp privilegiado e restaurar scheduling se o stop de rollback falhar;\n- recusar volume legado não-canônico para garantir que rollback Compose restaure a mesma mídia;\n- exigir resposta estrutural real de status do Director e rejeitar diagnósticos de conexão;\n- aplicar timeout interno a toda execução privilegiada via sudo/env, inclusive Compose forward e rollback;
- serializar todas as invocações CHECK/APPLY por lock host-wide root-owned em /run/lock, reutilizável por operadores diferentes;
- gerar nomes de evidência sem colisão por microssegundos+PID e criação exclusiva;
- gerar evidência textual + SHA-256.

Não fornece isolamento físico/disaster recovery. O destino padrão continua no
mesmo host e pode continuar no mesmo filesystem da VM.
"""
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import sys
import tempfile
import time
from typing import Any

VERSION = "2.0.16"
PROJECT = "conectaeduca-bacula"
STORAGE = "conectaeduca-bacula-storage"
DIRECTOR = "conectaeduca-bacula-director"
DEFAULT_TARGET = "/srv/conectaeduca-backup/bacula/volumes"
TARGET_ENV_FILENAME = ".conectaeduca-storage-path.env"
TARGET_ENV_KEY = "CONECTAEDUCA_BACULA_STORAGE_PATH"
SAFE_TARGET_RE = re.compile(r"^/[A-Za-z0-9._/+:-]+$")
BACULA_UID = 100
BACULA_GID = 101
STOP_TIMEOUT = 40
READY_TIMEOUT = 120
FINGERPRINT_TIMEOUT = 1800
COPY_TIMEOUT = 3600
CAPACITY_RESERVE_BYTES = 2 * 1024 * 1024 * 1024
HOST_LOCK_ROOT = Path("/run/lock")
HOST_LOCK_DIR = HOST_LOCK_ROOT / "conectaeduca-bacula"
HOST_LOCK_PATH = HOST_LOCK_DIR / "storage-emulado.lock"
HOST_LOCK_DIR_MODE = 0o755
HOST_LOCK_FILE_MODE = 0o444

PASS = WARN = FAIL = INFO = 0
ROLLBACK_USED = 0


def emit(msg: str = "") -> None:
    print(msg, flush=True)


def mark(kind: str, msg: str) -> None:
    global PASS, WARN, FAIL, INFO
    if kind == "PASS":
        PASS += 1
    elif kind == "WARN":
        WARN += 1
    elif kind == "FAIL":
        FAIL += 1
    else:
        INFO += 1
    emit(f"[{kind}] {msg}")


LOCK_NAMESPACE_HELPER = r"""
import os, stat, sys

root = os.path.abspath(sys.argv[1])
directory = os.path.abspath(sys.argv[2])
lock = os.path.abspath(sys.argv[3])

def fail(message):
    raise SystemExit(message)

if os.path.dirname(directory) != root:
    fail("namespace fora do lock root")
if os.path.dirname(lock) != directory:
    fail("arquivo de lock fora do namespace")

dir_name = os.path.basename(directory)
lock_name = os.path.basename(lock)
if not dir_name or not lock_name or dir_name in (".", "..") or lock_name in (".", ".."):
    fail("nome de lock inválido")

if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
    fail("flags seguras O_NOFOLLOW/O_DIRECTORY indisponíveis")

root_lstat = os.lstat(root)
root_mode = stat.S_IMODE(root_lstat.st_mode)
if (
    not stat.S_ISDIR(root_lstat.st_mode)
    or stat.S_ISLNK(root_lstat.st_mode)
    or root_lstat.st_uid != 0
):
    fail("lock root inseguro")
if (root_mode & 0o002) and not (root_mode & stat.S_ISVTX):
    fail("lock root world-writable sem sticky bit")

root_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
if hasattr(os, "O_CLOEXEC"):
    root_flags |= os.O_CLOEXEC

root_fd = os.open(root, root_flags)
try:
    root_fd_st = os.fstat(root_fd)
    if (
        root_fd_st.st_dev != root_lstat.st_dev
        or root_fd_st.st_ino != root_lstat.st_ino
        or not stat.S_ISDIR(root_fd_st.st_mode)
        or root_fd_st.st_uid != 0
    ):
        fail("lock root mudou durante validação")

    created_directory = False
    try:
        os.mkdir(dir_name, 0o755, dir_fd=root_fd)
        created_directory = True
    except FileExistsError:
        pass

    dir_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    if hasattr(os, "O_CLOEXEC"):
        dir_flags |= os.O_CLOEXEC

    dir_fd = os.open(dir_name, dir_flags, dir_fd=root_fd)
    try:
        dir_fd_st = os.fstat(dir_fd)
        path_dir_st = os.stat(dir_name, dir_fd=root_fd, follow_symlinks=False)
        if (
            not stat.S_ISDIR(dir_fd_st.st_mode)
            or stat.S_ISLNK(path_dir_st.st_mode)
            or dir_fd_st.st_dev != path_dir_st.st_dev
            or dir_fd_st.st_ino != path_dir_st.st_ino
        ):
            fail("namespace de lock mudou antes da normalização")

        if created_directory:
            os.fchown(dir_fd, 0, 0)
            os.fchmod(dir_fd, 0o755)

        dir_fd_st = os.fstat(dir_fd)
        path_dir_st = os.stat(dir_name, dir_fd=root_fd, follow_symlinks=False)
        if (
            not stat.S_ISDIR(dir_fd_st.st_mode)
            or stat.S_ISLNK(path_dir_st.st_mode)
            or dir_fd_st.st_dev != path_dir_st.st_dev
            or dir_fd_st.st_ino != path_dir_st.st_ino
            or dir_fd_st.st_uid != 0
            or dir_fd_st.st_gid != 0
            or stat.S_IMODE(dir_fd_st.st_mode) != 0o755
        ):
            fail("namespace de lock inseguro")

        try:
            existing_lock_st = os.stat(
                lock_name, dir_fd=dir_fd, follow_symlinks=False
            )
            lock_existed = True
            if (
                not stat.S_ISREG(existing_lock_st.st_mode)
                or stat.S_ISLNK(existing_lock_st.st_mode)
            ):
                fail("lock preexistente inseguro")
        except FileNotFoundError:
            lock_existed = False

        lock_flags = os.O_CREAT | os.O_RDONLY | os.O_NOFOLLOW
        if hasattr(os, "O_CLOEXEC"):
            lock_flags |= os.O_CLOEXEC

        lock_fd = os.open(lock_name, lock_flags, 0o444, dir_fd=dir_fd)
        try:
            lock_fd_st = os.fstat(lock_fd)
            path_lock_st = os.stat(
                lock_name, dir_fd=dir_fd, follow_symlinks=False
            )
            if (
                not stat.S_ISREG(lock_fd_st.st_mode)
                or stat.S_ISLNK(path_lock_st.st_mode)
                or lock_fd_st.st_dev != path_lock_st.st_dev
                or lock_fd_st.st_ino != path_lock_st.st_ino
            ):
                fail("lock mudou durante validação")

            if not lock_existed:
                os.fchown(lock_fd, 0, 0)
                os.fchmod(lock_fd, 0o444)

            lock_fd_st = os.fstat(lock_fd)
            path_lock_st = os.stat(
                lock_name, dir_fd=dir_fd, follow_symlinks=False
            )
            if (
                not stat.S_ISREG(lock_fd_st.st_mode)
                or stat.S_ISLNK(path_lock_st.st_mode)
                or lock_fd_st.st_dev != path_lock_st.st_dev
                or lock_fd_st.st_ino != path_lock_st.st_ino
                or lock_fd_st.st_uid != 0
                or lock_fd_st.st_gid != 0
                or stat.S_IMODE(lock_fd_st.st_mode) != 0o444
            ):
                fail("lock final inseguro")
        finally:
            os.close(lock_fd)

        final_dir_st = os.stat(dir_name, dir_fd=root_fd, follow_symlinks=False)
        final_fd_st = os.fstat(dir_fd)
        if (
            stat.S_ISLNK(final_dir_st.st_mode)
            or final_dir_st.st_dev != final_fd_st.st_dev
            or final_dir_st.st_ino != final_fd_st.st_ino
        ):
            fail("namespace de lock foi substituído durante a preparação")
    finally:
        os.close(dir_fd)
finally:
    os.close(root_fd)
"""


def validate_host_lock_namespace() -> bool:
    """Valida namespace root-owned; retorna False somente quando ainda não existe."""
    try:
        root_st = os.lstat(HOST_LOCK_ROOT)
    except OSError as exc:
        raise RuntimeError(
            f"não foi possível validar diretório de locks {HOST_LOCK_ROOT}: {exc}"
        ) from exc

    root_mode = stat.S_IMODE(root_st.st_mode)
    if not stat.S_ISDIR(root_st.st_mode) or root_st.st_uid != 0:
        raise RuntimeError(f"diretório de locks inseguro: {HOST_LOCK_ROOT}")
    if (root_mode & 0o002) and not (root_mode & stat.S_ISVTX):
        raise RuntimeError(
            f"diretório de locks world-writable sem sticky bit: {HOST_LOCK_ROOT}"
        )

    try:
        dir_st = os.lstat(HOST_LOCK_DIR)
    except FileNotFoundError:
        return False
    except OSError as exc:
        raise RuntimeError(
            f"não foi possível validar namespace de lock {HOST_LOCK_DIR}: {exc}"
        ) from exc

    if (
        not stat.S_ISDIR(dir_st.st_mode)
        or stat.S_ISLNK(dir_st.st_mode)
        or dir_st.st_uid != 0
        or dir_st.st_gid != 0
        or stat.S_IMODE(dir_st.st_mode) != HOST_LOCK_DIR_MODE
    ):
        raise RuntimeError(
            f"namespace de lock inseguro; esperado root:root 0755: {HOST_LOCK_DIR}"
        )

    try:
        lock_st = os.lstat(HOST_LOCK_PATH)
    except FileNotFoundError:
        return False
    except OSError as exc:
        raise RuntimeError(
            f"não foi possível validar lock host-wide {HOST_LOCK_PATH}: {exc}"
        ) from exc

    if (
        not stat.S_ISREG(lock_st.st_mode)
        or stat.S_ISLNK(lock_st.st_mode)
        or lock_st.st_uid != 0
        or lock_st.st_gid != 0
        or stat.S_IMODE(lock_st.st_mode) != HOST_LOCK_FILE_MODE
    ):
        raise RuntimeError(
            "lock host-wide inseguro; esperado arquivo regular root:root 0444: "
            f"{HOST_LOCK_PATH}"
        )

    return True


def ensure_host_lock_namespace() -> None:
    """Cria uma única vez, via sudo pontual, o lock compartilhado root-owned."""
    if validate_host_lock_namespace():
        return

    sudo(
        [
            "python3",
            "-",
            str(HOST_LOCK_ROOT),
            str(HOST_LOCK_DIR),
            str(HOST_LOCK_PATH),
        ],
        input_text=LOCK_NAMESPACE_HELPER,
        show=False,
        check=True,
        timeout=30,
    )

    if not validate_host_lock_namespace():
        raise RuntimeError("namespace de lock permaneceu ausente após preparação")


@contextlib.contextmanager
def host_migration_lock(mode: str):
    """Serializa CHECK/APPLY usando descritores estáveis e flock não-bloqueante."""
    ensure_host_lock_namespace()

    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
        raise RuntimeError("flags seguras O_NOFOLLOW/O_DIRECTORY indisponíveis")

    root_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    dir_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    lock_flags = os.O_RDONLY | os.O_NOFOLLOW
    if hasattr(os, "O_CLOEXEC"):
        root_flags |= os.O_CLOEXEC
        dir_flags |= os.O_CLOEXEC
        lock_flags |= os.O_CLOEXEC

    root_fd = os.open(HOST_LOCK_ROOT, root_flags)
    try:
        root_st = os.fstat(root_fd)
        if not stat.S_ISDIR(root_st.st_mode) or root_st.st_uid != 0:
            raise RuntimeError(f"diretório de locks inseguro: {HOST_LOCK_ROOT}")

        dir_fd = os.open(HOST_LOCK_DIR.name, dir_flags, dir_fd=root_fd)
        try:
            dir_st = os.fstat(dir_fd)
            path_dir_st = os.stat(
                HOST_LOCK_DIR.name, dir_fd=root_fd, follow_symlinks=False
            )
            if (
                not stat.S_ISDIR(dir_st.st_mode)
                or stat.S_ISLNK(path_dir_st.st_mode)
                or dir_st.st_dev != path_dir_st.st_dev
                or dir_st.st_ino != path_dir_st.st_ino
                or dir_st.st_uid != 0
                or dir_st.st_gid != 0
                or stat.S_IMODE(dir_st.st_mode) != HOST_LOCK_DIR_MODE
            ):
                raise RuntimeError(
                    f"namespace de lock inseguro: {HOST_LOCK_DIR}"
                )

            fd = os.open(HOST_LOCK_PATH.name, lock_flags, dir_fd=dir_fd)
            try:
                st = os.fstat(fd)
                path_lock_st = os.stat(
                    HOST_LOCK_PATH.name, dir_fd=dir_fd, follow_symlinks=False
                )
                if (
                    not stat.S_ISREG(st.st_mode)
                    or stat.S_ISLNK(path_lock_st.st_mode)
                    or st.st_dev != path_lock_st.st_dev
                    or st.st_ino != path_lock_st.st_ino
                    or st.st_uid != 0
                    or st.st_gid != 0
                    or stat.S_IMODE(st.st_mode) != HOST_LOCK_FILE_MODE
                ):
                    raise RuntimeError(
                        "lock host-wide inseguro; esperado arquivo regular "
                        f"root:root 0444: {HOST_LOCK_PATH}"
                    )

                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError as exc:
                    emit(f"HOST_MIGRATION_LOCK_PATH={HOST_LOCK_PATH}")
                    emit("HOST_MIGRATION_LOCK_ACQUIRED=0")
                    raise RuntimeError(
                        "outra execução do helper Bacula já está ativa neste host; "
                        "CHECK/APPLY concorrente foi recusado"
                    ) from exc

                # Reconfirma que o namespace e o lock ainda são os mesmos inodes
                # depois da aquisição. Se o parent foi renomeado/trocado, falha
                # fechado sem prosseguir para qualquer operação de migração.
                final_dir_st = os.stat(
                    HOST_LOCK_DIR.name, dir_fd=root_fd, follow_symlinks=False
                )
                final_lock_st = os.stat(
                    HOST_LOCK_PATH.name, dir_fd=dir_fd, follow_symlinks=False
                )
                if (
                    final_dir_st.st_dev != dir_st.st_dev
                    or final_dir_st.st_ino != dir_st.st_ino
                    or final_lock_st.st_dev != st.st_dev
                    or final_lock_st.st_ino != st.st_ino
                ):
                    fcntl.flock(fd, fcntl.LOCK_UN)
                    raise RuntimeError(
                        "namespace/lock host-wide mudou durante aquisição"
                    )

                emit(f"HOST_MIGRATION_LOCK_PATH={HOST_LOCK_PATH}")
                emit(f"HOST_MIGRATION_LOCK_MODE={mode}")
                emit(f"HOST_MIGRATION_LOCK_PID={os.getpid()}")
                emit("HOST_MIGRATION_LOCK_OWNER=root:root")
                emit("HOST_MIGRATION_LOCK_PERMISSIONS=0444")
                emit("HOST_MIGRATION_LOCK_STABLE_DESCRIPTOR=1")
                emit("HOST_MIGRATION_LOCK_ACQUIRED=1")
                try:
                    yield
                finally:
                    fcntl.flock(fd, fcntl.LOCK_UN)
                    emit("HOST_MIGRATION_LOCK_RELEASED=1")
            finally:
                os.close(fd)
        finally:
            os.close(dir_fd)
    finally:
        os.close(root_fd)



def qcmd(argv: list[str]) -> str:
    return " ".join(shlex.quote(str(x)) for x in argv)


def run(
    argv: list[str],
    *,
    input_text: str | None = None,
    timeout: int = 120,
    show: bool = True,
    check: bool = False,
) -> tuple[int, str]:
    emit(f"\n$ {qcmd(argv)}")
    try:
        p = subprocess.run(
            [str(x) for x in argv],
            input=input_text,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        out = exc.stdout or ""
        if isinstance(out, bytes):
            out = out.decode("utf-8", "replace")
        if show and out:
            emit(out.rstrip())
        emit(f"RC=TIMEOUT({timeout}s)")
        if check:
            raise RuntimeError(f"timeout: {qcmd(argv)}")
        return 124, out

    out = p.stdout or ""
    if show and out:
        emit(out.rstrip())
    elif not show:
        emit(f"OUTPUT_OMITIDO={len(out.encode('utf-8'))}_bytes")
    emit(f"RC={p.returncode}")
    if check and p.returncode != 0:
        raise RuntimeError(f"rc={p.returncode}: {qcmd(argv)}")
    return p.returncode, out


def _run_privileged_bounded(
    prefix: list[str],
    argv: list[str],
    **kwargs: Any,
) -> tuple[int, str]:
    """Aplica timeout dentro do sudo para não deixar filhos privilegiados órfãos."""
    inner_timeout = int(kwargs.pop("timeout", 120))
    if inner_timeout <= 0:
        raise ValueError("timeout privilegiado deve ser positivo")
    outer_timeout = inner_timeout + 30
    command = [
        *prefix,
        "timeout",
        "--signal=TERM",
        "--kill-after=10s",
        str(inner_timeout),
        *argv,
    ]
    return run(command, timeout=outer_timeout, **kwargs)


def sudo(argv: list[str], **kwargs: Any) -> tuple[int, str]:
    return _run_privileged_bounded(["sudo"], argv, **kwargs)


def sudo_storage_path(target: Path, argv: list[str], **kwargs: Any) -> tuple[int, str]:
    """Executa Compose privilegiado com env explícito e timeout interno."""
    assignment = f"{TARGET_ENV_KEY}={target}"
    return _run_privileged_bounded(
        ["sudo", "env", assignment],
        argv,
        **kwargs,
    )


def inspect(name: str) -> dict[str, Any]:
    rc, out = run(["docker", "inspect", name], show=False)
    if rc != 0:
        raise RuntimeError(f"docker inspect falhou: {name}")
    obj = json.loads(out)
    if len(obj) != 1:
        raise RuntimeError(f"docker inspect inesperado: {name}")
    return obj[0]


def backup_mount(ins: dict[str, Any]) -> dict[str, Any] | None:
    for m in ins.get("Mounts", []) or []:
        if m.get("Destination") == "/backup":
            return m
    return None


def canonical_files(base: Path) -> list[Path]:
    base_file = base / "compose.vm.yml"
    if not base_file.is_file():
        base_file = base / "compose.yml"
    files = [
        base_file,
        base / "compose.postgresql-hardening.yml",
        base / "compose.director-hardening.yml",
        base / "compose.storage-hardening.yml",
        base / "compose.director-pgbouncer.yml",
    ]
    missing = [str(p) for p in files if not p.is_file()]
    if missing:
        raise RuntimeError("overlays canônicos ausentes: " + ", ".join(missing))
    emit(f"BACULA_BASE_COMPOSE={base_file.name}")
    return files


def compose(base: Path, files: list[Path], overlay: bool, *tail: str) -> list[str]:
    argv = ["docker", "compose", "-p", PROJECT, "--project-directory", str(base)]
    for f in files:
        argv += ["-f", str(f)]
    if overlay:
        argv += ["-f", str(base / "compose.storage-emulado.yml")]
    argv += list(tail)
    return argv


def expected_legacy_storage_volume(base: Path, files: list[Path]) -> str:
    """Resolve o nome real do volume storage-data definido pelo Compose canônico."""
    argv = compose(base, files, False, "config", "--format", "json")
    rc, out = run(argv, show=False, check=True, timeout=120)
    obj = json.loads(out)
    volume = (obj.get("volumes") or {}).get("storage-data") or {}
    name = str(volume.get("name") or "").strip()
    if not name:
        raise RuntimeError(
            "Compose canônico não informou o nome efetivo do volume storage-data"
        )
    emit(f"EXPECTED_LEGACY_STORAGE_VOLUME={name}")
    return name


def validate_effective_compose(base: Path, files: list[Path], target: Path) -> None:
    argv = compose(base, files, True, "config", "--format", "json")
    rc, out = sudo_storage_path(target, argv, show=False, check=True, timeout=120)
    obj = json.loads(out)
    svc = (obj.get("services") or {}).get("storage") or {}
    mounts = [
        v
        for v in svc.get("volumes", [])
        if isinstance(v, dict) and v.get("target") == "/backup"
    ]
    if len(mounts) != 1:
        raise RuntimeError(f"/backup deve aparecer uma vez; encontrado={len(mounts)}")
    m = mounts[0]
    if m.get("type") != "bind" or Path(str(m.get("source"))) != target:
        raise RuntimeError(f"/backup efetivo não aponta ao bind esperado: {m}")
    mark("PASS", "Compose efetivo aponta /backup ao bind esperado.")


TREE_HELPER = r"""
import hashlib,json,os,stat,sys
root=os.path.abspath(sys.argv[1])
if not os.path.isdir(root): raise SystemExit("not_a_directory")
master=hashlib.sha256(); files=dirs=symlinks=total=0; rows=[]
for base,dnames,fnames in os.walk(root,topdown=True,followlinks=False):
 dnames.sort(); fnames.sort(); relbase=os.path.relpath(base,root); relbase="" if relbase=="." else relbase
 for name in dnames+fnames:
  full=os.path.join(base,name); rel=os.path.join(relbase,name).replace(os.sep,"/"); st=os.lstat(full); mode=stat.S_IMODE(st.st_mode)
  if stat.S_ISDIR(st.st_mode): kind="d"; dirs+=1; payload=""; logical_size=""
  elif stat.S_ISREG(st.st_mode):
   kind="f"; files+=1; total+=st.st_size; logical_size=str(st.st_size); h=hashlib.sha256()
   with open(full,"rb",buffering=1024*1024) as f:
    while True:
     b=f.read(1024*1024)
     if not b: break
     h.update(b)
   payload=h.hexdigest()
  elif stat.S_ISLNK(st.st_mode): kind="l"; symlinks+=1; payload=hashlib.sha256(os.readlink(full).encode("utf-8","surrogateescape")).hexdigest(); logical_size=""
  else: kind="o"; payload=""; logical_size=""
  rows.append("\0".join([rel,kind,str(mode),str(st.st_uid),str(st.st_gid),logical_size,payload]))
for row in sorted(rows): master.update(row.encode("utf-8","surrogateescape")); master.update(b"\n")
print(json.dumps({"files":files,"dirs":dirs,"symlinks":symlinks,"bytes":total,"digest":master.hexdigest()},sort_keys=True))
"""


def fingerprint(path: Path) -> dict[str, Any]:
    rc, out = sudo(
        ["python3", "-", str(path)],
        input_text=TREE_HELPER,
        show=False,
        check=True,
        timeout=FINGERPRINT_TIMEOUT,
    )
    lines = [x for x in out.splitlines() if x.strip().startswith("{")]
    if not lines:
        raise RuntimeError(f"fingerprint sem JSON: {path}")
    obj = json.loads(lines[-1])
    emit(f"FINGERPRINT[{path}]=" + json.dumps(obj, sort_keys=True))
    return obj


def allocated_bytes(path: Path) -> int:
    """Retorna bytes efetivamente alocados no filesystem, não tamanho lógico."""
    rc, out = sudo(
        ["du", "-s", "-B1", "--", str(path)],
        show=False,
        check=True,
        timeout=FINGERPRINT_TIMEOUT,
    )
    line = out.strip().splitlines()[-1] if out.strip() else ""
    token = line.split()[0] if line else ""
    try:
        value = int(token)
    except ValueError as exc:
        raise RuntimeError(f"du não retornou bytes alocados para {path}: {line!r}") from exc
    emit(f"ALLOCATED_BYTES[{path}]={value}")
    return value


def nearest_existing_ancestor(path: Path) -> Path:
    """Encontra o filesystem-alvo sem criar diretórios."""
    current = path
    while True:
        rc, _ = sudo(["test", "-e", str(current)], show=False)
        if rc == 0:
            rc_dir, _ = sudo(["test", "-d", str(current)], show=False)
            if rc_dir != 0:
                raise RuntimeError(f"ancestral existente do TARGET não é diretório: {current}")
            return current
        if current == current.parent:
            return Path("/")
        current = current.parent


def filesystem_available_bytes(path: Path) -> int:
    rc, out = sudo(["df", "-PB1", "--", str(path)], show=False, check=True)
    lines = [line for line in out.splitlines() if line.strip()]
    if len(lines) < 2:
        raise RuntimeError(f"df não retornou linha de dados para {path}")
    fields = lines[-1].split()
    if len(fields) < 4:
        raise RuntimeError(f"df com formato inesperado para {path}: {lines[-1]!r}")
    try:
        value = int(fields[3])
    except ValueError as exc:
        raise RuntimeError(f"df não retornou bytes livres numéricos: {lines[-1]!r}") from exc
    emit(f"TARGET_FILESYSTEM_AVAILABLE_BYTES={value}")
    return value


def validate_copy_capacity(source: Path, target: Path) -> None:
    """Falha se a cópia puder esgotar o filesystem alvo."""
    source_allocated = allocated_bytes(source)
    anchor = nearest_existing_ancestor(target)
    available = filesystem_available_bytes(anchor)
    required = source_allocated + CAPACITY_RESERVE_BYTES

    emit(f"CAPACITY_CHECK_ANCHOR={anchor}")
    emit(f"SOURCE_ALLOCATED_BYTES={source_allocated}")
    emit(f"CAPACITY_RESERVE_BYTES={CAPACITY_RESERVE_BYTES}")
    emit(f"CAPACITY_REQUIRED_BYTES={required}")
    emit(f"CAPACITY_AVAILABLE_BYTES={available}")

    if available < required:
        raise RuntimeError(
            "espaço insuficiente para preservar o named volume e copiar a mídia: "
            f"livre={available} requerido={required} "
            f"(source_alocado={source_allocated} + reserva={CAPACITY_RESERVE_BYTES})"
        )
    mark("PASS", "Capacidade do filesystem aprovada para a cópia.")


def copy_media_with_final_capacity_gate(source: Path, target: Path, reason: str) -> None:
    """Copia mídia com capacity gate e timeout aplicado ao processo privilegiado."""
    validate_copy_capacity(source, target)
    emit(f"FINAL_CAPACITY_GATE_BEFORE_COPY=PASS:{reason}")

    # sudo() aplica GNU timeout dentro do contexto privilegiado; assim o cp
    # supervisionado é encerrado antes de rollback/retry se o limite expirar.
    sudo(
        [
            "cp",
            "-a",
            str(source) + "/.",
            str(target) + "/",
        ],
        timeout=COPY_TIMEOUT,
        check=True,
    )
    emit(f"PRIVILEGED_COPY_TIMEOUT_ENFORCED=1:{reason}")


def validate_existing_target_root(target: Path) -> None:
    rc, out = sudo(["stat", "-Lc", "%u:%g:%a", str(target)], show=False)
    if rc != 0:
        raise RuntimeError(f"não foi possível validar owner/mode do TARGET: {target}")
    raw = out.strip().splitlines()[-1] if out.strip() else ""
    expected = f"{BACULA_UID}:{BACULA_GID}:750"
    emit(f"TARGET_ROOT_OWNERSHIP_MODE={raw}")
    if raw != expected:
        raise RuntimeError(
            "TARGET preexistente não está explicitamente dedicado ao Bacula; "
            f"esperado uid:gid:mode={expected}, observado={raw or 'indisponível'}"
        )
    mark(
        "PASS",
        "TARGET preexistente já está explicitamente dedicado ao Bacula; permissões não serão alteradas.",
    )


def validate_target_literal(raw: str) -> None:
    """Restringe TARGET ao subconjunto seguro e literal aceito pelo env-file Compose."""
    if not SAFE_TARGET_RE.fullmatch(raw):
        raise RuntimeError(
            "TARGET contém caracteres não suportados para persistência dotenv; "
            "use caminho absoluto com letras, números, '.', '_', '/', '+', ':', '-'"
        )


def persistent_env_path(base: Path) -> Path:
    return base / TARGET_ENV_FILENAME


def parse_persisted_target(base: Path) -> Path | None:
    path = persistent_env_path(base)
    if not path.is_file():
        return None
    lines = [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    if len(lines) != 1 or not lines[0].startswith(f"{TARGET_ENV_KEY}="):
        raise RuntimeError(f"arquivo de target persistente inválido: {path}")
    raw = lines[0].split("=", 1)[1].strip()
    if raw.startswith(("'", '"')) and raw.endswith(raw[0]) and len(raw) >= 2:
        raw = raw[1:-1]
    validate_target_literal(raw)
    candidate = Path(raw).expanduser()
    if not candidate.is_absolute():
        raise RuntimeError(f"target persistido não é absoluto: {raw}")
    return candidate.resolve()


def snapshot_persisted_target_env(base: Path) -> tuple[bool, str]:
    path = persistent_env_path(base)
    if not path.is_file():
        return False, ""
    content = path.read_text(encoding="utf-8")
    emit(f"STORAGE_TARGET_ENV_SNAPSHOT_SHA256={hashlib.sha256(content.encode('utf-8')).hexdigest()}")
    return True, content


def restore_persisted_target_env(base: Path, existed: bool, content: str) -> None:
    env_path = persistent_env_path(base)
    if not existed:
        sudo(["rm", "-f", "--", str(env_path)], check=True)
        emit("STORAGE_TARGET_ENV_ROLLBACK=REMOVED_NEW_FILE")
        mark("PASS", "Rollback removeu env-file criado durante APPLY malsucedido.")
        return

    fd, tmp_name = tempfile.mkstemp(prefix="conectaeduca-storage-path-rollback-", suffix=".env")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(content)
        sudo(
            ["install", "-o", "0", "-g", "0", "-m", "0644", tmp_name, str(env_path)],
            check=True,
        )
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(tmp_name)

    restored = env_path.read_text(encoding="utf-8")
    if restored != content:
        raise RuntimeError("env-file restaurado diverge do snapshot pré-APPLY")
    emit(f"STORAGE_TARGET_ENV_ROLLBACK_SHA256={hashlib.sha256(restored.encode('utf-8')).hexdigest()}")
    mark("PASS", "Rollback restaurou o env-file persistido anterior.")


def persist_target_env(base: Path, target: Path) -> Path:
    raw = str(target)
    validate_target_literal(raw)
    env_path = persistent_env_path(base)
    # Aspas simples tornam o valor literal no dotenv do Compose. O conjunto
    # SAFE_TARGET_RE rejeita aspas, '$', backslash, whitespace e metacaracteres.
    content = f"{TARGET_ENV_KEY}='{raw}'\n"

    fd, tmp_name = tempfile.mkstemp(prefix="conectaeduca-storage-path-", suffix=".env")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(content)
        sudo(
            ["install", "-o", "0", "-g", "0", "-m", "0644", tmp_name, str(env_path)],
            check=True,
        )
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(tmp_name)

    persisted = parse_persisted_target(base)
    if persisted != target:
        raise RuntimeError(
            f"target persistido diverge do ativo: esperado={target} observado={persisted}"
        )
    emit(f"STORAGE_TARGET_ENV_FILE={env_path}")
    emit(f"STORAGE_TARGET_ENV_SHA256={hashlib.sha256(env_path.read_bytes()).hexdigest()}")
    mark("PASS", "Target ativo persistido como literal dotenv para redeploys canônicos.")
    return env_path


def reconcile_target_env_with_live_storage(
    base: Path,
    target: Path,
    env_existed_before: bool,
    env_content_before: str,
) -> None:
    """Mantém o env-file alinhado ao mount /backup realmente ativo após falha."""
    storage_ins = inspect(STORAGE)
    if not (storage_ins.get("State") or {}).get("Running"):
        raise RuntimeError(
            "Storage não está running; env-file não será alterado sem provar o mount live"
        )

    mount = backup_mount(storage_ins) or {}
    mount_type = str(mount.get("Type") or "")
    mount_source = Path(str(mount.get("Source") or ""))

    emit(f"FAILED_APPLY_LIVE_BACKUP_TYPE={mount_type}")
    emit(f"FAILED_APPLY_LIVE_BACKUP_SOURCE={mount_source}")

    if mount_type == "volume":
        restore_persisted_target_env(
            base,
            env_existed_before,
            env_content_before,
        )
        emit("TARGET_ENV_RECONCILIATION=RESTORED_PRE_APPLY_FOR_LEGACY_VOLUME")
        mark(
            "PASS",
            "Env-file reconciliado com o Storage revertido ao named volume legado.",
        )
        return

    if (
        mount_type == "bind"
        and mount_source == target
        and mount.get("Destination") == "/backup"
        and mount.get("RW") is True
    ):
        persist_target_env(base, target)
        emit("TARGET_ENV_RECONCILIATION=PRESERVED_ACTIVE_BIND_TARGET")
        mark(
            "PASS",
            "Rollback não reverteu o Storage; env-file preserva o bind ativo para redeploy consistente.",
        )
        return

    raise RuntimeError(
        "mount live após falha não corresponde nem ao volume legado nem ao "
        f"TARGET bind esperado; env-file preservado sem mutação: {mount}"
    )


def output_no_jobs(out: str) -> bool:
    if re.search(r"No Jobs running\.", out, re.I):
        return True
    m = re.search(r"Running Jobs:\s*(.*?)\n={3,}", out, re.I | re.S)
    return bool(
        m
        and (
            not m.group(1).strip()
            or re.search(r"No Jobs running", m.group(1), re.I)
        )
    )

def query_director(
    base: Path,
    files: list[Path],
    show: bool = True,
    input_text: str = "status director\nquit\n",
) -> tuple[int, str]:
    rc, _ = run(
        [
            "docker",
            "exec",
            DIRECTOR,
            "sh",
            "-lc",
            "test -r /etc/bacula-runtime/bconsole.conf && command -v bconsole >/dev/null",
        ],
        show=False,
    )
    if rc == 0:
        return run(
            [
                "docker",
                "exec",
                "-i",
                DIRECTOR,
                "bconsole",
                "-c",
                "/etc/bacula-runtime/bconsole.conf",
            ],
            input_text=input_text,
            show=show,
            timeout=60,
        )
    return sudo(
        compose(
            base,
            files,
            False,
            "--profile",
            "tools",
            "run",
            "--rm",
            "--no-deps",
            "-T",
            "bconsole",
        ),
        input_text=input_text,
        show=show,
        timeout=90,
    )


def require_no_jobs(base: Path, files: list[Path]) -> None:
    rc, out = query_director(base, files)
    if rc != 0 or not output_no_jobs(out):
        raise RuntimeError("não foi possível provar 'No Jobs running'; operação bloqueada")
    mark("PASS", "Director confirmou No Jobs running.")


def quiesce_scheduler_and_require_no_jobs(base: Path, files: list[Path]) -> None:
    """Desabilita scheduling antes do gate final, fechando a race check->stop."""
    rc, out = query_director(
        base,
        files,
        input_text="disable job all\nstatus director\nquit\n",
    )

    command_error = re.search(
        r"(invalid command|unknown command|job all not found|not found|error:)",
        out,
        re.I,
    )
    if rc != 0 or command_error or not output_no_jobs(out):
        # O disable é alteração apenas em memória do Director. Se o gate não
        # puder ser provado, recarregamos a configuração para restaurar o
        # estado Enabled definido em bacula-dir.conf antes de abortar.
        rc_reload, reload_out = query_director(
            base,
            files,
            input_text="reload\nquit\n",
        )
        if rc_reload != 0 or re.search(
            r"(invalid command|unknown command|error:)",
            reload_out,
            re.I,
        ):
            mark(
                "FAIL",
                "Falha ao restaurar estado de scheduling após quiescência inconclusiva.",
            )
        emit("SCHEDULER_RUNTIME_QUIESCED=0")
        raise RuntimeError(
            "não foi possível desabilitar scheduling e provar 'No Jobs running' "
            "na mesma janela; APPLY bloqueado"
        )

    emit("SCHEDULER_RUNTIME_QUIESCED=1")
    mark(
        "PASS",
        "Scheduling de todos os Jobs foi desabilitado em runtime antes do gate final; Director confirmou No Jobs running.",
    )


def director_status_response_ok(out: str) -> bool:
    """Aceita somente resposta estrutural de 'status director', não diagnósticos."""
    if re.search(
        r"(failed to connect|connection refused|could not connect|"
        r"unable to connect|no route to host|timed out|fatal|error:)",
        out,
        re.I,
    ):
        return False

    # Bacula status director apresenta cabeçalho "<nome>-dir Version:" e
    # seções explícitas de status. Exigir ambos evita aceitar uma mensagem de
    # erro que apenas contenha a palavra "Director".
    has_version = bool(re.search(r"(?mi)^\s*\S+-dir\s+Version:\s+\S+", out))
    has_running = bool(re.search(r"(?mi)^\s*Running Jobs:\s*$", out))
    has_peer_section = bool(
        re.search(
            r"(?mi)^\s*(Scheduled Jobs(?:\s*\([^)]*\))?|Terminated Jobs):\s*$",
            out,
        )
    )
    return has_version and has_running and has_peer_section


def require_director_functional(base: Path, files: list[Path]) -> None:
    """Prova conectividade e resposta estrutural de status do Director."""
    rc, out = query_director(base, files)
    if rc != 0 or not director_status_response_ok(out):
        raise RuntimeError(
            "Director não retornou um status funcional verificável via bconsole"
        )
    emit("DIRECTOR_STATUS_RESPONSE_VALID=1")
    mark("PASS", "Director respondeu com status estrutural válido via bconsole.")


def restore_scheduler_after_prestop_failure(base: Path, files: list[Path]) -> None:
    """Evita vazar 'disable job all' se APPLY falhar antes do stop do Director."""
    ins = inspect(DIRECTOR)
    state = ins.get("State") or {}

    if state.get("Running"):
        rc, out = query_director(
            base,
            files,
            input_text="reload\nstatus director\nquit\n",
        )
        if rc != 0 or re.search(
            r"(invalid command|unknown command|error:)",
            out,
            re.I,
        ):
            raise RuntimeError(
                "falha ao executar reload do Director após erro pré-stop"
            )
        if not director_status_response_ok(out):
            raise RuntimeError(
                "reload respondeu sem status funcional verificável do Director"
            )
        emit("SCHEDULER_RUNTIME_RESTORED_AFTER_PRESTOP_FAILURE=RELOAD")
        mark(
            "PASS",
            "Estado de scheduling restaurado por reload após falha pré-stop.",
        )
        return

    run(["docker", "start", DIRECTOR], check=True)
    wait_running(DIRECTOR)
    require_director_functional(base, files)
    emit("SCHEDULER_RUNTIME_RESTORED_AFTER_PRESTOP_FAILURE=START")
    mark(
        "PASS",
        "Director restaurado após falha pré-stop; scheduling reaplicado da configuração.",
    )


def wait_running(name: str, timeout: int = READY_TIMEOUT) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    last = ""
    while time.monotonic() < deadline:
        try:
            ins = inspect(name)
            st = ins.get("State") or {}
            last = json.dumps(st)
            health = (st.get("Health") or {}).get("Status")
            if st.get("Running") and health in (None, "healthy"):
                return ins
            if st.get("Status") in ("dead", "exited"):
                break
        except Exception as exc:
            last = str(exc)
        time.sleep(2)
    raise RuntimeError(f"{name} não ficou operacional: {last}")


def find_legacy_source(
    storage_ins: dict[str, Any],
    expected_legacy_volume: str,
) -> tuple[str | None, Path | None, str]:
    m = backup_mount(storage_ins)
    if not m:
        raise RuntimeError("mount /backup ausente no Storage")
    typ = str(m.get("Type") or "")
    if typ == "volume":
        name = str(m.get("Name") or "")
        src = Path(str(m.get("Source") or ""))
        if not name or not src.is_absolute():
            raise RuntimeError("named volume /backup sem Name/Source válidos")
        emit(f"ACTIVE_LEGACY_VOLUME_NAME={name}")
        if name != expected_legacy_volume:
            raise RuntimeError(
                "Storage usa named volume não-canônico; migração recusada porque "
                "o rollback Compose não restauraria necessariamente a mesma mídia: "
                f"ativo={name} esperado={expected_legacy_volume}"
            )
        mark("PASS", "Named volume legado ativo coincide com o volume canônico do Compose.")
        return name, src, "legacy-volume"
    if typ == "bind":
        return None, Path(str(m.get("Source") or "")), "bind"
    raise RuntimeError(f"tipo de mount /backup inesperado: {typ}")


def summary(mode: str, target: Path, state: str) -> None:
    emit("\n=== RESUMO ===")
    emit(f"VERSION={VERSION}")
    emit(f"MODE={mode}")
    emit(f"TARGET={target}")
    emit(f"FINGERPRINT_TIMEOUT_SECONDS={FINGERPRINT_TIMEOUT}")
    emit(f"COPY_TIMEOUT_SECONDS={COPY_TIMEOUT}")
    emit(f"CAPACITY_RESERVE_BYTES={CAPACITY_RESERVE_BYTES}")
    emit(f"STATE={state}")
    emit(f"ROLLBACK_USED={ROLLBACK_USED}")
    emit("SOURCE_NAMED_VOLUME_DELETED=0")
    emit(f"PASS={PASS}")
    emit(f"WARN={WARN}")
    emit(f"FAIL={FAIL}")
    emit(f"INFO={INFO}")
    emit("FINAL=" + ("FAIL" if FAIL else "WARN" if WARN else "PASS"))


def _inspect_existing_ancestor(path: Path) -> tuple[int, int]:
    """Valida componente existente: diretório real, root-owned, sem escrita group/other."""
    rc_link, _ = sudo(["test", "-L", str(path)], show=False)
    if rc_link == 0:
        raise RuntimeError(f"ancestral do TARGET não pode ser symlink: {path}")

    rc_dir, _ = sudo(["test", "-d", str(path)], show=False)
    if rc_dir != 0:
        raise RuntimeError(f"ancestral do TARGET não é diretório: {path}")

    rc_stat, stat_out = sudo(
        ["stat", "-c", "%u|%a", "--", str(path)],
        show=False,
    )
    if rc_stat != 0:
        raise RuntimeError(f"não foi possível inspecionar segurança do ancestral: {path}")

    try:
        uid_raw, mode_raw = stat_out.strip().split("|", 1)
        uid = int(uid_raw)
        mode = int(mode_raw, 8)
    except (ValueError, TypeError) as exc:
        raise RuntimeError(
            f"stat inválido para ancestral do TARGET {path}: {stat_out.strip()!r}"
        ) from exc

    if uid != 0 or (mode & 0o022):
        raise RuntimeError(
            "cadeia de ancestrais do TARGET não é confiável "
            f"(exige owner=root e sem escrita group/other): {path} "
            f"uid={uid} mode={mode:04o}"
        )

    emit(f"TARGET_TRUSTED_ANCESTOR={path}|uid={uid}|mode={mode:04o}")
    return uid, mode


def _path_chain(path: Path) -> list[Path]:
    """Retorna os componentes absolutos de / até path, inclusive."""
    chain: list[Path] = []
    current = path
    while True:
        chain.append(current)
        if current == current.parent:
            break
        current = current.parent
    return list(reversed(chain))


def validate_target_parent_plan(target: Path) -> tuple[list[Path], Path]:
    """Preflight read-only da cadeia completa e da barreira root-only do parent."""
    parent = target.parent
    missing: list[Path] = []
    current = parent

    while True:
        rc, _ = sudo(["test", "-e", str(current)], show=False)
        if rc == 0:
            anchor = current
            break
        missing.append(current)
        if current == current.parent:
            raise RuntimeError("não foi encontrado ancestral existente para TARGET")
        current = current.parent

    # Valida toda a cadeia até o anchor. Assim /home/alice/anchor é recusado
    # mesmo que anchor seja root-owned, porque /home/alice também é checado.
    for component in _path_chain(anchor):
        _inspect_existing_ancestor(component)

    if not missing:
        # Se o parent final já existe, ele próprio precisa ser a barreira
        # root-only. /mnt (0755), por exemplo, não protege um target UID 100.
        _, parent_mode = _inspect_existing_ancestor(parent)
        if parent_mode != 0o700:
            raise RuntimeError(
                "parent existente do TARGET precisa ser root:root 0700 para "
                f"isolar a mídia do UID/GID do container: {parent} "
                f"mode={parent_mode:04o}; use um subdiretório dedicado"
            )

    planned = list(reversed(missing))
    emit("TARGET_PARENT_PLAN_MISSING=" + json.dumps([str(p) for p in planned]))
    emit(f"TARGET_PARENT_PLAN_ANCHOR={anchor}")
    emit(
        "TARGET_PARENT_BARRIER="
        + ("WILL_CREATE_ROOT_0700" if planned else "EXISTING_ROOT_0700")
    )
    mark(
        "PASS",
        "Cadeia completa do TARGET validada; nenhum componente existente é symlink, não-root ou gravável por group/other.",
    )
    return planned, anchor


def prepare_target_parent(target: Path) -> list[Path]:
    """Cria parents ausentes fail-closed e garante barreira root:root 0700."""
    missing, _anchor = validate_target_parent_plan(target)
    parent = target.parent
    created: list[Path] = []

    for path in missing:
        # A cadeia existente foi validada e não é gravável por não-root.
        # Se mkdir perder a corrida, falhamos fechado.
        rc, _ = sudo(["mkdir", "--", str(path)], show=True)
        if rc != 0:
            raise RuntimeError(
                "race detectada ao criar ancestral do TARGET; "
                f"path apareceu ou mkdir falhou: {path}"
            )

        rc_link, _ = sudo(["test", "-L", str(path)], show=False)
        if rc_link == 0:
            raise RuntimeError(f"ancestral recém-criado virou symlink: {path}")

        sudo(["chown", "0:0", "--", str(path)], check=True)
        sudo(["chmod", "0700", "--", str(path)], check=True)

        rc_dir, _ = sudo(["test", "-d", str(path)], show=False)
        rc_stat, stat_out = sudo(
            ["stat", "-c", "%u|%a", "--", str(path)],
            show=False,
        )
        if rc_dir != 0 or rc_stat != 0 or stat_out.strip() != "0|700":
            raise RuntimeError(
                f"ancestral recém-criado não ficou root:root 0700: {path} "
                f"stat={stat_out.strip()!r}"
            )

        created.append(path)
        emit(f"TARGET_PARENT_CREATED_SECURE={path}|owner=0:0|mode=0700")

    # Revalida a cadeia inteira após as criações e exige a barreira final 0700.
    for component in _path_chain(parent):
        _inspect_existing_ancestor(component)

    rc_stat, parent_stat = sudo(
        ["stat", "-c", "%u|%a", "--", str(parent)],
        show=False,
    )
    if rc_stat != 0 or parent_stat.strip() != "0|700":
        raise RuntimeError(
            f"parent final do TARGET não ficou root:root 0700: {parent} "
            f"stat={parent_stat.strip()!r}"
        )

    emit(f"TARGET_PARENTS_CREATED_COUNT={len(created)}")
    mark(
        "PASS",
        "Parent final possui barreira root:root 0700; cadeia completa foi revalidada e races/symlinks falham fechado.",
    )
    return created

def validate_live_bind(storage_ins: dict[str, Any], target: Path) -> None:
    m = backup_mount(storage_ins) or {}
    if (
        m.get("Type") != "bind"
        or Path(str(m.get("Source") or "")) != target
        or m.get("Destination") != "/backup"
        or m.get("RW") is not True
    ):
        raise RuntimeError(
            f"mount live /backup não é bind gravável para o TARGET solicitado: {m}"
        )
    mark("PASS", "Mount live /backup aponta ao TARGET e está RW=true.")


def execute(mode: str, base: Path, target: Path) -> int:
    global ROLLBACK_USED

    files = canonical_files(base)
    overlay = base / "compose.storage-emulado.yml"
    if not overlay.is_file():
        raise RuntimeError(f"overlay ausente: {overlay}")
    if not target.is_absolute() or str(target) in ("/", "/srv", "/var"):
        raise RuntimeError(f"TARGET inseguro: {target}")

    for cmd in ("docker", "sudo", "python3", "timeout"):
        rc, _ = run(["sh", "-lc", f"command -v {cmd}"], show=False)
        if rc != 0:
            raise RuntimeError(f"comando ausente: {cmd}")

    if os.geteuid() == 0:
        raise RuntimeError("execute como usuário comum; sudo será pontual")

    run(["sudo", "-v"], check=True)

    # Gate read-only também no modo check: targets rasos como /mnt/bacula são
    # rejeitados antes de qualquer parada de serviço.
    validate_target_parent_plan(target)

    validate_effective_compose(base, files, target)
    expected_legacy_volume = expected_legacy_storage_volume(base, files)

    persisted_before = parse_persisted_target(base)
    env_existed_before, env_content_before = snapshot_persisted_target_env(base)
    emit(f"STORAGE_TARGET_ENV_EXISTED_BEFORE={1 if env_existed_before else 0}")
    if persisted_before is not None:
        emit(f"STORAGE_TARGET_PERSISTED_BEFORE={persisted_before}")
        if persisted_before != target:
            mark(
                "WARN",
                "Target persistido atual diverge do solicitado; ele só será substituído após APPLY bem-sucedido.",
            )

    storage = inspect(STORAGE)
    if not (storage.get("State") or {}).get("Running"):
        raise RuntimeError(
            "Storage precisa estar running no início para identificar o mount ativo"
        )

    volume_name, source, kind = find_legacy_source(
        storage,
        expected_legacy_volume,
    )
    emit(f"ACTIVE_BACKUP_KIND={kind}")
    emit(f"ACTIVE_BACKUP_SOURCE={source}")
    if volume_name:
        emit(f"LEGACY_VOLUME_NAME={volume_name}")

    if kind == "bind":
        if source != target:
            raise RuntimeError(
                f"Storage já usa bind diferente do TARGET solicitado: {source}"
            )
        validate_live_bind(storage, target)
        validate_existing_target_root(target)
        fp = fingerprint(target)
        emit("TARGET_FINGERPRINT=" + json.dumps(fp, sort_keys=True))
        require_no_jobs(base, files)
        if mode == "apply":
            persist_target_env(base, target)
        elif persisted_before is None:
            mark(
                "WARN",
                f"{TARGET_ENV_FILENAME} ainda não existe; execute apply idempotente antes de redeploy.",
            )
        elif persisted_before != target:
            raise RuntimeError("target persistido diverge do bind live")
        mark("PASS", "Storage emulado já está ativo no TARGET; operação idempotente.")
        summary(mode, target, "ALREADY_ACTIVE")
        return 0

    assert source is not None

    src_fp_live = fingerprint(source)
    emit("SOURCE_FINGERPRINT_LIVE=" + json.dumps(src_fp_live, sort_keys=True))
    if src_fp_live.get("files", 0) == 0:
        mark(
            "WARN",
            "Named volume legado não contém arquivos regulares; a migração continuará somente se solicitada.",
        )

    rc, _ = sudo(["test", "-e", str(target)], show=False)
    target_exists = rc == 0
    target_needs_copy = True
    emit(f"TARGET_EXISTS={1 if target_exists else 0}")
    if target_exists:
        validate_existing_target_root(target)
        tgt_fp_live = fingerprint(target)
        emit("TARGET_FINGERPRINT_PRE=" + json.dumps(tgt_fp_live, sort_keys=True))
        if tgt_fp_live == src_fp_live:
            target_needs_copy = False
        elif any(tgt_fp_live.get(k, 0) for k in ("files", "dirs", "symlinks")):
            raise RuntimeError("TARGET já contém dados divergentes; recusa sobrescrever")

    emit(f"TARGET_COPY_REQUIRED={1 if target_needs_copy else 0}")
    if target_needs_copy:
        validate_copy_capacity(source, target)
    else:
        mark("PASS", "TARGET já coincide com a mídia legado; nova cópia não exige reserva adicional.")

    require_no_jobs(base, files)

    if mode == "check":
        mark("PASS", "Preflight aprovado; nenhuma alteração persistente realizada.")
        emit("READY_FOR_STORAGE_MIGRATION=1")
        summary(mode, target, "READY")
        return 0

    # APPLY: primeiro desabilita todos os Jobs para scheduling em runtime e só
    # então repete o gate No Jobs. Isso fecha a race em que um Job agendado
    # poderia iniciar entre o preflight e o docker stop do Director.
    quiesce_scheduler_and_require_no_jobs(base, files)

    # Tudo entre disable job all e o stop efetivo do Director precisa ter
    # cleanup próprio. Se capacity/no-jobs/stop falhar, restauramos scheduling
    # antes de propagar a exceção; o rollback destrutivo ainda não começou.
    try:
        # O primeiro capacity gate é preflight. Agora que o scheduler está
        # desabilitado e não há jobs em execução, recalculamos bytes alocados e
        # espaço livre sobre a mídia quiescente.
        if target_needs_copy:
            validate_copy_capacity(source, target)
            emit("CAPACITY_RECHECK_AFTER_SCHEDULER_QUIESCE=PASS")
        else:
            emit("CAPACITY_RECHECK_AFTER_SCHEDULER_QUIESCE=NOT_REQUIRED")

        # Reconfirma ausência de jobs após o capacity recheck. Os Jobs seguem
        # disabled em runtime, então o scheduler não pode criar um job nessa janela.
        require_no_jobs(base, files)
        emit("NO_JOBS_RECHECK_AFTER_CAPACITY=PASS")

        run(
            ["docker", "stop", "-t", str(STOP_TIMEOUT), DIRECTOR],
            timeout=STOP_TIMEOUT + 20,
            check=True,
        )
    except Exception:
        restore_scheduler_after_prestop_failure(base, files)
        raise

    director_stopped = True
    storage_stopped = False
    mark("PASS", "Director parado após quiescência do scheduler; novos jobs agendados estavam bloqueados.")

    try:
        run(
            ["docker", "stop", "-t", str(STOP_TIMEOUT), STORAGE],
            timeout=STOP_TIMEOUT + 20,
            check=True,
        )
        storage_stopped = True
        mark("PASS", "Storage parado; mídia legado quiescente.")

        src_fp = fingerprint(source)
        emit("SOURCE_FINGERPRINT_QUIESCED=" + json.dumps(src_fp, sort_keys=True))

        created_parents = prepare_target_parent(target)
        emit("TARGET_PARENTS_CREATED=" + json.dumps([str(p) for p in created_parents]))
        rc, _ = sudo(["test", "-e", str(target)], show=False)
        target_created_by_migration = rc != 0

        if target_created_by_migration:
            sudo(
                [
                    "install",
                    "-d",
                    "-o",
                    str(BACULA_UID),
                    "-g",
                    str(BACULA_GID),
                    "-m",
                    "0750",
                    str(target),
                ],
                check=True,
            )
            copy_media_with_final_capacity_gate(
                source,
                target,
                "TARGET_CREATED_BY_MIGRATION",
            )
            mark(
                "PASS",
                "TARGET dedicado criado pela migração e mídia legado copiada; named volume original preservado.",
            )
        else:
            validate_existing_target_root(target)
            tgt_pre = fingerprint(target)
            if tgt_pre != src_fp:
                empty = all(
                    tgt_pre.get(k, 0) == 0 for k in ("files", "dirs", "symlinks")
                )
                if not empty:
                    raise RuntimeError(
                        "TARGET divergente após quiesce; nada será sobrescrito"
                    )
                copy_media_with_final_capacity_gate(
                    source,
                    target,
                    "TARGET_PREEXISTING_EMPTY",
                )
                mark(
                    "PASS",
                    "TARGET preexistente dedicado e vazio preenchido a partir do named volume legado.",
                )
            else:
                mark(
                    "PASS",
                    "TARGET preexistente dedicado já coincide com o source quiescente; recópia dispensada.",
                )

        tgt_fp = fingerprint(target)
        emit("TARGET_FINGERPRINT_AFTER_COPY=" + json.dumps(tgt_fp, sort_keys=True))
        if tgt_fp != src_fp:
            raise RuntimeError("fingerprint source != target; bind NÃO será ativado")
        mark("PASS", "Fingerprint source/target idêntico; ativação liberada.")

        if target_created_by_migration:
            sudo(["chown", f"{BACULA_UID}:{BACULA_GID}", str(target)], check=True)
            sudo(["chmod", "0750", str(target)], check=True)
            mark(
                "PASS",
                "Owner/mode canônicos aplicados somente ao TARGET criado por esta migração.",
            )
        else:
            validate_existing_target_root(target)
            mark(
                "PASS",
                "TARGET preexistente dedicado preservou owner/mode sem mutação implícita.",
            )

        argv = compose(
            base,
            files,
            True,
            "up",
            "-d",
            "--no-deps",
            "--force-recreate",
            "storage",
        )
        rc, out = sudo_storage_path(target, argv, show=True, timeout=240)
        if rc != 0:
            raise RuntimeError("recreate do Storage com bind falhou")

        storage_stopped = False
        sins = wait_running(STORAGE)
        validate_live_bind(sins, target)

        post_fp = fingerprint(target)
        if post_fp != tgt_fp:
            raise RuntimeError("fingerprint do TARGET mudou durante ativação")
        mark("PASS", "TARGET íntegro após startup do Storage.")

        run(["docker", "start", DIRECTOR], check=True)
        director_stopped = False
        wait_running(DIRECTOR)
        emit("SCHEDULER_RUNTIME_RESET_BY_DIRECTOR_RESTART=1")
        # O restart reaplica Enabled conforme a configuração persistente.
        # Não exigir No Jobs running depois do restart: um job agendado pode
        # iniciar legitimamente nesse instante. O gate pós-start valida apenas
        # conectividade/funcionalidade do Director, evitando rollback destrutivo
        # por causa de um backup ordinário que acabou de ficar due.
        require_director_functional(base, files)

        persist_target_env(base, target)

        rc1, root_dev = sudo(["stat", "-Lc", "%d", "/"], show=False)
        rc2, target_dev = sudo(["stat", "-Lc", "%d", str(target)], show=False)
        if rc1 != 0 or rc2 != 0:
            raise RuntimeError("não foi possível comparar filesystem de / e TARGET")
        same_fs = root_dev.strip() == target_dev.strip()
        emit(f"PHYSICAL_ISOLATION={0 if same_fs else 1}")
        if same_fs:
            mark(
                "WARN",
                "Storage está no mesmo filesystem de '/': sem isolamento físico/disaster recovery.",
            )
        else:
            mark(
                "INFO",
                "TARGET está em filesystem distinto de '/'; ainda exige política externa de DR.",
            )

        emit("STORAGE_MIGRATION_RESULT=ACTIVE_BIND_VERIFIED")
        summary(mode, target, "ACTIVE")
        return 0

    except Exception:
        ROLLBACK_USED = 1
        mark("WARN", "Falha durante APPLY: avaliando rollback para o named volume legado.")

        rollback_safe = True
        try:
            ins = inspect(DIRECTOR)
            if (ins.get("State") or {}).get("Running"):
                # Se o Director já voltou e iniciou job agendado, NÃO paramos
                # nem trocamos o Storage por baixo dele. Falha fechado e mantém
                # o bind atual para preservar consistência mídia/catalog.
                try:
                    quiesce_scheduler_and_require_no_jobs(base, files)
                    emit("ROLLBACK_SCHEDULER_QUIESCED=1")
                except Exception as active_jobs:
                    rollback_safe = False
                    mark(
                        "FAIL",
                        "ROLLBACK_BLOQUEADO_JOBS_ATIVOS: Director está funcional "
                        "mas não foi possível quiescer scheduling e provar ausência de jobs; "
                        "Storage não será recriado.",
                    )
                    emit(f"ROLLBACK_BLOCK_REASON={type(active_jobs).__name__}")
                if rollback_safe:
                    try:
                        run(
                            ["docker", "stop", "-t", str(STOP_TIMEOUT), DIRECTOR],
                            timeout=STOP_TIMEOUT + 20,
                            check=True,
                        )
                        director_stopped = True
                    except Exception as stop_exc:
                        # O scheduler já foi desabilitado para o rollback. Se o
                        # stop falhar/timeout, restaure scheduling antes de
                        # abandonar o rollback, inclusive se o container tiver
                        # parado apesar do erro reportado.
                        try:
                            restore_scheduler_after_prestop_failure(base, files)
                            emit("ROLLBACK_SCHEDULER_RESTORED_AFTER_STOP_FAILURE=1")
                        except Exception as cleanup_exc:
                            mark(
                                "FAIL",
                                "ROLLBACK_SCHEDULER_RESTORE_FAILED: "
                                f"{type(cleanup_exc).__name__}",
                            )
                        rollback_safe = False
                        mark(
                            "FAIL",
                            "ROLLBACK_ABORTED_DIRECTOR_STOP_FAILED: scheduling "
                            "foi restaurado quando possível; Storage não será recriado.",
                        )
                        emit(f"ROLLBACK_STOP_FAILURE={type(stop_exc).__name__}")
            else:
                director_stopped = True
        except Exception as guard_exc:
            rollback_safe = False
            mark(
                "FAIL",
                f"ROLLBACK_GUARD_INCONCLUSIVO: {type(guard_exc).__name__}: "
                "Storage não será recriado sem provar quiescência.",
            )

        if rollback_safe:
            try:
                argv = compose(
                    base,
                    files,
                    False,
                    "up",
                    "-d",
                    "--no-deps",
                    "--force-recreate",
                    "storage",
                )
                sudo(argv, timeout=240, check=True)
                storage_stopped = False
                sins = wait_running(STORAGE)
                m = backup_mount(sins) or {}
                if m.get("Type") != "volume":
                    raise RuntimeError(f"rollback não restaurou volume: {m}")
                mark("PASS", "Rollback restaurou /backup ao named volume legado.")

                run(["docker", "start", DIRECTOR], check=True)
                director_stopped = False
                wait_running(DIRECTOR)
                emit("SCHEDULER_RUNTIME_RESET_BY_DIRECTOR_RESTART=1")
                require_director_functional(base, files)
                mark("PASS", "Director funcional após rollback.")
            except Exception as rb:
                mark("FAIL", f"ROLLBACK_INCOMPLETO: {type(rb).__name__}: {rb}")
        else:
            emit("ROLLBACK_STORAGE_MUTATION_SKIPPED=1")

        try:
            reconcile_target_env_with_live_storage(
                base,
                target,
                env_existed_before,
                env_content_before,
            )
        except Exception as env_rb:
            mark(
                "FAIL",
                f"TARGET_ENV_RECONCILIATION_INCOMPLETA: "
                f"{type(env_rb).__name__}: {env_rb}",
            )
        raise


def main() -> int:
    global FINGERPRINT_TIMEOUT, COPY_TIMEOUT

    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=("check", "apply"))
    ap.add_argument("--target")
    ap.add_argument("--bacula-dir", default=str(Path(__file__).resolve().parent))
    ap.add_argument(
        "--fingerprint-timeout",
        type=int,
        default=1800,
        help="timeout por fingerprint SHA-256 em segundos (default: 1800)",
    )
    ap.add_argument(
        "--copy-timeout",
        type=int,
        default=3600,
        help="timeout por cópia de mídia em segundos (default: 3600)",
    )
    ap.add_argument(
        "--evidence-dir",
        default=os.environ.get(
            "CONECTAEDUCA_EVIDENCE_DIR", "/var/tmp/conectaeduca-evidencias"
        ),
    )
    args = ap.parse_args()

    if not 300 <= args.fingerprint_timeout <= 21600:
        ap.error("--fingerprint-timeout deve ficar entre 300 e 21600 segundos")
    if not 600 <= args.copy_timeout <= 43200:
        ap.error("--copy-timeout deve ficar entre 600 e 43200 segundos")
    FINGERPRINT_TIMEOUT = args.fingerprint_timeout
    COPY_TIMEOUT = args.copy_timeout

    # Rejeita root antes de criar evidence-dir, lock ou qualquer outro
    # artefato persistente. O helper foi desenhado para usuário comum com
    # sudo pontual somente nas operações privilegiadas.
    if os.geteuid() == 0:
        print(
            "ERRO: execute como usuário comum; sudo será pontual",
            file=sys.stderr,
            flush=True,
        )
        return 2

    base = Path(args.bacula_dir).resolve()
    target_raw = args.target or os.environ.get(TARGET_ENV_KEY) or DEFAULT_TARGET
    target = Path(target_raw)

    outdir = Path(args.evidence_dir).expanduser()
    outdir.mkdir(parents=True, exist_ok=True)
    now = dt.datetime.now(dt.timezone.utc)
    stamp = now.strftime("%Y%m%d-%H%M%S-%fZ")
    run_id = f"{stamp}-pid{os.getpid()}"
    report = (
        outdir
        / f"conectaeduca-bacula-storage-emulado-migracao-{args.mode}-{run_id}.txt"
    )

    buf = io.StringIO()

    class Tee(io.TextIOBase):
        def write(self, s: str) -> int:
            sys.__stdout__.write(s)
            sys.__stdout__.flush()
            buf.write(s)
            return len(s)

        def flush(self) -> None:
            sys.__stdout__.flush()
            buf.flush()

    old = sys.stdout
    sys.stdout = Tee()
    rc = 0
    try:
        emit("=== CONECTAEDUCA BACULA STORAGE EMULADO — MIGRAÇÃO FAIL-CLOSED ===")
        emit(f"VERSION={VERSION}")
        emit(f"MODE={args.mode}")
        emit(f"EVIDENCE_RUN_ID={run_id}")
        emit(f"BACULA_DIR={base}")
        emit(f"TARGET_INPUT={target_raw}")
        emit(f"FINGERPRINT_TIMEOUT_SECONDS={FINGERPRINT_TIMEOUT}")
        emit(f"COPY_TIMEOUT_SECONDS={COPY_TIMEOUT}")
        emit(f"CAPACITY_RESERVE_BYTES={CAPACITY_RESERVE_BYTES}")
        emit(f"UTC={dt.datetime.now(dt.timezone.utc).isoformat()}")

        # O lock é adquirido antes de ler estado persistido e antes de qualquer
        # preflight/runtime inspection. Ele permanece retido durante execute(),
        # inclusive por toda a lógica de sucesso e rollback.
        with host_migration_lock(args.mode):
            persisted_default = parse_persisted_target(base)
            target_raw = (
                args.target
                or os.environ.get(TARGET_ENV_KEY)
                or (
                    str(persisted_default)
                    if persisted_default is not None
                    else DEFAULT_TARGET
                )
            )
            target = Path(target_raw)
            emit(f"TARGET_INPUT_LOCKED={target_raw}")

            validate_target_literal(target_raw)
            if not target.is_absolute():
                raise RuntimeError(
                    "TARGET deve ser caminho absoluto; "
                    f"valor relativo rejeitado: {target_raw}"
                )
            target = target.resolve()
            emit(f"TARGET={target}")

            rc = execute(args.mode, base, target)
    except Exception as exc:
        mark("FAIL", f"{type(exc).__name__}: {exc}")
        summary(args.mode, target, "FAILED")
        rc = 1
    finally:
        sys.stdout = old

    # O run_id contém microssegundos + PID. Abrir com modo exclusivo impede
    # sobrescrita silenciosa mesmo em uma colisão improvável.
    with report.open("x", encoding="utf-8") as fh:
        fh.write(buf.getvalue())
    digest = hashlib.sha256(report.read_bytes()).hexdigest()
    sha_file = report.with_suffix(report.suffix + ".sha256")
    sha_file.write_text(f"{digest}  {report.name}\n", encoding="utf-8")
    print(f"EVIDENCE={report}")
    print(f"EVIDENCE_SHA256={digest}")
    print(f"EVIDENCE_SHA256_FILE={sha_file}")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())