#!/usr/bin/env python3
"""ZT-01: compare private, integrity-checked Pentest B reports without network.

An observation is not proof of identity, MFA, RBAC, or Zero Trust enforcement.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat

SCHEMA = "CE-PB-FIELD-20261109-R1"
CASES = ("ZT_RESOURCE_VISIBILITY", "ZT_PROFILE_APP", "ZT_PROFILE_WAZUH")
STATUSES = frozenset({
    "TCP_REACHABLE", "TCP_TIMEOUT", "TCP_REFUSED", "TCP_INCONCLUSIVE",
    "HTTP_OBSERVED", "HTTP_INCONCLUSIVE", "HTTP_BLOCKED_PATH",
    "HTTP_BLOCKED_SNI", "HTTP_BLOCKED_COOKIE", "HTTP_BLOCKED_SIZE",
})
MAX_REPORT_BYTES = 65536
MAX_SIDECAR_BYTES = 256


def _read_private_file(path: Path, max_bytes: int) -> bytes:
    if path.parent.is_symlink():
        raise ValueError("PARENT_SYMLINK")
    parent = path.parent.stat()
    if parent.st_uid != os.geteuid() or stat.S_IMODE(parent.st_mode) & 0o077:
        raise ValueError("PARENT_NOT_PRIVATE")
    fd = os.open(str(path), os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    try:
        info = os.fstat(fd)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid()
                or stat.S_IMODE(info.st_mode) & 0o077 or info.st_size > max_bytes):
            raise ValueError("FILE_NOT_PRIVATE_OR_TOO_BIG")
        with os.fdopen(fd, "rb", closefd=False) as f:
            raw = f.read(max_bytes + 1)
        if len(raw) > max_bytes:
            raise ValueError("FILE_TOO_BIG")
        return raw
    finally:
        os.close(fd)


def _no_duplicate_keys(pairs: list[tuple[str, object]]) -> dict:
    out = {}
    for key, value in pairs:
        if key in out:
            raise ValueError("DUPLICATE_JSON_KEY")
        out[key] = value
    return out


def load_verified_report(filename: str) -> dict:
    path = Path(filename).expanduser()
    data = _read_private_file(path, MAX_REPORT_BYTES)
    sidecar = _read_private_file(Path(str(path) + ".sha256"), MAX_SIDECAR_BYTES)
    try:
        parts = sidecar.decode("ascii").strip().split()
    except UnicodeDecodeError as err:
        raise ValueError("SIDECAR_ENCODING") from err
    if not (1 <= len(parts) <= 2 and re.fullmatch(r"[a-f0-9]{64}", parts[0])):
        raise ValueError("SIDECAR_FORMAT")
    if len(parts) == 2 and parts[1] not in (path.name, "*" + path.name):
        raise ValueError("SIDECAR_FILENAME_MISMATCH")
    if hashlib.sha256(data).hexdigest() != parts[0]:
        raise ValueError("SHA256_MISMATCH")
    obj = json.loads(data.decode("utf-8"), object_pairs_hook=_no_duplicate_keys)
    if not isinstance(obj, dict):
        raise ValueError("REPORT_NOT_OBJECT")
    return obj


def _extract(report: dict, profile: str) -> dict[str, str]:
    if not isinstance(report, dict) or any((
        report.get("schema") != SCHEMA,
        report.get("role") != "client",
        report.get("stage") != "exploit",
        report.get("pa") != "PA-01",
        report.get("gate") != "OPEN",
        report.get("zt_profile") != profile,
    )):
        raise ValueError("PROFILE_SCOPE_INVALID")
    observations = report.get("results")
    if not isinstance(observations, list) or len(observations) > 40:
        raise ValueError("OBSERVATIONS_INVALID")
    result: dict[str, str] = {}
    for entry in observations:
        if not isinstance(entry, dict):
            raise ValueError("OBSERVATION_NOT_OBJECT")
        name = entry.get("case")
        if name in CASES:
            if name in result:
                raise ValueError("DUPLICATE_CASE")
            if entry.get("pa") not in (None, "PA-01") or entry.get("stage") not in (None, "exploit"):
                raise ValueError("CASE_SCOPE_INVALID")
            status = entry.get("status")
            if not isinstance(status, str) or status not in STATUSES:
                raise ValueError("STATUS_NOT_ALLOWED")
            result[name] = status
    if set(result) != set(CASES):
        raise ValueError("REQUIRED_CASES_MISSING")
    return result


def compare(portal: dict, soc: dict) -> dict:
    first = _extract(portal, "portal")
    second = _extract(soc, "soc")
    hostname = portal.get("hostname")
    if not isinstance(hostname, str) or not hostname or hostname != soc.get("hostname"):
        raise ValueError("HOSTS_NOT_COMPARABLE")
    return {
        "schema": "CE-PB-ZT01-COMPARE-OFFLINE-2",
        "result": ("REVIEW_POSSIBLE_UNEXPECTED_REACHABILITY"
                   if first["ZT_PROFILE_WAZUH"] == "TCP_REACHABLE"
                   else "REVIEW_ACCESS_POLICIES_AND_LOGS"),
        "profiles_are_operator_labels": True,
        "identity_and_mfa_independent_proof_required": True,
        "policy_and_access_logs_correlation_required": True,
        "tcp_reachability_is_not_rbac_allow": True,
        "no_automatic_pass": True,
        "portal": first,
        "soc": second,
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compare two existing private ZT reports offline; no network or live authentication."
    )
    parser.add_argument("--portal-report", required=True)
    parser.add_argument("--soc-report", required=True)
    args = parser.parse_args()
    try:
        result = compare(load_verified_report(args.portal_report),
                         load_verified_report(args.soc_report))
    except (OSError, UnicodeError, ValueError, TypeError) as exc:
        # Print only the failure class; not input paths or report content.
        parser.error("ZT01_REVIEW_BLOCKED:" + type(exc).__name__)
    print(json.dumps(result, ensure_ascii=True, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
