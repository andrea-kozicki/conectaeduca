#!/usr/bin/env python3
"""Offline contract for GA08.26 read-only E2E regression; never probes network."""
import importlib.util
import io
from contextlib import redirect_stdout
from pathlib import Path
from unittest import TestCase, main, mock

PATH = Path(__file__).resolve().parents[2] / "scripts/ga08-e2e-pa02-ep125.py"
spec = importlib.util.spec_from_file_location("ga08_e2e", PATH)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

def item(role, network, ip):
    return {
        "Config": {"Labels": {
            "com.docker.compose.project": "conectaeduca-dmz",
            "com.docker.compose.service": role,
        }},
        "State": {"Running": True, "Health": {"Status": "healthy"}},
        "NetworkSettings": {"Networks": {
            "conectaeduca-dmz_" + network: {"IPAddress": ip}
        }},
        "HostConfig": {"PortBindings": (
            {"8443/tcp": [{"HostIp": "192.168.6.34", "HostPort": "443"}]}
            if role == "waf" else {}
        )}
    }

class Contract(TestCase):
    def setUp(self):
        self.good = {
            "waf": item("waf", "waf_backend", "172.31.0.2"),
            "nginx": item("nginx", "waf_backend", "172.31.0.3"),
            "php": item("php", "php_egress", "172.30.0.2"),
        }

    def test_dry_run_has_no_side_effects(self):
        out = io.StringIO()
        with mock.patch("sys.argv", ["test"]), redirect_stdout(out), \
             mock.patch.object(mod, "inspect", side_effect=AssertionError("INSPECT_CALLED")), \
             mock.patch.object(mod, "request", side_effect=AssertionError("HTTP_CALLED")):
            self.assertEqual(mod.main(), 0)
        self.assertIn("MODO=PLANO", out.getvalue())

    def test_topology_positive(self):
        ip, port, addrs = mod.verify_baseline(self.good)
        self.assertEqual((ip, port), ("192.168.6.34", 443))
        self.assertEqual(addrs["nginx"], "172.31.0.3")

    def test_rejects_php_nginx_same_network(self):
        self.good["php"]["NetworkSettings"]["Networks"] = self.good["nginx"]["NetworkSettings"]["Networks"]
        with self.assertRaisesRegex(RuntimeError, "TOPOLOGIA_AINDA_BASELINE_OU_DIVERGENTE"):
            mod.verify_baseline(self.good)

    def test_rejects_published_backend(self):
        self.good["nginx"]["HostConfig"]["PortBindings"] = {"8080/tcp": [
            {"HostIp":"0.0.0.0","HostPort":"8080"}
        ]}
        with self.assertRaisesRegex(RuntimeError, "BACKEND_PORTA_PUBLICADA"):
            mod.verify_baseline(self.good)

    def test_rejects_healthy_but_still_baseline(self):
        self.good["php"]["NetworkSettings"]["Networks"] = {
            "conectaeduca-dmz_internal": {"IPAddress": "172.31.0.6"}
        }
        with self.assertRaisesRegex(RuntimeError, "TOPOLOGIA_AINDA_BASELINE_OU_DIVERGENTE"):
            mod.verify_baseline(self.good)

    def test_source_has_no_docker_mutation_or_secrets(self):
        src = PATH.read_text(encoding="utf-8")
        self.assertNotIn('"compose"', src)
        self.assertNotIn('"restart"', src)
        self.assertNotIn('"stop"', src)
        self.assertNotIn('"rm"', src)
        self.assertNotIn('"--privileged"', src)
        self.assertIn("PA02_FECHADO=NAO_POR_ESTE_TESTE", src)
        self.assertIn("WAF_XSS_CANARIO", src)

if __name__ == "__main__":
    main()
