#!/usr/bin/env python3
"""GA08.31 offline contract: only /var/run tmpfs varies; no production mutations."""
import importlib.util
import io
from contextlib import redirect_stdout
from pathlib import Path
import unittest
from unittest import mock

FILE=Path(__file__).resolve().parents[2]/"scripts/ga08-nginx-tmpfs-diferencial-ep125.py"
spec=importlib.util.spec_from_file_location("ga08_tmpfs_diff",FILE)
assert spec and spec.loader
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class Contract(unittest.TestCase):
    def test_default_does_not_access_runtime(self):
        out=io.StringIO()
        with mock.patch("sys.argv",["test"]), redirect_stdout(out), \
             mock.patch.object(mod.runpy,"run_path",side_effect=AssertionError("unexpected")):
            self.assertEqual(mod.main(),0)
        self.assertIn("DOCKER_EXECUTADO=NAO",out.getvalue())

    def test_omit_only_var_run_tmpfs(self):
        cmd=[
            "docker","run","--network","none",
            "--tmpfs","/var/cache/nginx:rw,uid=101",
            "--tmpfs","/var/run:rw,uid=101",
            "--tmpfs","/run/conectaeduca-http:rw,uid=101",
            "--tmpfs","/run/conectaeduca-fpm:rw,uid=82",
            "sha256:"+"a"*64
        ]
        x=mod.alter(cmd,"SEM_VAR_RUN")
        self.assertEqual(len(x),len(cmd)-2)
        self.assertFalse(any(s.startswith("/var/run:") for s in x))
        for item in ("/var/cache/nginx:rw,uid=101",
                     "/run/conectaeduca-http:rw,uid=101",
                     "/run/conectaeduca-fpm:rw,uid=82"):
            self.assertIn(item,x)

    def test_canonical_run_is_only_change(self):
        cmd=[
            "docker","run","--tmpfs","/var/run:rw,nosuid,uid=101",
            "--tmpfs","/run/conectaeduca-http:rw,uid=101",
            "sha256:"+"a"*64
        ]
        x=mod.alter(cmd,"RUN_CANONICO")
        self.assertEqual(len(x),len(cmd))
        self.assertIn("/run:rw,nosuid,uid=101",x)
        self.assertNotIn("/var/run:rw,nosuid,uid=101",x)
        self.assertIn("/run/conectaeduca-http:rw,uid=101",x)

    def test_invalid_or_ambiguous_safely_blocks(self):
        with self.assertRaises(ValueError):
            mod.alter(["docker","run"],"RUN_CANONICO")
        with self.assertRaises(ValueError):
            mod.alter(["docker","run","--tmpfs","/var/run:rw","--tmpfs","/var/run:rw"],"RUN_CANONICO")
        with self.assertRaises(ValueError):
            mod.alter(["docker","run","--tmpfs","/var/run:rw"],"INVALID")

    def test_disposable_and_no_production(self):
        source=FILE.read_text(encoding="utf-8")
        self.assertIn('module["args"](name, image)',source)
        self.assertIn('["docker", "rm", "--force", name]',source)
        self.assertIn("BLOBS",source)
        self.assertIn("MONTAGENS_HOST_TESTADAS=NAO",source)
        self.assertNotIn('["docker","compose"',source)
        self.assertNotIn('["docker","restart"',source)
        self.assertNotIn('["docker","stop"',source)

if __name__=="__main__":
    unittest.main()
