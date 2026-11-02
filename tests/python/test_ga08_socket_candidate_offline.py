"""GA08 candidate source contracts: no Docker, VM or network access."""
import re
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
def read(path):
    return (ROOT / path).read_text(encoding="utf-8")
def block(text, service):
    match = re.search(r"(?ms)^  " + re.escape(service) + r":\n(.*?)(?=^  [a-z][\w-]*:|^networks:|\Z)", text)
    if not match:
        raise AssertionError("Missing service: " + service)
    return match.group(1)
def networks(service_text):
    match = re.search(r"(?m)^    networks: !override\n((?:      - [\w-]+\n)+)", service_text)
    if not match:
        raise AssertionError("Expected explicit network override")
    return re.findall(r"(?m)^      - ([\w-]+)$", match.group(1))
class SocketCandidateContract(unittest.TestCase):
    def setUp(self):
        self.overlay = read("deploy/dmz/compose.ga08-socket.candidate.yml")
    def test_exact_network_isolation(self):
        self.assertEqual(networks(block(self.overlay, "waf")), ["waf_backend"])
        self.assertEqual(networks(block(self.overlay, "nginx")), ["waf_backend"])
        self.assertEqual(networks(block(self.overlay, "php")), ["php_egress"])
        self.assertNotEqual(networks(block(self.overlay, "nginx")), networks(block(self.overlay, "php")))
    def test_php_fastcgi_expose_removed(self):
        p = block(self.overlay, "php")
        self.assertRegex(p, r"(?m)^    expose: !reset \[\]$")

    def test_socket_mount_permissions(self):
        n = block(self.overlay, "nginx")
        p = block(self.overlay, "php")
        self.assertIn('group_add:\n      - "82"', n)
        self.assertIn("target: /run/conectaeduca-fpm\n        read_only: true", n)
        self.assertIn("target: /run/conectaeduca-fpm\n", p)
        self.assertNotIn("target: /run/conectaeduca-fpm\n        read_only: true", p)
        self.assertEqual(self.overlay.count("target: /run/conectaeduca-fpm"), 2)
        fpm = read("deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf")
        self.assertIn("listen.mode = 0660", fpm)
        self.assertIn("listen = /run/conectaeduca-fpm/php-fpm.sock", fpm)
    def test_nginx_delta_only_six_fastcgi_targets(self):
        original = read("deploy/dmz/nginx/app-http.conf")
        candidate = read("deploy/dmz/ga08/app-http.socket.candidate.conf")
        old = "fastcgi_pass php:9000;"
        new = "fastcgi_pass unix:/run/conectaeduca-fpm/php-fpm.sock;"
        self.assertEqual(original.count(old), 6)
        self.assertEqual(candidate.count(new), 6)
        self.assertEqual(candidate.replace(new, old), original)
    def test_deployment_gate_closed_by_default(self):
        gate = read("scripts/ga08-implantacao-controlada-ep125.sh")
        rollback = read("scripts/ga08-rollback-controlado-ep125.sh")
        engine = read("scripts/ga08-change-control.py")
        self.assertIn('--action cutover "$@"', gate)
        self.assertIn('--action rollback "$@"', rollback)
        self.assertNotIn('docker compose up', gate)
        self.assertNotIn('docker compose up', rollback)
        self.assertIn('if not args.execute:', engine)
        self.assertIn('GA08_ENABLE_LIVE_CHANGE', engine)
        self.assertIn('RESTAURAR_BASELINE_EP125', engine)
        self.assertIn('GA08_APLICACAO=NAO_EXECUTADA', engine)
        self.assertIn('GA08_ROLLBACK=NAO_EXECUTADO', engine)
    def test_negative_mutations_detected(self):
        mutated = self.overlay.replace("- php_egress", "- waf_backend", 1)
        self.assertNotEqual(networks(block(mutated, "php")), ["php_egress"])
        unlocked = read("scripts/ga08-change-control.py").replace(
            'os.environ.get("GA08_ENABLE_LIVE_CHANGE") == "YES"', 'True'
        )
        self.assertNotIn('os.environ.get("GA08_ENABLE_LIVE_CHANGE") == "YES"', unlocked)
        self.assertIn('os.environ.get("GA08_ENABLE_LIVE_CHANGE") == "YES"',
                      read("scripts/ga08-change-control.py"))
if __name__ == "__main__":
    unittest.main()
