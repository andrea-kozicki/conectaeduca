#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any

TARGET = "scripts/evidencias/ops01_ep126_readonly.py"


def run(cmd: list[str], cwd: Path | None = None, timeout: int = 300) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(cwd) if cwd else None,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
        return proc.returncode, proc.stdout, proc.stderr
    except FileNotFoundError:
        return 127, "", f"command not found: {cmd[0]}"
    except subprocess.TimeoutExpired:
        return 124, "", f"timeout: {cmd[0]}"


def sarif_results(payload: dict[str, Any]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for run_item in payload.get("runs", []) or []:
        rules: dict[str, dict[str, Any]] = {}
        driver = ((run_item.get("tool") or {}).get("driver") or {})
        for rule in driver.get("rules", []) or []:
            rule_id = str(rule.get("id") or "")
            if rule_id:
                rules[rule_id] = rule

        for result in run_item.get("results", []) or []:
            rule_id = str(result.get("ruleId") or "")
            rule = rules.get(rule_id, {})
            paths: list[str] = []
            for loc in result.get("locations", []) or []:
                uri = (
                    (((loc.get("physicalLocation") or {}).get("artifactLocation") or {}).get("uri"))
                    or ""
                )
                if uri:
                    paths.append(str(uri).replace("\\", "/").lstrip("./"))

            # O CWE pode aparecer em tags, descrição, help ou mensagem do
            # resultado dependendo da versão do Snyk/SARIF. Inspecionamos o
            # objeto completo somente em memória; nenhuma mensagem/snippet é
            # persistida no relatório sanitizado.
            metadata_blob = json.dumps(
                {"result": result, "rule": rule},
                sort_keys=True,
            ).upper()

            rows.append(
                {
                    "rule_id": rule_id or "unknown",
                    "paths": paths,
                    "cwe611": "CWE-611" in metadata_blob or "CWE_611" in metadata_blob,
                }
            )
    return rows


def classify(rows: list[dict[str, Any]]) -> dict[str, int]:
    total = len(rows)
    cwe611 = 0
    target = 0
    target_cwe611 = 0
    for row in rows:
        is_target = any(path.endswith(TARGET) for path in row["paths"])
        is_cwe611 = bool(row["cwe611"])
        cwe611 += int(is_cwe611)
        target += int(is_target)
        target_cwe611 += int(is_target and is_cwe611)
    return {
        "total": total,
        "cwe611": cwe611,
        "target": target,
        "target_cwe611": target_cwe611,
    }


def self_test() -> int:
    clean = {
        "runs": [
            {
                "tool": {"driver": {"rules": [{"id": "R1", "properties": {"tags": ["CWE-79"]}}]}},
                "results": [
                    {
                        "ruleId": "R1",
                        "locations": [
                            {
                                "physicalLocation": {
                                    "artifactLocation": {"uri": "src/example.py"}
                                }
                            }
                        ],
                    }
                ],
            }
        ]
    }
    bad = {
        "runs": [
            {
                "tool": {
                    "driver": {
                        "rules": [
                            {"id": "R611", "properties": {"tags": ["CWE-611"]}}
                        ]
                    }
                },
                "results": [
                    {
                        "ruleId": "R611",
                        "locations": [
                            {
                                "physicalLocation": {
                                    "artifactLocation": {"uri": TARGET}
                                }
                            }
                        ],
                    }
                ],
            }
        ]
    }

    c1 = classify(sarif_results(clean))
    c2 = classify(sarif_results(bad))
    if c1 != {"total": 1, "cwe611": 0, "target": 0, "target_cwe611": 0}:
        raise SystemExit(f"self-test clean failed: {c1}")
    if c2 != {"total": 1, "cwe611": 1, "target": 1, "target_cwe611": 1}:
        raise SystemExit(f"self-test CWE-611 failed: {c2}")
    print("APPSEC04_SNYK_REVALIDATION_SELFTEST=PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Revalida APPSEC-04 via Snyk Code na main e gera evidência sanitizada."
    )
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()

    rc, root_out, err = run(["git", "rev-parse", "--show-toplevel"])
    if rc != 0:
        raise SystemExit("FALHA: execute dentro do repositório Git")
    root = Path(root_out.strip()).resolve()

    utc = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%SZ")
    report = Path.home() / f"conectaeduca-appsec04-snyk-{utc}.txt"
    sha_file = Path(str(report) + ".sha256")
    lines: list[str] = []

    def emit(line: str = "") -> None:
        lines.append(line)
        print(line)

    emit("=== CONECTAEDUCA APPSEC-04 — SNYK CODE REVALIDATION ===")
    emit(f"UTC={utc}")
    emit(f"ROOT={root}")
    emit("MODE=READ_ONLY_SCAN")
    emit("SNYK_TOKEN_LOGGED=NO")
    emit("RAW_SARIF_PERSISTED=NO")
    emit(f"TARGET={TARGET}")

    rc, branch, _ = run(["git", "branch", "--show-current"], root)
    rc2, head, _ = run(["git", "rev-parse", "HEAD"], root)
    rc3, origin_main, _ = run(["git", "rev-parse", "origin/main"], root)
    rc4, dirty, _ = run(["git", "status", "--porcelain"], root)

    branch = branch.strip()
    head = head.strip()
    origin_main = origin_main.strip()
    emit(f"BRANCH={branch or 'unknown'}")
    emit(f"HEAD={head or 'unknown'}")
    emit(f"ORIGIN_MAIN={origin_main or 'unknown'}")
    emit(f"WORKTREE_DIRTY={'YES' if dirty.strip() else 'NO'}")

    provenance_ok = (
        rc == 0
        and rc2 == 0
        and rc3 == 0
        and rc4 == 0
        and branch == "main"
        and head == origin_main
        and not dirty.strip()
    )
    emit(f"PROVENANCE={'PASS' if provenance_ok else 'BLOCK'}")
    if not provenance_ok:
        emit("APPSEC04_SNYK_REVALIDATION=BLOCK_PROVENANCE")
        report.write_text("\n".join(lines) + "\n", encoding="utf-8")
        digest = hashlib.sha256(report.read_bytes()).hexdigest()
        sha_file.write_text(f"{digest}  {report.name}\n", encoding="utf-8")
        print(f"REPORT={report}")
        print(f"SHA256={digest}")
        print(f"SHA256_FILE={sha_file}")
        return 2

    rc, version_out, version_err = run(["snyk", "--version"], root, 60)
    if rc != 0:
        emit("SNYK_CLI=NOT_AVAILABLE")
        emit("APPSEC04_SNYK_REVALIDATION=BLOCK_TOOLING")
        report.write_text("\n".join(lines) + "\n", encoding="utf-8")
        digest = hashlib.sha256(report.read_bytes()).hexdigest()
        sha_file.write_text(f"{digest}  {report.name}\n", encoding="utf-8")
        print(f"REPORT={report}")
        print(f"SHA256={digest}")
        print(f"SHA256_FILE={sha_file}")
        return 2
    emit(f"SNYK_CLI_VERSION={version_out.strip()}")

    scan_rc, sarif_out, scan_err = run(["snyk", "code", "test", "--sarif"], root, 600)
    emit(f"SNYK_SCAN_RC={scan_rc}")
    if scan_rc not in (0, 1):
        emit("SNYK_SCAN_PARSE=NOT_ATTEMPTED")
        emit("APPSEC04_SNYK_REVALIDATION=BLOCK_SCAN_ERROR")
        report.write_text("\n".join(lines) + "\n", encoding="utf-8")
        digest = hashlib.sha256(report.read_bytes()).hexdigest()
        sha_file.write_text(f"{digest}  {report.name}\n", encoding="utf-8")
        print(f"REPORT={report}")
        print(f"SHA256={digest}")
        print(f"SHA256_FILE={sha_file}")
        return 2

    try:
        payload = json.loads(sarif_out)
    except json.JSONDecodeError:
        emit("SNYK_SCAN_PARSE=FAIL")
        emit("APPSEC04_SNYK_REVALIDATION=BLOCK_PARSE")
        report.write_text("\n".join(lines) + "\n", encoding="utf-8")
        digest = hashlib.sha256(report.read_bytes()).hexdigest()
        sha_file.write_text(f"{digest}  {report.name}\n", encoding="utf-8")
        print(f"REPORT={report}")
        print(f"SHA256={digest}")
        print(f"SHA256_FILE={sha_file}")
        return 2

    rows = sarif_results(payload)
    counts = classify(rows)
    emit("SNYK_SCAN_PARSE=PASS")
    emit(f"SNYK_TOTAL_RESULTS={counts['total']}")
    emit(f"SNYK_CWE611_RESULTS={counts['cwe611']}")
    emit(f"SNYK_TARGET_RESULTS={counts['target']}")
    emit(f"SNYK_TARGET_CWE611_RESULTS={counts['target_cwe611']}")

    # Somente metadados mínimos; nenhuma mensagem/snippet SARIF é persistida.
    for row in rows[:50]:
        path = row["paths"][0] if row["paths"] else "unknown"
        emit(
            "SNYK_RESULT="
            f"rule={row['rule_id']}|path={path}|cwe611={1 if row['cwe611'] else 0}"
        )

    appsec04_ok = counts["target_cwe611"] == 0 and counts["cwe611"] == 0
    full_clean = counts["total"] == 0
    emit(f"APPSEC04_CWE611={'PASS' if appsec04_ok else 'FAIL'}")
    emit(f"SNYK_CODE_MAIN={'PASS' if full_clean else 'FINDINGS_PRESENT'}")
    emit(
        "APPSEC04_SNYK_REVALIDATION="
        + ("PASS" if appsec04_ok and full_clean else "BLOCK")
    )
    emit("NO_SNYK_SUPPRESSION_EXPECTED=YES")
    emit("RAW_SARIF_PERSISTED=NO")

    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    digest = hashlib.sha256(report.read_bytes()).hexdigest()
    sha_file.write_text(f"{digest}  {report.name}\n", encoding="utf-8")
    print(f"REPORT={report}")
    print(f"SHA256={digest}")
    print(f"SHA256_FILE={sha_file}")
    return 0 if appsec04_ok and full_clean else 2


if __name__ == "__main__":
    raise SystemExit(main())
