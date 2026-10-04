#!/usr/bin/env python3
"""APPSEC-04/05: evidência Snyk em boundary CI dedicado e sem sudo."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

CANONICAL_REPOSITORY = "andrea-kozicki/conectaeduca"
APPSEC04_TARGET = "scripts/evidencias/ops01_ep126_readonly.py"
APPSEC05_TARGETS = {
    "scripts/dlp/submeter_ferret_pentest.py",
    "scripts/dlp/snapshot_ferret_input.py",
}
SUDO = Path("/usr/bin/sudo")
SNYK_ROOT = Path("/opt/conectaeduca-snyk")
SNAPSHOT = SNYK_ROOT / "snapshot"
SNYK_BIN = SNYK_ROOT / "snyk"
SCAN_HOME = SNYK_ROOT / "home"
OUTPUT_DIR = SNYK_ROOT / "evidence"
TOKEN_FILE = SCAN_HOME / ".snyk-token"
CWE611_RE = re.compile(r"\bCWE[-_: ]?611\b", re.IGNORECASE)
CWE23_RE = re.compile(r"\bCWE[-_: ]?23\b", re.IGNORECASE)


def run(
    argv: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    timeout: int = 600,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def emit(lines: list[str], key: str, value: Any) -> None:
    lines.append(f"{key}={value}")


def safe_text(value: Any) -> str:
    if isinstance(value, str):
        return value
    if value is None:
        return ""
    return json.dumps(value, ensure_ascii=True, sort_keys=True)


def normalize_uri(uri: str) -> str:
    parsed = urlparse(uri)
    value = parsed.path if parsed.scheme == "file" else uri
    return unquote(value).replace("\\", "/").lstrip("./")


def recursive_strings(value: Any) -> list[str]:
    out: list[str] = []
    if isinstance(value, str):
        out.append(value)
    elif isinstance(value, list):
        for item in value:
            out.extend(recursive_strings(item))
    elif isinstance(value, dict):
        for key, item in value.items():
            out.append(str(key))
            out.extend(recursive_strings(item))
    return out


def result_uri(result: dict[str, Any]) -> str:
    locations = result.get("locations")
    if not isinstance(locations, list) or not locations:
        return ""
    for location in locations:
        if not isinstance(location, dict):
            continue
        physical = location.get("physicalLocation")
        if not isinstance(physical, dict):
            continue
        artifact = physical.get("artifactLocation")
        if not isinstance(artifact, dict):
            continue
        uri = artifact.get("uri")
        if isinstance(uri, str):
            return normalize_uri(uri)
    return ""


def parse_sarif(payload: str) -> tuple[dict[str, int], str]:
    try:
        data = json.loads(payload)
    except json.JSONDecodeError as exc:
        return {}, f"SARIF JSON inválido: {exc}"

    if not isinstance(data, dict) or data.get("version") != "2.1.0":
        return {}, "SARIF version != 2.1.0"

    runs = data.get("runs")
    if not isinstance(runs, list) or not runs:
        return {}, "SARIF runs ausente/vazio"

    total = cwe611 = target611 = cwe23 = target23 = 0

    for run_item in runs:
        if not isinstance(run_item, dict):
            return {}, "SARIF run não é objeto"

        tool = run_item.get("tool")
        driver = tool.get("driver") if isinstance(tool, dict) else None
        if not isinstance(driver, dict) or not isinstance(driver.get("name"), str):
            return {}, "SARIF tool.driver inválido"

        invocations = run_item.get("invocations")
        if invocations is not None:
            if not isinstance(invocations, list):
                return {}, "SARIF invocations inválido"
            for invocation in invocations:
                if (
                    not isinstance(invocation, dict)
                    or invocation.get("executionSuccessful") is not True
                ):
                    return {}, "SARIF executionSuccessful != true"

        rules = driver.get("rules")
        if rules is None:
            rules = []
        if not isinstance(rules, list):
            return {}, "SARIF rules inválido"

        by_id: dict[str, dict[str, Any]] = {}
        for rule in rules:
            if not isinstance(rule, dict):
                return {}, "SARIF rule não é objeto"
            rid = rule.get("id")
            if not isinstance(rid, str) or not rid:
                return {}, "SARIF rule id inválido"
            if rid in by_id:
                return {}, "SARIF duplicate rule id"
            by_id[rid] = rule

        results = run_item.get("results")
        if results is None or not isinstance(results, list):
            return {}, "SARIF results inválido/null"

        for result in results:
            if not isinstance(result, dict):
                return {}, "SARIF result não é objeto"

            rid = result.get("ruleId")
            rule_index = result.get("ruleIndex")
            rule: dict[str, Any] = {}
            if isinstance(rid, str) and rid:
                rule = by_id.get(rid, {})
            elif isinstance(rule_index, int) and 0 <= rule_index < len(rules):
                candidate = rules[rule_index]
                rule = candidate if isinstance(candidate, dict) else {}
            elif rid is not None or rule_index is not None:
                return {}, "SARIF ruleId/ruleIndex inconsistente"

            total += 1
            haystack = "\n".join(recursive_strings(result) + recursive_strings(rule))
            uri = result_uri(result)
            is611 = bool(CWE611_RE.search(haystack))
            is23 = bool(CWE23_RE.search(haystack))
            if is611:
                cwe611 += 1
                if uri.endswith(APPSEC04_TARGET):
                    target611 += 1
            if is23:
                cwe23 += 1
                if any(uri.endswith(target) for target in APPSEC05_TARGETS):
                    target23 += 1

    return {
        "total": total,
        "cwe611": cwe611,
        "target611": target611,
        "cwe23": cwe23,
        "target23": target23,
    }, ""


def snapshot_manifest(root: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    count = 0
    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
        rel = path.relative_to(root).as_posix()
        info = path.lstat()
        if stat.S_ISLNK(info.st_mode):
            raise RuntimeError(f"symlink proibido no snapshot: {rel}")
        if info.st_uid != 0:
            raise RuntimeError(f"entrada não root-owned: {rel}")
        if info.st_mode & 0o222:
            raise RuntimeError(f"entrada gravável no snapshot: {rel}")

        digest.update(rel.encode("utf-8", "surrogateescape"))
        digest.update(b"\0")
        digest.update(str(stat.S_IMODE(info.st_mode)).encode("ascii"))
        digest.update(b"\0")
        if path.is_file():
            file_hash = hashlib.sha256(path.read_bytes()).hexdigest()
            digest.update(file_hash.encode("ascii"))
            count += 1
        elif not path.is_dir():
            raise RuntimeError(f"tipo de arquivo não suportado: {rel}")
        digest.update(b"\n")
    return digest.hexdigest(), count


def validate_ci_boundary(snapshot: Path, snyk_bin: Path, output_dir: Path) -> tuple[bool, str]:
    if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("CI") != "true":
        return False, "helper só pode produzir evidência dentro do GitHub Actions"
    if os.environ.get("GITHUB_REPOSITORY") != CANONICAL_REPOSITORY:
        return False, "repositório GitHub não-canônico"
    if os.environ.get("CONECTA_SNYK_SCAN_IDENTITY") != "dedicated-no-sudo":
        return False, "identidade CI dedicada não declarada"
    if os.geteuid() == 0:
        return False, "scan não pode executar como root"

    try:
        snap_info = snapshot.stat()
        bin_info = snyk_bin.stat()
        out_info = output_dir.stat()
    except OSError as exc:
        return False, f"boundary path indisponível: {exc}"

    if snap_info.st_uid != 0 or snap_info.st_mode & 0o222:
        return False, "snapshot raiz não é root-owned/read-only"
    if bin_info.st_uid != 0 or bin_info.st_mode & 0o022 or not (bin_info.st_mode & 0o111):
        return False, "Snyk binário não é root-controlled/executável"
    if out_info.st_uid != os.geteuid():
        return False, "diretório de evidência não pertence à identidade de scan"

    if SUDO.exists():
        probe = run([str(SUDO), "-n", "true"], timeout=10)
        if probe.returncode == 0:
            return False, "identidade dedicada ainda possui sudo não-interativo"

    return True, ""


def write_report(output_dir: Path, lines: list[str]) -> tuple[Path, Path, str]:
    output_dir.mkdir(parents=True, exist_ok=True)
    report = output_dir / "appsec-snyk-final.txt"
    sha_file = output_dir / "appsec-snyk-final.txt.sha256"
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    digest = hashlib.sha256(report.read_bytes()).hexdigest()
    sha_file.write_text(f"{digest}  {report.name}\n", encoding="utf-8")
    return report, sha_file, digest


def self_test() -> int:
    clean = {
        "version": "2.1.0",
        "runs": [{
            "tool": {"driver": {"name": "SnykCode", "rules": []}},
            "invocations": [{"executionSuccessful": True}],
            "results": [],
        }],
    }
    counts, error = parse_sarif(json.dumps(clean))
    if error or counts.get("total") != 0:
        print("SELF_TEST=FAIL clean", file=sys.stderr)
        return 2

    clean_without_invocations = {
        "version": "2.1.0",
        "runs": [{
            "tool": {"driver": {"name": "SnykCode", "rules": []}},
            "results": [],
        }],
    }
    counts, error = parse_sarif(json.dumps(clean_without_invocations))
    if error or counts.get("total") != 0:
        print("SELF_TEST=FAIL clean_without_invocations", file=sys.stderr)
        return 2

    clean_empty_invocations = {
        "version": "2.1.0",
        "runs": [{
            "tool": {"driver": {"name": "SnykCode", "rules": []}},
            "invocations": [],
            "results": [],
        }],
    }
    counts, error = parse_sarif(json.dumps(clean_empty_invocations))
    if error or counts.get("total") != 0:
        print("SELF_TEST=FAIL clean_empty_invocations", file=sys.stderr)
        return 2

    cwe611 = {
        "version": "2.1.0",
        "runs": [{
            "tool": {"driver": {"name": "SnykCode", "rules": [{
                "id": "R611", "properties": {"tags": ["CWE-611"]}
            }]}},
            "invocations": [{"executionSuccessful": True}],
            "results": [{
                "ruleId": "R611",
                "locations": [{"physicalLocation": {"artifactLocation": {
                    "uri": APPSEC04_TARGET
                }}}],
            }],
        }],
    }
    counts, error = parse_sarif(json.dumps(cwe611))
    if error or counts.get("target611") != 1:
        print("SELF_TEST=FAIL cwe611", file=sys.stderr)
        return 2

    cwe23 = {
        "version": "2.1.0",
        "runs": [{
            "tool": {"driver": {"name": "SnykCode", "rules": [{
                "id": "R23", "properties": {"tags": ["CWE-23"]}
            }]}},
            "invocations": [{"executionSuccessful": True}],
            "results": [{
                "ruleId": "R23",
                "locations": [{"physicalLocation": {"artifactLocation": {
                    "uri": "scripts/dlp/submeter_ferret_pentest.py"
                }}}],
            }],
        }],
    }
    counts, error = parse_sarif(json.dumps(cwe23))
    if error or counts.get("target23") != 1:
        print("SELF_TEST=FAIL cwe23", file=sys.stderr)
        return 2

    invalid = {
        "version": "2.1.0",
        "runs": [{
            "tool": {"driver": {"name": "SnykCode", "rules": []}},
            "invocations": [{"executionSuccessful": False}],
            "results": [],
        }],
    }
    _, error = parse_sarif(json.dumps(invalid))
    if not error:
        print("SELF_TEST=FAIL invalid invocation accepted", file=sys.stderr)
        return 2

    print("APPSEC_SNYK_CI_SELF_TEST=PASS")
    return 0


def evidence_run() -> int:
    lines: list[str] = []
    snapshot = SNAPSHOT
    output_dir = OUTPUT_DIR
    snyk_bin = SNYK_BIN
    expected_sha = os.environ.get("CONECTA_EXPECTED_SHA", "").strip()
    github_sha = os.environ.get("GITHUB_SHA", "").strip()

    emit(lines, "APPSEC_CI_BOUNDARY", "GITHUB_HOSTED_DEDICATED_NO_SUDO")
    emit(lines, "GITHUB_REPOSITORY", os.environ.get("GITHUB_REPOSITORY", ""))
    emit(lines, "EXPECTED_SHA", expected_sha)
    emit(lines, "GITHUB_SHA", github_sha)
    emit(lines, "SCAN_UID", os.geteuid())

    if not expected_sha or expected_sha != github_sha:
        emit(lines, "PROVENANCE", "FAIL")
        emit(lines, "APPSEC04_SNYK_REVALIDATION", "BLOCK_PROVENANCE")
        emit(lines, "APPSEC05_SNYK_REVALIDATION", "BLOCK_PROVENANCE")
        write_report(output_dir, lines)
        return 2

    ok, boundary_error = validate_ci_boundary(snapshot, snyk_bin, output_dir)
    emit(lines, "SCAN_IDENTITY_SUDO", "BLOCKED" if ok else "UNKNOWN")
    if not ok:
        emit(lines, "CI_BOUNDARY", "FAIL")
        emit(lines, "CI_BOUNDARY_ERROR", safe_text(boundary_error))
        emit(lines, "APPSEC04_SNYK_REVALIDATION", "BLOCK_CI_BOUNDARY")
        emit(lines, "APPSEC05_SNYK_REVALIDATION", "BLOCK_CI_BOUNDARY")
        write_report(output_dir, lines)
        return 2

    try:
        pre_digest, pre_files = snapshot_manifest(snapshot)
    except Exception as exc:
        emit(lines, "SNAPSHOT_PRECHECK", "FAIL")
        emit(lines, "SNAPSHOT_ERROR", safe_text(str(exc)))
        emit(lines, "APPSEC04_SNYK_REVALIDATION", "BLOCK_SNAPSHOT")
        emit(lines, "APPSEC05_SNYK_REVALIDATION", "BLOCK_SNAPSHOT")
        write_report(output_dir, lines)
        return 2

    emit(lines, "CI_BOUNDARY", "PASS")
    emit(lines, "SNAPSHOT_ROOT_OWNED_READ_ONLY", "PASS")
    emit(lines, "SNAPSHOT_PRE_SHA256", pre_digest)
    emit(lines, "SNAPSHOT_FILES", pre_files)

    token_path = TOKEN_FILE
    try:
        token_info = token_path.stat()
        if token_info.st_uid != os.geteuid() or token_info.st_mode & 0o077:
            raise RuntimeError("token file ownership/mode inválido")
        token = token_path.read_text(encoding="utf-8").strip()
        token_path.unlink()
    except Exception as exc:
        emit(lines, "SNYK_AUTH", "INVALID_TOKEN_FILE")
        emit(lines, "SNYK_AUTH_ERROR", safe_text(str(exc)))
        emit(lines, "APPSEC04_SNYK_REVALIDATION", "BLOCK_SNYK_AUTH")
        emit(lines, "APPSEC05_SNYK_REVALIDATION", "BLOCK_SNYK_AUTH")
        write_report(output_dir, lines)
        return 2

    if not token:
        emit(lines, "SNYK_AUTH", "EMPTY")
        emit(lines, "APPSEC04_SNYK_REVALIDATION", "BLOCK_SNYK_AUTH")
        emit(lines, "APPSEC05_SNYK_REVALIDATION", "BLOCK_SNYK_AUTH")
        write_report(output_dir, lines)
        return 2

    emit(lines, "SNYK_AUTH", "EPHEMERAL_0400_FILE_CONSUMED")
    snyk_env = {
        "PATH": "/usr/bin:/bin",
        "LANG": "C",
        "LC_ALL": "C",
        "HOME": str(SCAN_HOME),
        "SNYK_TOKEN": token,
    }
    scan = run(
        [str(snyk_bin), "code", "test", "--sarif", "--include-ignores"],
        cwd=snapshot,
        env=snyk_env,
        timeout=900,
    )

    emit(lines, "SNYK_SCAN_RC", scan.returncode)
    if scan.stderr.strip():
        stderr_safe = scan.stderr.replace(token, "[REDACTED]").strip()
        emit(lines, "SNYK_SCAN_STDERR", safe_text(stderr_safe[:2000]))
    counts, sarif_error = parse_sarif(scan.stdout)
    if sarif_error:
        emit(lines, "SARIF_VALIDATION", "FAIL")
        emit(lines, "SARIF_ERROR", safe_text(sarif_error))
        emit(lines, "APPSEC04_SNYK_REVALIDATION", "BLOCK_SARIF")
        emit(lines, "APPSEC05_SNYK_REVALIDATION", "BLOCK_SARIF")
        write_report(output_dir, lines)
        return 2

    emit(lines, "SARIF_VALIDATION", "PASS")
    emit(lines, "SNYK_TOTAL_RESULTS", counts["total"])
    emit(lines, "SNYK_CWE611_RESULTS", counts["cwe611"])
    emit(lines, "SNYK_TARGET_CWE611_RESULTS", counts["target611"])
    emit(lines, "SNYK_CWE23_RESULTS", counts["cwe23"])
    emit(lines, "SNYK_APPSEC05_TARGET_CWE23_RESULTS", counts["target23"])

    try:
        post_digest, post_files = snapshot_manifest(snapshot)
    except Exception as exc:
        emit(lines, "SNAPSHOT_POSTSCAN_INTEGRITY", "FAIL")
        emit(lines, "SNAPSHOT_ERROR", safe_text(str(exc)))
        emit(lines, "APPSEC04_SNYK_REVALIDATION", "BLOCK_SNAPSHOT_CHANGED")
        emit(lines, "APPSEC05_SNYK_REVALIDATION", "BLOCK_SNAPSHOT_CHANGED")
        write_report(output_dir, lines)
        return 2

    emit(lines, "SNAPSHOT_POST_SHA256", post_digest)
    emit(lines, "SNAPSHOT_POST_FILES", post_files)
    integrity_ok = pre_digest == post_digest and pre_files == post_files
    emit(lines, "SNAPSHOT_POSTSCAN_INTEGRITY", "PASS" if integrity_ok else "FAIL")

    appsec04_ok = counts["cwe611"] == 0 and counts["target611"] == 0
    appsec05_ok = counts["cwe23"] == 0 and counts["target23"] == 0
    clean = scan.returncode == 0 and counts["total"] == 0 and integrity_ok

    emit(lines, "APPSEC04_CWE611", "PASS" if appsec04_ok else "FAIL")
    emit(lines, "APPSEC05_CWE23", "PASS" if appsec05_ok else "FAIL")
    emit(lines, "APPSEC04_SNYK_REVALIDATION", "PASS" if clean and appsec04_ok else "BLOCK")
    emit(lines, "APPSEC05_SNYK_REVALIDATION", "PASS" if clean and appsec05_ok else "BLOCK")

    report, sha_file, digest = write_report(output_dir, lines)
    print(f"REPORT={report}")
    print(f"SHA256_FILE={sha_file}")
    print(f"SHA256={digest}")
    return 0 if clean and appsec04_ok and appsec05_ok else 2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    return evidence_run()


if __name__ == "__main__":
    raise SystemExit(main())
