#!/usr/bin/env python3
"""Offline tests for GA08.29 differentiated entrypoint experiment."""
from contextlib import redirect_stdout
import importlib.util
import io
from pathlib import Path
import unittest
from unittest import mock

FILE = Path(__file__).resolve().parents[2] / "scripts/ga08-nginx-entrypoint-isolation-ep125.py"
spec = importlib.util.spec_from_file_location("ga08_nginx_direct", FILE)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class Contract(unittest.TestCase):
    def test_plan_only_no_runtime_access(self):
        out = io.StringIO()
        with mock.patch("sys.argv", ["diag"]), redirect_stdout(out), \
             mock.patch.object(mod.runpy, "run_path", side_effect=AssertionError("unexpected runtime")):
            self.assertEqual(mod.main(), 0)
        self.assertIn("DOCKER_EXECUTADO=NAO", out.getvalue())

    def test_sanitizes_specific_fatal_log(self):
        cases = {
            'nginx: [emerg] bind() to unix:/run/conectaeduca-http/nginx.sock failed (13: Permission denied)': ("PERMISSAO", "SOCKET_HTTP"),
            'nginx: [emerg] open() "/var/run/nginx.pid" failed (30: Read-only file system)': ("ROOTFS_RO", "PID_NGINX"),
            'nginx: [emerg] mkdir() "/var/cache/nginx/client_temp" failed (30: Read-only file system)': ("ROOTFS_RO", "CACHE_NGINX"),
            'nginx: [emerg] open() "/etc/nginx/nginx.conf" failed (13: Permission denied)': ("PERMISSAO", "CONFIG_NGINX"),
            'nginx: [emerg] mkdir() "/run/conectaeduca-http" failed (13: Permission denied)': ("PERMISSAO", "DIRETORIO_HTTP"),
            'no errors here': ("SEM_ERRO_IDENTIFICADO", "NAO_APLICAVEL"),
        }
        for text, expected in cases.items():
            with self.subTest(text=text[:20]):
                self.assertEqual(mod.category_and_target(text), expected)

    def test_fatal_line_overrides_nonfatal_readonly_warning(self):
        logs = (
            '10-listen-on-ipv6-by-default.sh: can not modify /etc/nginx/conf.d/default.conf (read-only file system?)\n'
            'nginx: [emerg] bind() to unix:/run/conectaeduca-http/nginx.sock failed (13: Permission denied)'
        )
        self.assertEqual(mod.category_and_target(logs), ("PERMISSAO", "SOCKET_HTTP"))

    def test_preserves_safe_canary_contract(self):
        src = FILE.read_text(encoding="utf-8")
        self.assertIn('CANARY_GIT_BLOB', src)
        self.assertIn('"--entrypoint", "nginx"', src)
        self.assertIn('["-g", "daemon off;"]', src)
        self.assertIn('"docker", "rm", "--force", name', src)
        self.assertIn('BIND_HOST_PERSISTENTE_TESTADO=NAO', src)
        self.assertNotIn('["docker", "compose"', src)
        self.assertNotIn('["docker", "restart"', src)
        self.assertNotIn('["docker", "stop"', src)

if __name__ == "__main__":
    unittest.main()
