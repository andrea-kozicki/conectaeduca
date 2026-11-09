"""CE-ZT31 — validação offline do relatório sem acesso ao tenant."""
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
P = ROOT / "scripts/twingate/ce_zt31_acesso_minimo.py"
spec = importlib.util.spec_from_file_location("zt31", P)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def conn(nodes):
    return {"pageInfo": {"hasNextPage": False}, "edges": [{"node": n} for n in nodes]}


class TestZT31(unittest.TestCase):
    def test_redacts_identity(self):
        self.assertNotIn("andrea@example.com", mod.private_identity("andrea@example.com"))
        self.assertIn("@example.com", mod.private_identity("andrea@example.com"))

    def test_ports(self):
        self.assertEqual("RESTRICTED:443", mod.ports(
            {"policy": "RESTRICTED", "ports": [{"start": 443, "end": 443}]}))
        self.assertEqual("ALLOW_ALL", mod.ports({"policy": "ALLOW_ALL", "ports": []}))

    def test_expected_minimal_access(self):
        self.assertTrue(mod.port443only({"protocols": {
            "tcp": {"policy": "RESTRICTED", "ports": [{"start": 443, "end": 443}]},
            "udp": {"policy": "RESTRICTED", "ports": []},
            "allowIcmp": False
        }}))
        self.assertFalse(mod.port443only({"protocols": {
            "tcp": {"policy": "ALLOW_ALL", "ports": []},
            "udp": {"policy": "DENY_ALL", "ports": []},
            "allowIcmp": False
        }}))

    def test_report_redacts_and_flags_wide_port(self):
        data = {
            "users": {**conn([{"email": "andrea@example.com", "state": "ACTIVE",
                               "role": "ADMIN", "groups": conn([{"name": "CE-PORTAL"}])}]),
                      "totalCount": 1},
            "resources": conn([{"name": "ConectaEducaAPP", "remoteNetwork": {"name": "DMZ"},
                                "securityPolicy": {"name": "CE-PORTAL-MFA-1DIA"},
                                "protocols": {"allowIcmp": True, "tcp": {"policy": "ALLOW_ALL"},
                                              "udp": {"policy": "ALLOW_ALL"}},
                                "groups": conn([{"name": "CE-PORTAL"}])}]),
        }
        output = mod.report(data)
        self.assertNotIn("andrea@example.com", output)
        self.assertIn("PORTAS_MINIMAS_443=REVISAR", output)
        self.assertIn("ALTERACOES=NAO", output)

    def test_pagination_fails_closed(self):
        data = {"users": {**conn([]), "totalCount": 0},
                "resources": conn([])}
        data["users"]["pageInfo"]["hasNextPage"] = True
        with self.assertRaisesRegex(ValueError, "PAGINACAO_PENDENTE"):
            mod.report(data)


if __name__ == "__main__":
    unittest.main()
