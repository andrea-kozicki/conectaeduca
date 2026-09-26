#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import os
import pwd
import shutil
import socket
import subprocess
import tempfile
from pathlib import Path

UTC = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%SZ")
HOST = socket.gethostname().split(".")[0]

FIELDS = [
    "COMPONENTE",
    "MECANISMO",
    "OBRIGATORIO",
    "STATUS",
    "AUTH_POSITIVA",
    "AUTH_NEGATIVA",
    "MENOR_PRIVILEGIO",
    "EVIDENCIA",
    "JUSTIFICATIVA",
]

TEMPLATES = {
    "ep125": [
        ("linux_pam", "PAM_password", "YES", "PENDENTE", "", "", "", "", ""),
        ("wazuh_agent", "machine_identity", "NO", "N_A", "N_A", "N_A", "PASS", "", "Agent sem login humano; identidade de maquina."),
        ("nginx", "service_account", "NO", "N_A", "N_A", "N_A", "PASS", "", "Daemon sem autenticacao humana propria."),
        ("php_fpm", "service_account", "NO", "N_A", "N_A", "N_A", "PASS", "", "Daemon sem autenticacao humana propria."),
        ("waf", "service_account", "NO", "N_A", "N_A", "N_A", "PASS", "", "Daemon sem autenticacao humana propria."),
    ],
    "ep126": [
        ("linux_pam", "PAM_password", "YES", "PENDENTE", "", "", "", "", ""),
        ("openbao_userpass", "userpass_password", "YES", "PENDENTE", "", "", "", "", ""),
        ("bacularis_web", "web_password", "YES", "PENDENTE", "", "", "", "", ""),
        ("mariadb_phpmyadmin", "sql_web_password", "YES", "PENDENTE", "", "", "", "", ""),
        ("postgresql_pgbouncer", "SCRAM_password", "YES", "PENDENTE", "", "", "", "", ""),
        ("bacula_console", "console_TLS_PSK", "YES", "PENDENTE", "", "", "", "", ""),
        ("wazuh_dashboard", "indexer_password_RBAC", "YES", "PENDENTE", "", "", "", "", ""),
        ("ferret", "service_account_no_human_RBAC", "NO", "N_A", "N_A", "N_A", "PASS", "", "Ferret sem login humano proprio no baseline."),
    ],
}

LOOPBACK_PORTS = {
    "ep125": [],
    "ep126": [18200, 9097, 9443, 6432, 9101, 8443],
}

PRIVILEGED_GROUPS = {"sudo", "wheel", "docker", "lxd", "libvirt"}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_private_text(path: Path, text: str, mode: int = 0o600) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    flags |= getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags, mode)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        os.fchmod(fh.fileno(), mode)
        fh.write(text)


def tcp_open(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.4)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def git_fact() -> tuple[str, str, str]:
    try:
        root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        head = subprocess.check_output(
            ["git", "-C", root, "rev-parse", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        status = subprocess.check_output(
            ["git", "-C", root, "status", "--porcelain=v1"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        return root, head, "YES" if not status else "NO"
    except (OSError, subprocess.CalledProcessError):
        return "UNAVAILABLE", "UNAVAILABLE", "UNAVAILABLE"


def linux_identity() -> dict[str, str]:
    try:
        entry = pwd.getpwnam("teste")
    except KeyError:
        return {"exists": "NO"}

    try:
        groups = subprocess.check_output(
            ["id", "-nG", "teste"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).split()
    except (OSError, subprocess.CalledProcessError):
        groups = []

    privileged = sorted(set(groups) & PRIVILEGED_GROUPS)
    return {
        "exists": "YES",
        "uid": str(entry.pw_uid),
        "gid": str(entry.pw_gid),
        "home": entry.pw_dir,
        "shell": entry.pw_shell,
        "groups": ",".join(groups) if groups else "UNKNOWN",
        "privileged_groups": ",".join(privileged) if privileged else "none",
    }


def write_matrix(path: Path, role: str) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    flags |= getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
        os.fchmod(fh.fileno(), 0o600)
        writer = csv.writer(
            fh,
            delimiter="\t",
            lineterminator="\n",
            quoting=csv.QUOTE_ALL,
        )
        writer.writerow(FIELDS)
        writer.writerows(TEMPLATES[role])


def prepare(role: str) -> int:
    home = Path.home().resolve()
    out = home / f"conectaeduca-cred01-{HOST}-{UTC}"
    if out.exists():
        raise SystemExit(f"FALHA: diretorio ja existe: {out}")
    # Diretório de evidência nasce privado; evitar chmod(path) redundante.
    out.mkdir(mode=0o700)

    matrix = out / "CRED01-MATRIZ.tsv"
    summary = out / "RESUMO-CRED01-RAW.txt"
    sums = out / "SHA256SUMS-RAW"

    write_matrix(matrix, role)

    root, head, clean = git_fact()
    identity = linux_identity()
    lines = [
        "=== CONECTAEDUCA CRED-01 PREPARE ===",
        f"HOST={HOST}",
        f"UTC={UTC}",
        f"HOST_ROLE={role}",
        "MODE=READ_ONLY_PREPARE",
        f"OPERATOR={pwd.getpwuid(os.geteuid()).pw_name}",
        f"EUID={os.geteuid()}",
        f"GIT_ROOT={root}",
        f"GIT_HEAD={head}",
        f"GIT_CLEAN={clean}",
        f"TESTE_EXISTS={identity.get('exists','NO')}",
    ]
    for key in ("uid", "gid", "home", "shell", "groups", "privileged_groups"):
        if key in identity:
            lines.append(f"TESTE_{key.upper()}={identity[key]}")

    if identity.get("exists") == "YES":
        lines.append(
            "TESTE_PRIVILEGE_BASELINE="
            + ("PASS" if identity.get("privileged_groups") == "none" else "BLOCK")
        )
    else:
        lines.append("TESTE_PRIVILEGE_BASELINE=BLOCK")

    for port in LOOPBACK_PORTS[role]:
        lines.append(f"LOOPBACK_{port}={'OPEN' if tcp_open(port) else 'CLOSED'}")

    for binary in (
        "su", "curl", "openssl", "mariadb", "psql", "bconsole", "bao", "python3"
    ):
        lines.append(f"BINARY_{binary.upper().replace('-','_')}={shutil.which(binary) or 'ABSENT'}")

    lines += [
        "PASSWORD_PROMPTED=NO",
        "PASSWORD_PERSISTED=NO",
        "SECRET_VALUES_LOGGED=NO",
        f"MATRIX={matrix}",
        "CRED01_STATUS=BLOCK",
        "NEXT=executar testes por mecanismo, preencher matriz e usar --finalize",
    ]
    write_private_text(summary, "\n".join(lines) + "\n")

    write_private_text(
        sums,
        f"{sha256(summary)}  {summary.name}\n",
    )

    print(summary.read_text(encoding="utf-8"), end="")
    print(f"EVIDENCE_DIR={out}")
    print(f"SHA256SUMS_RAW={sums}")
    return 0


def validate_rows(rows: list[dict[str, str]], role: str | None = None) -> list[str]:
    errors: list[str] = []
    seen: set[str] = set()

    if role is not None:
        expected = {
            row[0]: {"MECANISMO": row[1], "OBRIGATORIO": row[2]}
            for row in TEMPLATES[role]
        }
        actual = {(row.get("COMPONENTE") or "").strip(): row for row in rows}
        missing = set(expected) - set(actual)
        extra = set(actual) - set(expected)
        if missing:
            errors.append(
                f"{role}: componentes ausentes=" + ",".join(sorted(missing))
            )
        if extra:
            errors.append(
                f"{role}: componentes inesperados=" + ",".join(sorted(extra))
            )
        for component in sorted(set(expected) & set(actual)):
            mechanism = (actual[component].get("MECANISMO") or "").strip()
            required = (actual[component].get("OBRIGATORIO") or "").strip()
            if mechanism != expected[component]["MECANISMO"]:
                errors.append(
                    f"{component}: MECANISMO imutavel esperado="
                    f"{expected[component]['MECANISMO']!r}"
                )
            if required != expected[component]["OBRIGATORIO"]:
                errors.append(
                    f"{component}: OBRIGATORIO imutavel esperado="
                    f"{expected[component]['OBRIGATORIO']!r}"
                )

    for index, row in enumerate(rows, start=2):
        component = (row.get("COMPONENTE") or "").strip()
        if not component:
            errors.append(f"linha {index}: COMPONENTE vazio")
            continue
        if component in seen:
            errors.append(f"linha {index}: COMPONENTE duplicado={component}")
        seen.add(component)

        required = (row.get("OBRIGATORIO") or "").strip()
        status = (row.get("STATUS") or "").strip()
        positive = (row.get("AUTH_POSITIVA") or "").strip()
        negative = (row.get("AUTH_NEGATIVA") or "").strip()
        least = (row.get("MENOR_PRIVILEGIO") or "").strip()
        evidence = (row.get("EVIDENCIA") or "").strip()
        justification = (row.get("JUSTIFICATIVA") or "").strip()

        if required == "YES":
            if status != "PASS":
                errors.append(f"{component}: STATUS precisa ser PASS")
                continue
            if positive != "PASS":
                errors.append(f"{component}: AUTH_POSITIVA precisa ser PASS")
            if least != "PASS":
                errors.append(f"{component}: MENOR_PRIVILEGIO precisa ser PASS")
            if negative not in {"PASS", "N_A_SAFE"}:
                errors.append(
                    f"{component}: AUTH_NEGATIVA precisa ser PASS ou N_A_SAFE"
                )
            if component == "openbao_userpass" and negative != "PASS":
                errors.append(
                    "openbao_userpass: credencial antiga/incorreta precisa ser rejeitada"
                )
            if not evidence:
                errors.append(f"{component}: EVIDENCIA obrigatoria")
            if negative == "N_A_SAFE" and not justification:
                errors.append(
                    f"{component}: N_A_SAFE exige JUSTIFICATIVA"
                )

        elif required == "NO":
            if status != "N_A":
                errors.append(f"{component}: mecanismo nao obrigatorio deve ficar N_A")
            if not justification:
                errors.append(f"{component}: N_A exige JUSTIFICATIVA")
        else:
            errors.append(f"{component}: OBRIGATORIO invalido={required!r}")

    return errors


def read_raw_role(raw: Path) -> str:
    prefix = "HOST_ROLE="
    roles = [
        line[len(prefix):].strip()
        for line in raw.read_text(encoding="utf-8").splitlines()
        if line.startswith(prefix)
    ]
    if len(roles) != 1 or roles[0] not in TEMPLATES:
        raise SystemExit("FALHA: HOST_ROLE ausente/invalido no resumo RAW")
    return roles[0]


def verify_raw_manifest(directory: Path, manifest: Path) -> list[str]:
    errors: list[str] = []
    entries = manifest.read_text(encoding="utf-8").splitlines()
    if not entries:
        return ["SHA256SUMS-RAW vazio"]
    seen: set[str] = set()
    for index, line in enumerate(entries, start=1):
        parts = line.split("  ", 1)
        if len(parts) != 2:
            errors.append(f"SHA256SUMS-RAW linha {index}: formato invalido")
            continue
        expected, name = parts
        if (
            len(expected) != 64
            or any(ch not in "0123456789abcdefABCDEF" for ch in expected)
            or not name
            or Path(name).name != name
        ):
            errors.append(f"SHA256SUMS-RAW linha {index}: entrada invalida")
            continue
        if name in seen:
            errors.append(f"SHA256SUMS-RAW: entrada duplicada={name}")
            continue
        seen.add(name)
        target = directory / name
        if not target.is_file():
            errors.append(f"SHA256SUMS-RAW: arquivo ausente={name}")
            continue
        if sha256(target).lower() != expected.lower():
            errors.append(f"SHA256SUMS-RAW: hash divergente={name}")
    if "RESUMO-CRED01-RAW.txt" not in seen:
        errors.append("SHA256SUMS-RAW nao cobre RESUMO-CRED01-RAW.txt")
    return errors


def finalize(directory: Path) -> int:
    if os.geteuid() == 0:
        raise SystemExit("FALHA: --finalize deve ser executado como usuario normal")

    directory = directory.expanduser().resolve()
    home = Path.home().resolve()
    try:
        directory.relative_to(home)
    except ValueError:
        raise SystemExit("FALHA: evidence-dir precisa estar dentro do HOME")
    if directory.is_symlink():
        raise SystemExit("FALHA: evidence-dir nao pode ser symlink")
    if not directory.name.startswith("conectaeduca-cred01-"):
        raise SystemExit("FALHA: evidence-dir nao corresponde ao prefixo CRED-01")
    if directory.stat().st_uid != os.geteuid():
        raise SystemExit("FALHA: evidence-dir precisa pertencer ao operador")

    matrix = directory / "CRED01-MATRIZ.tsv"
    raw = directory / "RESUMO-CRED01-RAW.txt"
    raw_sums = directory / "SHA256SUMS-RAW"
    for path in (matrix, raw, raw_sums):
        if not path.is_file():
            raise SystemExit(f"FALHA: arquivo obrigatorio ausente: {path}")

    with matrix.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        if reader.fieldnames != FIELDS:
            raise SystemExit("FALHA: cabecalho da matriz CRED-01 inesperado")
        rows = list(reader)

    role = read_raw_role(raw)
    errors = verify_raw_manifest(directory, raw_sums)
    errors.extend(validate_rows(rows, role))
    if errors:
        for item in errors:
            print(f"[FAIL] {item}")
        print(f"CRED01_STATUS=BLOCK errors={len(errors)}")
        return 2

    required = sum(1 for row in rows if row["OBRIGATORIO"] == "YES")
    not_applicable = sum(1 for row in rows if row["OBRIGATORIO"] == "NO")
    summary = directory / "RESUMO-CRED01-FINAL.txt"
    write_private_text(
        summary,
        "\n".join(
            [
                "=== CONECTAEDUCA CRED-01 FINAL ===",
                f"HOST={HOST}",
                f"UTC_FINALIZE={UTC}",
                f"REQUIRED_PASS={required}",
                f"N_A={not_applicable}",
                "PENDING=0",
                "BLOCK=0",
                "PASSWORD_PERSISTED=NO",
                "SECRET_VALUES_LOGGED=NO",
                "CRED01_STATUS=PASS",
            ]
        ) + "\n",
    )

    final = directory / "SHA256SUMS-FINAL"
    files = [raw, raw_sums, matrix, summary]
    write_private_text(
        final,
        "".join(f"{sha256(path)}  {path.name}\n" for path in files),
    )

    print(summary.read_text(encoding="utf-8"), end="")
    print(f"SHA256SUMS_FINAL={final}")
    return 0


def self_test() -> int:
    rows = [
        dict(zip(FIELDS, row))
        for row in TEMPLATES["ep126"]
    ]
    if not validate_rows(rows):
        raise SystemExit("SELFTEST FAIL: matriz pendente foi aceita")

    completed = []
    for row in rows:
        item = dict(row)
        if item["OBRIGATORIO"] == "YES":
            item.update(
                STATUS="PASS",
                AUTH_POSITIVA="PASS",
                AUTH_NEGATIVA="PASS",
                MENOR_PRIVILEGIO="PASS",
                EVIDENCIA="fixture.txt",
                JUSTIFICATIVA="teste sintetico",
            )
        completed.append(item)

    errors = validate_rows(completed, "ep126")
    if errors:
        raise SystemExit("SELFTEST FAIL: matriz completa rejeitada: " + "; ".join(errors))

    bad = [dict(item) for item in completed]
    for item in bad:
        if item["COMPONENTE"] == "openbao_userpass":
            item["AUTH_NEGATIVA"] = "N_A_SAFE"
    if not validate_rows(bad, "ep126"):
        raise SystemExit("SELFTEST FAIL: OpenBao sem teste negativo foi aceito")

    missing = [dict(item) for item in completed if item["COMPONENTE"] != "linux_pam"]
    if not validate_rows(missing, "ep126"):
        raise SystemExit("SELFTEST FAIL: componente obrigatorio ausente foi aceito")

    weakened = [dict(item) for item in completed]
    for item in weakened:
        if item["COMPONENTE"] == "openbao_userpass":
            item["OBRIGATORIO"] = "NO"
            item["STATUS"] = "N_A"
            item["JUSTIFICATIVA"] = "tentativa de enfraquecimento"
    if not validate_rows(weakened, "ep126"):
        raise SystemExit("SELFTEST FAIL: OBRIGATORIO alterado foi aceito")

    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        raw = tmpdir / "RESUMO-CRED01-RAW.txt"
        manifest = tmpdir / "SHA256SUMS-RAW"
        raw.write_text("HOST_ROLE=ep126\n", encoding="utf-8")
        manifest.write_text(f"{sha256(raw)}  {raw.name}\n", encoding="utf-8")
        if verify_raw_manifest(tmpdir, manifest):
            raise SystemExit("SELFTEST FAIL: manifesto RAW valido foi rejeitado")
        raw.write_text("HOST_ROLE=ep125\n", encoding="utf-8")
        if not verify_raw_manifest(tmpdir, manifest):
            raise SystemExit("SELFTEST FAIL: adulteracao RAW foi aceita")

    print("CRED01_MATRIX_SELFTEST=PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--prepare", action="store_true")
    mode.add_argument("--finalize", type=Path, metavar="EVIDENCE_DIR")
    mode.add_argument("--self-test", action="store_true")
    parser.add_argument("--host-role", choices=("ep125", "ep126"))
    args = parser.parse_args()

    if args.self_test:
        return self_test()
    if args.prepare:
        if not args.host_role:
            parser.error("--prepare exige --host-role ep125|ep126")
        return prepare(args.host_role)
    return finalize(args.finalize)


if __name__ == "__main__":
    raise SystemExit(main())
