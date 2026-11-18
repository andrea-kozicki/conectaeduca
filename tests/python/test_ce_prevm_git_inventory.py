#!/usr/bin/env python3
"""Synthetic, offline tests for the pre-VM Git-only inventory."""
from __future__ import annotations

import contextlib
import io
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "evidencias"))
import ce_prevm_git_inventory as inv  # noqa: E402


def run_git(root: pathlib.Path, *argv: str) -> bytes:
    return subprocess.run(
        ["git", "-C", str(root), *argv],
        capture_output=True, check=True, timeout=8,
    ).stdout


def make_repo(root: pathlib.Path) -> None:
    run_git(root, "init", "-q", "-b", "main")
    run_git(root, "config", "user.name", "Synthetic CI")
    run_git(root, "config", "user.email", "ci@example.invalid")
    (root / ".gitignore").write_text("*.env\n", encoding="utf-8")
    (root / "deploy/dmz").mkdir(parents=True)
    (root / "deploy/dmz/compose.yml").write_text("safe", encoding="utf-8")
    (root / "public").mkdir()
    (root / "public/index.txt").write_text("hello", encoding="utf-8")
    (root / "deploy/interna").mkdir()
    (root / "deploy/interna/rules.txt").write_text("rules", encoding="utf-8")
    run_git(root, "add", ".gitignore", "deploy", "public")
    run_git(root, "commit", "-qm", "Synthetic baseline")


class PreVmGitInventoryTests(unittest.TestCase):
    def test_default_is_plan_only_and_does_not_call_git(self):
        buffer = io.StringIO()
        with patch.object(inv, "git_read", side_effect=AssertionError("GIT_MUST_NOT_RUN")):
            with contextlib.redirect_stdout(buffer):
                rc = inv.main(["--role", "ep125"])
        self.assertEqual(rc, 0)
        plan = json.loads(buffer.getvalue())
        self.assertEqual(plan["mode"], "PLAN_ONLY_NOT_EXECUTED")
        self.assertEqual(plan["expected_hostname"], "ep125-pucpr")

    def test_wrong_host_is_rejected_before_any_git_call(self):
        with patch.object(inv, "git_read", side_effect=AssertionError("GIT_MUST_NOT_RUN")):
            with self.assertRaisesRegex(inv.InventoryError, "HOST_OUT_OF_SCOPE"):
                inv.inventory("ep125", hostname="other-host", effective_uid=1001)

    def test_root_is_rejected_before_any_git_call(self):
        with patch.object(inv, "git_read", side_effect=AssertionError("GIT_MUST_NOT_RUN")):
            with self.assertRaisesRegex(inv.InventoryError, "ROOT_FORBIDDEN"):
                inv.inventory("ep126", hostname="ep126-pucpr-br", effective_uid=0)

    def test_forbidden_git_commands_fail_without_subprocess(self):
        with patch.object(inv.subprocess, "run", side_effect=AssertionError("NO_EXEC")):
            for command in ("fetch", "pull", "reset", "clean", "checkout", "push", "commit", "config"):
                with self.subTest(command=command):
                    with self.assertRaisesRegex(inv.InventoryError, "GIT_COMMAND_NOT_ALLOWED"):
                        inv.git_read(pathlib.Path("/tmp"), command)

    def test_ep125_classification_does_not_leak_paths(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            make_repo(root)
            (root / "deploy/dmz/compose.yml").write_text("changed", encoding="utf-8")
            (root / "deploy/dmz/private-diagnostic.txt").write_text("NOT_FOR_OUTPUT", encoding="utf-8")
            (root / "deploy/dmz/hidden.env").write_text("DUMMY_SECRET_MARKER", encoding="utf-8")
            report = inv.inventory("ep125", root, hostname="ep125-pucpr", effective_uid=1001)
            payload = json.dumps(report)
            self.assertEqual(report["tracked_modified_by_area"], {"DMZ": 1})
            self.assertEqual(report["untracked_nonignored_by_area"], {"DMZ": 1})
            self.assertEqual(report["branch_class"], "MAIN")
            self.assertEqual(report["origin_main_local_cache"], "NOT_PRESENT")
            self.assertFalse(report["remote_consulted"])
            self.assertFalse(report["runtime_checked"])
            self.assertNotIn("private-diagnostic", payload)
            self.assertNotIn("DUMMY_SECRET_MARKER", payload)
            self.assertNotIn("hidden.env", payload)

    def test_ep126_independent_scopes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            make_repo(root)
            (root / "deploy/interna/rules.txt").write_text("changed", encoding="utf-8")
            (root / "deploy/interna/candidate.txt").write_text("synthetic", encoding="utf-8")
            (root / "deploy/dmz/compose.yml").write_text("changed", encoding="utf-8")
            report = inv.inventory("ep126", root, hostname="ep126-pucpr-br", effective_uid=1001)
            self.assertEqual(report["tracked_modified_by_area"], {"INTERNA": 1})
            self.assertEqual(report["untracked_nonignored_by_area"], {"INTERNA": 1})
            self.assertEqual(report["role"], "EP126")

    def test_symlink_root_is_fail_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            linked = root / "linked"
            linked.symlink_to(root, target_is_directory=True)
            with self.assertRaisesRegex(inv.InventoryError, "REPOSITORY_PATH_INVALID"):
                inv.inventory("ep125", linked, hostname="ep125-pucpr", effective_uid=1001)

    def test_root_mismatch_is_fail_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            make_repo(root)
            nested = root / "deploy/dmz"
            with self.assertRaisesRegex(inv.InventoryError, "REPOSITORY_ROOT_MISMATCH"):
                inv.inventory("ep125", nested, hostname="ep125-pucpr", effective_uid=1001)

    def test_no_network_and_no_mutating_git_verb(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            make_repo(root)
            original = inv.subprocess.run
            verbs = []
            def monitor(args, **kwargs):
                if args[0] == "git":
                    self.assertEqual(args[1:3], ["-C", str(root)])
                    verbs.append(args[3])
                    self.assertIn(args[3], inv.ALLOWED_GIT)
                    self.assertEqual(kwargs.get("stdin"), subprocess.DEVNULL)
                    self.assertEqual(kwargs["env"]["GIT_OPTIONAL_LOCKS"], "0")
                return original(args, **kwargs)
            with patch.object(inv.subprocess, "run", side_effect=monitor):
                data = inv.inventory("ep125", root, hostname="ep125-pucpr", effective_uid=1001)
            self.assertEqual(data["mode"], "LOCAL_READ_ONLY")
            self.assertNotIn("fetch", verbs)
            self.assertEqual(len(verbs), 6)

    def test_no_invalid_sha_is_published(self):
        with self.assertRaisesRegex(inv.InventoryError, "INVALID_COMMIT_SHA"):
            inv.valid_sha(b"fake-branch-output\n")


if __name__ == "__main__":
    unittest.main()
