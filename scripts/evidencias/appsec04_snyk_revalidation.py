#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import tarfile
import tempfile
import unicodedata
from pathlib import Path
from typing import Any

TARGET = "scripts/evidencias/ops01_ep126_readonly.py"
APPSEC05_TARGETS = {
    "scripts/dlp/submeter_ferret_pentest.py",
    "scripts/dlp/snapshot_ferret_input.py",
}
CANONICAL_REPO_SLUG = "andrea-kozicki/conectaeduca"
CANONICAL_MAIN_URL = "https://github.com/andrea-kozicki/conectaeduca.git"


def run(
    cmd: list[str],
    cwd: Path | None = None,
    timeout: int = 300,
    env: dict[str, str] | None = None,
) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(cwd) if cwd else None,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
            env=env,
        )
        return proc.returncode, proc.stdout, proc.stderr
    except FileNotFoundError:
        return 127, "", f"command not found: {cmd[0]}"
    except subprocess.TimeoutExpired:
        return 124, "", f"timeout: {cmd[0]}"


def canonical_origin_url(url: str) -> bool:
    value = url.strip()
    patterns = (
        r"^https://github\.com/([^/]+/[^/]+?)(?:\.git)?/?$",
        r"^git@github\.com:([^/]+/[^/]+?)(?:\.git)?$",
        r"^ssh://git@github\.com/([^/]+/[^/]+?)(?:\.git)?/?$",
    )
    for pattern in patterns:
        match = re.fullmatch(
            pattern,
            value,
            flags=re.IGNORECASE | re.ASCII,
        )
        if match and match.group(1).lower() == CANONICAL_REPO_SLUG:
            return True
    return False


def isolated_git_env(
    base_env: dict[str, str] | None = None,
) -> dict[str, str]:
    env = dict(os.environ if base_env is None else base_env)
    for key in list(env):
        if (
            key in {"GIT_CONFIG", "GIT_CONFIG_PARAMETERS"}
            or key.startswith("GIT_CONFIG_KEY_")
            or key.startswith("GIT_CONFIG_VALUE_")
            or key in {
                "GIT_DIR",
                "GIT_WORK_TREE",
                "GIT_COMMON_DIR",
                "GIT_CONFIG_SYSTEM",
                "GIT_CONFIG_GLOBAL",
                "GIT_CONFIG_NOSYSTEM",
                "GIT_CONFIG_COUNT",
            }
        ):
            env.pop(key, None)
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_CONFIG_GLOBAL"] = os.devnull
    env["GIT_CONFIG_COUNT"] = "0"
    env["GIT_TERMINAL_PROMPT"] = "0"
    return env


def canonical_remote_main_query() -> tuple[int, str, str]:
    """Query canonical main without inheriting any repository-local Git config."""
    env = isolated_git_env()
    with tempfile.TemporaryDirectory(prefix="conectaeduca-git-remote-") as tmp:
        tmp_path = Path(tmp).resolve()
        env["GIT_CEILING_DIRECTORIES"] = str(tmp_path)
        return run(
            ["git", "ls-remote", "--exit-code", CANONICAL_MAIN_URL, "refs/heads/main"],
            tmp_path,
            120,
            env,
        )


def git_blob_sha1(path: Path) -> str:
    size = path.stat().st_size
    digest = hashlib.sha1()
    digest.update(f"blob {size}\0".encode("ascii"))
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def materialize_git_snapshot(
    root: Path,
    commit: str,
    destination: Path,
) -> tuple[bool, str, int, str]:
    """Materialize and verify a read-only snapshot from the validated Git commit."""
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        return False, "", 0, "invalid commit id"

    destination.mkdir(mode=0o700, parents=True, exist_ok=False)
    archive = destination.parent / "snapshot.tar"
    rc, _, err = run(
        ["git", "archive", "--format=tar", f"--output={archive}", commit],
        root,
        120,
    )
    if rc != 0:
        return False, "", 0, "git archive failed: " + err.strip()[:200]

    rc, tree_raw, tree_err = run(
        ["git", "ls-tree", "-r", "-z", commit],
        root,
        120,
    )
    if rc != 0:
        return False, "", 0, "git ls-tree failed: " + tree_err.strip()[:200]

    expected: dict[str, tuple[str, str]] = {}
    for record in tree_raw.split(chr(0)):
        if not record:
            continue
        try:
            meta, path_text = record.split("\t", 1)
            mode, kind, object_id = meta.split(" ", 2)
        except ValueError:
            return False, "", 0, "malformed git ls-tree record"
        if kind != "blob" or mode not in {"100644", "100755"}:
            return False, "", 0, f"unsupported tracked entry: {mode} {kind} {path_text}"
        if (
            not path_text
            or Path(path_text).is_absolute()
            or ".." in Path(path_text).parts
            or path_text in expected
        ):
            return False, "", 0, "unsafe or duplicate tracked path"
        expected[path_text] = (mode, object_id)

    actual: set[str] = set()
    try:
        with tarfile.open(archive, mode="r:") as tar:
            for member in tar:
                if member.name in {".", "./"}:
                    continue
                rel = Path(member.name)
                if rel.is_absolute() or ".." in rel.parts or not rel.parts:
                    return False, "", 0, "unsafe archive path"
                target = destination.joinpath(*rel.parts)
                if member.isdir():
                    target.mkdir(mode=0o755, parents=True, exist_ok=True)
                    continue
                if not member.isfile():
                    return False, "", 0, "archive contains non-regular entry"
                target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
                source = tar.extractfile(member)
                if source is None:
                    return False, "", 0, "archive regular file has no payload"
                with source, target.open("xb") as output:
                    while True:
                        chunk = source.read(1024 * 1024)
                        if not chunk:
                            break
                        output.write(chunk)
                actual.add(rel.as_posix())
    except (OSError, tarfile.TarError) as exc:
        return False, "", 0, f"snapshot extraction failed: {exc}"

    if actual != set(expected):
        return False, "", 0, "snapshot file set differs from git tree"

    for path_text, (mode, object_id) in expected.items():
        path = destination / path_text
        try:
            if not path.is_file() or path.is_symlink():
                return False, "", 0, f"snapshot entry is not regular: {path_text}"
            if git_blob_sha1(path) != object_id:
                return False, "", 0, f"snapshot blob mismatch: {path_text}"
            path.chmod(0o555 if mode == "100755" else 0o444)
        except OSError as exc:
            return False, "", 0, f"snapshot verification failed: {path_text}: {exc}"

    for directory in sorted(
        (p for p in destination.rglob("*") if p.is_dir()),
        key=lambda p: len(p.parts),
        reverse=True,
    ):
        directory.chmod(0o555)
    destination.chmod(0o555)

    archive_digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    return True, archive_digest, len(expected), ""


def verify_materialized_snapshot(
    root: Path,
    commit: str,
    destination: Path,
) -> tuple[bool, int, str]:
    """Revalidate snapshot bytes after Snyk and before any PASS verdict."""
    rc, tree_raw, tree_err = run(
        ["git", "ls-tree", "-r", "-z", commit],
        root,
        120,
    )
    if rc != 0:
        return False, 0, "git ls-tree failed: " + tree_err.strip()[:200]

    expected: dict[str, str] = {}
    for record in tree_raw.split(chr(0)):
        if not record:
            continue
        try:
            meta, path_text = record.split("\t", 1)
            mode, kind, object_id = meta.split(" ", 2)
        except ValueError:
            return False, 0, "malformed git ls-tree record"
        if kind != "blob" or mode not in {"100644", "100755"}:
            return False, 0, f"unsupported tracked entry: {mode} {kind} {path_text}"
        if (
            not path_text
            or Path(path_text).is_absolute()
            or ".." in Path(path_text).parts
            or path_text in expected
        ):
            return False, 0, "unsafe or duplicate tracked path"
        expected[path_text] = object_id

    actual: set[str] = set()
    try:
        for path in destination.rglob("*"):
            if path.is_symlink():
                return False, 0, "snapshot contains symlink after scan"
            if path.is_dir():
                continue
            if not path.is_file():
                return False, 0, "snapshot contains non-regular entry after scan"
            rel = path.relative_to(destination).as_posix()
            actual.add(rel)
    except (OSError, ValueError) as exc:
        return False, 0, f"snapshot post-scan walk failed: {exc}"

    if actual != set(expected):
        missing = sorted(set(expected) - actual)
        extra = sorted(actual - set(expected))
        detail = (
            f"snapshot file set changed: missing={missing[:3]} extra={extra[:3]}"
        )
        return False, 0, detail

    for path_text, object_id in expected.items():
        path = destination / path_text
        try:
            if git_blob_sha1(path) != object_id:
                return False, 0, f"snapshot blob changed during scan: {path_text}"
        except OSError as exc:
            return False, 0, f"snapshot post-scan hash failed: {path_text}: {exc}"

    return True, len(expected), ""


def lock_snapshot_for_scan(
    temp_root: Path,
) -> tuple[bool, int, int, str]:
    """Make the complete snapshot tree non-writable to the Snyk process user."""
    uid = os.geteuid()
    gid = os.getegid()
    if uid == 0:
        return False, uid, gid, "refuse root scan: DAC isolation cannot protect against EUID 0"

    rc, _, _ = run(["sudo", "-n", "-v"], timeout=10)
    if rc != 0:
        return False, uid, gid, (
            "sudo credential unavailable; run 'sudo -v' once and rerun the gate"
        )

    ownership_taken = False

    def rollback_setup(reason: str) -> tuple[bool, int, int, str]:
        if ownership_taken:
            run(
                ["sudo", "-n", "chown", "-R", f"{uid}:{gid}", str(temp_root)],
                timeout=120,
            )
            run(
                ["chmod", "-R", "u+rwX", str(temp_root)],
                timeout=120,
            )
            try:
                temp_root.chmod(0o700)
            except OSError:
                pass
        return False, uid, gid, reason

    rc, _, err = run(
        ["sudo", "-n", "chown", "-R", "0:0", str(temp_root)],
        timeout=120,
    )
    if rc != 0:
        return False, uid, gid, "root ownership failed: " + err.strip()[:200]
    ownership_taken = True

    rc, _, err = run(
        ["sudo", "-n", "chmod", "-R", "a-w", str(temp_root)],
        timeout=120,
    )
    if rc != 0:
        return rollback_setup("write-bit removal failed: " + err.strip()[:200])

    rc, _, err = run(
        ["sudo", "-n", "chmod", "a+rx", str(temp_root)],
        timeout=30,
    )
    if rc != 0:
        return rollback_setup(
            "temporary root traversal failed: " + err.strip()[:200]
        )

    try:
        paths = [temp_root, *temp_root.rglob("*")]
        for path in paths:
            stat = path.lstat()
            if path.is_symlink():
                return rollback_setup(
                    f"symlink in isolated snapshot: {path.name}"
                )
            if stat.st_uid != 0 or stat.st_gid != 0:
                return rollback_setup(
                    f"non-root-owned isolated entry: {path.name}"
                )
            if stat.st_mode & 0o222:
                return rollback_setup(
                    f"write bit remains in isolated entry: {path.name}"
                )
            if os.access(path, os.W_OK):
                return rollback_setup(
                    f"scan user can still write isolated entry: {path.name}"
                )
    except OSError as exc:
        return rollback_setup(f"isolation verification failed: {exc}")

    return True, uid, gid, ""


def unlock_snapshot_after_scan(
    temp_root: Path,
    uid: int,
    gid: int,
) -> tuple[bool, str]:
    """Return temporary files to the caller solely so they can be deleted."""
    rc, _, err = run(
        ["sudo", "-n", "chown", "-R", f"{uid}:{gid}", str(temp_root)],
        timeout=120,
    )
    if rc != 0:
        return False, "temporary ownership restore failed: " + err.strip()[:200]

    try:
        temp_root.chmod(0o700)
        snapshot_root = temp_root / "repo"
        if snapshot_root.exists():
            restore_snapshot_permissions(snapshot_root)
        archive = temp_root / "snapshot.tar"
        if archive.exists():
            archive.chmod(0o600)
    except OSError as exc:
        return False, f"temporary permission restore failed: {exc}"

    return True, ""


def restore_snapshot_permissions(destination: Path) -> None:
    """Best-effort permission reset so TemporaryDirectory can remove the snapshot."""
    for path in sorted(
        destination.rglob("*"),
        key=lambda p: len(p.parts),
        reverse=True,
    ):
        try:
            path.chmod(0o700 if path.is_dir() else 0o600)
        except OSError:
            pass
    try:
        destination.chmod(0o700)
    except OSError:
        pass


def safe_metadata_text(value: Any) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    return all(
        unicodedata.category(ch) not in {"Cc", "Cs", "Zl", "Zp"}
        for ch in value
    )


def special_index_entries(raw: str) -> list[str]:
    """Return tracked paths whose ls-files -v tag is not the normal H tag."""
    flagged: list[str] = []
    for record in raw.split(chr(0)):
        if not record:
            continue
        if len(record) < 3 or record[1] != " ":
            return ["<malformed-ls-files-record>"]
        if record[0] != "H":
            flagged.append(record[2:])
    return flagged


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
        tool = run_item["tool"] if "tool" in run_item else None
        if not isinstance(tool, dict):
            return False, f"run[{idx}].tool is not an object"
        driver = tool["driver"] if "driver" in tool else None
        if not isinstance(driver, dict):
            return False, f"run[{idx}] missing or invalid tool.driver"
        driver_name = driver.get("name")
        if not safe_metadata_text(driver_name):
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
        seen_rule_ids: set[str] = set()
        for rule_idx, rule in enumerate(rules):
            if not isinstance(rule, dict):
                return False, f"run[{idx}].tool.driver.rules[{rule_idx}] is not an object"
            rule_id = rule.get("id")
            if not safe_metadata_text(rule_id):
                return False, (
                    f"run[{idx}].tool.driver.rules[{rule_idx}] missing or invalid id"
                )
            if rule_id in seen_rule_ids:
                return False, f"run[{idx}].tool.driver.rules has duplicate id: {rule_id}"
            seen_rule_ids.add(rule_id)

        for result_idx, result in enumerate(results):
            if not isinstance(result, dict):
                return False, f"run[{idx}].results[{result_idx}] is not an object"

            if "ruleId" in result:
                rule_id = result["ruleId"]
                if not safe_metadata_text(rule_id):
                    return False, (
                        f"run[{idx}].results[{result_idx}] has invalid ruleId"
                    )

            if "ruleIndex" in result:
                rule_index = result["ruleIndex"]
                if (
                    not isinstance(rule_index, int)
                    or isinstance(rule_index, bool)
                    or rule_index < 0
                    or rule_index >= len(rules)
                ):
                    return False, (
                        f"run[{idx}].results[{result_idx}] has invalid ruleIndex"
                    )
                if "ruleId" in result:
                    indexed_rule_id = rules[rule_index]["id"]
                    if result["ruleId"] != indexed_rule_id:
                        return False, (
                            f"run[{idx}].results[{result_idx}] has inconsistent ruleId/ruleIndex"
                        )

            locations = result["locations"] if "locations" in result else []
            if not isinstance(locations, list):
                return False, (
                    f"run[{idx}].results[{result_idx}].locations is not a list"
                )
            for location_idx, location in enumerate(locations):
                if not isinstance(location, dict):
                    return False, (
                        f"run[{idx}].results[{result_idx}].locations[{location_idx}] "
                        "is not an object"
                    )
                if "physicalLocation" not in location:
                    continue
                physical = location["physicalLocation"]
                if not isinstance(physical, dict):
                    return False, (
                        f"run[{idx}].results[{result_idx}].locations[{location_idx}]."
                        "physicalLocation is not an object"
                    )
                if "artifactLocation" not in physical:
                    continue
                artifact = physical["artifactLocation"]
                if not isinstance(artifact, dict):
                    return False, (
                        f"run[{idx}].results[{result_idx}].locations[{location_idx}]."
                        "physicalLocation.artifactLocation is not an object"
                    )
                if "uri" in artifact:
                    uri = artifact["uri"]
                    if not safe_metadata_text(uri):
                        return False, (
                            f"run[{idx}].results[{result_idx}].locations[{location_idx}]."
                            "physicalLocation.artifactLocation.uri is invalid"
                        )
    return True, "ok"


def sarif_results(payload: dict[str, Any]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for run_item in payload.get("runs", []) or []:
        rules: dict[str, dict[str, Any]] = {}
        tool = run_item["tool"]
        driver = tool["driver"]
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
            for loc in result["locations"] if "locations" in result else []:
                physical = loc.get("physicalLocation")
                if physical is None:
                    continue
                artifact = physical.get("artifactLocation")
                if artifact is None:
                    continue
                uri = artifact.get("uri") or ""
                if uri:
                    paths.append(uri.replace("\\", "/").lstrip("./"))

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
                    "cwe23": "CWE-23" in metadata_blob or "CWE_23" in metadata_blob,
                }
            )
    return rows


def classify(rows: list[dict[str, Any]]) -> dict[str, int]:
    total = len(rows)
    cwe611 = 0
    target = 0
    target_cwe611 = 0
    cwe23 = 0
    appsec05_target = 0
    appsec05_target_cwe23 = 0
    for row in rows:
        is_target = any(path.endswith(TARGET) for path in row["paths"])
        is_cwe611 = bool(row["cwe611"])
        is_cwe23 = bool(row["cwe23"])
        is_appsec05_target = any(
            any(path.endswith(target) for target in APPSEC05_TARGETS)
            for path in row["paths"]
        )
        cwe611 += int(is_cwe611)
        target += int(is_target)
        target_cwe611 += int(is_target and is_cwe611)
        cwe23 += int(is_cwe23)
        appsec05_target += int(is_appsec05_target)
        appsec05_target_cwe23 += int(is_appsec05_target and is_cwe23)
    return {
        "total": total,
        "cwe611": cwe611,
        "target": target,
        "target_cwe611": target_cwe611,
        "cwe23": cwe23,
        "appsec05_target": appsec05_target,
        "appsec05_target_cwe23": appsec05_target_cwe23,
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

    bad_cwe23 = {
        "version": "2.1.0",
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": "Snyk Code",
                        "rules": [
                            {"id": "R23", "properties": {"tags": ["CWE-23"]}}
                        ],
                    }
                },
                "results": [
                    {
                        "ruleId": "R23",
                        "locations": [
                            {
                                "physicalLocation": {
                                    "artifactLocation": {
                                        "uri": "scripts/dlp/submeter_ferret_pentest.py"
                                    }
                                }
                            }
                        ],
                    }
                ],
            }
        ],
    }

    for accepted_origin in (
        "https://github.com/andrea-kozicki/conectaeduca.git",
        "https://github.com/andrea-kozicki/conectaeduca",
        "git@github.com:andrea-kozicki/conectaeduca.git",
        "ssh://git@github.com/andrea-kozicki/conectaeduca.git",
    ):
        if not canonical_origin_url(accepted_origin):
            raise SystemExit(f"self-test canonical origin rejected: {accepted_origin}")

    for rejected_origin in (
        "https://github.com/other/conectaeduca.git",
        "https://user:token@github.com/andrea-kozicki/conectaeduca.git",
        "http://github.com/andrea-kozicki/conectaeduca.git",
        "git@gitlab.com:andrea-kozicki/conectaeduca.git",
        "https://gıthub.com/andrea-kozicki/conectaeduca.git",
    ):
        if canonical_origin_url(rejected_origin):
            raise SystemExit(f"self-test noncanonical origin accepted: {rejected_origin}")

    poisoned_git_env = {
        "PATH": os.environ.get("PATH", ""),
        "GIT_CONFIG_PARAMETERS": "'url.https://mirror.invalid/.insteadOf=https://github.com/'",
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": "url.https://mirror.invalid/.insteadOf",
        "GIT_CONFIG_VALUE_0": "https://github.com/",
        "GIT_DIR": "/tmp/not-a-real-git-dir",
    }
    isolated_env = isolated_git_env(poisoned_git_env)
    for forbidden_env in (
        "GIT_CONFIG_PARAMETERS",
        "GIT_CONFIG_KEY_0",
        "GIT_CONFIG_VALUE_0",
        "GIT_DIR",
    ):
        if forbidden_env in isolated_env:
            raise SystemExit(
                f"self-test isolated git env retained {forbidden_env}"
            )
    if isolated_env.get("GIT_CONFIG_NOSYSTEM") != "1":
        raise SystemExit("self-test isolated git env missing GIT_CONFIG_NOSYSTEM")
    if isolated_env.get("GIT_CONFIG_GLOBAL") != os.devnull:
        raise SystemExit("self-test isolated git env missing null global config")
    if isolated_env.get("GIT_CONFIG_COUNT") != "0":
        raise SystemExit("self-test isolated git env missing zero command config")
    if isolated_env.get("GIT_TERMINAL_PROMPT") != "0":
        raise SystemExit("self-test isolated git env allows terminal prompt")
    if "GIT_CEILING_DIRECTORIES" in isolated_env:
        raise SystemExit("self-test base isolated git env unexpectedly sets ceiling")
    if special_index_entries("H normal.py" + chr(0)) != []:
        raise SystemExit("self-test normal index entry rejected")
    if special_index_entries("h assumed.py" + chr(0)) != ["assumed.py"]:
        raise SystemExit("self-test assume-unchanged index entry not rejected")
    if special_index_entries("S sparse.py" + chr(0)) != ["sparse.py"]:
        raise SystemExit("self-test skip-worktree index entry not rejected")
    if special_index_entries("H normal.py" + chr(0) + "h assumed.py" + chr(0)) != ["assumed.py"]:
        raise SystemExit("self-test special index entry after normal record not rejected")
    if not special_index_entries("malformed"):
        raise SystemExit("self-test malformed ls-files record not rejected")

    bad_surrogate = chr(0xD800)

    for invalid in (
        {},
        {"version": "2.1.0", "runs": []},
        {"version": "2.0.0", "runs": [{}]},
        {"version": "2.1.0", "runs": [{"results": []}]},
        {"version": "2.1.0", "runs": [{"tool": None, "results": []}]},
        {"version": "2.1.0", "runs": [{"tool": "Snyk Code", "results": []}]},
        {"version": "2.1.0", "runs": [{"tool": [], "results": []}]},
        {"version": "2.1.0", "runs": [{"tool": {}, "results": []}]},
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
            "runs": [
                {
                    "tool": {"driver": {"name": "Snyk Code", "rules": [{"id": "R611"}]}},
                    "results": [{"ruleId": "OTHER", "ruleIndex": 0}],
                }
            ],
        },
        {
            "version": "2.1.0",
            "runs": [
                {
                    "tool": {"driver": {"name": "Snyk Code", "rules": [{"id": "DUP"}, {"id": "DUP"}]}},
                    "results": [{"ruleId": "DUP", "ruleIndex": 0}],
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
            "runs": [{"tool": {"driver": {"name": "Snyk Code", "rules": [None]}}, "results": []}],
        },
        {
            "version": "2.1.0",
            "runs": [{"tool": {"driver": {"name": "Snyk Code", "rules": ["R1"]}}, "results": []}],
        },
        {
            "version": "2.1.0",
            "runs": [{"tool": {"driver": {"name": "Snyk Code", "rules": [{}]}}, "results": []}],
        },
        {
            "version": "2.1.0",
            "runs": [{"tool": {"driver": {"name": "Snyk Code", "rules": [{"id": ""}]}}, "results": []}],
        },
        {
            "version": "2.1.0",
            "runs": [
                {
                    "tool": {"driver": {"name": "Snyk Code", "rules": []}},
                    "results": [{"ruleId": 611}],
                }
            ],
        },
        {
            "version": "2.1.0",
            "runs": [
                {
                    "tool": {"driver": {"name": "Snyk Code", "rules": []}},
                    "results": [{"ruleId": "R1\nAPPSEC04_SNYK_REVALIDATION=PASS"}],
                }
            ],
        },
        {
            "version": "2.1.0",
            "runs": [
                {
                    "tool": {"driver": {"name": "Snyk Code", "rules": []}},
                    "results": [{"ruleId": bad_surrogate}],
                }
            ],
        },
        {
            "version": "2.1.0",
            "runs": [
                {
                    "tool": {"driver": {"name": "Snyk Code", "rules": []}},
                    "results": [
                        {
                            "locations": [
                                {
                                    "physicalLocation": {
                                        "artifactLocation": {
                                            "uri": "src/x.py\nAPPSEC04_SNYK_REVALIDATION=PASS"
                                        }
                                    }
                                }
                            ]
                        }
                    ],
                }
            ],
        },
        {
            "version": "2.1.0",
            "runs": [
                {
                    "tool": {"driver": {"name": "Snyk Code", "rules": []}},
                    "results": [{"ruleId": ""}],
                }
            ],
        },
        {
            "version": "2.1.0",
            "runs": [
                {
                    "tool": {"driver": {"name": "Snyk Code", "rules": []}},
                    "results": [{"locations": None}],
                }
            ],
        },
        {
            "version": "2.1.0",
            "runs": [
                {
                    "tool": {"driver": {"name": "Snyk Code", "rules": []}},
                    "results": [{"locations": ["not-an-object"]}],
                }
            ],
        },
        {
            "version": "2.1.0",
            "runs": [
                {
                    "tool": {"driver": {"name": "Snyk Code", "rules": []}},
                    "results": [{"locations": [{"physicalLocation": "bad"}]}],
                }
            ],
        },
        {
            "version": "2.1.0",
            "runs": [
                {
                    "tool": {"driver": {"name": "Snyk Code", "rules": []}},
                    "results": [
                        {
                            "locations": [
                                {"physicalLocation": {"artifactLocation": "bad"}}
                            ]
                        }
                    ],
                }
            ],
        },
        {
            "version": "2.1.0",
            "runs": [
                {
                    "tool": {"driver": {"name": "Snyk Code", "rules": []}},
                    "results": [
                        {
                            "locations": [
                                {
                                    "physicalLocation": {
                                        "artifactLocation": {"uri": 123}
                                    }
                                }
                            ]
                        }
                    ],
                }
            ],
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
        {
            "version": "2.1.0",
            "runs": [
                {
                    "tool": {"driver": {"name": "Snyk Code", "rules": []}},
                    "invocations": [{}],
                    "results": [],
                }
            ],
        },
    ):
        ok, _ = validate_sarif(invalid)
        if ok:
            raise SystemExit(f"self-test invalid SARIF accepted: {invalid}")

    matching_rule_reference = {
        "version": "2.1.0",
        "runs": [
            {
                "tool": {"driver": {"name": "Snyk Code", "rules": [{"id": "R611MATCH", "properties": {"tags": ["CWE-611"]}}]}},
                "results": [{"ruleId": "R611MATCH", "ruleIndex": 0, "locations": [{"physicalLocation": {"artifactLocation": {"uri": TARGET}}}]}],
            }
        ],
    }

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

    for valid in (
        clean,
        bad,
        bad_rule_index,
        bad_cwe23,
        matching_rule_reference,
        clean_invocation,
    ):
        ok, reason = validate_sarif(valid)
        if not ok:
            raise SystemExit(f"self-test valid SARIF rejected: {reason}")

    c1 = classify(sarif_results(clean))
    c2 = classify(sarif_results(bad))
    c3 = classify(sarif_results(bad_rule_index))
    c4 = classify(sarif_results(matching_rule_reference))
    c5 = classify(sarif_results(bad_cwe23))
    expected_clean = {
        "total": 1,
        "cwe611": 0,
        "target": 0,
        "target_cwe611": 0,
        "cwe23": 0,
        "appsec05_target": 0,
        "appsec05_target_cwe23": 0,
    }
    if c1 != expected_clean:
        raise SystemExit(f"self-test clean failed: {c1}")
    expected_cwe611 = {
        "total": 1,
        "cwe611": 1,
        "target": 1,
        "target_cwe611": 1,
        "cwe23": 0,
        "appsec05_target": 0,
        "appsec05_target_cwe23": 0,
    }
    if c2 != expected_cwe611:
        raise SystemExit(f"self-test CWE-611 failed: {c2}")
    if c3 != expected_cwe611:
        raise SystemExit(f"self-test CWE-611 ruleIndex failed: {c3}")
    if c4 != expected_cwe611:
        raise SystemExit(f"self-test matching ruleId/ruleIndex failed: {c4}")
    if c5 != {
        "total": 1,
        "cwe611": 0,
        "target": 0,
        "target_cwe611": 0,
        "cwe23": 1,
        "appsec05_target": 1,
        "appsec05_target_cwe23": 1,
    }:
        raise SystemExit(f"self-test CWE-23 Ferret failed: {c5}")
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
    rc3, origin_out, _ = run(
        [
            "git",
            "config",
            "--local",
            "--no-includes",
            "--get-all",
            "remote.origin.url",
        ],
        root,
        60,
    )
    origin_urls = [
        line.strip()
        for line in origin_out.splitlines()
        if line.strip()
    ]
    origin_ok = (
        rc3 == 0
        and len(origin_urls) == 1
        and canonical_origin_url(origin_urls[0])
    )
    rc4, remote_out, remote_err = canonical_remote_main_query()
    rc5, dirty, _ = run(
        ["git", "-c", "core.fsmonitor=false", "status", "--porcelain", "--untracked-files=all"],
        root,
    )
    rc6, index_state, _ = run(
        ["git", "ls-files", "-v", "-z"],
        root,
    )
    special_index = special_index_entries(index_state) if rc6 == 0 else ["<git-ls-files-failed>"]
    rc7, fsmonitor_state, _ = run(
        ["git", "ls-files", "-f", "-z"],
        root,
    )
    fsmonitor_index = (
        special_index_entries(fsmonitor_state)
        if rc7 == 0
        else ["<git-ls-files-fsmonitor-failed>"]
    )

    branch = branch.strip()
    head = head.strip()
    remote_parts = remote_out.strip().split()
    remote_main = (
        remote_parts[0]
        if rc4 == 0 and len(remote_parts) >= 2 and remote_parts[1] == "refs/heads/main"
        else ""
    )
    emit(f"BRANCH={branch or 'unknown'}")
    emit(f"HEAD={head or 'unknown'}")
    emit(f"ORIGIN_RAW_URL_COUNT={len(origin_urls)}")
    emit(f"ORIGIN_CANONICAL={'PASS' if origin_ok else 'FAIL'}")
    emit("REMOTE_QUERY_GIT_CONFIG_ISOLATED=YES")
    emit("REMOTE_QUERY_LOCAL_CONFIG_DISCOVERY=BLOCKED_BY_TEMP_CEILING")
    emit(f"REMOTE_MAIN={remote_main or 'unavailable'}")
    emit(f"REMOTE_MAIN_QUERY={'PASS' if remote_main else 'FAIL'}")
    emit("WORKTREE_STATUS_FSMONITOR_DISABLED=YES")
    emit(f"WORKTREE_DIRTY={'YES' if dirty.strip() else 'NO'}")
    emit(f"INDEX_SPECIAL_FLAGS_COUNT={len(special_index)}")
    emit(f"INDEX_TRACKING_FLAGS={'PASS' if not special_index else 'FAIL'}")
    emit(f"INDEX_FSMONITOR_FLAGS_COUNT={len(fsmonitor_index)}")
    emit(f"INDEX_FSMONITOR_FLAGS={'PASS' if not fsmonitor_index else 'FAIL'}")

    provenance_ok = (
        rc == 0
        and rc2 == 0
        and rc3 == 0
        and rc4 == 0
        and rc5 == 0
        and rc6 == 0
        and rc7 == 0
        and not special_index
        and not fsmonitor_index
        and origin_ok
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

    emit("SNYK_INCLUDE_IGNORES=YES")
    with tempfile.TemporaryDirectory(prefix="conectaeduca-snyk-snapshot-") as tmp:
        snapshot_root = Path(tmp).resolve() / "repo"
        snapshot_ok, snapshot_sha256, snapshot_files, snapshot_error = materialize_git_snapshot(
            root,
            head,
            snapshot_root,
        )
        emit(f"SNYK_SNAPSHOT_COMMIT={head}")
        emit("SNYK_SCAN_INPUT=VERIFIED_GIT_COMMIT_SNAPSHOT")
        emit(f"SNYK_SNAPSHOT_FILES={snapshot_files}")
        emit(f"SNYK_SNAPSHOT_ARCHIVE_SHA256={snapshot_sha256 or 'unavailable'}")
        emit(f"SNYK_SNAPSHOT_READ_ONLY={'YES' if snapshot_ok else 'NO'}")
        if not snapshot_ok:
            emit("SNYK_SNAPSHOT_MATERIALIZATION=FAIL")
            emit("SNYK_SNAPSHOT_ERROR=" + snapshot_error)
            emit("APPSEC04_SNYK_REVALIDATION=BLOCK_SNAPSHOT")
            report.write_text("\n".join(lines) + "\n", encoding="utf-8")
            digest = hashlib.sha256(report.read_bytes()).hexdigest()
            sha_file.write_text(f"{digest}  {report.name}\n", encoding="utf-8")
            print(f"REPORT={report}")
            print(f"SHA256={digest}")
            print(f"SHA256_FILE={sha_file}")
            return 2

        emit("SNYK_SNAPSHOT_MATERIALIZATION=PASS")
        post_snapshot_ok = False
        post_snapshot_files = 0
        post_snapshot_error = "post-scan verification not executed"
        isolation_ok = False
        isolation_uid = os.geteuid()
        isolation_gid = os.getegid()
        isolation_error = "snapshot isolation not executed"
        cleanup_ok = True
        cleanup_error = ""

        try:
            (
                isolation_ok,
                isolation_uid,
                isolation_gid,
                isolation_error,
            ) = lock_snapshot_for_scan(Path(tmp).resolve())

            emit("SNYK_SNAPSHOT_ISOLATION=ROOT_OWNED_DAC")
            emit(f"SNYK_SCAN_EUID={isolation_uid}")
            emit("SNYK_ROOT_SCAN_ALLOWED=NO")
            emit(
                "SNYK_SNAPSHOT_WRITABLE_BY_SCAN_USER="
                + ("NO" if isolation_ok else "UNKNOWN")
            )

            if not isolation_ok:
                emit("SNYK_SNAPSHOT_ISOLATION_PROOF=FAIL")
                emit("SNYK_SNAPSHOT_ISOLATION_ERROR=" + isolation_error)
                emit("APPSEC04_SNYK_REVALIDATION=BLOCK_ISOLATION")
                emit("APPSEC05_SNYK_REVALIDATION=BLOCK_ISOLATION")
                report.write_text("\n".join(lines) + "\n", encoding="utf-8")
                digest = hashlib.sha256(report.read_bytes()).hexdigest()
                sha_file.write_text(f"{digest}  {report.name}\n", encoding="utf-8")
                print(f"REPORT={report}")
                print(f"SHA256={digest}")
                print(f"SHA256_FILE={sha_file}")
                return 2

            emit("SNYK_SNAPSHOT_ISOLATION_PROOF=PASS")
            scan_rc, sarif_out, scan_err = run(
                ["snyk", "code", "test", "--sarif", "--include-ignores"],
                snapshot_root,
                600,
            )
            (
                post_snapshot_ok,
                post_snapshot_files,
                post_snapshot_error,
            ) = verify_materialized_snapshot(root, head, snapshot_root)
        finally:
            if isolation_ok:
                cleanup_ok, cleanup_error = unlock_snapshot_after_scan(
                    Path(tmp).resolve(),
                    isolation_uid,
                    isolation_gid,
                )

        emit(
            "SNYK_SNAPSHOT_TEMP_CLEANUP_READY="
            + ("PASS" if cleanup_ok else "FAIL")
        )
        if not cleanup_ok:
            emit("SNYK_SNAPSHOT_TEMP_CLEANUP_ERROR=" + cleanup_error)
            emit("APPSEC04_SNYK_REVALIDATION=BLOCK_TEMP_CLEANUP")
            emit("APPSEC05_SNYK_REVALIDATION=BLOCK_TEMP_CLEANUP")
            report.write_text("\n".join(lines) + "\n", encoding="utf-8")
            digest = hashlib.sha256(report.read_bytes()).hexdigest()
            sha_file.write_text(f"{digest}  {report.name}\n", encoding="utf-8")
            print(f"REPORT={report}")
            print(f"SHA256={digest}")
            print(f"SHA256_FILE={sha_file}")
            return 2

        emit(f"SNYK_SNAPSHOT_POSTSCAN_FILES={post_snapshot_files}")
        emit(
            "SNYK_SNAPSHOT_POSTSCAN_INTEGRITY="
            + ("PASS" if post_snapshot_ok else "FAIL")
        )
        if not post_snapshot_ok:
            emit("SNYK_SNAPSHOT_POSTSCAN_ERROR=" + post_snapshot_error)
            emit("APPSEC04_SNYK_REVALIDATION=BLOCK_SNAPSHOT_CHANGED")
            report.write_text("\n".join(lines) + "\n", encoding="utf-8")
            digest = hashlib.sha256(report.read_bytes()).hexdigest()
            sha_file.write_text(f"{digest}  {report.name}\n", encoding="utf-8")
            print(f"REPORT={report}")
            print(f"SHA256={digest}")
            print(f"SHA256_FILE={sha_file}")
            return 2
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
    emit(f"SNYK_CWE23_RESULTS={counts['cwe23']}")
    emit(f"SNYK_APPSEC05_TARGET_RESULTS={counts['appsec05_target']}")
    emit(
        f"SNYK_APPSEC05_TARGET_CWE23_RESULTS="
        f"{counts['appsec05_target_cwe23']}"
    )

    # Somente metadados mínimos; nenhuma mensagem/snippet SARIF é persistida.
    for row in rows[:50]:
        path = row["paths"][0] if row["paths"] else "unknown"
        emit(
            "SNYK_RESULT="
            f"rule={row['rule_id']}|path={path}"
            f"|cwe611={1 if row['cwe611'] else 0}"
            f"|cwe23={1 if row['cwe23'] else 0}"
        )

    appsec04_ok = counts["target_cwe611"] == 0 and counts["cwe611"] == 0
    appsec05_ok = (
        counts["appsec05_target_cwe23"] == 0
        and counts["cwe23"] == 0
    )
    scan_exit_clean = scan_rc == 0
    full_clean = scan_exit_clean and counts["total"] == 0
    emit(f"SNYK_SCAN_EXIT_CLEAN={'PASS' if scan_exit_clean else 'FAIL'}")
    emit(f"APPSEC04_CWE611={'PASS' if appsec04_ok else 'FAIL'}")
    emit(f"APPSEC05_CWE23={'PASS' if appsec05_ok else 'FAIL'}")
    emit(f"SNYK_CODE_MAIN={'PASS' if full_clean else 'FINDINGS_OR_NONZERO_EXIT'}")
    emit(
        "APPSEC04_SNYK_REVALIDATION="
        + ("PASS" if appsec04_ok and full_clean else "BLOCK")
    )
    emit(
        "APPSEC05_SNYK_REVALIDATION="
        + ("PASS" if appsec05_ok and full_clean else "BLOCK")
    )
    emit("SNYK_SUPPRESSION_CAN_HIDE_FINDINGS=NO")
    emit("NO_SNYK_SUPPRESSION_EXPECTED=YES")
    emit("RAW_SARIF_PERSISTED=NO")

    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    digest = hashlib.sha256(report.read_bytes()).hexdigest()
    sha_file.write_text(f"{digest}  {report.name}\n", encoding="utf-8")
    print(f"REPORT={report}")
    print(f"SHA256={digest}")
    print(f"SHA256_FILE={sha_file}")
    return 0 if appsec04_ok and appsec05_ok and full_clean else 2


if __name__ == "__main__":
    raise SystemExit(main())
