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

    # PA-07 DLP-O08: zero findings nao implica cobertura comprovada.
    # A regra silenciosa 110101 so deve existir no subconjunto conservador:
    # processamento positivo, sem arquivo explicitamente ignorado.
    quiet = rules.get("110101")
    check(quiet is not None and quiet.get("level") == "0", "Regra 110101 ausente/alterada")
    check(quiet.findtext("if_sid") == "110100", "Regra 110101 sem pai")
    check(quiet.findtext("options") == "no_full_log", "Regra 110101 sem minimizacao")
    quiet_fields = {element.get("name"): element.text
                    for element in quiet.findall("field")}
    check(quiet_fields.get("event_type") == "^dlp_scan_summary$",
          "Regra 110101 deve ser somente scan summary")
    check(quiet_fields.get("emitted_findings") == "^0$",
          "Regra 110101 deve exigir zero findings emitidos")
    check(quiet_fields.get("files_processed") == "^[1-9][0-9]*$",
          "Regra 110101 nao comprova processamento positivo")
    check(quiet_fields.get("files_skipped") == "^0$",
          "Regra 110101 deve rejeitar itens ignorados")
    check(quiet_fields.get("files_skipped_reported") == "^yes$",
          "Regra 110101 deve exigir campo skipped explicitamente informado")
    check(all(el.get("type") == "pcre2" for el in quiet.findall("field")),
          "Regra 110101 exige PCRE2 nos campos")
    check("concluíd" not in (quiet.findtext("description") or "").lower(),
          "Descricao da regra 110101 nao deve alegar cobertura integral")
    print(f"DLP_CONFIDENCE_STATIC=PASS rules=3 cases={test_count} fallback=110110")
    print("DLP_COVERAGE_STATIC=PASS quiet_rule=110101 requires processed>0/skipped=0/skipped_reported=yes")
    print("NOTA=wazuh-logtest e runtime Manager ainda precisam de verificacao autorizada")
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, ET.ParseError, OSError) as exc:
        print(f"DLP_CONFIDENCE_STATIC=FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
