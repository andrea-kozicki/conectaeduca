#!/usr/bin/env python3
"""GA-08: resolve 3 overlays em CI com variaveis ficticias; nao sobe Docker.

Escopo limitado: compose.yml + compose.waf.yml + compose.host.yml.
NAO comprova o stack de 9/10 overlays ou as redes efetivas da EP125.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
COMPOSE_FILES = (
    ROOT / "deploy/dmz/compose.yml",
    ROOT / "deploy/dmz/compose.waf.yml",
    ROOT / "deploy/dmz/compose.host.yml",
)
LAB_WAF_IP = "192.0.2.34"
LAB_DB_IP = "192.0.2.50"


def resolved_compose() -> dict:
    if shutil.which("docker") is None:
        raise RuntimeError("docker CLI ausente: gate deve falhar, nao ser ignorado")
    args = ["docker", "compose"]
    for file in COMPOSE_FILES:
        args.extend(("-f", str(file)))
    args.extend(("config", "--format", "json"))
    env = dict(os.environ)
    env.update({
        "CONECTAEDUCA_WAF_BIND_ADDRESS": LAB_WAF_IP,
        "CONECTAEDUCA_HTTP_PORT": "80",
        "CONECTAEDUCA_HTTPS_PORT": "443",
        "CONECTAEDUCA_DB_HOST": LAB_DB_IP,
        "CONECTAEDUCA_DB_PORT": "3306",
        "CONECTAEDUCA_SOURCE_COMMIT": "GA08-OFFLINE-TEST",
    })
    run = subprocess.run(args, cwd=ROOT, env=env, capture_output=True,
                         text=True, timeout=30, check=False)
    if run.returncode != 0:
        # Nao despejar ambiente do runner ou arquivo renderizado em logs.
        raise RuntimeError("docker compose config recusou o conjunto GA08 "
                           f"(exit={run.returncode})")
    data = json.loads(run.stdout)
    if not isinstance(data, dict) or not isinstance(data.get("services"), dict):
        raise RuntimeError("docker compose config nao retornou servicos JSON")
    return data


class GA08ResolvedComposeOffline(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.services = resolved_compose()["services"]

    def test_nginx_never_publishes_host_port(self):
        nginx = self.services["nginx"]
        self.assertFalse(nginx.get("ports"), "8088 do laboratorio reapareceu no host")
        self.assertIn("8080", [str(p) for p in nginx.get("expose", [])])

    def test_php_is_not_published_and_uses_internal_db(self):
        php = self.services["php"]
        self.assertFalse(php.get("ports"), "PHP-FPM exposto indevidamente")
        self.assertEqual(php["environment"]["DB_HOST"], LAB_DB_IP)
        self.assertEqual(str(php["environment"]["DB_PORT"]), "3306")

    def test_waf_only_exposes_standard_ports_on_explicit_address(self):
        waf = self.services["waf"]
        ports = waf.get("ports", [])
        found = {(str(p.get("published")), str(p.get("target")), p.get("host_ip"))
                 for p in ports}
        self.assertEqual(found, {
            ("80", "8080", LAB_WAF_IP),
            ("443", "8443", LAB_WAF_IP),
        })
        self.assertEqual(waf["environment"]["BACKEND"], "http://nginx:8080")

    def test_nginx_waf_php_share_only_expected_frontend(self):
        networks = [
            set(self.services[name].get("networks", []))
            for name in ("nginx", "waf", "php")
        ]
        self.assertTrue(networks[0] & networks[1] & networks[2],
                        "WAF e backend deixaram de partilhar frontend")
        # Rede compartilhada e necessaria ao fluxo; nao prova isolamento
        # contra um atacante no host ou dentro da mesma bridge.


if __name__ == "__main__":
    unittest.main()
