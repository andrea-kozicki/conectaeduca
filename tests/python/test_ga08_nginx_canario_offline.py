#!/usr/bin/env python3
"""Offline contract GA08.28: safe one-shot Nginx canary with no network."""
import importlib.util
import io
from contextlib import redirect_stdout
from pathlib import Path
import unittest
from unittest import mock

FILE = Path(__file__).resolve().parents[2] / "scripts/ga08-nginx-canario-ep125.py"
spec = importlib.util.spec_from_file_location("ga08_nginx_canary", FILE)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class Contract(unittest.TestCase):
    def test_default_is_plan_only(self):
        out = io.StringIO()
        with mock.patch("sys.argv", ["canary"]), redirect_stdout(out), \
             mock.patch.object(mod, "preconditions", side_effect=AssertionError("called")):
            self.assertEqual(mod.main(), 0)
        self.assertIn("CONTEINER_CRIADO=NAO", out.getvalue())

    def test_disposable_arguments_use_running_image_no_secrets(self):
        argv = mod.args("ga08-nginx-canary-abc", "sha256:" + "a"*64)
        self.assertEqual(argv[:2], ["docker", "run"])
        self.assertIn("--network", argv)
        self.assertEqual(argv[argv.index("--network")+1], "none")
        self.assertIn("--read-only", argv)
        self.assertEqual(argv[argv.index("--user")+1], "101:101")
        self.assertEqual(argv[argv.index("--group-add")+1], "82")
        self.assertIn("no-new-privileges:true", argv)
        self.assertIn("--health-cmd", argv)
        self.assertIn("test -S /run/conectaeduca-http/nginx.sock", argv)
        self.assertIn("dst=/etc/nginx/conf.d/default.conf,readonly", " ".join(argv))
        self.assertFalse(any("/run/secrets" in x for x in argv))
        self.assertFalse(any("--privileged" in x for x in argv))
        self.assertEqual(argv[-1], "sha256:" + "a"*64)

    def test_status_classifier_no_logs(self):
        self.assertEqual(mod.classify("bind() Permission denied"), "PERMISSAO")
        self.assertEqual(mod.classify("Read-only file system"), "ROOTFS_RO")
        self.assertEqual(mod.classify("nginx: [emerg] invalid directive"), "CONFIGURACAO_NGINX")
        self.assertEqual(mod.classify("ready"), "SEM_ERRO_IDENTIFICADO")

    def test_source_never_mutates_production_or_logs_raw(self):
        source = FILE.read_text()
        self.assertNotIn('["docker", "compose"', source)
        self.assertNotIn('["docker", "restart"', source)
        self.assertNotIn('["docker", "stop"', source)
        self.assertNotIn('["docker", "cp"', source)
        self.assertIn('"BIND_PERSISTENTE_HOST_TESTADO=NAO"', source)
        self.assertIn('"LOG_CATEGORIA=" + category', source)
        self.assertIn('["docker", "rm", "--force", tempname]', source)

if __name__ == "__main__":
    unittest.main()
