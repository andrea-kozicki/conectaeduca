#!/usr/bin/env python3
from __future__ import annotations

import ast
import datetime as dt
import hashlib
import os
import re
import subprocess
from pathlib import Path

UTC = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%SZ")

PASS = 0
WARN = 0
FAIL = 0


def run(cmd: list[str], cwd: Path | None = None) -> tuple[int, str, str]:
    p = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    return p.returncode, p.stdout.rstrip(), p.stderr.rstrip()


def emit(line: str = "") -> None:
    print(line)


def passed(msg: str) -> None:
    global PASS
    PASS += 1
    emit(f"[PASS] {msg}")


def warn(msg: str) -> None:
    global WARN
    WARN += 1
    emit(f"[WARN] {msg}")


def fail(msg: str) -> None:
    global FAIL
    FAIL += 1
    emit(f"[FAIL] {msg}")


rc, root_out, _ = run(["git", "rev-parse", "--show-toplevel"])
if rc != 0:
    raise SystemExit("ERROR: execute dentro do repositorio Git")

ROOT = Path(root_out).resolve()
REPORT = Path.home() / f"conectaeduca-prefreeze-repo-gate-{UTC}.txt"

lines: list[str] = []


def capture(line: str = "") -> None:
    lines.append(line)
    emit(line)


def p2(msg: str) -> None:
    global PASS
    PASS += 1
    capture(f"[PASS] {msg}")


def w2(msg: str) -> None:
    global WARN
    WARN += 1
    capture(f"[WARN] {msg}")


def f2(msg: str) -> None:
    global FAIL
    FAIL += 1
    capture(f"[FAIL] {msg}")


capture("=== CONECTAEDUCA PREFREEZE REPO GATE ===")
capture(f"utc={UTC}")
capture(f"root={ROOT}")
capture("mode=READ_ONLY_REPOSITORY_CHECK")
capture("runtime_vm_changes=0")
capture("sudo_used=0")
capture("docker_used=0")

required = [
    "docs/BACKLOG-TECNICO.md",
    "docs/plano-testes.md",
    "docs/release/HANDOFF-FINAL.md",
    "docs/release/RETOMADA-VM-20260924.md",
    "docs/release/ROTEIRO-DEMONSTRACAO-FINAL.md",
    "docs/release/INDICE-EVIDENCIAS-FINAIS.md",
    "docs/release/CHECKLIST-FECHAMENTO-ACADEMICO.md",
    "docs/seguranca/MITRE-ATTACK-MATRIZ-FINAL.md",
    "docs/seguranca/PENTEST-SEM-SUDO.md",
    "docs/seguranca/PENTEST-S01-S13-ZERO-SUDO.md",
    "deploy/interna/mariadb/PHPMYADMIN-READONLY.md",
    "scripts/evidencias/gui01c_phpmyadmin_precheck.py",
    "scripts/evidencias/pentest_no_sudo_readiness.py",
    "scripts/evidencias/pentest_sem_sudo_runtime_check.py",
]

capture()
capture("=== REQUIRED ARTIFACTS ===")
for rel in required:
    path = ROOT / rel
    if path.is_file():
        p2(rel)
    else:
        f2(f"missing: {rel}")

capture()
capture("=== GIT STATE ===")
rc, branch, _ = run(["git", "branch", "--show-current"], ROOT)
capture(f"branch={branch if rc == 0 else 'unknown'}")
if branch == "main":
    p2("branch main")
else:
    w2("gate final deve ser repetido na main")

rc, dirty, _ = run(["git", "status", "--short"], ROOT)
if rc == 0 and not dirty.strip():
    p2("working tree clean")
else:
    f2("working tree possui alteracoes nao commitadas")

rc, head, _ = run(["git", "rev-parse", "HEAD"], ROOT)
capture(f"head={head if rc == 0 else 'unknown'}")

capture()
capture("=== TRACKED SECRET-LIKE PATHS ===")
rc, tracked_out, _ = run(["git", "ls-files"], ROOT)
tracked = [x.strip() for x in tracked_out.splitlines() if x.strip()] if rc == 0 else []

blockers: list[str] = []
warnings: list[str] = []
for rel in tracked:
    low = rel.lower()
    parts = Path(rel).parts
    base = Path(rel).name.lower()

    if ".runtime" in parts:
        blockers.append(rel)
        continue
    if base == ".env":
        blockers.append(rel)
        continue
    if base in {"secret-id", "role-id", "root-token", "unseal-share", "recovery-share"}:
        blockers.append(rel)
        continue
    if base.endswith((".p12", ".pfx", ".jks", ".kdbx")):
        blockers.append(rel)
        continue
    if base.endswith(".key"):
        warnings.append(rel)

if blockers:
    for rel in blockers:
        f2(f"arquivo sensivel rastreado: {rel}")
else:
    p2("nenhum path sensivel proibido detectado no indice Git")

for rel in warnings:
    w2(f"revisar key-like file rastreado: {rel}")

capture()
capture("=== CONFLICT MARKERS ===")
text_ext = {
    ".md", ".txt", ".py", ".sh", ".bash", ".fish", ".yml", ".yaml", ".json",
    ".php", ".ini", ".conf", ".sql", ".toml", ".xml", ".env", ".example",
}
conflicts: list[str] = []
pattern = re.compile(r"^(<<<<<<< |=======|>>>>>>> )", re.MULTILINE)

for rel in tracked:
    path = ROOT / rel
    if not path.is_file():
        continue
    if path.suffix.lower() not in text_ext and path.name not in {"Dockerfile", "Makefile"}:
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    if pattern.search(text):
        conflicts.append(rel)

if conflicts:
    for rel in conflicts:
        f2(f"merge conflict marker: {rel}")
else:
    p2("sem marcadores de conflito em arquivos texto rastreados")

capture()
capture("=== PYTHON SYNTAX ===")
python_files = [
    "scripts/evidencias/gui01c_phpmyadmin_precheck.py",
    "scripts/evidencias/pentest_no_sudo_readiness.py",
    "scripts/evidencias/pentest_sem_sudo_runtime_check.py",
    "scripts/evidencias/prefreeze_repo_gate.py",
]
for rel in python_files:
    path = ROOT / rel
    if not path.is_file():
        f2(f"python ausente: {rel}")
        continue
    try:
        source = path.read_text(encoding="utf-8")
        ast.parse(source, filename=rel)
        p2(f"syntax: {rel}")
    except (SyntaxError, UnicodeDecodeError, OSError) as exc:
        f2(f"syntax: {rel}: {exc}")

capture()
capture("=== CANONICAL CONTENT ===")
checks = {
    "docs/BACKLOG-TECNICO.md": [
        "### HOST-01",
        "### BAC-04",
        "### GUI-01C",
        "### PENTEST-00",
        "### FREEZE-01",
    ],
    "docs/seguranca/PENTEST-S01-S13-ZERO-SUDO.md": [
        "**S01**", "**S02**", "**S03**", "**S04**", "**S05**", "**S06**",
        "**S07**", "**S08**", "**S09**", "**S10**", "**S11**", "**S12**", "**S13**",
    ],
    "docs/seguranca/PENTEST-SEM-SUDO.md": [
        "zero dependência de sudo/root",
        "pentest_sem_sudo_runtime_check.py",
    ],
}
for rel, tokens in checks.items():
    path = ROOT / rel
    if not path.is_file():
        continue
    text = path.read_text(encoding="utf-8")
    missing = [token for token in tokens if token not in text]
    if missing:
        f2(f"{rel}: tokens ausentes: {missing}")
    else:
        p2(f"conteudo canonico presente: {rel}")

capture()
capture("=== BACKLOG DONE CONSISTENCY ===")
backlog_path = ROOT / "docs/BACKLOG-TECNICO.md"
if backlog_path.is_file():
    text = backlog_path.read_text(encoding="utf-8")
    sections = re.split(r"(?=^### )", text, flags=re.MULTILINE)
    contradictions: list[str] = []
    for section in sections:
        if "**Estado:** DONE" not in section:
            continue
        title = section.splitlines()[0] if section.splitlines() else "unknown"
        suspicious = [
            line.strip() for line in section.splitlines()
            if re.search(r"\b(ainda|permanece|pendente|decisao necessaria)\b", line, re.IGNORECASE)
            and "reabrir" not in line.lower()
            and "nao devem" not in line.lower()
        ]
        if suspicious:
            contradictions.append(title + " -> " + " | ".join(suspicious[:3]))
    if contradictions:
        for item in contradictions:
            w2(f"revisar DONE possivelmente contraditorio: {item}")
    else:
        p2("itens DONE sem linguagem pendente obvia")

capture()
capture("=== SUMMARY ===")
capture(f"PASS={PASS}")
capture(f"WARN={WARN}")
capture(f"FAIL={FAIL}")
capture(f"PREFREEZE_REPO_READY={'YES' if FAIL == 0 else 'NO'}")
capture("runtime_vm_changes=0")
capture("sudo_used=0")
capture("docker_used=0")

REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
digest = hashlib.sha256(REPORT.read_bytes()).hexdigest()
sha_path = Path(str(REPORT) + ".sha256")
sha_path.write_text(f"{digest}  {REPORT.name}\n", encoding="utf-8")
emit(f"REPORT={REPORT}")
emit(f"SHA256={digest}")
emit(f"SHA256_FILE={sha_path}")

raise SystemExit(0 if FAIL == 0 else 2)
