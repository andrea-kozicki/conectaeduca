#!/usr/bin/env python3
"""Read-only GA08/PA05 interpolation diagnostics: offline contracts."""

import importlib.util
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

SCRIPT = (Path(__file__).resolve().parents[2] / "scripts" /
          "ga08-private-interpolation-preflight-ep125.py")
spec = importlib.util.spec_from_file_location("ga08_private_interpolation", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)


class GA08PrivateInterpolationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def test_digest_requires_safe_regular_configuration(self):
        source = self.root / "sample.conf"
        source.write_bytes(b"test configuration\n")
        source.chmod(0o600)
        self.assertEqual(len(mod.secure_digest(source, limit=1024,
                                               suffix=".conf")), 64)
        source.chmod(0o666)
        with self.assertRaisesRegex(mod.PreflightError, "fonte_permissao_insegura"):
            mod.secure_digest(source, limit=1024, suffix=".conf")
        source.chmod(0o600)
        alias = self.root / "alias.conf"
        alias.symlink_to(source)
        with self.assertRaises(mod.PreflightError):
            mod.secure_digest(alias, limit=1024, suffix=".conf")

    def test_compose_invokes_only_quiet_config_with_private_env(self):
        paths = tuple(self.root / f"compose-{index}.yml" for index in range(14))
        captured = []

        def execute(command, **kwargs):
            captured.append((command, kwargs))
            return SimpleNamespace(returncode=0, stdout=b"SECRET_NEVER_PRINT",
                                   stderr=b"SECRET_NEVER_PRINT")

        with mock.patch.object(mod.subprocess, "run", side_effect=execute):
            self.assertTrue(mod.compose_interpolation(
                paths, {"CONECTAEDUCA_DB_HOST": "SECRET_DO_NOT_PRINT"}, 11))
            self.assertTrue(mod.compose_interpolation(
                paths, {"CONECTAEDUCA_DB_HOST": "SECRET_DO_NOT_PRINT"}, 14))
        self.assertEqual([sum(1 for item in argv if item == "-f")
                          for argv, _ in captured], [11, 14])
        for argv, options in captured:
            self.assertEqual(argv[-3:], ["config", "--no-env-resolution", "--quiet"])
            self.assertNotIn("up", argv)
            self.assertNotIn("down", argv)
            self.assertNotIn("--no-interpolate", argv)
            self.assertEqual(options["env"]["CONECTAEDUCA_DB_HOST"],
                             "SECRET_DO_NOT_PRINT")
            self.assertEqual(options["env"]["COMPOSE_DISABLE_ENV_FILE"], "1")

    def test_failed_config_never_dumps_secret_stderr(self):
        paths = tuple(self.root / f"compose-{index}.yml" for index in range(14))
        with mock.patch.object(mod.subprocess, "run", return_value=SimpleNamespace(
            returncode=1, stdout=b"SECRET_DO_NOT_PRINT",
            stderr=b"SECRET_DO_NOT_PRINT")):
            out = io.StringIO()
            with redirect_stdout(out):
                self.assertFalse(mod.compose_interpolation(
                    paths, {"CONECTAEDUCA_APP_URL": "SECRET_DO_NOT_PRINT"}, 14))
            self.assertNotIn("SECRET_DO_NOT_PRINT", out.getvalue())

    def test_main_summarizes_both_contexts_without_exposing_values(self):
        with (mock.patch.object(mod.socket, "gethostname", return_value="ep125-pucpr"),
              mock.patch.object(mod.os, "geteuid", return_value=1000),
              mock.patch.object(mod, "REPO", self.root),
              mock.patch.object(mod, "load_verified_library", return_value={}),
              mock.patch.object(mod, "analyze", return_value=[(True, True),
                                                              (True, False)])):
            out = io.StringIO()
            with redirect_stdout(out):
                self.assertEqual(mod.main(), 3)
        self.assertIn("COMPOSE11_INTERPOLACAO=PASS", out.getvalue())
        self.assertIn("COMPOSE14_INTERPOLACAO=FALHOU", out.getvalue())
        self.assertIn("CONFIG_EFETIVA_COMPLETA=NAO_COMPROVADA", out.getvalue())
        self.assertIn("ROLLBACK_HABILITADO=NAO", out.getvalue())

    def test_source_cannot_issue_container_mutations_or_log_config(self):
        src = SCRIPT.read_text(encoding="utf-8")
        for forbidden in ("print(result.stderr)", "print(result.stdout)",
                          "docker compose up", "docker compose down",
                          '"--execute"', '"rollback"', '"--env-file"'):
            self.assertNotIn(forbidden, src)


if __name__ == "__main__":
    unittest.main()
