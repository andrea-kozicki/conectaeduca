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
- proteger somente os ancestrais de TARGET criados pela própria migração;\n- rejeitar symlinks, ancestrais não-root/graváveis e races em toda a cadeia;\n- exigir barreira root:root 0700 no parent final do TARGET;\n- não converter job agendado pós-restart em rollback; rollback só muta Storage com quiescência comprovada;\n- reconciliar env-file com o mount /backup realmente ativo após qualquer falha;
- gerar evidência textual + SHA-256.

Não fornece isolamento físico/disaster recovery. O destino padrão continua no
mesmo host e pode continuar no mesmo filesystem da VM.
"""
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import time
from typing import Any

VERSION = "2.0.1"
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


def sudo(argv: list[str], **kwargs: Any) -> tuple[int, str]:
    return run(["sudo", *argv], **kwargs)


def sudo_storage_path(target: Path, argv: list[str], **kwargs: Any) -> tuple[int, str]:
    """Executa Compose privilegiado com o path explicitamente após sudo."""
    assignment = f"{TARGET_ENV_KEY}={target}"
    return run(["sudo", "env", assignment, *argv], **kwargs)


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
    """Falha antes de parar serviços se a cópia puder esgotar o filesystem."""
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
    mark("PASS", "Capacidade do filesystem aprovada antes de parar Director/Storage.")


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
    # SAFE_TARGET_RE rejeita aspas, 'def output_no_jobs(out: str) -> bool:
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


def query_director(base: Path, files: list[Path], show: bool = True) -> tuple[int, str]:
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
            input_text="status director\nquit\n",
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
        input_text="status director\nquit\n",
        show=show,
        timeout=90,
    )


def require_no_jobs(base: Path, files: list[Path]) -> None:
    rc, out = query_director(base, files)
    if rc != 0 or not output_no_jobs(out):
        raise RuntimeError("não foi possível provar 'No Jobs running'; operação bloqueada")
    mark("PASS", "Director confirmou No Jobs running.")


def require_director_functional(base: Path, files: list[Path]) -> None:
    """Prova conectividade/consulta do Director sem exigir ausência de jobs."""
    rc, out = query_director(base, files)
    if rc != 0:
        raise RuntimeError("Director não respondeu ao bconsole após ativação")
    if not re.search(r"Director|Running Jobs|Scheduled Jobs|No Jobs running", out, re.I):
        raise RuntimeError("resposta do Director não contém marcadores funcionais esperados")
    mark("PASS", "Director respondeu funcionalmente ao bconsole após ativação.")


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


def find_legacy_source(storage_ins: dict[str, Any]) -> tuple[str | None, Path | None, str]:
    m = backup_mount(storage_ins)
    if not m:
        raise RuntimeError("mount /backup ausente no Storage")
    typ = str(m.get("Type") or "")
    if typ == "volume":
        name = str(m.get("Name") or "")
        src = Path(str(m.get("Source") or ""))
        if not name or not src.is_absolute():
            raise RuntimeError("named volume /backup sem Name/Source válidos")
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

    for cmd in ("docker", "sudo", "python3"):
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

    volume_name, source, kind = find_legacy_source(storage)
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

    director_stopped = False
    storage_stopped = False
    try:
        run(
            ["docker", "stop", "-t", str(STOP_TIMEOUT), DIRECTOR],
            timeout=STOP_TIMEOUT + 20,
            check=True,
        )
        director_stopped = True
        mark("PASS", "Director parado; novos jobs bloqueados.")

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
            sudo(
                ["cp", "-a", str(source) + "/.", str(target) + "/"],
                timeout=COPY_TIMEOUT,
                check=True,
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
                sudo(
                    ["cp", "-a", str(source) + "/.", str(target) + "/"],
                    timeout=COPY_TIMEOUT,
                    check=True,
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
                    require_no_jobs(base, files)
                except Exception as active_jobs:
                    rollback_safe = False
                    mark(
                        "FAIL",
                        "ROLLBACK_BLOQUEADO_JOBS_ATIVOS: Director está funcional "
                        "mas não foi possível provar ausência de jobs; Storage não será recriado.",
                    )
                    emit(f"ROLLBACK_BLOCK_REASON={type(active_jobs).__name__}")
                if rollback_safe:
                    run(
                        ["docker", "stop", "-t", str(STOP_TIMEOUT), DIRECTOR],
                        timeout=STOP_TIMEOUT + 20,
                        check=True,
                    )
                    director_stopped = True
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

    base = Path(args.bacula_dir).resolve()
    persisted_default = parse_persisted_target(base)
    target_raw = (
        args.target
        or os.environ.get(TARGET_ENV_KEY)
        or (str(persisted_default) if persisted_default is not None else DEFAULT_TARGET)
    )
    target = Path(target_raw)

    outdir = Path(args.evidence_dir).expanduser()
    outdir.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%SZ")
    report = outdir / f"conectaeduca-bacula-storage-emulado-migracao-{args.mode}-{stamp}.txt"

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
        emit(f"BACULA_DIR={base}")
        emit(f"TARGET_INPUT={target_raw}")
        emit(f"FINGERPRINT_TIMEOUT_SECONDS={FINGERPRINT_TIMEOUT}")
        emit(f"COPY_TIMEOUT_SECONDS={COPY_TIMEOUT}")
        emit(f"CAPACITY_RESERVE_BYTES={CAPACITY_RESERVE_BYTES}")
        emit(f"UTC={dt.datetime.now(dt.timezone.utc).isoformat()}")

        validate_target_literal(target_raw)
        if not target.is_absolute():
            raise RuntimeError(
                f"TARGET deve ser caminho absoluto; valor relativo rejeitado: {target_raw}"
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

    report.write_text(buf.getvalue(), encoding="utf-8")
    digest = hashlib.sha256(report.read_bytes()).hexdigest()
    sha_file = report.with_suffix(report.suffix + ".sha256")
    sha_file.write_text(f"{digest}  {report.name}\n", encoding="utf-8")
    print(f"EVIDENCE={report}")
    print(f"EVIDENCE_SHA256={digest}")
    print(f"EVIDENCE_SHA256_FILE={sha_file}")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
