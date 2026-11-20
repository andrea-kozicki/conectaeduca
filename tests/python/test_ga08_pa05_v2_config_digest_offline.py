#!/usr/bin/env python3
"""Offline data-leak and no-mutation contracts for private config digests."""

from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

SCRIPT = (Path(__file__).resolve().parents[2] / "scripts" /
          "ga08-pa05-v2-config-digest-ep125.py")
spec = importlib.util.spec_from_file_location("ga08_pa05_v2_digest", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)


def config() -> dict:
    return {"name": mod.PROJECT, "services": {
        "php": {"image": mod.PHP_PA05,
                "environment": {"SECRET_TEST_ONLY": "SECRET_DO_NOT_PRINT"}},
        "nginx": {"image": "conectaeduca/nginx:dmz"},
        "waf": {"image": "conectaeduca/waf:dmz"},
    }}


class PrivateDigestOfflineTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.tmp = Path(temp.name)

    def test_json_canonical_digest_independent_of_key_order(self):
        first = {"b": 2, "a": {"y": "é", "x": 1}}
        reordered = {"a": {"x": 1, "y": "é"}, "b": 2}
        self.assertEqual(mod.canonical_digest(first), mod.canonical_digest(reordered))
        old_expected = hashlib.sha256(json.dumps(
            first, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")).hexdigest()
        self.assertEqual(mod.canonical_digest(first), old_expected)

    def test_full_config_json_kept_in_memory_and_compose_not_mutated(self):
        secret_data = json.dumps(config()).encode()
        observed = []

        def execute(command, **kwargs):
            observed.append((command, kwargs))
            return SimpleNamespace(returncode=0, stdout=secret_data,
                                   stderr=b"SECRET_DO_NOT_PRINT")

        with mock.patch.object(mod.subprocess, "run", side_effect=execute):
            log = io.StringIO()
            with redirect_stdout(log):
                digest = mod.resolved_digest(tuple(Path(f"/tmp/f{i}.yml")
                                  for i in range(14)),
                                  {"CONECTAEDUCA_DB_HOST": "SECRET_DO_NOT_PRINT"},
                                  11)
        self.assertEqual(len(digest), 64)
        self.assertEqual(observed[0][0][-3:], ["config", "--format", "json"])
        self.assertEqual(sum(x == "-f" for x in observed[0][0]), 11)
        self.assertEqual(observed[0][1]["env"]["COMPOSE_DISABLE_ENV_FILE"], "1")
        self.assertNotIn("--no-interpolate", observed[0][0])
        self.assertNotIn("SECRET_DO_NOT_PRINT", log.getvalue())

    def test_rejects_php_downgrade_before_any_digest_acceptance(self):
        bad = config()
        bad["services"]["php"]["image"] = "conectaeduca/php-fpm:legacy"
        with mock.patch.object(mod.subprocess, "run", return_value=SimpleNamespace(
            returncode=0, stdout=json.dumps(bad).encode(), stderr=b"")):
            with self.assertRaisesRegex(mod.DigestError, "php_pa05_nao_preservado"):
                mod.resolved_digest(tuple(Path(f"/tmp/f{i}.yml")
                                    for i in range(14)), {}, 14)

    def test_bad_compose_output_does_not_leak_sensitive_bytes(self):
        with mock.patch.object(mod.subprocess, "run", return_value=SimpleNamespace(
            returncode=1, stdout=b"SECRET_DO_NOT_PRINT",
            stderr=b"SECRET_DO_NOT_PRINT")):
            with self.assertRaises(mod.DigestError) as caught:
                mod.resolved_digest(tuple(Path(f"/tmp/f{i}.yml")
                                    for i in range(14)), {}, 14)
        self.assertNotIn("SECRET_DO_NOT_PRINT", str(caught.exception))

    def test_two_contexts_equal_and_different_digest_classification(self):
        custody = {"collect": lambda home, peer: {
            "context_count": 2, "service_parity_count": 6,
            "compose_count": 14, "source_hashes": dict.fromkeys(range(14)),
            "images": dict.fromkeys(("php", "nginx", "waf")),
        }, "load_peer": lambda home: {}}
        source_paths = tuple(Path(f"/tmp/file{i}.yml") for i in range(14))
        with (mock.patch.object(mod, "record_envs", return_value=(
              source_paths, [{"CONECTAEDUCA_DB_HOST": "a"},
                             {"CONECTAEDUCA_DB_HOST": "b"}])),
              mock.patch.object(mod, "resolved_digest", side_effect=["a", "b", "a", "b"])):
            result = mod.analyze(self.tmp, custody)
        self.assertTrue(result["baseline_identical"])
        self.assertTrue(result["active_identical"])
        with (mock.patch.object(mod, "record_envs", return_value=(
              source_paths, [{"CONECTAEDUCA_DB_HOST": "a"},
                             {"CONECTAEDUCA_DB_HOST": "b"}])),
              mock.patch.object(mod, "resolved_digest", side_effect=["a", "b", "c", "b"])):
            result = mod.analyze(self.tmp, custody)
        self.assertFalse(result["baseline_identical"])

    def test_tampered_peer_rejected_before_execution(self):
        downloads = self.tmp / "Downloads"
        downloads.mkdir()
        script = downloads / mod.PEER
        script.write_text("print('SECRET_DO_NOT_PRINT')\n")
        script.chmod(0o600)
        with mock.patch.object(mod.runpy, "run_path") as run:
            with self.assertRaisesRegex(mod.DigestError, "biblioteca_hash_divergente"):
                mod.trusted_peer(self.tmp)
            run.assert_not_called()

    def test_main_reports_only_statuses_and_never_hashes(self):
        data = {"models": 4, "baseline_identical": True,
                "active_identical": True, "php_pa05": True}
        with (mock.patch.object(mod.socket, "gethostname", return_value="ep125-pucpr"),
              mock.patch.object(mod.os, "geteuid", return_value=1000),
              mock.patch.object(mod, "trusted_peer", return_value={}),
              mock.patch.object(mod, "analyze", return_value=data)):
            text = io.StringIO()
            with redirect_stdout(text):
                self.assertEqual(mod.main(), 0)
        self.assertIn("DIGEST_V2=PASS_EM_MEMORIA", text.getvalue())
        self.assertIn("ROLLBACK_HABILITADO=NAO", text.getvalue())
        self.assertNotIn("SECRET_DO_NOT_PRINT", text.getvalue())

    def test_source_excludes_mutation_and_config_logging(self):
        script = SCRIPT.read_text()
        for forbidden in ('"up"', '"down"', '"--execute"',
                          "print(proc.stdout)", "print(proc.stderr)",
                          "write_text(", "write_bytes(", "os.replace("):
            self.assertNotIn(forbidden, script)


if __name__ == "__main__":
    unittest.main()
