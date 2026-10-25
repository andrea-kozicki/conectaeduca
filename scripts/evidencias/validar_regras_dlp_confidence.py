#!/usr/bin/env python3
"""Gate estático do ruleset Ferret/Wazuh. Não substitui wazuh-logtest no Manager."""
from __future__ import annotations

from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
RULES = ROOT / "deploy/interna/wazuh/config/rules/conectaeduca_dlp_rules.xml"

EXPECTED = {
    "low": ("110111", "5"),
    "medium": ("110112", "8"),
    "high": ("110113", "12"),
}

def check(ok: bool, message: str) -> None:
    if not ok:
        raise AssertionError(message)

def main() -> int:
    root = ET.parse(RULES).getroot()
    check(root.tag == "group", "Raiz de regras inesperada")
    rules = {}
    for rule in root.findall("rule"):
        rid = rule.get("id")
        check(bool(rid) and rid not in rules, "ID de regra ausente/duplicado")
        rules[rid] = rule
    fallback = rules.get("110110")
    check(fallback is not None and fallback.get("level") == "6", "Fallback DLP divergente")
    check(fallback.findtext("if_sid") == "110100", "Hierarquia do fallback divergente")
    check(fallback.findtext("event_type") is None, "Event type deve permanecer em field")
    check(any(el.get("name") == "event_type" and el.text == "^dlp_finding$"
              for el in fallback.findall("field")), "Fallback sem dlp_finding")
    check(fallback.findtext("options") == "no_full_log", "Fallback nao minimiza full_log")

    test_count = 0
    for confidence, (rid, level) in EXPECTED.items():
        rule = rules.get(rid)
        check(rule is not None, f"Regra {rid} ausente")
        check(rule.get("level") == level, f"Nivel {rid} alterado")
        check(rule.findtext("if_sid") == "110110", f"Regra {rid} sem fallback")
        check(rule.findtext("options") == "no_full_log", f"Regra {rid} sem no_full_log")
        fields = [x for x in rule.findall("field") if x.get("name") == "confidence_level"]
        check(len(fields) == 1, f"Regra {rid}: confidence_level ambiguo")
        check(fields[0].get("type") == "pcre2", f"Regra {rid}: PCRE2 ausente")
        pattern = fields[0].text or ""
        check(pattern == f"(?i)^{confidence}$", f"Regra {rid}: regex inesperada")
        for value in [confidence, confidence.upper(), confidence.title(), " " + confidence,
                      confidence + "x", "", "UNKNOWN"]:
            expected = value.lower() == confidence
            matched = re.fullmatch(pattern, value) is not None
            check(matched == expected, f"Regra {rid}: variante {value!r}")
            test_count += 1
    check("110100" in rules, "Regra base ausente")
    print(f"DLP_CONFIDENCE_STATIC=PASS rules=3 cases={test_count} fallback=110110")
    print("NOTA=wazuh-logtest e runtime Manager ainda precisam de verificacao autorizada")
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, ET.ParseError, OSError) as exc:
        print(f"DLP_CONFIDENCE_STATIC=FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
