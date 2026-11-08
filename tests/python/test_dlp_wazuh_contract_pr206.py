#!/usr/bin/env python3
"""PA-07/GA-06: contrato sintetico sanitizador -> regras DLP do Wazuh.

Nao instancia Wazuh, Docker, EP126 nem usa logs reais. A funcao match_rule
e um modelo restrito de regex/cadeia if_sid para estes eventos e NAO e
equivalente ao wazuh-logtest/engine PCRE2 em producao.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

REPO = Path(__file__).resolve().parents[2]
SANITIZER = REPO / "scripts/dlp/sanitizar_ferret.py"
RULESET = REPO / "deploy/interna/wazuh/config/rules/conectaeduca_dlp_rules.xml"
SPEC = importlib.util.spec_from_file_location("ga06_sanitizer_pr206", SANITIZER)
assert SPEC and SPEC.loader
san = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(san)
RULES = {r.attrib["id"]: r for r in ET.parse(RULESET).getroot().findall("rule")}
FILE_ID = "c" * 64
SECRET_SYNTHETIC = "GA06-FAKE-SECRET-TEST-ONLY"


def events_from_fixture(*, findings=None, stats=None):
    report = {"results": [] if findings is None else findings,
              "stats": {} if stats is None else stats}
    return san.build_events(report, FILE_ID, "object", True)


def models_rule_match(rule_id: str, event: dict, seen=frozenset()) -> bool:
    """Somente os campos decodificados usados pelas regras DLP deste PR."""
    if rule_id in seen:
        raise AssertionError("ciclo if_sid no XML")
    rule = RULES[rule_id]
    parent = rule.findtext("if_sid")
    if parent is not None:
        parents = parent.replace(",", " ").split()
        if not any(models_rule_match(p, event, seen | {rule_id}) for p in parents):
            return False
    if rule.findtext("decoded_as") not in (None, "json"):
        raise AssertionError("decoder inesperado")
    for field in rule.findall("field"):
        name = field.attrib["name"]
        if field.attrib.get("type") != "pcre2":
            raise AssertionError(f"regex nao PCRE2: {rule_id}/{name}")
        if name not in event or re.fullmatch(field.text or "", str(event[name])) is None:
            return False
    return True


class DLPWazuhContractOffline(unittest.TestCase):
    def test_rule_id_levels_hierarchy_and_no_full_log(self):
        expected = {
            "110100": "0", "110101": "0", "110102": "3", "110110": "6",
            "110111": "5", "110112": "8", "110113": "12"
        }
        for rid, level in expected.items():
            with self.subTest(rule_id=rid):
                self.assertIn(rid, RULES)
                self.assertEqual(RULES[rid].attrib.get("level"), level)
        for rid in ("110101", "110102", "110110", "110111", "110112", "110113"):
            self.assertEqual(RULES[rid].findtext("options"), "no_full_log")

    def test_confidence_level_case_is_preserved_and_rules_match(self):
        for label, rule_id in [
            ("LOW", "110111"), ("low", "110111"), ("Low", "110111"),
            ("MEDIUM", "110112"), ("medium", "110112"), ("Medium", "110112"),
            ("HIGH", "110113"), ("high", "110113"), ("High", "110113")
        ]:
            with self.subTest(label=label):
                finding = {
                    "type": "synthetic", "validator": "fixture", "confidence_level": label,
                    "confidence": 84, "line_number": 1,
                    "text": SECRET_SYNTHETIC, "filename": "/fake/input.txt",
                    "metadata": {"other_secret": SECRET_SYNTHETIC}
                }
                events = events_from_fixture(findings=[finding], stats={"total_findings": 1})
                self.assertEqual(events[1]["confidence_level"], label)
                self.assertTrue(models_rule_match("110100", events[1]))
                self.assertTrue(models_rule_match("110110", events[1]))
                matches = [rid for rid in ("110111", "110112", "110113")
                           if models_rule_match(rid, events[1])]
                self.assertEqual(matches, [rule_id])
                dumped = json.dumps(events, ensure_ascii=False)
                self.assertNotIn(SECRET_SYNTHETIC, dumped)
                self.assertNotIn("filename", dumped)

    def test_unknown_confidence_stays_on_fallback(self):
        for label in ("UNKNOWN", "MEDIUMx", "", "CRITICAL"):
            with self.subTest(label=label):
                event = events_from_fixture(findings=[
                    {"confidence_level": label}
                ])[1]
                self.assertTrue(models_rule_match("110110", event))
                self.assertFalse(any(models_rule_match(rid, event) for rid in
                                     ("110111", "110112", "110113")))

    def test_empty_stats_does_not_prove_clean_scan(self):
        event = events_from_fixture()[0]
        self.assertEqual(event["files_processed"], 0)
        self.assertEqual(event["emitted_findings"], 0)
        # stats_complete = integridade estrutural do JSON, NAO cobertura.
        self.assertTrue(event["stats_complete"])
        self.assertTrue(models_rule_match("110100", event))
        self.assertFalse(models_rule_match("110101", event))

    def test_zero_processed_does_not_prove_clean_scan(self):
        event = events_from_fixture(stats={"files_processed": 0, "files_skipped": 0})[0]
        self.assertFalse(models_rule_match("110101", event))

    def test_all_skipped_does_not_prove_clean_scan(self):
        event = events_from_fixture(stats={"files_processed": 0, "files_skipped": 3})[0]
        self.assertFalse(models_rule_match("110101", event))

    def test_partially_skipped_does_not_prove_clean_scan(self):
        event = events_from_fixture(stats={"files_processed": 1, "files_skipped": 2})[0]
        self.assertFalse(models_rule_match("110101", event))

    def test_positive_processed_zero_skipped_matches_narrow_quiet_rule(self):
        # Modela o novo contrato quando PR #206 e #207 sao combinados:
        # a versao antiga do sanitizador em main ainda nao emite esse campo.
        event = events_from_fixture(stats={
            "files_processed": 1, "files_skipped": 0,
            "total_findings": 0, "suppressed": 0,
        })[0]
        event["files_skipped_reported"] = "yes"
        event["total_findings_reported"] = "yes"
        event["suppressed_reported"] = "yes"
        self.assertTrue(models_rule_match("110101", event))
        # Ainda assim nao significa cobertura integral do scanner.
        self.assertNotIn("concluída", RULES["110101"].findtext("description", "").lower())
        self.assertNotIn("concluida", RULES["110101"].findtext("description", "").lower())

    def test_missing_skipped_field_cannot_satisfy_quiet_rule(self):
        # A versao antiga do sanitizador podia inferir skipped=0 por default.
        event = events_from_fixture(stats={"files_processed": 1})[0]
        self.assertEqual(event["files_skipped"], 0)
        self.assertFalse(models_rule_match("110101", event))
        # Indicador explicito negativo tambem nao autoriza quiet.
        event["files_skipped_reported"] = "no"
        self.assertFalse(models_rule_match("110101", event))

    def test_explicit_zero_requires_provenance_flag_for_quiet_rule(self):
        event = events_from_fixture(stats={
            "files_processed": 1, "files_skipped": 0,
            "total_findings": 0, "suppressed": 0,
        })[0]
        event.update({
            "total_findings_reported": "yes",
            "suppressed_reported": "yes",
        })
        event.pop("files_skipped_reported", None)
        self.assertFalse(models_rule_match("110101", event))
        for bad in ("no", "YES", "", "1"):
            with self.subTest(flag=bad):
                event["files_skipped_reported"] = bad
                self.assertFalse(models_rule_match("110101", event))
        event["files_skipped_reported"] = "yes"
        self.assertTrue(models_rule_match("110101", event))

    def test_summary_quiet_requires_explicit_zero_findings_and_suppressions(self):
        explicit = {
            "files_processed": 1, "files_skipped": 0,
            "total_findings": 0, "suppressed": 0,
        }
        event = events_from_fixture(stats=explicit)[0]
        event.update({
            "files_skipped_reported": "yes",
            "total_findings_reported": "yes",
            "suppressed_reported": "yes",
        })
        self.assertTrue(models_rule_match("110101", event))
        for field in ("total_findings_reported", "suppressed_reported"):
            with self.subTest(missing=field):
                partial = dict(event)
                partial.pop(field)
                self.assertFalse(models_rule_match("110101", partial))
                partial[field] = "no"
                self.assertFalse(models_rule_match("110101", partial))
        for counter in ("total_findings", "suppressed"):
            with self.subTest(nonzero=counter):
                inconsistent = dict(event)
                inconsistent[counter] = 2
                self.assertFalse(models_rule_match("110101", inconsistent))
        # Os defaults antigos nao justificam supressao silenciosa.
        inferred = events_from_fixture(stats={"files_processed": 1, "files_skipped": 0})[0]
        inferred["files_skipped_reported"] = "yes"
        self.assertFalse(models_rule_match("110101", inferred))

    def test_findings_summary_preserves_nonempty_classification(self):
        event = events_from_fixture(
            findings=[{"type": "synthetic", "confidence_level": "MEDIUM"}],
            stats={"files_processed": 1, "total_findings": 1}
        )[0]
        self.assertEqual(event["emitted_findings"], 1)
        self.assertFalse(models_rule_match("110101", event))
        self.assertTrue(models_rule_match("110102", event))

    def test_unrelated_event_does_not_match_dlp_rules(self):
        event = {"source": "other", "schema_version": "1",
                 "event_type": "dlp_finding", "confidence_level": "HIGH"}
        for rid in ("110100", "110110", "110113"):
            self.assertFalse(models_rule_match(rid, event))


if __name__ == "__main__":
    unittest.main()
