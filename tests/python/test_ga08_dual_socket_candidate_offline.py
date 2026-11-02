"""GA-08: source-only contracts for WAF->Nginx HTTP Unix socket.

No Docker, VM, network, secrets, or privileged operations. Runtime gates
(ownership, read-only bind, HTTP behavior and denial of host->bridge) are
explicitly outside the scope of these checks.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


class DualSocketCandidateContract(unittest.TestCase):
    def setUp(self):
        self.overlay = read("deploy/dmz/compose.ga08-dual-socket.candidate.yml")
        self.base = read("deploy/dmz/ga08/app-http.socket.candidate.conf")
        self.candidate = read("deploy/dmz/ga08/app-http.dual-socket.candidate.conf")

    def test_nginx_delta_is_exactly_one_listener(self):
        old = "    listen 8080;"
        new = "    listen unix:/run/conectaeduca-http/nginx.sock;"
        self.assertEqual(self.base.count(old), 1)
        self.assertEqual(self.candidate.count(new), 1)
        self.assertEqual(self.candidate.replace(new, old), self.base)
        self.assertNotRegex(self.candidate, r"(?m)^\s*listen\s+(?:\S*:)?8080\s*;")

    def test_fastcgi_socket_b_unchanged(self):
        fpm = "fastcgi_pass unix:/run/conectaeduca-fpm/php-fpm.sock;"
        self.assertEqual(self.base.count(fpm), 6)
        self.assertEqual(self.candidate.count(fpm), 6)
        self.assertNotIn("fastcgi_pass php:9000;", self.candidate)

    def test_waf_backend_explicit_unix_url_without_uri_rewrite(self):
        self.assertIn(
            'BACKEND: "http://unix:/run/conectaeduca-http/nginx.sock:"',
            self.overlay,
        )
        self.assertNotIn("http://nginx:8080", self.overlay)
        self.assertNotIn("modsecurity.conf", self.overlay)
        self.assertNotIn("MODSEC_RULE_ENGINE", self.overlay)

    def test_two_shared_mounts_separate_from_fastcgi(self):
        path = "target: /run/conectaeduca-http"
        self.assertEqual(self.overlay.count(path), 2)
        self.assertEqual(self.overlay.count("read_only: true"), 2)
        self.assertEqual(self.overlay.count("target: /etc/nginx/conf.d/default.conf"), 1)
        self.assertNotIn("target: /run/conectaeduca-fpm", self.overlay)
        self.assertIn("CONECTAEDUCA_GA08_HTTP_SOCKET_DIR", self.overlay)
        self.assertIn("CONECTAEDUCA_GA08_NGINX_HTTP_UNIX_CONF", self.overlay)

    def test_nginx_tcp_exposure_reset(self):
        self.assertRegex(
            self.overlay,
            r"(?m)^  nginx:\n(?:.*\n)*?    ports: !reset \[\]",
        )
        self.assertIn("    expose: !reset []", self.overlay)
        self.assertNotIn("    networks:", self.overlay)

    def test_healthcheck_does_not_use_removed_tcp_port(self):
        self.assertIn("nginx -t >/dev/null 2>&1", self.overlay)
        self.assertIn("test -S /run/conectaeduca-http/nginx.sock", self.overlay)
        self.assertNotIn("127.0.0.1:8080", self.overlay)
        self.assertNotIn("    privileged:", self.overlay)

    def test_deployment_still_blocked(self):
        gate = read("scripts/ga08-implantacao-controlada-ep125.sh")
        self.assertIn("APLICACAO=NAO_EXECUTADA", gate)
        self.assertRegex(gate, r"(?m)^exit 3\s*$")


if __name__ == "__main__":
    unittest.main()
