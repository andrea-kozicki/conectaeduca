#!/usr/bin/env python3
"""Publication readiness guards: read-only, selected files only; no network."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "docs/operacao/CE-ACADEMIC-PUBLICATION-GATES-20261118.json"
SENSITIVE_PATTERNS = {
    "private_key": re.compile(r"-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----"),
    "private_ipv4": re.compile(r"\b(?:10\.(?:\d{1,3}\.){2}\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b"),
    "email": re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
    "home": re.compile(r"/home/[A-Za-z0-9._-]+/"),
}


def categories(payload: str) -> set[str]:
    """Never return original matched values; only pattern categories."""
    return {name for name, pattern in SENSITIVE_PATTERNS.items() if pattern.search(payload)}


class PublicationPrivacyReadinessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))

    def test_pending_owner_approval_is_explicit(self):
        m = self.manifest
        self.assertEqual(m["schema"], "CE-ACADEMIC-PUBLICATION-GATE-1")
        self.assertEqual(m["publication_status"], "BLOCKED_PENDING_APPROVAL")
        self.assertFalse(m["automatic_tag_or_release"])
        self.assertTrue(m["source_only"])
        self.assertFalse(m["any_vm_gate_closed"])
        self.assertEqual(len(m["checks"]), 6)
        self.assertEqual(len({x["id"] for x in m["checks"]}), 6)
        self.assertTrue(all(x["status"].startswith("PENDING_") for x in m["checks"]))

    def test_citation_does_not_silently_grant_a_license(self):
        composer = json.loads((ROOT / "composer.json").read_text(encoding="utf-8"))
        self.assertEqual(composer.get("license"), "proprietary")
        self.assertFalse((ROOT / "LICENSE").exists())
        self.assertEqual(self.manifest["license"]["root_license_file"], "ABSENT")
        self.assertEqual(self.manifest["license"]["composer_declared"], "proprietary")
        self.assertTrue(self.manifest["license"]["citation_is_not_license"])
        self.assertTrue((ROOT / "CITATION.cff").is_file())

    def test_gitleaks_history_gate_is_preserved(self):
        workflow = (ROOT / ".github/workflows/gitleaks.yml").read_text(encoding="utf-8")
        self.assertIn("fetch-depth: 0", workflow)
        self.assertIn("scripts/evidencias/checkpoint_gitleaks.sh", workflow)
        config = (ROOT / ".gitleaks.toml").read_text(encoding="utf-8")
        self.assertIn("useDefault = true", config)

    def test_public_doc_snapshot_selected_only(self):
        names = self.manifest["public_documents_checked"]
        self.assertGreaterEqual(len(names), 7)
        for name in names:
            with self.subTest(document=name):
                relative = Path(name)
                self.assertFalse(relative.is_absolute())
                self.assertNotIn("..", relative.parts)
                source = ROOT / relative
                self.assertTrue(source.is_file())
                self.assertEqual(categories(source.read_text(encoding="utf-8")), set(),
                                 "Review selected public file; do not print sensitive match")

    def test_synthetic_patterns_detect_without_leaking_values(self):
        examples = {
            "private_key": "-----BEGIN PRIVATE KEY-----\nSYNTHETIC_NOT_REAL\n",
            "private_ipv4": "host=192.168.22.33",
            "email": "person@example.invalid",
            "home": "somewhere /home/test-user/sensitive",
        }
        for tag, payload in examples.items():
            with self.subTest(tag=tag):
                result = categories(payload)
                self.assertIn(tag, result)
                self.assertNotIn(payload, repr(result))

    def test_evidence_gitignore_exceptions_are_reviewed_not_removed(self):
        ignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
        self.assertIn("/docs/evidencias/*", ignore)
        self.assertIn("!/docs/evidencias/*.md", ignore)
        self.assertIn("!/docs/evidencias/*.txt", ignore)
        self.assertIn("CE-PUB-CONTEXT", {x["id"] for x in self.manifest["checks"]})

    def test_release_candidate_stays_unpublished(self):
        release = (ROOT / "docs/release/RELEASE-ACADEMICO-CANDIDATO-2026-11-18.md").read_text(encoding="utf-8")
        self.assertIn("não publicado como release final", release.lower())
        self.assertIn("PENDENTE", release)
        self.assertIn("PENDING_FINAL_SHA", {x["status"] for x in self.manifest["checks"]})


if __name__ == "__main__":
    unittest.main()
