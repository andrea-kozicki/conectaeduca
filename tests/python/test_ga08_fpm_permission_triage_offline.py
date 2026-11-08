#!/usr/bin/env python3
"""Offline tests for GA08.21 sanitized permission classifier; no Docker."""
from contextlib import redirect_stdout
import importlib.util
import io
from pathlib import Path
import unittest
from unittest import mock

FILE = Path(__file__).resolve().parents[2] / "scripts/ga08-fpm-permission-triage-ep125.py"
spec = importlib.util.spec_from_file_location("ga08_permission", FILE)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class Contract(unittest.TestCase):
    def test_default_is_plan_only(self):
        out = io.StringIO()
        with mock.patch("sys.argv", ["diag"]), redirect_stdout(out), \
             mock.patch.object(mod, "load_canary", side_effect=AssertionError()):
            self.assertEqual(mod.main(), 0)
        self.assertIn("DOCKER_EXECUTADO=NAO", out.getvalue())

    def test_explicit_allowlist_no_raw_logs(self):
        samples = {
            "ERROR: unable to bind listening socket for address '/run/conectaeduca-fpm/php-fpm.sock': Permission denied": ("PERMISSAO","SOCKET_UNIX"),
            "ERROR: permission denied /run/conectaeduca-fpm": ("PERMISSAO","DIRETORIO_SOCKET"),
            "php-fpm.pid: Operation not permitted": ("PERMISSAO","PID_FPM"),
            "failed to open error_log (/proc/self/fd/2) Permission denied": ("PERMISSAO","ERROR_LOG_STDERR"),
            "could not open /usr/local/etc/php-fpm.d/z.conf: permission denied": ("PERMISSAO","CONFIG_FPM"),
            "Permission denied: SECRET=1234": ("PERMISSAO","ALVO_NAO_CLASSIFICADO"),
            "CONFIG /run/conectaeduca-fpm/php-fpm.sock loaded\nERROR /proc/self/fd/2 Permission denied": ("PERMISSAO","ERROR_LOG_STDERR"),
            "No such file or directory": ("ARQUIVO_AUSENTE","NAO_APLICAVEL"),
            "ready to handle connections": ("NAO_IDENTIFICADO","NAO_APLICAVEL"),
        }
        for log, answer in samples.items():
            with self.subTest(log=log[:30]):
                self.assertEqual(mod.error_detail(log), answer)

    def test_compose_not_used_and_network_disabled(self):
        src = FILE.read_text()
        self.assertNotIn('["compose"', src)
        self.assertNotIn('["restart"', src)
        self.assertNotIn('["stop"', src)
        self.assertNotIn('["exec"', src)
        self.assertIn("PINNED_CANARY_BLOB", src)
        self.assertIn("PINNED_FPM_CONFIG_BLOB", src)
        self.assertIn("LOGS_BRUTOS_EXIBIDOS=NAO", src)

    def test_reuse_hardening_of_known_canary(self):
        from types import SimpleNamespace
        src = Path(__file__).resolve().parents[2] / "scripts/ga08-canario-fpm-offline-ep125.py"
        self.assertEqual(mod.git_blob(src), mod.PINNED_CANARY_BLOB)
        cfg = Path(__file__).resolve().parents[2] / "deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf"
        self.assertEqual(mod.git_blob(cfg), mod.PINNED_FPM_CONFIG_BLOB)
        base = ["run", "--network", "none", "--name", "temporary", "--entrypoint", "php-fpm", "sha256:" + "a"*64, "-F"]
        x = mod.diag_args(SimpleNamespace(canary_args=lambda name,img:base[:]), "temporary", "sha256:"+"a"*64)
        self.assertEqual(x[x.index("--entrypoint")+1], "/bin/sh")
        self.assertEqual(x[-2], "-c")
        self.assertIn("exec php-fpm -F", x[-1])

if __name__ == "__main__":
    unittest.main()
