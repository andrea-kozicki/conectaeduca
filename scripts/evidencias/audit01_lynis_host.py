#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import os
import pwd
import re
import shutil
import socket
import subprocess
from pathlib import Path

HOST = socket.gethostname()
UTC = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%SZ")
TEST_ID_RE = re.compile(r"\b(?:[A-Z]{3,8}-[0-9]{4}|LYNIS)\b")
FINAL_CLASSES = {"APLICAVEL", "JA_MITIGADO", "N_A_LAB", "RISCO_ACEITO"}


def run(cmd: list[str], timeout: int = 7200) -> tuple[int, str, str]:
    try:
        p = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
        return p.returncode, p.stdout, p.stderr
    except FileNotFoundError:
        return 127, "", f"command not found: {cmd[0]}"
    except subprocess.TimeoutExpired:
        return 124, "", f"timeout after {timeout}s: {cmd[0]}"


def operator_identity() -> tuple[str, int, int, Path]:
    if os.geteuid() == 0:
        sudo_uid_raw = os.environ.get("SUDO_UID", "")
        if not sudo_uid_raw.isdecimal():
            raise SystemExit(
                "FALHA: execute --run com sudo one-shot a partir da conta normal; "
                "SUDO_UID ausente/invalido."
            )
        sudo_uid = int(sudo_uid_raw, 10)
        if sudo_uid <= 0:
            raise SystemExit(
                "FALHA: execute --run com sudo one-shot a partir da conta normal; "
                "nao use root shell."
            )
        entry = pwd.getpwuid(sudo_uid)
    else:
        entry = pwd.getpwuid(os.geteuid())

    home = Path(entry.pw_dir).resolve()
    if not home.is_absolute() or home == Path("/"):
        raise SystemExit("FALHA: HOME do operador invalido")
    return entry.pw_name, entry.pw_uid, entry.pw_gid, home


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_report(report: Path) -> tuple[list[dict[str, str]], str | None]:
    findings: list[dict[str, str]] = []
    hardening_index: str | None = None

    for raw in report.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()

        if key == "hardening_index":
            hardening_index = value

        if key not in {"warning[]", "suggestion[]"}:
            continue

        match = TEST_ID_RE.search(value)
        findings.append(
            {
                "type": "WARNING" if key == "warning[]" else "SUGGESTION",
                "test_id": match.group(0) if match else "UNKNOWN",
                "message": value.replace("\t", " ").replace("\r", " "),
                "classification": "PENDENTE_REVISAO",
                "justification": "",
                "action": "",
            }
        )

    return findings, hardening_index


def spreadsheet_safe(value: object) -> str:
    """Neutraliza células que poderiam ser interpretadas como fórmula."""
    text = str(value)
    if text and text[0] in ("=", "+", "-", "@", "\t", "\r"):
        return "'" + text
    return text


def write_triage(path: Path, findings: list[dict[str, str]]) -> None:
    headers = [
        "TYPE",
        "TEST_ID",
        "MESSAGE",
        "CLASSIFICACAO",
        "JUSTIFICATIVA",
        "ACAO",
    ]
    with path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(
            fh,
            delimiter="\t",
            lineterminator="\n",
            quoting=csv.QUOTE_ALL,
        )
        writer.writerow([spreadsheet_safe(value) for value in headers])
        for item in findings:
            writer.writerow(
                [
                    spreadsheet_safe(value)
                    for value in [
                        item["type"],
                        item["test_id"],
                        item["message"],
                        item["classification"],
                        item["justification"],
                        item["action"],
                    ]
                ]
            )


def secure_fd(path: Path, *, directory: bool = False) -> int:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    if directory:
        flags |= getattr(os, "O_DIRECTORY", 0)
    return os.open(path, flags)


def chown_chmod(path: Path, uid: int, gid: int, mode: int = 0o600) -> None:
    fd = secure_fd(path, directory=path.is_dir())
    try:
        os.fchown(fd, uid, gid)
        os.fchmod(fd, mode)
    finally:
        os.close(fd)


def write_private_text(path: Path, text: str, mode: int = 0o600) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    flags |= getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags, mode)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        os.fchmod(fh.fileno(), mode)
        fh.write(text)


def precheck() -> int:
    lynis = shutil.which("lynis")
    print("=== AUDIT-01 LYNIS PRECHECK ===")
    print(f"host={HOST}")
    print(f"user={pwd.getpwuid(os.geteuid()).pw_name}")
    print(f"euid={os.geteuid()}")
    print("mode=READ_ONLY_PRECHECK")
    print(f"lynis={lynis or 'MISSING'}")

    if not lynis:
        print("AUDIT01_PRECHECK=BLOCK")
        print("NEXT=instalar Lynis antes do corte de sudo")
        return 2

    rc, out, err = run([lynis, "show", "version"], timeout=30)
    compact = " ".join((out or err).split())
    print(f"LYNIS_VERSION_RC={rc}")
    print(f"LYNIS_VERSION={compact[:500]}")
    print("AUDIT01_PRECHECK=PASS" if rc == 0 else "AUDIT01_PRECHECK=WARN")
    return 0 if rc == 0 else 1


def execute() -> int:
    if os.geteuid() != 0:
        raise SystemExit(
            "FALHA: --run precisa de sudo one-shot para a cobertura completa do Lynis."
        )

    operator, uid, gid, home = operator_identity()
    lynis = shutil.which("lynis")
    if not lynis:
        raise SystemExit("FALHA: Lynis nao encontrado no PATH do sudo.")

    evidence = home / f"conectaeduca-audit01-lynis-{HOST}-{UTC}"
    if evidence.exists():
        raise SystemExit(f"FALHA: diretorio de evidencia ja existe: {evidence}")

    evidence.mkdir(mode=0o700)
    chown_chmod(evidence, uid, gid, 0o700)

    screen = evidence / "lynis-screen.txt"
    log_file = evidence / "lynis.log"
    report_file = evidence / "lynis-report.dat"
    triage = evidence / "TRIAGEM-LYNIS.tsv"
    summary = evidence / "RESUMO-AUDIT01.txt"
    sums = evidence / "SHA256SUMS-RAW"

    cmd = [
        lynis,
        "audit",
        "system",
        "--quick",
        "--no-colors",
        "--auditor",
        "ConectaEduca AUDIT-01",
        "--log-file",
        str(log_file),
        "--report-file",
        str(report_file),
    ]

    rc, out, err = run(cmd)
    screen.write_text(
        "COMMAND=" + " ".join(cmd) + "\n"
        + f"RC={rc}\n"
        + "--- STDOUT ---\n"
        + out
        + "\n--- STDERR ---\n"
        + err,
        encoding="utf-8",
    )

    for path in (screen, log_file, report_file):
        if path.exists():
            chown_chmod(path, uid, gid)

    if not report_file.exists():
        summary.write_text(
            f"AUDIT01_STATUS=BLOCK\nHOST={HOST}\nLYNIS_RC={rc}\n"
            "REASON=report_file_missing\n",
            encoding="utf-8",
        )
        chown_chmod(summary, uid, gid)
        raise SystemExit(
            f"FALHA: Lynis nao produziu {report_file}; consulte {screen}"
        )

    findings, hardening_index = parse_report(report_file)
    write_triage(triage, findings)
    chown_chmod(triage, uid, gid)

    warnings = sum(1 for item in findings if item["type"] == "WARNING")
    suggestions = sum(1 for item in findings if item["type"] == "SUGGESTION")

    summary.write_text(
        "\n".join(
            [
                "=== CONECTAEDUCA AUDIT-01 LYNIS ===",
                f"HOST={HOST}",
                f"UTC={UTC}",
                f"OPERATOR={operator}",
                f"LYNIS_RC={rc}",
                f"HARDENING_INDEX={hardening_index or 'UNKNOWN'}",
                f"WARNINGS={warnings}",
                f"SUGGESTIONS={suggestions}",
                f"FINDINGS_TOTAL={len(findings)}",
                "AUTO_REMEDIATION=NO",
                "TRIAGE_REQUIRED=YES",
                "CLASSIFICATIONS=APLICAVEL|JA_MITIGADO|N_A_LAB|RISCO_ACEITO",
                f"EVIDENCE_DIR={evidence}",
                "AUDIT01_RAW_COLLECTION=PASS" if rc == 0 else "AUDIT01_RAW_COLLECTION=WARN",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    chown_chmod(summary, uid, gid)

    # TRIAGEM-LYNIS.tsv é intencionalmente editável após a coleta e portanto
    # não entra no manifesto RAW. O modo --finalize gera o manifesto final.
    evidence_files = [
        p for p in (screen, log_file, report_file, summary) if p.exists()
    ]
    sums.write_text(
        "".join(f"{sha256(path)}  {path.name}\n" for path in evidence_files),
        encoding="utf-8",
    )
    chown_chmod(sums, uid, gid)

    print(summary.read_text(encoding="utf-8"), end="")
    print(f"SHA256SUMS_RAW={sums}")
    print("NEXT=preencher TRIAGEM-LYNIS.tsv e executar --finalize no diretorio")
    return 0 if rc == 0 else 1


def finalize(evidence: Path) -> int:
    if os.geteuid() == 0:
        raise SystemExit("FALHA: --finalize deve ser executado como usuario normal")

    evidence = evidence.expanduser().resolve()
    home = Path.home().resolve()
    try:
        evidence.relative_to(home)
    except ValueError:
        raise SystemExit("FALHA: evidence-dir precisa estar dentro do HOME do operador")

    required = {
        "screen": evidence / "lynis-screen.txt",
        "log": evidence / "lynis.log",
        "report": evidence / "lynis-report.dat",
        "triage": evidence / "TRIAGEM-LYNIS.tsv",
        "summary": evidence / "RESUMO-AUDIT01.txt",
        "raw_sums": evidence / "SHA256SUMS-RAW",
    }
    missing = [name for name, path in required.items() if not path.is_file()]
    if missing:
        raise SystemExit("FALHA: arquivos obrigatorios ausentes: " + ",".join(missing))

    with required["triage"].open("r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        expected = [
            "TYPE", "TEST_ID", "MESSAGE", "CLASSIFICACAO", "JUSTIFICATIVA", "ACAO"
        ]
        if reader.fieldnames != expected:
            raise SystemExit("FALHA: cabecalho TRIAGEM-LYNIS.tsv inesperado")
        rows = list(reader)

    invalid: list[str] = []
    counts = {name: 0 for name in sorted(FINAL_CLASSES)}
    for idx, row in enumerate(rows, start=2):
        classification = (row.get("CLASSIFICACAO") or "").strip()
        justification = (row.get("JUSTIFICATIVA") or "").strip()
        action = (row.get("ACAO") or "").strip()

        if classification not in FINAL_CLASSES:
            invalid.append(f"linha {idx}: CLASSIFICACAO={classification or '<vazia>'}")
            continue
        counts[classification] += 1

        if not justification:
            invalid.append(f"linha {idx}: JUSTIFICATIVA vazia")
        if classification in {"APLICAVEL", "RISCO_ACEITO"} and not action:
            invalid.append(f"linha {idx}: ACAO obrigatoria para {classification}")

    if invalid:
        for item in invalid:
            print(f"FALHA       {item}")
        print(f"AUDIT01_TRIAGE=BLOCK invalid={len(invalid)}")
        return 2

    triage_summary = evidence / "RESUMO-TRIAGEM-AUDIT01.txt"
    write_private_text(
        triage_summary,
        "\n".join(
            [
                "=== CONECTAEDUCA AUDIT-01 TRIAGEM FINAL ===",
                f"HOST={HOST}",
                f"UTC_FINALIZE={UTC}",
                f"FINDINGS_TOTAL={len(rows)}",
                *(f"{name}={counts[name]}" for name in sorted(counts)),
                "PENDENTE_REVISAO=0",
                "AUDIT01_TRIAGE=PASS",
            ]
        ) + "\n",
    )

    final_manifest = evidence / "SHA256SUMS-FINAL"
    final_files = [
        required["screen"],
        required["log"],
        required["report"],
        required["summary"],
        required["triage"],
        required["raw_sums"],
        triage_summary,
    ]
    write_private_text(
        final_manifest,
        "".join(f"{sha256(path)}  {path.name}\n" for path in final_files),
    )

    print(f"AUDIT01_TRIAGE=PASS findings={len(rows)}")
    print(f"SHA256SUMS_FINAL={final_manifest}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Coleta controlada AUDIT-01/Lynis para EP125/EP126."
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--precheck", action="store_true")
    mode.add_argument("--run", action="store_true")
    mode.add_argument("--finalize", metavar="EVIDENCE_DIR")
    args = parser.parse_args()

    if args.precheck:
        return precheck()
    if args.finalize:
        return finalize(Path(args.finalize))
    return execute()


if __name__ == "__main__":
    raise SystemExit(main())
