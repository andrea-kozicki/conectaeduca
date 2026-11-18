#!/usr/bin/env python3
"""ConectaEduca: git-only, offline, pre-VM reconciliation.

Never contacts a remote, reads file content, or changes the Git index/worktree.
A plan is printed by default. Live local reads require --execute-readonly and
the exact institutional hostname, as a non-root user.
"""
from __future__ import annotations

import argparse
import collections
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys

HOSTS = {"ep125": "ep125-pucpr", "ep126": "ep126-pucpr-br"}
SCOPES = {
    "ep125": ("deploy/dmz", "public", "scripts/implantacao/vms"),
    "ep126": ("deploy/interna", "scripts/implantacao", "scripts/observabilidade"),
}
CATEGORIES = (
    ("DMZ", "deploy/dmz/"),
    ("INTERNA", "deploy/interna/"),
    ("PUBLIC", "public/"),
    ("IMPLANTACAO", "scripts/implantacao/"),
    ("OBSERVABILIDADE", "scripts/observabilidade/"),
)
ALLOWED_GIT = frozenset({"rev-parse", "symbolic-ref", "diff", "ls-files"})
HEX_SHA = re.compile(r"[0-9a-f]{40}(?:[0-9a-f]{24})?\Z")


class InventoryError(Exception):
    """An intentionally terse, sanitized reason to stop."""


def git_read(root: Path, *args: str, optional: bool = False) -> bytes | None:
    """Only enumerated local read commands, no shell, hooks, network or writes."""
    verb = args[0] if args else ""
    if verb not in ALLOWED_GIT:
        raise InventoryError("GIT_COMMAND_NOT_ALLOWED")
    env = dict(os.environ)
    env["GIT_OPTIONAL_LOCKS"] = "0"
    env["GIT_TERMINAL_PROMPT"] = "0"
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    try:
        result = subprocess.run(
            ["git", "-C", str(root), *args],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL, timeout=8, check=False, env=env,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise InventoryError("GIT_READ_UNAVAILABLE") from None
    if result.returncode != 0:
        if optional:
            return None
        raise InventoryError("GIT_READ_FAILED")
    if len(result.stdout) > 2_000_000:
        raise InventoryError("GIT_OUTPUT_TOO_LARGE")
    return result.stdout


def valid_sha(value: bytes | None) -> str:
    if value is None:
        return "NOT_PRESENT"
    text = value.decode("ascii", errors="replace").strip()
    if HEX_SHA.fullmatch(text) is None:
        raise InventoryError("INVALID_COMMIT_SHA")
    return text


def count_scoped_paths(raw: bytes) -> dict[str, int]:
    out: collections.Counter[str] = collections.Counter()
    for entry in raw.split(b"\x00"):
        if not entry:
            continue
        path = entry.decode("utf-8", errors="surrogateescape")
        bucket = next((label for label, prefix in CATEGORIES if path.startswith(prefix)), "OUTROS")
        out[bucket] += 1
    return dict(sorted(out.items()))


def inventory(
    role: str, root: Path = Path("/opt/conectaeduca"),
    *, hostname: str | None = None, effective_uid: int | None = None,
) -> dict:
    """Collect only anonymized local Git metadata after strict identity gate."""
    if role not in HOSTS:
        raise InventoryError("ROLE_INVALID")
    actual = socket.gethostname().split(".")[0] if hostname is None else hostname
    if actual != HOSTS[role]:
        raise InventoryError("HOST_OUT_OF_SCOPE")
    uid = os.geteuid() if effective_uid is None else effective_uid
    if uid == 0:
        raise InventoryError("ROOT_FORBIDDEN")
    if root.is_symlink() or not root.is_dir() or not root.is_absolute():
        raise InventoryError("REPOSITORY_PATH_INVALID")

    top = git_read(root, "rev-parse", "--show-toplevel")
    if top is None or top.decode("utf-8", "replace").strip() != str(root):
        raise InventoryError("REPOSITORY_ROOT_MISMATCH")
    head = valid_sha(git_read(root, "rev-parse", "--verify", "HEAD"))
    cached = valid_sha(git_read(root, "rev-parse", "--verify", "refs/remotes/origin/main", optional=True))
    branch = git_read(root, "symbolic-ref", "--quiet", "--short", "HEAD", optional=True)
    branch_name = branch.decode("utf-8", "replace").strip() if branch else ""
    branch_class = "MAIN" if branch_name == "main" else "DETACHED_OR_OTHER"
    tracked = git_read(
        root, "diff", "--no-ext-diff", "--name-only", "-z", "HEAD", "--", *SCOPES[role],
    )
    untracked = git_read(
        root, "ls-files", "--others", "--exclude-standard", "-z", "--", *SCOPES[role],
    )
    if tracked is None or untracked is None:
        raise InventoryError("GIT_ENUMERATION_FAILED")
    return {
        "schema": "CE-PREVM-GIT-INVENTORY-1",
        "mode": "LOCAL_READ_ONLY",
        "role": role.upper(),
        "hostname_verified": True,
        "git_head_local": head,
        "origin_main_local_cache": cached,
        "remote_consulted": False,
        "branch_class": branch_class,
        "tracked_modified_by_area": count_scoped_paths(tracked),
        "untracked_nonignored_by_area": count_scoped_paths(untracked),
        "scopes_checked": list(SCOPES[role]),
        "ignored_files_scanned": False,
        "paths_and_file_contents_emitted": False,
        "runtime_checked": False,
        "runtime_modified": False,
        "git_changed": False,
        "snapshot_or_backup_verified": False,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Offline Git inventory; plan only unless explicitly enabled")
    parser.add_argument("--role", required=True, choices=sorted(HOSTS))
    parser.add_argument("--execute-readonly", action="store_true",
                        help="Local read on the exact VM hostname; never changes Git or runtime")
    args = parser.parse_args(argv)
    if not args.execute_readonly:
        print(json.dumps({
            "schema": "CE-PREVM-GIT-INVENTORY-1",
            "mode": "PLAN_ONLY_NOT_EXECUTED",
            "role": args.role.upper(),
            "expected_hostname": HOSTS[args.role],
            "scopes_proposed": list(SCOPES[args.role]),
            "remote_consulted": False,
            "runtime_modified": False,
        }, indent=2, sort_keys=True))
        return 0
    try:
        report = inventory(args.role)
    except InventoryError as exc:
        print("ABORTED=" + str(exc), file=sys.stderr)
        return 2
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
