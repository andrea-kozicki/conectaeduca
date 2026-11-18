#!/usr/bin/env python3
"""Verifica, sem efeitos colaterais, o artefato PA-06/Wazuh V6 versionado."""

from __future__ import annotations

import hashlib
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACT = REPO_ROOT / "ops/pa06/artefatos/ce_pa06_wz05_80710.xml"
EXPECTED_SHA256 = "4da3e4fe32a151f058c6d646340e8fc8a410e7bcfd41124207830cfc7e691ecf"


def validate(content: bytes) -> None:
    if hashlib.sha256(content).hexdigest() != EXPECTED_SHA256:
        raise ValueError("PA06_V6_HASH_MISMATCH")

    try:
        root = ET.fromstring(content)
    except ET.ParseError as exc:
        raise ValueError("PA06_V6_XML_INVALID") from exc

    if root.tag != "group" or root.attrib != {"name": "audit,"}:
        raise ValueError("PA06_V6_GROUP_INVALID")

    rules = root.findall("rule")
    if len(rules) != 1 or len(root) != 1:
        raise ValueError("PA06_V6_RULE_COUNT_INVALID")

    rule = rules[0]
    if rule.attrib != {"id": "80710", "level": "10", "overwrite": "yes"}:
        raise ValueError("PA06_V6_RULE_ATTRS_INVALID")
    if rule.findtext("if_sid") != "80700":
        raise ValueError("PA06_V6_PARENT_INVALID")

    actual = {
        (node.get("name"), node.get("type"), node.text)
        for node in rule.findall("field")
    }
    expected = {
        ("audit.type", None, "ANOM_PROMISCUOUS"),
        ("audit.prom", "pcre2", "^256$"),
        ("audit.old_prom", "pcre2", "^0$"),
    }
    if len(rule.findall("field")) != 3 or actual != expected:
        raise ValueError("PA06_V6_FIELDS_INVALID")

    tags = [node.tag for node in rule]
    if tags != ["if_sid", "field", "field", "field", "description", "group"]:
        raise ValueError("PA06_V6_STRUCTURE_INVALID")


def main() -> int:
    if len(sys.argv) != 1:
        print("PA06_V6_ARGUMENTS_UNSUPPORTED", file=sys.stderr)
        return 2
    try:
        content = ARTIFACT.read_bytes()
        validate(content)
    except (OSError, ValueError) as exc:
        print(f"PA06_V6_INTEGRITY=FAIL reason={exc}", file=sys.stderr)
        return 1

    print("PA06_V6_INTEGRITY=PASS")
    print("PA06_V6_SHA256=" + EXPECTED_SHA256)
    print("PA06_V6_SCOPE=SOURCE_ONLY_NO_DEPLOY")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
