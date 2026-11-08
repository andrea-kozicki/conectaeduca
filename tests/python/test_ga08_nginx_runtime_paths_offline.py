#!/usr/bin/env python3
"""Offline tests for GA08.30 Nginx mount-namespace diagnostic."""
import importlib.util
from contextlib import redirect_stdout
from pathlib import Path
import io
import unittest
from unittest import mock

FILE=Path(__file__).resolve().parents[2]/"scripts/ga08-nginx-runtime-paths-ep125.py"
spec=importlib.util.spec_from_file_location("ga08_nginx_paths",FILE)
assert spec and spec.loader
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class Contract(unittest.TestCase):
    def test_dry_run_does_not_execute_docker(self):
        out=io.StringIO()
        with mock.patch("sys.argv",["test"]), redirect_stdout(out), \
             mock.patch.object(mod.runpy,"run_path",side_effect=AssertionError("runtime invoked")):
            self.assertEqual(mod.main(),0)
        self.assertIn("MODO=PLANO",out.getvalue())

    def test_mount_diagnostics_before_nginx(self):
        s=mod.SHELL_PROBE
        self.assertIn("GA08_HTTP_DIR_WRITABLE:-w:/run/conectaeduca-http",s)
        self.assertIn("GA08_HTTP_MOUNT_PRESENTE=",s)
        self.assertIn("/proc/self/mountinfo",s)
        self.assertIn("GA08_NGINX_CONF_TEST=",s)
        self.assertIn("exec nginx -g 'daemon off;'",s)
        self.assertLess(s.index("GA08_HTTP_DIR_WRITABLE"),s.index("exec nginx -g"))

    def test_no_host_socket_mount_secrets_mutations(self):
        s=FILE.read_text(encoding="utf-8")
        self.assertIn("CANARY_BLOB",s)
        self.assertIn("DIFF_BLOB",s)
        self.assertIn('argv[idx:idx]=["--entrypoint","/bin/sh"]',s)
        self.assertIn('["docker","rm","--force",name]',s)
        self.assertNotIn('["docker","compose"',s)
        self.assertNotIn('["docker","restart"',s)
        self.assertNotIn('["docker","stop"',s)
        self.assertIn("SERVICOS_PRODUCAO_MODIFICADOS=NAO_POR_ESTE_SCRIPT",s)

if __name__=="__main__":
    unittest.main()
