#!/usr/bin/env python3
"""Precheck somente leitura para o Bacularis na EP126.

Não instala pacotes, não lê credenciais e não altera Git, Bacula ou Docker.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import shlex
import shutil
import socket
import subprocess
from pathlib import Path

VERSION = "1.0.0"
PASS = WARN = FAIL = 0
LOG: list[str] = []


def emit(message: str = "") -> None:
    print(message, flush=True)
    LOG.append(message)


def passed(message: str) -> None:
    global PASS
    PASS += 1
    emit(f"[PASS] {message}")


def warned(message: str) -> None:
    global WARN
    WARN += 1
    emit(f"[WARN] {message}")


def failed(message: str) -> None:
    global FAIL
    FAIL += 1
    emit(f"[FAIL] {message}")


def run(argv: list[str]) -> subprocess.CompletedProcess[str]:
    emit("[CMD] " + " ".join(shlex.quote(part) for part in argv))
    proc = subprocess.run(
        argv,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    emit(f"[RC] {proc.returncode}")
    return proc


def os_release() -> dict[str, str]:
    values: dict[str, str] = {}
    for line in Path("/etc/os-release").read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value.strip().strip('"')
    return values


def inspect_container(name: str) -> dict[str, object] | None:
    proc = run(["docker", "inspect", name])
    if proc.returncode:
        return None
    try:
        return json.loads(proc.stdout)[0]
    except (IndexError, TypeError, json.JSONDecodeError):
        return None


def tcp_open(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(1.0)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def apt_candidate(package: str) -> str:
    proc = run(["apt-cache", "policy", package])
    if proc.returncode:
        return "ERROR"
    for line in proc.stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("Candidate:"):
            value = stripped.split(":", 1)[1].strip()
            return "NONE" if value == "(none)" else value
    return "NONE"


def write_evidence(directory: Path) -> tuple[Path, Path, str]:
    directory = directory.expanduser().resolve()
    directory.mkdir(parents=True, exist_ok=True)
    host = socket.gethostname().split(".")[0]
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%SZ")
    report = directory / f"conectaeduca-gui01b-precheck-{host}-{stamp}-pid{os.getpid()}.txt"
    report.write_text("\n".join(LOG) + "\n", encoding="utf-8")
    os.chmod(report, 0o644)
    digest = hashlib.sha256(report.read_bytes()).hexdigest()
    checksum = Path(str(report) + ".sha256")
    checksum.write_text(f"{digest}  {report.name}\n", encoding="utf-8")
    os.chmod(checksum, 0o644)
    return report, checksum, digest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-dir", type=Path, default=Path.home())
    args = parser.parse_args()

    emit("=== GUI-01B PRECHECK ===")
    emit(f"VERSION={VERSION}")
    emit("MODE=READ_ONLY")
    emit("RUNTIME_CHANGED=0")
    emit("GIT_CHANGED=0")

    try:
        release = os_release()
        if release.get("ID") == "ubuntu" and release.get("VERSION_ID") == "24.04":
            passed("EP126/Ubuntu 24.04 confirmada.")
        else:
            failed("Host não corresponde à EP126/Ubuntu 24.04 esperada.")
    except OSError as exc:
        failed(f"Não foi possível ler /etc/os-release: {exc}")

    binaries = (
        ("docker", "DOCKER"),
        ("git", "GIT"),
        ("bconsole", "BCONSOLE"),
        ("apt-cache", "APT_CACHE"),
        ("gpg", "GPG"),
        ("wget", "WGET"),
        ("curl", "CURL"),
    )
    for binary, label in binaries:
        location = shutil.which(binary)
        emit(f"BINARY_{label}={location or 'ABSENT'}")
        passed(f"{binary} disponível.") if location else failed(f"{binary} ausente.")

    if shutil.which("docker"):
        for name in ("conectaeduca-bacula-director", "conectaeduca-bacula-catalog"):
            obj = inspect_container(name)
            if obj is None:
                failed(f"{name} não encontrado ou inspect inválido.")
                continue
            state = obj.get("State") or {}
            status = state.get("Status")
            health = (state.get("Health") or {}).get("Status", "n/a")
            restarts = obj.get("RestartCount", 0)
            emit(f"CONTAINER={name}|state={status}|health={health}|restart_count={restarts}")
            if status == "running" and health in {"healthy", "n/a"}:
                passed(f"{name} running.")
            else:
                failed(f"{name} não está running/healthy.")

    loopback = {port: tcp_open(port) for port in (9097, 9101, 15432)}
    for port, is_open in loopback.items():
        emit(f"LOOPBACK_{port}={'OPEN' if is_open else 'CLOSED'}")
    passed("Director responde em loopback.") if loopback[9101] else failed(
        "Director não responde em 127.0.0.1:9101."
    )
    passed("9097 disponível.") if not loopback[9097] else failed(
        "127.0.0.1:9097 já está em uso."
    )
    passed("15432 disponível.") if not loopback[15432] else failed(
        "127.0.0.1:15432 já está em uso."
    )

    if shutil.which("apt-cache"):
        emit(f"APT_BACULARIS={apt_candidate('bacularis')}")
        emit(f"APT_BACULARIS_NGINX={apt_candidate('bacularis-nginx')}")

    if FAIL == 0:
        passed("Precheck concluído sem alterações.")
    else:
        warned("Precheck concluído com falhas; não autorizar APPLY.")

    final = "FAIL" if FAIL else ("WARN" if WARN else "PASS")
    emit("")
    emit("=== SUMMARY ===")
    emit(f"PASS={PASS}")
    emit(f"WARN={WARN}")
    emit(f"FAIL={FAIL}")
    emit(f"FINAL={final}")
    emit("SECRET_VALUES_LOGGED=0")
    emit("ROOT_SHELL_USED=0")
    emit("APPLY_AUTHORIZED=0")

    report, checksum, digest = write_evidence(args.evidence_dir)
    print(f"EVIDENCE_FILE={report}")
    print(f"SHA256={digest}")
    print(f"SHA256_FILE={checksum}")
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
