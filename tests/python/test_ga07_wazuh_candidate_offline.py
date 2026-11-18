#!/usr/bin/env python3
"""PA-06 GA-07: offline contract of non-installable Wazuh candidate sources.

Parses only committed documentation fixtures. No Wazuh, logcollector, VM or
 institutional event/log is contacted or modified.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import unittest
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
CANDIDATES = ROOT / "docs/release/ga07-wazuh-candidates"
RULES = CANDIDATES / "rules.xml.candidate.txt"
COLLECTOR = CANDIDATES / "localfile.xml.candidate.txt"
EXPECTED = {
    RULES: "e22c1724fb42f6fb50ec9f9003314fd5000a8de0",
    COLLECTOR: "13326f2f421bbb3f3a12612b1c9251792da0028b",
}
LOG_PATH = "/var/log/conectaeduca/php-audit/audit.log"
IDS = {"110250": "3", "110251": "5", "110252": "7"}


def git_blob_sha(content: bytes) -> str:
    header = b"blob " + str(len(content)).encode("ascii") + b"\0"
    return hashlib.sha1(header + content).hexdigest()


class GA07WazuhCandidateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = ET.fromstring(RULES.read_bytes())
        cls.rules = {x.attrib["id"]: x for x in cls.root.findall("rule")}
        cls.collector = ET.fromstring(COLLECTOR.read_bytes())

    def test_historical_blob_provenance_unchanged(self):
        for path, sha in EXPECTED.items():
            with self.subTest(source=path.name):
                self.assertEqual(git_blob_sha(path.read_bytes()), sha)

    def test_candidates_are_documentation_not_active_xml(self):
        self.assertTrue(all(str(p.relative_to(ROOT)).startswith("docs/release/") for p in EXPECTED))
        self.assertTrue(all(p.name.endswith(".candidate.txt") for p in EXPECTED))
        self.assertFalse((ROOT / "deploy/interna/wazuh/rules/zz_conectaeduca_php_audit_rules.xml").exists())

    def test_ruleset_has_expected_ids_levels_and_json_decoder(self):
        self.assertEqual(set(self.rules), set(IDS))
        for ident, level in IDS.items():
            with self.subTest(rule=ident):
                rule = self.rules[ident]
                self.assertEqual(rule.attrib["level"], level)
                self.assertEqual(rule.findtext("decoded_as"), "json")
                self.assertEqual(rule.findtext("options"), "no_full_log")
                self.assertEqual(rule.find("location").attrib.get("type"), "pcre2")
                self.assertRegex(LOG_PATH, rule.findtext("location") or "")
                self.assertEqual(len(rule.findall("field")), 1)
                self.assertEqual(rule.find("field").attrib.get("type"), "pcre2")

    def test_markers_and_event_types_are_disjoint(self):
        cases = {
            "110250": ("wazuh_php_audit_e2e_probe",),
            "110251": ("login_failed",),
            "110252": ("forbidden_access_attempt", "unauthorized_access_attempt"),
        }
        for ident, events in cases.items():
            expr = self.rules[ident].findtext("field") or ""
            self.assertEqual(self.rules[ident].find("field").attrib["name"], "event")
            for event in events:
                self.assertIsNotNone(re.fullmatch(expr, event))
            for other in [e for key, es in cases.items() if key != ident for e in es]:
                self.assertIsNone(re.fullmatch(expr, other))
        # Python re on synthetic events is only a source check, not Wazuh PCRE2/logtest.

    def test_standalone_collector_has_exact_one_json_log_path(self):
        self.assertEqual(self.collector.tag, "localfile")
        self.assertEqual(self.collector.findtext("location"), LOG_PATH)
        self.assertEqual(self.collector.findtext("log_format"), "json")
        self.assertEqual(len(list(self.collector)), 2)

    def test_candidate_ids_not_already_defined_in_deploy_xml(self):
        # Fail closed on known collisions in versioned XML; runtime may still differ.
        active_root = ROOT / "deploy/interna/wazuh"
        if not active_root.exists():
            self.fail("WAZUH_SOURCE_TREE_MISSING")
        defined = []
        for path in active_root.rglob("*.xml"):
            src = path.read_text(encoding="utf-8", errors="replace")
            for id_ in IDS:
                if re.search(r'<rule\s+id=["\x27]' + id_ + r'["\x27]', src):
                    defined.append((str(path.relative_to(ROOT)), id_))
        self.assertEqual(defined, [], "Source has an overlapping Wazuh rule ID")

    def test_no_real_log_or_service_executed(self):
        # No call to a Wazuh executable. Check only synthetic source bytes.
        payload = RULES.read_text(encoding="utf-8") + COLLECTOR.read_text(encoding="utf-8")
        self.assertIn("CANDIDATA, NAO IMPLANTADA", payload)
        self.assertIn("NAO configuracao ativa", payload)
        self.assertNotIn("-----BEGIN PRIVATE KEY-----", payload)
        self.assertNotIn("secret_id=", payload.lower())


if __name__ == "__main__":
    unittest.main()
