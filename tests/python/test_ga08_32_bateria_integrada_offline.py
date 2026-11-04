#!/usr/bin/env python3
"""GA08.32 offline contracts: joined batch, narrow Compose delta, no prod writes."""
from contextlib import redirect_stdout
import importlib.util
import io
from pathlib import Path
import unittest
from unittest import mock

FILE=Path(__file__).resolve().parents[2]/"scripts/ga08-32-bateria-integrada-ep125.py"
SPEC=importlib.util.spec_from_file_location("ga08_batch",FILE)
assert SPEC and SPEC.loader
M=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)

class BatchTests(unittest.TestCase):
    def test_default_does_not_probe_runtime(self):
        out=io.StringIO()
        with mock.patch("sys.argv",["ga08_batch"]), redirect_stdout(out), \
             mock.patch.object(M.runpy,"run_path",side_effect=AssertionError("loaded runtime")):
            self.assertEqual(M.main(),0)
        self.assertIn("MODO=PLANEJAMENTO",out.getvalue())
        self.assertIn("DOCKER_EXECUTADO=NAO",out.getvalue())

    def test_overlay_is_canonical_tmpfs_override(self):
        overlay=(FILE.parents[2]/"deploy/dmz/compose.ga08-runtimefix.candidate.yml").read_text()
        self.assertIn("tmpfs: !override",overlay)
        self.assertIn("      - /run:rw,nosuid,nodev,noexec,size=4m,uid=101,gid=101,mode=0750",overlay)
        self.assertIn("      - /var/cache/nginx:rw,nosuid,nodev,noexec,size=16m,uid=101,gid=101,mode=0750",overlay)
        self.assertNotIn("      - /var/run:",overlay)
        self.assertNotIn("read_only: false",overlay)
        self.assertNotIn("privileged:",overlay)
        self.assertNotIn("network_mode: host",overlay)

    def test_static_batch_includes_all_must_have(self):
        s=FILE.read_text()
        for marker in ("BASELINE_3_SERVICOS_HEALTHY",
                       "COMPOSE_DIFF=APENAS_TMPFS_NGINX",
                       "COMPOSE_RUN_CANONICO=PASS",
                       "COMPOSE_SEGREGACAO=PASS",
                       "\"CRS_XSS\"",
                       "CANARIO_NGINX_HEALTHY",
                       "CANARIO_NGINX_TEST",
                       "CANARIO_SOCKET_HTTP",
                       "BIND_HOST_REAL_LEITURA",
                       "BIND_HOST_RW_E2E_TESTADO=NAO",
                       "PA02_FECHADO=NAO",
                       "CUTOVER_EXECUTADO=NAO"):
            self.assertIn(marker,s)
        self.assertNotIn('["docker", "compose", "up"',s)
        self.assertNotIn('["docker", "restart"',s)
        self.assertNotIn('["docker", "stop"',s)
        self.assertNotIn('["docker", "prune"',s)
        self.assertNotIn('chmod(',s)
        self.assertNotIn('chown(',s)

    def test_host_binds_both_read_only(self):
        s=FILE.read_text()
        self.assertIn('f"type=bind,src={host},dst={parent},readonly"',s)
        self.assertIn('("/run/conectaeduca-http", "/var/lib/conectaeduca-ga08/http")',s)
        self.assertIn('("/run/conectaeduca-fpm", "/var/lib/conectaeduca-ga08/fpm")',s)
        self.assertIn("CANARIO_BIND_RO_REMOVIDO",s)
        self.assertIn("CANARIO_ISOLADO_REMOVIDO",s)
        self.assertIn('["docker", "rm", "--force", name]',s)

    def test_compose_rejects_non_tmpfs_drift(self):
        base={
            "services":{
                "nginx":{"tmpfs":["/var/cache/nginx:rw","/var/run:rw"],"read_only":True,"ports":[]},
                "php":{"image":"a"},
                "waf":{"image":"b"},
            },
        }
        fixed={
            "services":{
                "nginx":{"tmpfs":["/var/cache/nginx:rw","/run:rw"],"read_only":True,"ports":["80:80"]},
                "php":{"image":"a"},
                "waf":{"image":"b"},
            },
        }
        calls=[base,fixed]
        driver={
            "files":lambda n:[Path(f"f{i}") for i in range(n)],
            "get_config":lambda xs:calls.pop(0),
            "check_candidate":lambda b,c:None
        }
        with self.assertRaisesRegex(RuntimeError,"COMPOSE_MUDANCA_FORA_TMPFS"):
            M.validate_compose(driver)

    def test_compose_accepts_only_canonical_delta(self):
        base={"services":{"nginx":{"tmpfs":["/var/cache/nginx:rw","/var/run:rw"],"read_only":True},
                          "php":{"image":"a"},"waf":{"image":"b"}}}
        fixed={"services":{"nginx":{"tmpfs":["/var/cache/nginx:rw","/run:rw"],"read_only":True},
                           "php":{"image":"a"},"waf":{"image":"b"}}}
        def cfg(xs):
            return fixed if any(str(x).endswith("compose.ga08-runtimefix.candidate.yml") for x in xs) else base
        driver={"files":lambda n:[Path(f"f{i}") for i in range(n)],
                "get_config":cfg,
                "check_candidate":lambda b,c:None}
        with redirect_stdout(io.StringIO()):
            out=M.validate_compose(driver)
        self.assertEqual(out,fixed)

    def test_health_baseline_four_checks(self):
        observed=[]
        def curl(path):
            observed.append(path)
            return (0,"403" if "ga08_validation" in path else "200")
        with mock.patch.object(M,"curl_code",side_effect=curl),redirect_stdout(io.StringIO()):
            self.assertTrue(M.smoke())
        self.assertEqual(len(observed),4)

if __name__=="__main__":
    unittest.main()
