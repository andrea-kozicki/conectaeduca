#!/usr/bin/env python3
"""GA-07 / PA-06: contrato estatico de persistencia e Wazuh da auditoria PHP.

Sem VM, Docker, logrotate, Wazuh Manager, dados de usuarios ou eventos reais.
Nao comprova leitura depois de rotacao, inode, ACL ou retencao institucional.
"""
from __future__ import annotations

from pathlib import Path
import re
import unittest
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
OVERLAY = ROOT / "deploy/dmz/compose.audit-persistent.yml"
GROUP = ROOT / "deploy/interna/wazuh/groups/conectaeduca-dmz/agent.conf"
EXAMPLE = ROOT / "deploy/interna/wazuh/agent/conectaeduca-php-audit-localfile.xml.example"
RULES = ROOT / "deploy/interna/wazuh/rules/zz_conectaeduca_php_audit_rules.xml"
LOG_PATH = "/var/log/conectaeduca/php-audit/audit.log"
LOG_DIR = "/var/log/conectaeduca/php-audit"


class GA07AuditContractOffline(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.overlay = OVERLAY.read_text(encoding="utf-8")
        cls.group = ET.parse(GROUP).getroot()
        cls.example = ET.parse(EXAMPLE).getroot()
        cls.rules = {
            node.attrib["id"]: node for node in ET.parse(RULES).getroot().findall("rule")
        }

    def test_compose_bind_is_explicit_not_auto_created(self):
        self.assertIn("source: " + LOG_DIR, self.overlay)
        self.assertIn("target: /var/www/conectaeduca/storage/logs", self.overlay)
        self.assertIn("create_host_path: false", self.overlay)

    def test_overlay_keeps_private_keys_and_tmpfs_without_log_tmpfs(self):
        self.assertIn("tmpfs: !override", self.overlay)
        self.assertRegex(self.overlay, r"/tmp:rw,nosuid,nodev,noexec")
        self.assertIn("/var/www/conectaeduca/storage/keys:rw,nosuid,nodev,noexec", self.overlay)
        self.assertNotRegex(self.overlay, r"(?m)^\s*-\s*/var/www/conectaeduca/storage/logs:")

    def test_audit_bind_is_writable_only_where_required(self):
        self.assertRegex(self.overlay, r"(?m)^\s+read_only:\s+false\s*$")
        self.assertNotIn("privileged: true", self.overlay)
        self.assertNotIn("chmod 777", self.overlay)

    def test_group_agent_conf_collects_log_exactly_once(self):
        collectors = self.group.findall(".//localfile")
        matches = [
            entry for entry in collectors if entry.findtext("location") == LOG_PATH
        ]
        self.assertEqual(len(matches), 1, "agente deve ter um unico coletor para audit.log")
        self.assertEqual(matches[0].findtext("log_format"), "json")

    def test_example_collector_uses_same_path_and_json(self):
        self.assertEqual(self.example.tag, "localfile")
        self.assertEqual(self.example.findtext("location"), LOG_PATH)
        self.assertEqual(self.example.findtext("log_format"), "json")

    def test_rules_identifiers_and_severities_preserved(self):
        self.assertEqual(set(self.rules), {"110250", "110251", "110252"})
        for rid, level in {"110250": "3", "110251": "5", "110252": "7"}.items():
            with self.subTest(rule_id=rid):
                self.assertEqual(self.rules[rid].attrib["level"], level)

    def test_rules_require_json_decoder_and_correct_location(self):
        for rid, rule in self.rules.items():
            with self.subTest(rule_id=rid):
                self.assertEqual(rule.findtext("decoded_as"), "json")
                location = rule.find("location")
                self.assertIsNotNone(location)
                self.assertEqual(location.attrib["type"], "pcre2")
                self.assertRegex(LOG_PATH, location.text or "")

    def test_rules_minimize_full_logs(self):
        for rid, rule in self.rules.items():
            with self.subTest(rule_id=rid):
                self.assertEqual(rule.findtext("options"), "no_full_log")
        # Esta opcao NAO remove todos os campos decodificados do evento.
        # A politica de privacidade e retencao continua pendente.

    def test_synthetic_marker_is_not_normal_user_login(self):
        marker = self.rules["110250"].find("field")
        self.assertIsNotNone(marker)
        self.assertEqual(marker.attrib["name"], "event")
        self.assertEqual(marker.attrib["type"], "pcre2")
        self.assertEqual(marker.text, "^wazuh_php_audit_e2e_probe$")

    def test_login_failed_and_forbidden_rules_are_disjoint(self):
        login = self.rules["110251"].find("field")
        deny = self.rules["110252"].find("field")
        self.assertIsNotNone(login)
        self.assertIsNotNone(deny)
        self.assertEqual(login.text, "^login_failed$")
        self.assertEqual(deny.text, "^(?:forbidden_access_attempt|unauthorized_access_attempt)$")
        self.assertIsNone(re.fullmatch(login.text, "forbidden_access_attempt"))
        self.assertIsNone(re.fullmatch(deny.text, "login_failed"))

    def test_group_collector_does_not_disable_security_agent(self):
        syscheck = self.group.find("syscheck")
        self.assertIsNotNone(syscheck)
        self.assertEqual(syscheck.findtext("disabled"), "no")
        self.assertIn(LOG_PATH, [
            node.findtext("location") for node in self.group.findall(".//localfile")
        ])


if __name__ == "__main__":
    unittest.main()
