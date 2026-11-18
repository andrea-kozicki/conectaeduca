#!/usr/bin/env python3
"""Validação estática de YAML e XML versionados, sem acesso às VMs.

Dependência de análise YAML: PyYAML 6.0.3. Não executa Compose ou serviços.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path
import re
import subprocess
import sys
from xml.etree import ElementTree

import yaml


class StrictComposeLoader(yaml.SafeLoader):
    """SafeLoader com suporte restrito às tags declarativas do Compose."""


def _unique_mapping(loader: StrictComposeLoader, node: yaml.MappingNode) -> dict:
    result: dict = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=True)
        try:
            duplicate = key in result
        except TypeError as exc:
            raise yaml.constructor.ConstructorError(
                None, None, "chave YAML não escalar", key_node.start_mark
            ) from exc
        if duplicate:
            raise yaml.constructor.ConstructorError(
                None, None, f"chave YAML duplicada: {key!r}", key_node.start_mark
            )
        result[key] = loader.construct_object(value_node, deep=True)
    return result


def _compose_tag(loader: StrictComposeLoader, node: yaml.Node) -> object:
    if isinstance(node, yaml.MappingNode):
        return loader.construct_mapping(node, deep=True)
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node, deep=True)
    return loader.construct_scalar(node)


StrictComposeLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _unique_mapping
)
for _tag in ("!override", "!reset"):
    StrictComposeLoader.add_constructor(_tag, _compose_tag)


def validate_yaml(source: str, label: str) -> None:
    """Rejeita YAML inválido, chaves repetidas e tags não reconhecidas."""
    try:
        parsed = yaml.load(source, Loader=StrictComposeLoader)
    except yaml.YAMLError as exc:
        raise ValueError(f"{label}: YAML inválido: {exc}") from exc
    if not isinstance(parsed, dict):
        raise ValueError(f"{label}: documento YAML deve ser um mapeamento")


def parse_wazuh_fragment(source: str, label: str, kind: str) -> ElementTree.Element:
    """Wazuh aceita vários elementos top-level, diferentemente do XML comum."""
    if re.search(r"<!\s*(?:DOCTYPE|ENTITY)\b", source, re.IGNORECASE):
        raise ValueError(f"{label}: DTD/ENTITY não permitido neste teste")
    cleaned = re.sub(r"^\s*<\?xml\s+[^>]*\?>", "", source, count=1)
    try:
        wrapper = ElementTree.fromstring(f"<ce-fragments>{cleaned}</ce-fragments>")
    except ElementTree.ParseError as exc:
        raise ValueError(f"{label}: XML Wazuh malformado: {exc}") from exc

    expected = "group" if kind == "rules" else "decoder"
    children = list(wrapper)
    if not children or any(element.tag != expected for element in children):
        raise ValueError(f"{label}: esperados elementos <{expected}> no topo")
    if (wrapper.text or "").strip() or any((child.tail or "").strip() for child in children):
        raise ValueError(f"{label}: texto solto fora dos elementos XML")
    return wrapper


def tracked_configs(root: Path) -> tuple[list[Path], list[Path]]:
    raw = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z"])
    tracked = [Path(item.decode("utf-8")) for item in raw.split(b"\0") if item]
    yaml_paths = sorted(
        path for path in tracked
        if path.suffix in {".yml", ".yaml"}
        and (path.parts[:2] == (".github", "workflows") or path.parts[0] == "deploy")
    )
    xml_paths = sorted(
        path for path in tracked
        if path.suffix == ".xml"
        and (path.parts[:3] == ("deploy", "interna", "wazuh")
             or path.parts[:2] == ("ops", "pa06")
             or path.name == "phpunit.xml")
    )
    return yaml_paths, xml_paths


def validate_repository(root: Path) -> tuple[int, int]:
    yaml_paths, xml_paths = tracked_configs(root)
    if not yaml_paths or not xml_paths:
        raise ValueError("inventário vazio: YAML/XML versionados não localizados")

    failures: list[str] = []
    rule_ids: dict[str, list[str]] = defaultdict(list)
    decoder_names: dict[str, list[str]] = defaultdict(list)
    for path in yaml_paths:
        try:
            validate_yaml((root / path).read_text(encoding="utf-8"), str(path))
        except (ValueError, OSError) as exc:
            failures.append(str(exc))

    for path in xml_paths:
        label = str(path)
        try:
            source = (root / path).read_text(encoding="utf-8")
            if path.parts[:4] == ("deploy", "interna", "wazuh", "config"):
                kind = path.parts[4]
                if kind not in {"rules", "decoders"}:
                    raise ValueError(f"{label}: localização XML Wazuh inesperada")
                wrapper = parse_wazuh_fragment(source, label, kind)
                if kind == "rules":
                    for element in wrapper.iter("rule"):
                        rule_id = element.get("id")
                        if rule_id is None or not rule_id.isdecimal():
                            raise ValueError(f"{label}: regra sem ID decimal")
                        rule_ids[rule_id].append(label)
                else:
                    for element in wrapper.iter("decoder"):
                        name = element.get("name")
                        if not name:
                            raise ValueError(f"{label}: decoder sem nome")
                        decoder_names[name].append(label)
            else:
                ElementTree.fromstring(source)
        except (ValueError, OSError, ElementTree.ParseError) as exc:
            failures.append(f"{label}: {exc}")

    for kind, items in (("rule ID", rule_ids), ("decoder", decoder_names)):
        for key, locations in items.items():
            if len(locations) > 1:
                failures.append(f"{kind} duplicado ({key}): {', '.join(locations)}")

    if failures:
        for message in failures:
            print(f"::error::{message}", file=sys.stderr)
        raise ValueError(f"CONFIG_OFFLINE=FAIL erros={len(failures)}")

    return len(yaml_paths), len(xml_paths)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    try:
        yaml_count, xml_count = validate_repository(args.root.resolve())
    except (ValueError, subprocess.CalledProcessError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(f"CONFIG_OFFLINE=PASS yaml={yaml_count} xml={xml_count} runtime=NOT_TESTED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
