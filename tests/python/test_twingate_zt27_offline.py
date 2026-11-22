"""CE-ZT27: regressões isoladas sem DNS, Docker ou conexões externas."""
import importlib.util
import io
import pathlib
import subprocess
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "scripts/twingate/ce_zt27_operacional.py"
spec = importlib.util.spec_from_file_location("ce_zt27_operacional", SOURCE)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class TestZt27(unittest.TestCase):
    def test_endpoints_are_fixed_and_https(self):
        self.assertEqual(4, len(mod.ENDPOINTS))
        self.assertEqual(4, len({domain for _, domain, _ in mod.ENDPOINTS}))
        self.assertTrue(all(p.startswith("/") for _, _, p in mod.ENDPOINTS))

    def test_tls_reset_classification(self):
        with patch.object(mod, "call", return_value=subprocess.CompletedProcess(
            [], 35, stdout="HTTP=000;TLS=1;IP=204.57.240.10",
            stderr="Recv failure: Connection reset by peer")):
            result = mod.probe("PUBNUB_H2", "h2.pubnubapi.com", "/time/0")
        self.assertEqual(result["erro"], "TLS_RESET_OU_NEGOCIACAO")
        self.assertFalse(result["ok"])

    def test_endpoint_200_tls_ok(self):
        with patch.object(mod, "call", return_value=subprocess.CompletedProcess(
            [], 0, stdout="HTTP=200;TLS=0;IP=204.57.240.1", stderr="")):
            result = mod.probe("PUBNUB_PNDSN", "ps.pndsn.com", "/time/0")
        self.assertTrue(result["ok"])

    def test_http_404_is_not_accepted_as_time_api_success(self):
        with patch.object(mod, "call", return_value=subprocess.CompletedProcess(
            [], 0, stdout="HTTP=404;TLS=0;IP=204.57.240.1", stderr="")):
            result = mod.probe("PUBNUB_PNDSN", "ps.pndsn.com", "/time/0")
        self.assertFalse(result["ok"])
        self.assertEqual("HTTP_NAO_200", result["erro"])

    def test_mismatched_host_is_fail_closed(self):
        buffer = io.StringIO()
        with patch.object(mod.socket, "gethostname", return_value="another-machine"):
            with redirect_stdout(buffer):
                exit_code = mod.main(["--role", "ep125"])
        self.assertEqual(4, exit_code)
        self.assertIn("HOST_NAO_CORRESPONDE", buffer.getvalue())

    def test_connector_inspect_does_not_return_secret_values(self):
        import json
        inspect = [{
            "State": {"Running": True, "Health": {"Status": "healthy"}},
            "RestartCount": 0,
            "NetworkSettings": {"Networks": {"bridge": {}}},
            "Config": {"Image": "twingate/connector:1",
                       "Env": ["TWINGATE_NETWORK=tenant",
                               "TWINGATE_ACCESS_TOKEN=extremely-secret-value",
                               "TWINGATE_REFRESH_TOKEN=another-secret"]},
        }]
        result = subprocess.CompletedProcess([], 0, stdout=json.dumps(inspect), stderr="")
        with patch.object(mod, "call", return_value=result):
            info = mod.inspect_connector("conectaeduca-dmz-01")
        self.assertTrue(info["env"]["TWINGATE_ACCESS_TOKEN"])
        self.assertNotIn("extremely-secret-value", str(info))
        self.assertNotIn("another-secret", str(info))

    def test_logs_never_return_raw_lines(self):
        text = (
            "[ERROR] [libsdwan] [pubnub-lib] TLS/SSL I/O operation failed\n"
            "Authorization: Bearer definitely-never-expose\n"
            "[ERROR] [libsdwan] [pubnub-lib] error_message(Transaction failed)\n"
        )
        p = subprocess.CompletedProcess([], 0, stdout=text, stderr="")
        with patch.object(mod, "call", return_value=p):
            info = mod.log_counts("conectaeduca-dmz-01")
        self.assertEqual(1, info["counts"]["PUBNUB_TLS_IO"])
        self.assertEqual(1, info["counts"]["PUBNUB_TRANSACTION"])
        self.assertNotIn("definitely-never-expose", str(info))

    def test_no_network_when_host_wrong(self):
        with patch.object(mod.socket, "gethostname", return_value="ep126-pucpr-br"):
            with patch.object(mod, "probe") as probe:
                with redirect_stdout(io.StringIO()):
                    rc = mod.main(["--role", "ep125"])
        self.assertEqual(4, rc)
        probe.assert_not_called()


if __name__ == "__main__":
    unittest.main()
