#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
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


def validate_sarif(payload: Any) -> tuple[bool, str]:
    if not isinstance(payload, dict):
        return False, "top-level SARIF must be an object"
    if payload.get("version") != "2.1.0":
        return False, "unsupported or missing SARIF version"
    runs = payload.get("runs")
    if not isinstance(runs, list) or not runs:
        return False, "SARIF must contain at least one run"
    for idx, run_item in enumerate(runs):
        if not isinstance(run_item, dict):
            return False, f"run[{idx}] is not an object"
        driver = ((run_item.get("tool") or {}).get("driver") or {})
        if not isinstance(driver, dict):
            return False, f"run[{idx}] missing tool.driver"
        driver_name = driver.get("name")
        if not isinstance(driver_name, str) or not driver_name.strip():
            return False, f"run[{idx}] missing or invalid tool.driver.name"
        invocations = run_item["invocations"] if "invocations" in run_item else []
        if not isinstance(invocations, list):
            return False, f"run[{idx}].invocations is not a list"
        for invocation_idx, invocation in enumerate(invocations):
            if not isinstance(invocation, dict):
                return False, (
                    f"run[{idx}].invocations[{invocation_idx}] is not an object"
                )
            if "executionSuccessful" not in invocation:
                return False, (
                    f"run[{idx}].invocations[{invocation_idx}] missing "
                    "executionSuccessful"
                )
            execution_successful = invocation["executionSuccessful"]
            if not isinstance(execution_successful, bool):
                return False, (
                    f"run[{idx}].invocations[{invocation_idx}]."
                    "executionSuccessful is not boolean"
                )
            if execution_successful is False:
                return False, (
                    f"run[{idx}].invocations[{invocation_idx}] reports "
                    "executionSuccessful=false"
                )

        results = run_item["results"] if "results" in run_item else []
        if not isinstance(results, list):
            return False, f"run[{idx}].results is not a list"

        rules = driver["rules"] if "rules" in driver else []
        if not isinstance(rules, list):
            return False, f"run[{idx}].tool.driver.rules is not a list"

        for result_idx, result in enumerate(results):
            if not isinstance(result, dict):
                return False, f"run[{idx}].results[{result_idx}] is not an object"
            if result.get("ruleId"):
                continue
            rule_index = result.get("ruleIndex")
            if rule_index is None:
                continue
            if (
                not isinstance(rule_index, int)
                or isinstance(rule_index, bool)
                or rule_index < 0
                or rule_index >= len(rules)
            ):
                return False, (
                    f"run[{idx}].results[{result_idx}] has invalid ruleIndex"
                )
    return True, "ok"


def sarif_results(payload: dict[str, Any]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for run_item in payload.get("runs", []) or []:
        rules: dict[str, dict[str, Any]] = {}
        driver = ((run_item.get("tool") or {}).get("driver") or {})
        rule_list = driver.get("rules", []) or []
        for rule in rule_list:
            rule_id = str(rule.get("id") or "")
            if rule_id:
                rules[rule_id] = rule

        for result in run_item.get("results", []) or []:
            rule_id = str(result.get("ruleId") or "")
            rule = rules.get(rule_id, {})
            if not rule and not rule_id:
                rule_index = result.get("ruleIndex")
                if (
                    isinstance(rule_index, int)
                    and not isinstance(rule_index, bool)
                    and 0 <= rule_index < len(rule_list)
                ):
                    rule = rule_list[rule_index]
                    rule_id = str(rule.get("id") or f"rule-index-{rule_index}")
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
        "version": "2.1.0",
        "runs": [
            {
                "tool": {"driver": {"name": "Snyk Code", "rules": [{"id": "R1", "properties": {"tags": ["CWE-79"]}}]}},
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
        "version": "2.1.0",
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": "Snyk Code",
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
    bad_rule_index = {
        "version": "2.1.0",
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": "Snyk Code",
                        "rules": [
                            {"id": "R611IDX", "properties": {"tags": ["CWE-611"]}}
                        ]
                    }
                },
                "results": [
                    {
                        "ruleIndex": 0,
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

    for invalid in (
        {},
        {"version": "2.1.0", "runs": []},
        {"version": "2.0.0", "runs": [{}]},
        {
            "version": "2.1.0",
            "runs": [
                {
                    "tool": {"driver": {"name": "Snyk Code", "rules": []}},
                    "results": [{"ruleIndex": 2}],
                }
            ],
        },
        {
            "version": "2.1.0",
            "runs": [{"tool": {"driver": {"name": {}, "rules": []}}, "results": []}],
        },
        {
            "version": "2.1.0",
            "runs": [{"tool": {"driver": {"name": ["Snyk Code"], "rules": []}}, "results": []}],
        },
        {
            "version": "2.1.0",
            "runs": [{"tool": {"driver": {"name": "Snyk Code", "rules": []}}, "results": None}],
        },
        {
            "version": "2.1.0",
            "runs": [{"tool": {"driver": {"name": "Snyk Code", "rules": None}}, "results": []}],
        },
        {
            "version": "2.1.0",
            "runs": [
                {
                    "tool": {"driver": {"name": "Snyk Code", "rules": []}},
                    "invocations": [{"executionSuccessful": False}],
                    "results": [],
                }
            ],
        },
        {
            "version": "2.1.0",
            "runs": [
                {
                    "tool": {"driver": {"name": "Snyk Code", "rules": []}},
                    "invocations": [{"executionSuccessful": "false"}],
                    "results": [],
                }
            ],
        },
    ):
        ok, _ = validate_sarif(invalid)
        if ok:
            raise SystemExit(f"self-test invalid SARIF accepted: {invalid}")

    clean_invocation = {
        "version": "2.1.0",
        "runs": [
            {
                "tool": {"driver": {"name": "Snyk Code", "rules": []}},
                "invocations": [{"executionSuccessful": True}],
                "results": [],
            }
        ],
    }

    for valid in (clean, bad, bad_rule_index, clean_invocation):
        ok, reason = validate_sarif(valid)
        if not ok:
            raise SystemExit(f"self-test valid SARIF rejected: {reason}")

    c1 = classify(sarif_results(clean))
    c2 = classify(sarif_results(bad))
    c3 = classify(sarif_results(bad_rule_index))
    if c1 != {"total": 1, "cwe611": 0, "target": 0, "target_cwe611": 0}:
        raise SystemExit(f"self-test clean failed: {c1}")
    if c2 != {"total": 1, "cwe611": 1, "target": 1, "target_cwe611": 1}:
        raise SystemExit(f"self-test CWE-611 failed: {c2}")
    if c3 != {"total": 1, "cwe611": 1, "target": 1, "target_cwe611": 1}:
        raise SystemExit(f"self-test CWE-611 ruleIndex failed: {c3}")
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
    rc3, remote_out, remote_err = run(
        ["git", "ls-remote", "--exit-code", "origin", "refs/heads/main"],
        root,
        120,
    )
    rc4, dirty, _ = run(
        ["git", "status", "--porcelain", "--untracked-files=all"],
        root,
    )

    branch = branch.strip()
    head = head.strip()
    remote_parts = remote_out.strip().split()
    remote_main = (
        remote_parts[0]
        if rc3 == 0 and len(remote_parts) >= 2 and remote_parts[1] == "refs/heads/main"
        else ""
    )
    emit(f"BRANCH={branch or 'unknown'}")
    emit(f"HEAD={head or 'unknown'}")
    emit(f"REMOTE_MAIN={remote_main or 'unavailable'}")
    emit(f"REMOTE_MAIN_QUERY={'PASS' if remote_main else 'FAIL'}")
    emit(f"WORKTREE_DIRTY={'YES' if dirty.strip() else 'NO'}")

    provenance_ok = (
        rc == 0
        and rc2 == 0
        and rc3 == 0
        and rc4 == 0
        and branch == "main"
        and bool(re.fullmatch(r"[0-9a-f]{40}", remote_main))
        and head == remote_main
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

    sarif_ok, sarif_reason = validate_sarif(payload)
    if not sarif_ok:
        emit("SNYK_SCAN_PARSE=FAIL_INVALID_SARIF")
        emit("SNYK_SARIF_VALIDATION=" + sarif_reason)
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
    scan_exit_clean = scan_rc == 0
    full_clean = scan_exit_clean and counts["total"] == 0
    emit(f"SNYK_SCAN_EXIT_CLEAN={'PASS' if scan_exit_clean else 'FAIL'}")
    emit(f"APPSEC04_CWE611={'PASS' if appsec04_ok else 'FAIL'}")
    emit(f"SNYK_CODE_MAIN={'PASS' if full_clean else 'FINDINGS_OR_NONZERO_EXIT'}")
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
