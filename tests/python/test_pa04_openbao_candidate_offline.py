#!/usr/bin/env python3
"""OpenBao least-privilege policy candidate: stdlib-only, no network or VM."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
FILE = ROOT / "docs/release/pa04-openbao-candidate/approle-policy.candidate.json"
EXPECTED_SHA = "923d264313c103da14e2ae3ca9c989c1a00c3414"
EXACT_PATH = "ce-app/data/runtime/app"
POLICY_NAME = "ce-app-runtime-read-v1"


def validate(data: dict) -> None:
    if data.get("schema") != "CE-PA04-OPENBAO-SOURCE-CANDIDATE-1":
        raise ValueError("SCHEMA_MISMATCH")
    if data.get("status") != "NOT_DEPLOYABLE_DOC_ONLY":
        raise ValueError("OPERATING_MODE_NOT_OFFLINE")
    if data.get("source_pr") != 228 or data.get("source_blob_sha") != EXPECTED_SHA:
        raise ValueError("PROVENANCE_INVALID")
    if data.get("kv_v2_mount") != "ce-app/" or data.get("approle_auth_mount") != "ce-approle/":
        raise ValueError("MOUNT_NAMESPACE_INVALID")
    if data.get("exact_secret_path") != EXACT_PATH or data.get("policy_name") != POLICY_NAME:
        raise ValueError("SCOPE_INVALID")
    if data.get("role_name") != "ce-app-runtime-read":
        raise ValueError("ROLE_NAME_INVALID")
    expected_hcl = 'path "' + EXACT_PATH + '" {\n  capabilities = ["read"]\n}\n'
    if data.get("policy_hcl") != expected_hcl:
        raise ValueError("ACL_NOT_EXACT_READ_ONLY")
    expected_role = {
        "bind_secret_id": True,
        "secret_id_num_uses": 1,
        "secret_id_ttl": "10m",
        "token_policies": [POLICY_NAME],
        "token_no_default_policy": True,
        "token_ttl": "15m",
        "token_max_ttl": "1h",
        "token_type": "service",
    }
    if data.get("role_config") != expected_role:
        raise ValueError("ROLE_CAPABILITIES_DIVERGED")
    if not isinstance(data.get("limitations"), list) or len(data["limitations"]) < 3:
        raise ValueError("MISSING_RUNTIME_LIMITATIONS")
    for bad_key in ("role_id", "secret_id", "token_value", "admin_token", "unseal_share"):
        if bad_key in data or bad_key in data["role_config"]:
            raise ValueError("LIVE_CREDENTIAL_NOT_ALLOWED")


class AppRoleCandidateOfflineTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads(FILE.read_text(encoding="utf-8"))

    def test_baseline_contract(self):
        validate(self.data)

    def test_exact_acl_only_read_one_path(self):
        policy = self.data["policy_hcl"]
        self.assertEqual(policy.count("path "), 1)
        self.assertEqual(re.findall(r'capabilities\s*=\s*\[(.*?)\]', policy), ['"read"'])
        self.assertNotIn("*", policy)
        self.assertEqual(self.data["exact_secret_path"], EXACT_PATH)

    def test_reject_added_write_privilege(self):
        unsafe = copy.deepcopy(self.data)
        unsafe["policy_hcl"] = unsafe["policy_hcl"].replace('["read"]', '["read", "update"]')
        with self.assertRaisesRegex(ValueError, "ACL_NOT_EXACT_READ_ONLY"):
            validate(unsafe)

    def test_secret_id_single_use_and_no_default(self):
        role = self.data["role_config"]
        self.assertTrue(role["bind_secret_id"])
        self.assertEqual(role["secret_id_num_uses"], 1)
        self.assertTrue(role["token_no_default_policy"])
        self.assertEqual(role["token_policies"], [POLICY_NAME])
        self.assertEqual(role["secret_id_ttl"], "10m")
        self.assertEqual(role["token_ttl"], "15m")
        self.assertEqual(role["token_max_ttl"], "1h")

    def test_reject_unbounded_or_default_policy(self):
        for key, val in (("bind_secret_id", False), ("secret_id_num_uses", 0),
                         ("token_no_default_policy", False), ("token_max_ttl", "24h")):
            with self.subTest(key=key):
                item = copy.deepcopy(self.data)
                item["role_config"][key] = val
                with self.assertRaisesRegex(ValueError, "ROLE_CAPABILITIES_DIVERGED"):
                    validate(item)

    def test_reject_live_secrets_or_scope_widening(self):
        for key, value in (("secret_id", "DO_NOT_STORE"), ("admin_token", "DO_NOT_STORE")):
            with self.subTest(key=key):
                item = copy.deepcopy(self.data)
                item[key] = value
                with self.assertRaisesRegex(ValueError, "LIVE_CREDENTIAL_NOT_ALLOWED"):
                    validate(item)
        item = copy.deepcopy(self.data)
        item["exact_secret_path"] = "ce-app/data/*"
        with self.assertRaisesRegex(ValueError, "SCOPE_INVALID"):
            validate(item)

    def test_documentation_only_not_runtime_configuration(self):
        self.assertTrue(str(FILE.relative_to(ROOT)).startswith("docs/release/"))
        self.assertTrue(FILE.name.endswith(".candidate.json"))
        self.assertEqual(self.data["status"], "NOT_DEPLOYABLE_DOC_ONLY")
        self.assertNotIn("http", FILE.read_text(encoding="utf-8"))
        self.assertNotIn("password", FILE.read_text(encoding="utf-8").lower())

    def test_source_provenance_and_no_pretend_execution(self):
        self.assertEqual(self.data["source_pr"], 228)
        self.assertEqual(self.data["source_blob_sha"], EXPECTED_SHA)
        text = json.dumps(self.data)
        self.assertIn("No RoleID, SecretID", text)
        self.assertNotIn("CE-PA04-ACL01_CONCLUIDO", text)


if __name__ == "__main__":
    unittest.main()
