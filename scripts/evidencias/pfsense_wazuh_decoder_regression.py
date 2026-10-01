#!/usr/bin/env python3
"""Regressão estática do decoder pfSense/Wazuh para syslog com PRI.

O gate cobre a causa reproduzida em 30/09/2026:
- o formato real "<PRI>... filterlog[PID]: ..." não deve ficar sem decoder próprio;
- o decoder/rule customizados precisam permanecer montados no Manager;
- o decoder/ruleset FreePBX padrão, que captura esse formato como falso positivo,
  deve ser excluído em conjunto nesta topologia (ConectaEduca não executa FreePBX);
- a amostra controlada deve extrair os campos usados pela regra 110620.

Este teste não substitui wazuh-analysisd -t / wazuh-logtest na VM.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
DECODER = ROOT / "deploy/interna/wazuh/config/decoders/conectaeduca_pfsense_pri_decoders.xml"
RULE = ROOT / "deploy/interna/wazuh/config/rules/conectaeduca_pfsense_rules.xml"
CONF = ROOT / "deploy/interna/wazuh/config/wazuh_cluster/wazuh_manager.conf"
COMPOSE = ROOT / "deploy/interna/wazuh/compose.yml"

SAMPLE = (
    "<134>Sep 30 15:07:06 filterlog[14325]: "
    "61,,,1787965966,hn1,match,block,in,4,0x0,,64,55068,0,DF,6,tcp,60,"
    "192.168.6.34,192.168.6.50,60162,62173,0,S,788863052,,64240,,"
    "mss;sackOK;TS;nop;wscale"
)

PREMATCH = re.compile(r"filterlog\[\d+\]:\s+")
FIELDS = re.compile(
    r"^(?:[^,]*,){3}([^,]*),(?:[^,]*,){2}([^,]*),"
    r"(?:[^,]*,){9}([^,]*),[^,]*,([^,]*),([^,]*),([^,]*),([^,]*),"
)
EXPECTED = (
    "1787965966",
    "block",
    "tcp",
    "192.168.6.34",
    "192.168.6.50",
    "60162",
    "62173",
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def validate_sample() -> None:
    prematch = PREMATCH.search(SAMPLE)
    require(prematch is not None, "PFSENSE_PRI: prematch não casou com a amostra")
    payload = SAMPLE[prematch.end():]
    fields = FIELDS.search(payload)
    require(fields is not None, "PFSENSE_PRI: regex CSV não casou com a amostra")
    require(fields.groups() == EXPECTED, f"PFSENSE_PRI: campos inesperados: {fields.groups()}")


def require_once(text: str, needle: str, message: str) -> None:
    require(text.count(needle) == 1, message)


def validate_decoder() -> None:
    text = DECODER.read_text(encoding="utf-8")
    require(
        re.fullmatch(
            r'\s*<decoder name="conectaeduca_pfsense_pri">.*</decoder>\s*',
            text,
            flags=re.DOTALL,
        ) is not None,
        "PFSENSE_PRI: raiz/nome do decoder inválidos",
    )
    require_once(
        text,
        r'<prematch type="pcre2">filterlog\[\d+\]:\s+</prematch>',
        "PFSENSE_PRI: prematch divergente",
    )
    require_once(
        text,
        '<regex offset="after_prematch" type="pcre2">',
        "PFSENSE_PRI: regex/offset divergente",
    )
    require_once(
        text,
        "<order>id,action,protocol,srcip,dstip,srcport,dstport</order>",
        "PFSENSE_PRI: order divergente",
    )


def validate_rule() -> None:
    text = RULE.read_text(encoding="utf-8")
    require(
        re.fullmatch(
            r'\s*<group name="conectaeduca,pfsense,firewall,">.*</group>\s*',
            text,
            flags=re.DOTALL,
        ) is not None,
        "PFSENSE_PRI: group raiz inválido",
    )
    for needle, message in (
        ('<rule id="110620" level="8">', "PFSENSE_PRI: rule id/level divergente"),
        ("<decoded_as>conectaeduca_pfsense_pri</decoded_as>", "PFSENSE_PRI: decoded_as divergente"),
        ("<action>block</action>", "PFSENSE_PRI: action deve ser block"),
        ("<srcip>192.168.6.34</srcip>", "PFSENSE_PRI: srcip divergente"),
        ("<dstip>192.168.6.50</dstip>", "PFSENSE_PRI: dstip divergente"),
        ("<options>no_full_log</options>", "PFSENSE_PRI: no_full_log obrigatório"),
    ):
        require_once(text, needle, message)


def validate_wiring() -> None:
    conf = CONF.read_text(encoding="utf-8")
    compose = COMPOSE.read_text(encoding="utf-8")

    require(
        "<decoder_exclude>ruleset/decoders/0495-freepbs_decoders.xml</decoder_exclude>" in conf,
        "PFSENSE_PRI: exclusão do decoder FreePBX ausente",
    )
    require(
        "<rule_exclude>0715-freepbx_rules.xml</rule_exclude>" in conf,
        "PFSENSE_PRI: exclusão das rules FreePBX ausente",
    )

    for mount in (
        "./config/decoders/conectaeduca_pfsense_pri_decoders.xml:/wazuh-config-mount/etc/decoders/conectaeduca_pfsense_pri_decoders.xml:ro",
        "./config/rules/conectaeduca_pfsense_rules.xml:/wazuh-config-mount/etc/rules/conectaeduca_pfsense_rules.xml:ro",
    ):
        require(mount in compose, f"PFSENSE_PRI: mount ausente: {mount}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.parse_args()

    validate_sample()
    validate_decoder()
    validate_rule()
    validate_wiring()

    print("PFSENSE_WAZUH_PRI_REGRESSION=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
