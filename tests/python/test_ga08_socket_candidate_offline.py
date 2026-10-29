"""GA08 socket candidate: read-only source contract."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class SocketCandidateContract(unittest.TestCase):
    def test_socket_network_contract(self):
        text = (ROOT / "deploy/dmz/compose.ga08-socket.candidate.yml").read_text()
        self.assertIn("waf_backend", text)
        self.assertIn("php_egress", text)
        self.assertEqual(text.count("target: /run/conectaeduca-fpm"), 2)

    def test_fastcgi_socket(self):
        text = (ROOT / "deploy/dmz/ga08/app-http.socket.candidate.conf").read_text()
        self.assertIn("unix:/run/conectaeduca-fpm/php-fpm.sock", text)

    def test_deployment_gate_closed(self):
        text = (ROOT / "scripts/ga08-implantacao-controlada-ep125.sh").read_text()
        self.assertIn("APLICACAO=NAO_EXECUTADA", text)
        self.assertIn("exit 3", text)

if __name__ == "__main__":
    unittest.main()
