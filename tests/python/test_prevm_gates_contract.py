#!/usr/bin/env python3
"""Pre-VM readiness manifest: source success never becomes runtime PASS."""
import json
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
FILE = ROOT / "docs/operacao/CE-PREVM-GATES-20261118.json"


class PreVmGatesContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.raw = FILE.read_text(encoding="utf-8")
        cls.data = json.loads(cls.raw)

    def test_schema_and_unique_gates(self):
        m = self.data
        self.assertEqual(m["schema"], "CE-PREVM-GATES-1")
        self.assertEqual(m["repository"], "andrea-kozicki/conectaeduca")
        self.assertGreaterEqual(len(m["vm_gates"]), 10)
        self.assertGreaterEqual(len(m["documentation_gates"]), 2)
        ids = [x["id"] for x in m["vm_gates"] + m["documentation_gates"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(all(re.fullmatch(r"CE-[A-Z0-9-]{6,64}", x) for x in ids))

    def test_no_runtime_gate_misrepresented_as_pass(self):
        for gate in self.data["vm_gates"]:
            with self.subTest(gate=gate["id"]):
                self.assertEqual(gate["status"], "PENDING_VM")
                self.assertTrue(gate["requires_institutional_approval"])
                self.assertIn(gate["asset"], {"EP125", "EP126", "openSUSE"})
                self.assertIn(gate["priority"], {"P0", "P1", "P2"})
                self.assertTrue(gate["related_prs"])
                self.assertTrue(gate["required_evidence"])
                self.assertTrue(gate["stop_if"])

    def test_documentation_requires_human_review(self):
        self.assertTrue(all(x["status"] == "PENDING_DOC_REVIEW"
                            for x in self.data["documentation_gates"]))
        self.assertTrue(all(x["decision"] for x in self.data["documentation_gates"]))

    def test_source_merges_are_valid_git_ancestors_not_runtime_proof(self):
        self.assertIn("never runtime proof", self.data["source_status_means"])
        for item in self.data["verified_source_merges"]:
            with self.subTest(pr=item["pr"]):
                self.assertRegex(item["commit"], r"^[a-f0-9]{40}$")
                proc = subprocess.run(
                    ["git", "-C", str(ROOT), "merge-base", "--is-ancestor", item["commit"], "HEAD"],
                    capture_output=True, timeout=12, check=False,
                )
                self.assertEqual(proc.returncode, 0, f"Source PR #{item['pr']} not in main ancestry")

    def test_no_runtime_contact_or_automatic_deploy_claimed(self):
        p = self.data["policy"]
        self.assertTrue(p["no_vm_contact_in_this_round"])
        self.assertTrue(p["no_dockerfile_change"])
        self.assertTrue(p["no_automatic_deploy"])
        self.assertTrue(p["all_vm_gates_must_be_rechecked_before_executing"])
        self.assertNotIn("PENDING_VM\": false", self.raw)
        self.assertNotIn("PASSWORD=", self.raw)
        self.assertNotIn("SECRET_ID=", self.raw)
        self.assertNotIn("PRIVATE KEY", self.raw)


if __name__ == "__main__":
    unittest.main()
