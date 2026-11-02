#!/usr/bin/env python3
"""GA-08 change control: offline tests; no Docker, network or VM required."""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/ga08-change-control.py"
spec = importlib.util.spec_from_file_location("ga08_control", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def approval(change_id: str) -> dict:
    return {
        "change_id": change_id,
        "snapshot_id": "SNAP-ACADEMICO-EXEMPLO",
        "snapshot_covers_all_ep125_disks": True,
        "snapshot_restore_confirmed_by_operator": True,
        "bind_mounts_verified_by_operator": True,
        "secrets_and_tls_recoverable": True,
        "operator_and_window_approved": True,
        "cross_vm_dependencies_checked": True,
        "socket_directories_clean": True,
        "cutover_approved": True,
        "rollback_approved": True,
        "approver": "operador de teste",
    }


class GuardTests(unittest.TestCase):
    def test_interlock_is_closed_without_all_three_controls(self):
        args = argparse.Namespace(execute=True, ack="APLICAR_GA08_NA_EP125")
        with mock.patch.dict(os.environ, {"GA08_ENABLE_LIVE_CHANGE": ""}):
            with self.assertRaises(mod.GateError):
                mod.require_cli_interlock(args, "cutover")
        with mock.patch.dict(os.environ, {"GA08_ENABLE_LIVE_CHANGE": "YES"}):
            args.ack = "RESTAURAR_BASELINE_EP125"
            with self.assertRaises(mod.GateError):
                mod.require_cli_interlock(args, "cutover")
            args.ack = "APLICAR_GA08_NA_EP125"
            mod.require_cli_interlock(args, "cutover")
            args.execute = False
            with self.assertRaises(mod.GateError):
                mod.require_cli_interlock(args, "cutover")

    def test_rollback_has_different_explicit_acknowledgment(self):
        args = argparse.Namespace(execute=True, ack="APLICAR_GA08_NA_EP125")
        with mock.patch.dict(os.environ, {"GA08_ENABLE_LIVE_CHANGE": "YES"}):
            with self.assertRaises(mod.GateError):
                mod.require_cli_interlock(args, "rollback")
            args.ack = "RESTAURAR_BASELINE_EP125"
            mod.require_cli_interlock(args, "rollback")

    def test_private_approval_all_gates_required(self):
        change_id = "GA08-20261103-ABC"
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "approval.json"
            original = approval(change_id)
            path.write_text(json.dumps(original), encoding="utf-8")
            path.chmod(0o600)
            parsed = mod.verify_approvals(str(path), change_id, "cutover")
            self.assertEqual(parsed["snapshot_id"], "SNAP-ACADEMICO-EXEMPLO")
            for key in (
                "snapshot_covers_all_ep125_disks",
                "snapshot_restore_confirmed_by_operator",
                "bind_mounts_verified_by_operator",
                "secrets_and_tls_recoverable",
                "operator_and_window_approved",
                "cross_vm_dependencies_checked",
                "socket_directories_clean",
                "cutover_approved",
            ):
                altered = dict(original)
                altered[key] = False
                path.write_text(json.dumps(altered), encoding="utf-8")
                with self.subTest(key=key), self.assertRaises(mod.GateError):
                    mod.verify_approvals(str(path), change_id, "cutover")
            path.write_text(json.dumps(original))
            path.chmod(0o644)
            with self.assertRaises(mod.GateError):
                mod.verify_approvals(str(path), change_id, "cutover")

    def test_rollback_cannot_use_cutover_only_approval(self):
        change_id = "GA08-20261103-ABC"
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "approval.json"
            a = approval(change_id)
            a["rollback_approved"] = False
            path.write_text(json.dumps(a))
            path.chmod(0o600)
            with self.assertRaises(mod.GateError):
                mod.verify_approvals(str(path), change_id, "rollback")

    def test_manifest_is_private_and_atomic(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "manifest.json"
            mod.write_manifest(path, {"change_id": "GA08-20261103-ABC"})
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertFalse(path.with_suffix(".tmp").exists())
            mod.write_manifest(path, {"phase": "CUTOVER_STARTED_php"})
            self.assertEqual(json.loads(path.read_text())["phase"],
                             "CUTOVER_STARTED_php")

    def test_lock_blocks_parallel_mutations(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            fd = mod.acquire_lock(directory)
            try:
                with self.assertRaises(mod.GateError):
                    mod.acquire_lock(directory)
            finally:
                os.close(fd)

    def test_change_id_rejects_path_traversal(self):
        for attack in ("../../etc", "GA08-20261103-../", "ga08", ""):
            with self.subTest(value=attack), self.assertRaises(mod.GateError):
                mod.evidence_directory(attack)

    def test_service_specific_baseline_orders_are_fixed(self):
        self.assertEqual(mod.BASE_COUNTS, {"waf": 9, "nginx": 9, "php": 10})
        self.assertEqual(mod.BASE_FILES[9], "compose.audit-persistent.yml")
        self.assertEqual(
            mod.CANDIDATE_FILES,
            ("compose.ga08-socket.candidate.yml",
             "compose.ga08-dual-socket.candidate.yml"),
        )

    def test_digest_catches_env_or_port_drift(self):
        a = {"name": "conectaeduca-dmz", "services": {"waf": {"ports": [443]}}}
        b = {"services": {"waf": {"ports": [443]}}, "name": "conectaeduca-dmz"}
        self.assertEqual(mod.config_digest(a), mod.config_digest(b))
        b["services"]["waf"]["ports"] = [443, 8080]
        self.assertNotEqual(mod.config_digest(a), mod.config_digest(b))

    def test_default_main_uses_preflight_not_mutator(self):
        with mock.patch.object(mod, "require_runtime_host", return_value="ep125-pucpr"), \
             mock.patch.object(mod, "preflight") as preflight, \
             mock.patch.object(mod, "execute_cutover") as execute, \
             mock.patch("sys.argv", ["script", "--action", "cutover"]):
            self.assertEqual(mod.main(), 0)
            preflight.assert_called_once_with()
            execute.assert_not_called()

    def test_execute_interlock_blocks_before_docker(self):
        with mock.patch.object(mod, "require_runtime_host", return_value="ep125-pucpr"), \
             mock.patch.dict(os.environ, {"GA08_ENABLE_LIVE_CHANGE": ""}), \
             mock.patch.object(mod, "run") as command, \
             mock.patch("sys.argv", [
                 "script", "--action", "cutover", "--execute",
                 "--change-id", "GA08-20261103-ABC",
                 "--ack", "APLICAR_GA08_NA_EP125",
             ]):
            self.assertEqual(mod.main(), 3)
            command.assert_not_called()

    def test_mutations_have_no_pull_build_or_down(self):
        content = SCRIPT.read_text(encoding="utf-8")
        self.assertIn('"--no-deps", "--no-build", "--pull", "never"', content)
        self.assertNotIn('"down"', content)
        self.assertNotIn('"prune"', content)
        self.assertIn('"CUTOVER_STARTED_" + service', content)
        self.assertIn('"ROLLBACK_STARTED_" + service', content)
        self.assertIn("candidate_config_sha256", content)
        self.assertIn("rollback_config_sha256", content)


if __name__ == "__main__":
    unittest.main()
