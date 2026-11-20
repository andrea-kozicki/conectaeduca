#!/usr/bin/env python3
"""Offline tests for the protected GA08 runtime hash parity gate."""

import importlib.util
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/ga08-runtime-hash-parity-ep125.py"
spec = importlib.util.spec_from_file_location("ga08_runtime_hash_parity", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)


class GA08RuntimeHashParityTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.tmp = Path(temp.name)

    def files(self, count=14):
        result = []
        for i in range(count):
            p = self.tmp / ("compose%02d.yml" % i)
            p.write_text("services:\n  php:\n    image: example.local\n")
            result.append(p)
        return tuple(result)

    def test_envfile_or_include_prevents_hash_read(self):
        paths = self.files()
        mod.check_no_service_env_files(paths)
        for declaration in ("    env_file: secret.env\n", "  include: other.yml\n",
                            "    extends: old\n"):
            paths[4].write_text("services:\n  php:\n" + declaration)
            with self.assertRaisesRegex(mod.GuardError,
                                        "compose_envfile_ou_inclusao_nao_aprovada"):
                mod.check_no_service_env_files(paths)

    def test_hash_output_is_sanitized_and_invocation_read_only(self):
        expected = "f" * 64
        observed = []

        def execute(argv, **options):
            observed.append((argv, options))
            return SimpleNamespace(returncode=0,
                                   stdout=("php " + expected + "\n").encode(),
                                   stderr=b"SECRET_DO_NOT_PRINT")

        with mock.patch.object(mod.subprocess, "run", side_effect=execute):
            digest = mod.service_hash(self.files(),
                                     {"CONECTAEDUCA_APP_URL": "SECRET_DO_NOT_PRINT"},
                                     "php")
        self.assertEqual(digest, expected)
        self.assertEqual(observed[0][0][-3:], ["config", "--hash", "php"])
        self.assertEqual(sum(x == "-f" for x in observed[0][0]), 14)
        self.assertNotIn("--no-env-resolution", observed[0][0])
        self.assertEqual(observed[0][1]["env"]["COMPOSE_DISABLE_ENV_FILE"], "1")
        self.assertEqual(observed[0][1]["env"]["CONECTAEDUCA_APP_URL"],
                         "SECRET_DO_NOT_PRINT")

    def test_unexpected_hash_output_fails_without_printing(self):
        with mock.patch.object(mod.subprocess, "run", return_value=SimpleNamespace(
            returncode=0, stdout=b"SECRET_DO_NOT_PRINT", stderr=b"password")):
            log = io.StringIO()
            with redirect_stdout(log):
                self.assertIsNone(mod.service_hash(self.files(), {}, "php"))
            self.assertNotIn("SECRET", log.getvalue())

    def test_version_pin(self):
        with mock.patch.object(mod.subprocess, "run", return_value=SimpleNamespace(
            returncode=0, stdout=b"5.7.0\n", stderr=b"")):
            self.assertEqual(mod.compose_version(), "5.7.0")
        with mock.patch.object(mod.subprocess, "run", return_value=SimpleNamespace(
            returncode=0, stdout=b"5.6.0\n", stderr=b"")):
            with self.assertRaisesRegex(mod.GuardError, "versao_inesperada"):
                mod.compose_version()

    def test_main_no_hashes_or_secrets_in_output(self):
        comparisons = [dict.fromkeys(mod.SERVICES, "IGUAL"),
                       {"php": "IGUAL", "nginx": "DIFERENTE", "waf": "IGUAL"}]
        with (mock.patch.object(mod.socket, "gethostname", return_value="ep125-pucpr"),
              mock.patch.object(mod.os, "geteuid", return_value=1000),
              mock.patch.object(mod, "compose_version", return_value="5.7.0"),
              mock.patch.object(mod, "verified_peer", return_value={}),
              mock.patch.object(mod, "report", return_value=comparisons)):
            log = io.StringIO()
            with redirect_stdout(log):
                self.assertEqual(mod.main(), 3)
        self.assertIn("NGINX_HASH=DIFERENTE", log.getvalue())
        self.assertIn("ROLLBACK_HABILITADO=NAO", log.getvalue())
        self.assertNotIn("SECRET", log.getvalue())
        self.assertNotIn("ff" * 32, log.getvalue())

    def test_script_has_no_mutation_or_raw_diagnostics(self):
        code = SCRIPT.read_text()
        for forbidden in ("print(proc.stdout)", "print(proc.stderr)",
                          '"up"', '"down"', '"--execute"',
                          '"--environment"', '"--env-file"'):
            self.assertNotIn(forbidden, code)


if __name__ == "__main__":
    unittest.main()
