#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import os
import re
import tempfile
from collections import Counter, defaultdict
from pathlib import Path

UTC = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%SZ")
FINAL_CLASSES = {"APLICAVEL", "JA_MITIGADO", "N_A_LAB", "RISCO_ACEITO"}
TRIAGE_FIELDS = [
    "TYPE",
    "TEST_ID",
    "MESSAGE",
    "CLASSIFICACAO",
    "JUSTIFICATIVA",
    "ACAO",
]
MANIFEST_RE = re.compile(r"^([0-9a-f]{64})  ([^/]+)$")


class AuditError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_manifest(path: Path) -> list[tuple[str, str]]:
    if not path.is_file():
        raise AuditError(f"manifesto ausente: {path}")

    entries: list[tuple[str, str]] = []
    for line_no, raw in enumerate(
        path.read_text(encoding="utf-8", errors="strict").splitlines(),
        start=1,
    ):
        if not raw.strip():
            continue
        match = MANIFEST_RE.fullmatch(raw)
        if not match:
            raise AuditError(
                f"{path.name}: linha {line_no} fora do formato SHA256SUMS"
            )
        entries.append((match.group(1), match.group(2)))

    if not entries:
        raise AuditError(f"{path.name}: manifesto vazio")

    names = [name for _, name in entries]
    if len(names) != len(set(names)):
        raise AuditError(f"{path.name}: nomes duplicados no manifesto")

    return entries


def verify_manifest(directory: Path, manifest_name: str) -> list[str]:
    manifest = directory / manifest_name
    entries = parse_manifest(manifest)
    verified: list[str] = []

    for expected, name in entries:
        target = directory / name
        if not target.is_file():
            raise AuditError(
                f"{manifest_name}: arquivo referenciado ausente: {name}"
            )
        actual = sha256(target)
        if actual != expected:
            raise AuditError(
                f"{manifest_name}: hash divergente para {name}: "
                f"expected={expected} actual={actual}"
            )
        verified.append(name)

    return verified


def parse_key_values(path: Path) -> dict[str, str]:
    if not path.is_file():
        raise AuditError(f"arquivo ausente: {path}")
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        key = key.strip()
        if key:
            values[key] = value.strip()
    return values


def load_triage(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        raise AuditError(f"triagem ausente: {path}")

    with path.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        if reader.fieldnames != TRIAGE_FIELDS:
            raise AuditError(
                f"{path.name}: cabecalho inesperado: {reader.fieldnames}"
            )
        rows = [dict(row) for row in reader]

    invalid: list[str] = []
    for idx, row in enumerate(rows, start=2):
        classification = (row.get("CLASSIFICACAO") or "").strip()
        justification = (row.get("JUSTIFICATIVA") or "").strip()
        action = (row.get("ACAO") or "").strip()
        test_id = (row.get("TEST_ID") or "").strip()

        # Canonicalize validated human-editable fields before aggregation.
        row["TEST_ID"] = test_id
        row["CLASSIFICACAO"] = classification
        row["JUSTIFICATIVA"] = justification
        row["ACAO"] = action

        if not test_id:
            invalid.append(f"linha {idx}: TEST_ID vazio")
        if classification not in FINAL_CLASSES:
            invalid.append(
                f"linha {idx}: classificacao invalida={classification or '<vazia>'}"
            )
        if not justification:
            invalid.append(f"linha {idx}: justificativa vazia")
        if classification in {"APLICAVEL", "RISCO_ACEITO"} and not action:
            invalid.append(
                f"linha {idx}: acao obrigatoria para {classification}"
            )

    if invalid:
        raise AuditError(
            f"{path.name}: triagem nao finalizada: " + "; ".join(invalid)
        )

    return rows


def validate_package(role: str, directory: Path) -> dict[str, object]:
    directory = directory.expanduser().resolve()
    if not directory.is_dir():
        raise AuditError(f"{role}: diretorio inexistente: {directory}")

    raw_verified = verify_manifest(directory, "SHA256SUMS-RAW")
    final_verified = verify_manifest(directory, "SHA256SUMS-FINAL")

    required_raw = {
        "lynis-screen.txt",
        "lynis.log",
        "lynis-report.dat",
        "RESUMO-AUDIT01.txt",
    }
    missing_from_raw = required_raw - set(raw_verified)
    if missing_from_raw:
        raise AuditError(
            f"{role}: SHA256SUMS-RAW nao cobre: "
            + ",".join(sorted(missing_from_raw))
        )

    required_final = {
        "lynis-screen.txt",
        "lynis.log",
        "lynis-report.dat",
        "RESUMO-AUDIT01.txt",
        "TRIAGEM-LYNIS.tsv",
        "SHA256SUMS-RAW",
        "RESUMO-TRIAGEM-AUDIT01.txt",
    }
    missing_from_final = required_final - set(final_verified)
    if missing_from_final:
        raise AuditError(
            f"{role}: SHA256SUMS-FINAL nao cobre: "
            + ",".join(sorted(missing_from_final))
        )

    summary = parse_key_values(directory / "RESUMO-AUDIT01.txt")
    triage_summary = parse_key_values(
        directory / "RESUMO-TRIAGEM-AUDIT01.txt"
    )
    if triage_summary.get("AUDIT01_TRIAGE") != "PASS":
        raise AuditError(f"{role}: AUDIT01_TRIAGE != PASS")

    rows = load_triage(directory / "TRIAGEM-LYNIS.tsv")

    raw_total = summary.get("FINDINGS_TOTAL")
    if raw_total is not None and raw_total.isdigit():
        if int(raw_total) != len(rows):
            raise AuditError(
                f"{role}: FINDINGS_TOTAL raw={raw_total} "
                f"diverge da triagem={len(rows)}"
            )

    final_total = triage_summary.get("FINDINGS_TOTAL")
    if final_total is not None and final_total.isdigit():
        if int(final_total) != len(rows):
            raise AuditError(
                f"{role}: FINDINGS_TOTAL final={final_total} "
                f"diverge da triagem={len(rows)}"
            )

    counts = Counter(row["CLASSIFICACAO"] for row in rows)
    types = Counter(row["TYPE"] for row in rows)

    return {
        "role": role,
        "directory": directory,
        "host": summary.get("HOST", "UNKNOWN"),
        "hardening_index": summary.get("HARDENING_INDEX", "UNKNOWN"),
        "warnings": types.get("WARNING", 0),
        "suggestions": types.get("SUGGESTION", 0),
        "rows": rows,
        "counts": counts,
        "raw_verified": raw_verified,
        "final_verified": final_verified,
    }


def write_comparison(
    ep125: dict[str, object],
    ep126: dict[str, object],
    output: Path,
) -> None:
    output.mkdir(parents=True, exist_ok=False)
    os.chmod(output, 0o700)

    packages = [ep125, ep126]
    rows_by_id: dict[str, dict[str, list[dict[str, str]]]] = defaultdict(
        lambda: {"ep125": [], "ep126": []}
    )

    for package in packages:
        role = str(package["role"])
        for row in package["rows"]:
            rows_by_id[row["TEST_ID"]][role].append(row)

    matrix = output / "MATRIZ-COMPARATIVA-LYNIS.tsv"
    with matrix.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
        writer.writerow(
            [
                "TEST_ID",
                "EP125_PRESENTE",
                "EP125_CLASSES",
                "EP126_PRESENTE",
                "EP126_CLASSES",
                "PRESENCA",
            ]
        )
        for test_id in sorted(rows_by_id):
            a = rows_by_id[test_id]["ep125"]
            b = rows_by_id[test_id]["ep126"]
            if a and b:
                presence = "AMBAS"
            elif a:
                presence = "SOMENTE_EP125"
            else:
                presence = "SOMENTE_EP126"
            writer.writerow(
                [
                    test_id,
                    "YES" if a else "NO",
                    ",".join(sorted({r["CLASSIFICACAO"] for r in a}))
                    or "-",
                    "YES" if b else "NO",
                    ",".join(sorted({r["CLASSIFICACAO"] for r in b}))
                    or "-",
                    presence,
                ]
            )
    os.chmod(matrix, 0o600)

    priority = output / "ACHADOS-PRIORITARIOS.md"
    priority_lines = [
        "# AUDIT-01 — achados que exigem acao ou aceite de risco",
        "",
        "Gerado a partir das duas triagens finalizadas. "
        "Este arquivo nao reclassifica findings.",
        "",
    ]
    priority_count = 0
    for package in packages:
        role = str(package["role"]).upper()
        priority_lines += [f"## {role}", ""]
        selected = [
            row
            for row in package["rows"]
            if row["CLASSIFICACAO"] in {"APLICAVEL", "RISCO_ACEITO"}
        ]
        if not selected:
            priority_lines += ["Nenhum finding nesta categoria.", ""]
            continue
        for row in selected:
            priority_count += 1
            priority_lines += [
                f"### {row['TEST_ID']} — {row['CLASSIFICACAO']}",
                "",
                f"- Tipo: {row['TYPE']}",
                f"- Finding: {row['MESSAGE']}",
                f"- Justificativa: {row['JUSTIFICATIVA']}",
                f"- Acao/controle: {row['ACAO']}",
                "",
            ]
    priority.write_text("\n".join(priority_lines), encoding="utf-8")
    os.chmod(priority, 0o600)

    summary = output / "RESUMO-AUDIT01-CONSOLIDADO.txt"
    summary_lines = [
        "=== CONECTAEDUCA AUDIT-01 CONSOLIDADO ===",
        f"UTC={UTC}",
    ]
    for package in packages:
        role = str(package["role"]).upper()
        counts: Counter[str] = package["counts"]
        summary_lines += [
            f"{role}_HOST={package['host']}",
            f"{role}_HARDENING_INDEX={package['hardening_index']}",
            f"{role}_WARNINGS={package['warnings']}",
            f"{role}_SUGGESTIONS={package['suggestions']}",
            f"{role}_APLICAVEL={counts.get('APLICAVEL', 0)}",
            f"{role}_JA_MITIGADO={counts.get('JA_MITIGADO', 0)}",
            f"{role}_N_A_LAB={counts.get('N_A_LAB', 0)}",
            f"{role}_RISCO_ACEITO={counts.get('RISCO_ACEITO', 0)}",
            f"{role}_RAW_MANIFEST=PASS",
            f"{role}_FINAL_MANIFEST=PASS",
        ]

    both = sum(
        1
        for value in rows_by_id.values()
        if value["ep125"] and value["ep126"]
    )
    only125 = sum(
        1
        for value in rows_by_id.values()
        if value["ep125"] and not value["ep126"]
    )
    only126 = sum(
        1
        for value in rows_by_id.values()
        if value["ep126"] and not value["ep125"]
    )
    summary_lines += [
        f"TEST_IDS_BOTH={both}",
        f"TEST_IDS_ONLY_EP125={only125}",
        f"TEST_IDS_ONLY_EP126={only126}",
        f"PRIORITY_FINDINGS={priority_count}",
        "AUTO_RECLASSIFICATION=NO",
        "AUDIT01_CONSOLIDATION=PASS",
    ]
    summary.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")
    os.chmod(summary, 0o600)

    manifest = output / "SHA256SUMS"
    files = [matrix, priority, summary]
    manifest.write_text(
        "".join(f"{sha256(path)}  {path.name}\n" for path in files),
        encoding="utf-8",
    )
    os.chmod(manifest, 0o600)


def synthetic_package(root: Path, role: str, rows: list[dict[str, str]]) -> Path:
    directory = root / role
    directory.mkdir()

    raw_files = {
        "lynis-screen.txt": "screen\n",
        "lynis.log": "log\n",
        "lynis-report.dat": "hardening_index=80\n",
        "RESUMO-AUDIT01.txt": (
            f"HOST={role}-fixture\n"
            "HARDENING_INDEX=80\n"
            f"FINDINGS_TOTAL={len(rows)}\n"
        ),
    }
    for name, content in raw_files.items():
        (directory / name).write_text(content, encoding="utf-8")

    raw_manifest = directory / "SHA256SUMS-RAW"
    raw_manifest.write_text(
        "".join(
            f"{sha256(directory / name)}  {name}\n"
            for name in raw_files
        ),
        encoding="utf-8",
    )

    triage = directory / "TRIAGEM-LYNIS.tsv"
    with triage.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=TRIAGE_FIELDS,
            delimiter="\t",
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(rows)

    triage_summary = directory / "RESUMO-TRIAGEM-AUDIT01.txt"
    triage_summary.write_text(
        f"FINDINGS_TOTAL={len(rows)}\nAUDIT01_TRIAGE=PASS\n",
        encoding="utf-8",
    )

    final_manifest = directory / "SHA256SUMS-FINAL"
    final_names = [
        "lynis-screen.txt",
        "lynis.log",
        "lynis-report.dat",
        "RESUMO-AUDIT01.txt",
        "TRIAGEM-LYNIS.tsv",
        "SHA256SUMS-RAW",
        "RESUMO-TRIAGEM-AUDIT01.txt",
    ]
    final_manifest.write_text(
        "".join(
            f"{sha256(directory / name)}  {name}\n"
            for name in final_names
        ),
        encoding="utf-8",
    )
    return directory


def self_test() -> int:
    base_rows = [
        {
            "TYPE": "WARNING",
            "TEST_ID": "AUTH-0001",
            "MESSAGE": "fixture warning",
            "CLASSIFICACAO": "APLICAVEL",
            "JUSTIFICATIVA": "fixture",
            "ACAO": "corrigir fixture",
        },
        {
            "TYPE": "SUGGESTION",
            "TEST_ID": "TIME-0002",
            "MESSAGE": "fixture suggestion",
            "CLASSIFICACAO": "RISCO_ACEITO",
            "JUSTIFICATIVA": "restricao fixture",
            "ACAO": "documentar risco",
        },
    ]

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        ep125_dir = synthetic_package(root, "ep125", base_rows[:1])
        ep126_dir = synthetic_package(root, "ep126", base_rows)

        ep125 = validate_package("ep125", ep125_dir)
        ep126 = validate_package("ep126", ep126_dir)

        output = root / "consolidado"
        write_comparison(ep125, ep126, output)

        summary = (output / "RESUMO-AUDIT01-CONSOLIDADO.txt").read_text(
            encoding="utf-8"
        )
        if "AUDIT01_CONSOLIDATION=PASS" not in summary:
            raise SystemExit("SELFTEST FAIL: consolidacao nao marcou PASS")
        if "TEST_IDS_BOTH=1" not in summary:
            raise SystemExit("SELFTEST FAIL: comparacao cross-host incorreta")

        # Negative control: any tamper after SHA256SUMS-FINAL must block.
        target = ep126_dir / "lynis.log"
        target.write_text("tampered\n", encoding="utf-8")
        try:
            validate_package("ep126", ep126_dir)
        except AuditError:
            pass
        else:
            raise SystemExit("SELFTEST FAIL: pacote adulterado foi aceito")

    print("AUDIT01_CONSOLIDATOR_SELFTEST=PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Valida e consolida evidencias AUDIT-01 de EP125 e EP126."
    )
    parser.add_argument("--ep125-dir", type=Path)
    parser.add_argument("--ep126-dir", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    if not args.ep125_dir or not args.ep126_dir:
        parser.error("--ep125-dir e --ep126-dir sao obrigatorios")

    ep125 = validate_package("ep125", args.ep125_dir)
    ep126 = validate_package("ep126", args.ep126_dir)

    if Path(ep125["directory"]) == Path(ep126["directory"]):
        raise SystemExit("FALHA: EP125 e EP126 apontam para o mesmo pacote")

    output = (
        args.output_dir.expanduser().resolve()
        if args.output_dir
        else Path.home() / f"conectaeduca-audit01-consolidado-{UTC}"
    )
    write_comparison(ep125, ep126, output)

    print(f"AUDIT01_CONSOLIDATION=PASS")
    print(f"OUTPUT_DIR={output}")
    print(f"SHA256SUMS={output / 'SHA256SUMS'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
