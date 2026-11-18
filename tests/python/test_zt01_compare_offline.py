#!/usr/bin/env python3
"""Synthetic offline regression tests. No VM, Twingate, HTTP or credentials."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "evidencias"))
import zt01_compare_offline as c  # noqa: E402


def synthetic(profile, host="synthetic-test-client", *, wazuh="TCP_REFUSED"):
    return {
        "schema": c.SCHEMA, "role": "client", "stage": "exploit",
        "pa": "PA-01", "gate": "OPEN", "hostname": host,
        "zt_profile": profile, "operator_identity_note": "DO_NOT_PUBLISH_SYNTHETIC",
        "results": [
            {"case": "ZT_RESOURCE_VISIBILITY", "status": "TCP_REFUSED", "detail": {"cookie": "PRIVATE"}},
            {"case": "ZT_PROFILE_APP", "status": "HTTP_OBSERVED", "detail": {"token": "PRIVATE"}},
            {"case": "ZT_PROFILE_WAZUH", "status": wazuh, "detail": {"ip": "PRIVATE"}},
        ],
    }


def save_private(parent, name, data):
    p = parent / name
    raw = json.dumps(data, ensure_ascii=True).encode("utf-8")
    p.write_bytes(raw)
    p.chmod(0o600)
    sidecar = Path(str(p) + ".sha256")
    sidecar.write_text(hashlib.sha256(raw).hexdigest() + "  " + p.name + "\n")
    sidecar.chmod(0o600)
    return p


class ZtOfflineContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.portal = synthetic("portal")
        self.soc = synthetic("soc")

    def store(self):
        return (save_private(self.folder, "portal.json", self.portal),
                save_private(self.folder, "soc.json", self.soc))

    def test_synthetic_comparison_does_not_prove_authorization_or_expose_raw(self):
        a, b = self.store()
        output = c.compare(c.load_verified_report(str(a)), c.load_verified_report(str(b)))
        self.assertTrue(output["no_automatic_pass"])
        self.assertTrue(output["identity_and_mfa_independent_proof_required"])
        self.assertTrue(output["tcp_reachability_is_not_rbac_allow"])
        self.assertNotIn("PRIVATE", repr(output))
        self.assertNotIn("DO_NOT_PUBLISH", repr(output))
        self.assertNotIn("hostname", repr(output))
        self.assertNotIn("synthetic-test-client", repr(output))

    def test_possible_unexpected_wazuh_reachability_is_not_pass(self):
        self.portal["results"][2]["status"] = "TCP_REACHABLE"
        out = c.compare(self.portal, self.soc)
        self.assertEqual(out["result"], "REVIEW_POSSIBLE_UNEXPECTED_REACHABILITY")
        self.assertTrue(out["no_automatic_pass"])

    def test_reject_cross_host(self):
        self.soc["hostname"] = "another-synthetic-client"
        with self.assertRaisesRegex(ValueError, "HOSTS_NOT_COMPARABLE"):
            c.compare(self.portal, self.soc)

    def test_reject_same_profile_and_missing_case(self):
        self.soc["zt_profile"] = "portal"
        with self.assertRaisesRegex(ValueError, "PROFILE_SCOPE_INVALID"):
            c.compare(self.portal, self.soc)
        self.soc["zt_profile"] = "soc"
        self.soc["results"].pop()
        with self.assertRaisesRegex(ValueError, "REQUIRED_CASES_MISSING"):
            c.compare(self.portal, self.soc)

    def test_reject_duplicate_case_and_bad_status(self):
        self.portal["results"].append(dict(self.portal["results"][0]))
        with self.assertRaisesRegex(ValueError, "DUPLICATE_CASE"):
            c.compare(self.portal, self.soc)
        self.portal["results"].pop()
        self.portal["results"][0]["status"] = "PASSWORD_LIKE_TOKEN"
        with self.assertRaisesRegex(ValueError, "STATUS_NOT_ALLOWED"):
            c.compare(self.portal, self.soc)

    def test_reject_gate_and_case_scope(self):
        self.portal["gate"] = "DRY_RUN"
        with self.assertRaisesRegex(ValueError, "PROFILE_SCOPE_INVALID"):
            c.compare(self.portal, self.soc)
        self.portal["gate"] = "OPEN"
        self.portal["results"][0]["pa"] = "PA-07"
        with self.assertRaisesRegex(ValueError, "CASE_SCOPE_INVALID"):
            c.compare(self.portal, self.soc)

    def test_hash_mismatch_fail_closed(self):
        a, _ = self.store()
        a.write_text("tampered")
        with self.assertRaisesRegex(ValueError, "SHA256_MISMATCH"):
            c.load_verified_report(str(a))

    def test_world_readable_file_rejected(self):
        a, _ = self.store()
        a.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "FILE_NOT_PRIVATE"):
            c.load_verified_report(str(a))

    def test_world_readable_sidecar_rejected(self):
        a, _ = self.store()
        Path(str(a) + ".sha256").chmod(0o644)
        with self.assertRaisesRegex(ValueError, "FILE_NOT_PRIVATE"):
            c.load_verified_report(str(a))

    def test_symlink_destination_rejected(self):
        a, _ = self.store()
        link = self.folder / "alias.json"
        link.symlink_to(a)
        with self.assertRaises(OSError):
            c.load_verified_report(str(link))

    def test_public_parent_rejected(self):
        a, _ = self.store()
        self.folder.chmod(0o755)
        self.addCleanup(lambda: self.folder.chmod(0o700))
        with self.assertRaisesRegex(ValueError, "PARENT_NOT_PRIVATE"):
            c.load_verified_report(str(a))

    def test_reject_oversized_report(self):
        a, _ = self.store()
        a.write_bytes(b"x" * (c.MAX_REPORT_BYTES + 1))
        with self.assertRaisesRegex(ValueError, "FILE_NOT_PRIVATE"):
            c.load_verified_report(str(a))

    def test_reject_duplicate_json_keys(self):
        p = self.folder / "duplicate.json"
        raw = b'{"schema":"first","schema":"second"}'
        p.write_bytes(raw)
        p.chmod(0o600)
        s = Path(str(p) + ".sha256")
        s.write_text(hashlib.sha256(raw).hexdigest() + "\n")
        s.chmod(0o600)
        with self.assertRaisesRegex(ValueError, "DUPLICATE_JSON_KEY"):
            c.load_verified_report(str(p))

    def test_cli_prints_only_sanitized_comparison(self):
        a, b = self.store()
        proc = subprocess.run(
            [sys.executable, str(ROOT / "scripts/evidencias/zt01_compare_offline.py"),
             "--portal-report", str(a), "--soc-report", str(b)],
            capture_output=True, text=True, timeout=8,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        output = json.loads(proc.stdout)
        self.assertTrue(output["no_automatic_pass"])
        self.assertNotIn("PRIVATE", proc.stdout)
        self.assertNotIn(str(self.folder), proc.stdout)

    def test_no_network_imports_in_comparator(self):
        code = (ROOT / "scripts/evidencias/zt01_compare_offline.py").read_text()
        for word in ("import socket", "import http", "import urllib", "import requests",
                     "import subprocess", "docker compose", "twingate start"):
            self.assertNotIn(word, code)


if __name__ == "__main__":
    unittest.main()
