"""Testes offline do CE-ZT26; não acessam o tenant nem o Docker."""
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FILE = ROOT / "scripts" / "twingate" / "ce_twingate_reconcile.py"
spec = importlib.util.spec_from_file_location("ce_twingate_reconcile", FILE)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

def collection(items):
    return {"pageInfo": {"hasNextPage": False},
            "edges": [{"node": item} for item in items]}

def baseline():
    return {
        "remoteNetworks": collection([
            {"name": name, "isActive": True} for name in mod.EXPECTED_NETWORKS
        ]),
        "groups": collection([
            {"name": name, "isActive": True} for name in mod.EXPECTED_GROUPS
        ]),
        "connectors": collection([
            {"name": name, "state": "ALIVE", "lastHeartbeatAt": "2026-11-05T00:00:00+00:00",
             "remoteNetwork": {"name": network}}
            for name, network in mod.EXPECTED_CONNECTORS.items()
        ]),
        "resources": collection([
            {"name": name, "isActive": True,
             "remoteNetwork": {"name": desired["network"]},
             "securityPolicy": {"name": desired["policy"]},
             "groups": collection([{"name": group} for group in desired["groups"]])}
            for name, desired in mod.EXPECTED_RESOURCES.items()
        ]),
    }

class TestTwingateReconcile(unittest.TestCase):
    def test_baseline(self):
        self.assertEqual({"OK"}, {f["status"] for f in mod.audit(baseline())})

    def test_connector_offline_is_not_resource_drift(self):
        data = baseline()
        data["connectors"]["edges"][0]["node"]["state"] = "DEAD_HEARTBEAT_TOO_OLD"
        findings = mod.audit(data)
        self.assertIn("BLOQUEADO", {f["status"] for f in findings})
        self.assertFalse(any(f["tipo"] == "RECURSO" and f["status"] != "OK" for f in findings))

    def test_extra_group_flagged_not_removed(self):
        data = baseline()
        data["resources"]["edges"][0]["node"]["groups"]["edges"].append(
            {"node": {"name": "Everyone"}})
        findings = mod.audit(data)
        self.assertTrue(any(f["tipo"] == "RECURSO" and f["status"] == "REVISAR"
                            for f in findings))

    def test_pagination_fails_closed(self):
        data = baseline()
        data["connectors"]["pageInfo"]["hasNextPage"] = True
        with self.assertRaisesRegex(ValueError, "PAGINACAO_PENDENTE"):
            mod.audit(data)

    def test_missing_group(self):
        data = baseline()
        data["groups"]["edges"] = []
        self.assertTrue(any(f["tipo"] == "GRUPO" and f["status"] == "REVISAR"
                            for f in mod.audit(data)))

    def test_deploy_guard_exists(self):
        shell = (ROOT / "scripts/twingate/ce_twingate_dmz_preflight_deploy.sh").read_text()
        guard = shell.index("DEPLOY_BLOQUEADO=CONNECTOR_JA_EXISTE")
        deploy = shell.index("docker compose -f \"$COMPOSE\" up -d --no-build")
        self.assertLess(guard, deploy)

if __name__ == "__main__":
    unittest.main()
