#!/usr/bin/env python3
"""Static WAF/client-IP contract, without a WAF process or VM."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
TLS = ROOT / "deploy/dmz/compose.waf-tls.yml"
BASE = ROOT / "deploy/dmz/compose.waf.yml"

EXPECTED = {
    "REAL_IP_PROXY_HEADER": "X-ConectaEduca-Client-IP",
    "REAL_IP_HEADER": "X-ConectaEduca-Upstream-IP",
    "SET_REAL_IP_FROM": "127.0.0.1",
    "REAL_IP_RECURSIVE": "off",
    "NGINX_X_FORWARDED_PROTO": "https",
    "NGINX_X_FORWARDED_PORT": "443",
}


def env_entries(yaml: str) -> dict[str, str]:
    # Strictly read the known, quoted string scalar values, never run compose.
    found = {}
    for name, value in re.findall(r'(?m)^\s*([A-Z][A-Z_0-9]+): "([^"\n]*)"\s*$', yaml):
        if name in found:
            raise ValueError("DUPLICATE_CONFIGURATION_KEY")
        found[name] = value
    return found


def validate(tls_text: str, compose_text: str) -> None:
    env = env_entries(tls_text)
    for key, value in EXPECTED.items():
        if env.get(key) != value:
            raise ValueError("WAF_CLIENT_IP_CONTRACT_CHANGED:" + key)
    if env["REAL_IP_PROXY_HEADER"] == env["REAL_IP_HEADER"]:
        raise ValueError("SELF_TRUSTED_HEADER")
    if not re.search(r'(?m)^\s+- "127\.0\.0\.1:18443:8443"\s*$', tls_text):
        raise ValueError("TLS_BIND_NOT_LOOPBACK")
    if not re.search(r'(?m)^\s+- "127\.0\.0\.1:18080:8080"\s*$', compose_text):
        raise ValueError("HTTP_BIND_NOT_LOOPBACK")
    if not re.search(r'(?m)^\s+ports: !reset \[\]\s*$', compose_text):
        raise ValueError("NGINX_DIRECT_PORT_RESET_MISSING")
    base_env = env_entries(compose_text)
    if base_env.get("BACKEND") != "http://nginx:8080":
        raise ValueError("WAF_BACKEND_DRIFTED")
    if base_env.get("MODSEC_RULE_ENGINE") != "On":
        raise ValueError("MODSEC_NOT_ENFORCING")


class WafClientIpContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tls = TLS.read_text(encoding="utf-8")
        cls.base = BASE.read_text(encoding="utf-8")

    def test_current_offline_overlay_contract(self):
        validate(self.tls, self.base)

    def test_spoofable_public_header_replacement_rejected(self):
        altered = self.tls.replace(
            'REAL_IP_PROXY_HEADER: "X-ConectaEduca-Client-IP"',
            'REAL_IP_PROXY_HEADER: "X-Forwarded-For"',
        )
        with self.assertRaisesRegex(ValueError, "REAL_IP_PROXY_HEADER"):
            validate(altered, self.base)

    def test_broad_trusted_sources_rejected(self):
        altered = self.tls.replace(
            'SET_REAL_IP_FROM: "127.0.0.1"',
            'SET_REAL_IP_FROM: "0.0.0.0/0"',
        )
        with self.assertRaisesRegex(ValueError, "SET_REAL_IP_FROM"):
            validate(altered, self.base)

    def test_same_trusted_header_as_forwarded_client_rejected(self):
        altered = self.tls.replace(
            'REAL_IP_HEADER: "X-ConectaEduca-Upstream-IP"',
            'REAL_IP_HEADER: "X-ConectaEduca-Client-IP"',
        )
        with self.assertRaisesRegex(ValueError, "REAL_IP_HEADER"):
            validate(altered, self.base)

    def test_public_tls_bind_rejected(self):
        altered = self.tls.replace("127.0.0.1:18443:8443", "0.0.0.0:18443:8443")
        with self.assertRaisesRegex(ValueError, "TLS_BIND_NOT_LOOPBACK"):
            validate(altered, self.base)

    def test_direct_nginx_port_publishing_rejected(self):
        altered = self.base.replace("ports: !reset []", 'ports: ["8080:8080"]')
        with self.assertRaisesRegex(ValueError, "NGINX_DIRECT_PORT_RESET_MISSING"):
            validate(self.tls, altered)

    def test_waf_fail_open_rejected(self):
        altered = self.base.replace('MODSEC_RULE_ENGINE: "On"', 'MODSEC_RULE_ENGINE: "Off"')
        with self.assertRaisesRegex(ValueError, "MODSEC_NOT_ENFORCING"):
            validate(self.tls, altered)

    def test_duplicated_config_key_rejected(self):
        altered = self.tls.replace(
            'REAL_IP_RECURSIVE: "off"',
            'REAL_IP_RECURSIVE: "off"\n      REAL_IP_RECURSIVE: "on"',
        )
        with self.assertRaisesRegex(ValueError, "DUPLICATE_CONFIGURATION_KEY"):
            validate(altered, self.base)


if __name__ == "__main__":
    unittest.main()
