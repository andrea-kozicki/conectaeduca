#!/usr/bin/env python3
"""Offline contract tests for GA08.20 canary. No Docker or VM required."""
from __future__ import annotations

from contextlib import redirect_stdout
import importlib.util
import io
from pathlib import Path
import re
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/ga08-canario-fpm-offline-ep125.py"
spec = importlib.util.spec_from_file_location("ga08_fpm_canary", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class CanaryContractTests(unittest.TestCase):
    def test_default_dry_run_never_calls_docker(self) -> None:
        buf = io.StringIO()
        with mock.patch("sys.argv", ["canary"]), redirect_stdout(buf), \
             mock.patch.object(mod, "docker", side_effect=AssertionError("Docker called")):
            self.assertEqual(mod.main(), 0)
        self.assertIn("DOCKER_EXECUTADO=NAO", buf.getvalue())
        self.assertIn("CUTOVER_EXECUTADO=NAO", buf.getvalue())

    def test_run_args_are_disposable_and_segregated(self) -> None:
        name = "ga08-fpm-canary-example"
        image_id = "sha256:" + ("a" * 64)
        args = mod.canary_args(name, image_id)
        self.assertIn("--network", args)
        self.assertEqual(args[args.index("--network") + 1], "none")
        self.assertIn("--read-only", args)
        self.assertIn("--cap-drop", args)
        self.assertIn("--restart", args)
        self.assertEqual(args[args.index("--restart") + 1], "no")
        self.assertIn("--user", args)
        self.assertEqual(args[args.index("--user") + 1], "82:82")
        self.assertIn(image_id, args)
        self.assertIn("-F", args)
        self.assertNotIn("up", args)
        self.assertNotIn("compose", args)
        self.assertNotIn("--privileged", args)
        self.assertNotIn("--publish", args)
        self.assertNotIn("-p", args)
        self.assertNotIn("--env-file", args)
        self.assertNotIn("--secret", args)
        mounts = [args[i + 1] for i, v in enumerate(args[:-1]) if v == "--mount"]
        self.assertEqual(len(mounts), 1)
        self.assertIn("zz-conectaeduca.socket.candidate.conf", mounts[0])
        self.assertIn("readonly", mounts[0])
        self.assertFalse(any("/var/lib/conectaeduca-ga08" in v for v in args))

    def test_log_triage_does_not_print_raw_secrets(self) -> None:
        self.assertEqual(mod.classify("Permission denied: /run/foo"), "PERMISSAO")
        self.assertEqual(mod.classify("Address already in use"), "SOCKET_OCUPADO")
        self.assertEqual(mod.classify("No such file or directory"), "ARQUIVO_OU_DIRETORIO")
        self.assertEqual(mod.classify("unable to bind"), "LISTENER")
        self.assertEqual(mod.classify("fpm is running"), "FPM_INICIOU")
        self.assertEqual(mod.classify("no data"), "SEM_CLASSIFICACAO")

    def test_host_guard_does_not_assume_vm_access(self) -> None:
        with mock.patch.object(mod.socket, "gethostname", return_value="not-ep125"), \
             self.assertRaisesRegex(RuntimeError, "HOST_FORA_EP125"):
            mod.assert_preconditions()

    def test_no_production_docker_mutators(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertNotIn('["compose"', source)
        self.assertNotIn('["restart"', source)
        self.assertNotIn('["stop"', source)
        self.assertNotIn('["start"', source)
        self.assertNotIn('"--privileged"', source)
        self.assertNotIn('"--network", "host"', source)
        self.assertTrue(re.search(r'docker\(\["rm", "--force", name\]', source))
        self.assertIn("TESTE_BIND_PERSISTENTE=NAO_ABRANGIDO", source)


if __name__ == "__main__":
    unittest.main()
