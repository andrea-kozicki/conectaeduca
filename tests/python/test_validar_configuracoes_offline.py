"""Regressões positivas e negativas do gate de configurações offline."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/evidencias/validar_configuracoes_offline.py"
SPEC = importlib.util.spec_from_file_location("validar_configuracoes_offline", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class ConfiguracoesOfflineTests(unittest.TestCase):
    def test_yaml_com_compose_tags_permitidas(self) -> None:
        module.validate_yaml(
            "services:\n  portal: !override\n    ports: !reset []\n",
            "compose.yml",
        )

    def test_yaml_rejeita_chave_duplicada(self) -> None:
        with self.assertRaisesRegex(ValueError, "duplicada"):
            module.validate_yaml("services: {}\nservices: {}\n", "duplicado.yml")

    def test_yaml_rejeita_duplicata_em_override(self) -> None:
        source = (
            "services:\n  portal: !override\n"
            "    image: nginx:stable\n    image: nginx:latest\n"
        )
        with self.assertRaisesRegex(ValueError, "duplicada"):
            module.validate_yaml(source, "compose.override.yml")

    def test_yaml_rejeita_duplicata_em_reset_mapeamento(self) -> None:
        source = "services: !reset\n  portal: {}\n  portal: {}\n"
        with self.assertRaisesRegex(ValueError, "duplicada"):
            module.validate_yaml(source, "compose.reset.yml")

    def test_yaml_aceita_heranca_com_override_explicito(self) -> None:
        source = (
            "defaults: &defaults\n  image: nginx:stable\n  restart: always\n"
            "services:\n  portal: !override\n"
            "    <<: *defaults\n    image: nginx:latest\n"
        )
        module.validate_yaml(source, "heranca.yml")

    def test_yaml_aceita_heranca_com_sequencia_de_ancoras(self) -> None:
        source = (
            "image_defaults: &image_defaults {image: nginx:stable}\n"
            "restart_defaults: &restart_defaults {restart: always}\n"
            "services:\n  portal: !override\n"
            "    <<: [*image_defaults, *restart_defaults]\n"
            "    image: nginx:latest\n"
        )
        module.validate_yaml(source, "multiplos_defaults.yml")

    def test_yaml_rejeita_duplicata_explicita_apos_merge(self) -> None:
        source = (
            "defaults: &defaults {image: nginx:stable}\n"
            "services:\n  portal: !override\n"
            "    <<: *defaults\n"
            "    image: nginx:latest\n    image: nginx:other\n"
        )
        with self.assertRaisesRegex(ValueError, "duplicada"):
            module.validate_yaml(source, "merge_duplicado.yml")

    def test_yaml_rejeita_duplicata_em_ancora_usada_apenas_no_merge(self) -> None:
        source = (
            "services:\n  portal: !override\n"
            "    <<: &defaults\n"
            "      image: nginx:stable\n      image: nginx:latest\n"
        )
        with self.assertRaisesRegex(ValueError, "duplicada"):
            module.validate_yaml(source, "ancora_duplicada.yml")

    def test_yaml_rejeita_heranca_circular(self) -> None:
        source = "defaults: &defaults\n  <<: *defaults\n"
        with self.assertRaisesRegex(ValueError, "circular"):
            module.validate_yaml(source, "heranca_circular.yml")

    def test_yaml_rejeita_tag_arbitraria(self) -> None:
        with self.assertRaisesRegex(ValueError, "YAML inválido"):
            module.validate_yaml("services: !python/object {}\n", "tag.yml")

    def test_yaml_rejeita_raiz_incorreta(self) -> None:
        with self.assertRaisesRegex(ValueError, "mapeamento"):
            module.validate_yaml("- item\n", "lista.yml")

    def test_xml_wazuh_aceita_multiplas_raizes_validas(self) -> None:
        root = module.parse_wazuh_fragment(
            '<group name="a"><rule id="1101"/></group>\n'
            '<group name="b"><rule id="1102"/></group>',
            "regras.xml",
            "rules",
        )
        self.assertEqual(len(root), 2)

    def test_xml_wazuh_aceita_decoders_multiplos(self) -> None:
        root = module.parse_wazuh_fragment(
            '<decoder name="um"/><decoder name="dois"/>', "decoders.xml", "decoders"
        )
        self.assertEqual(len(root), 2)

    def test_xml_wazuh_rejeita_xml_malformado(self) -> None:
        with self.assertRaisesRegex(ValueError, "malformado"):
            module.parse_wazuh_fragment("<group><rule></group>", "x.xml", "rules")

    def test_xml_wazuh_rejeita_elemento_indevido(self) -> None:
        with self.assertRaisesRegex(ValueError, "esperados"):
            module.parse_wazuh_fragment("<service/>", "x.xml", "rules")

    def test_xml_wazuh_rejeita_dtd(self) -> None:
        with self.assertRaisesRegex(ValueError, "DTD/ENTITY"):
            module.parse_wazuh_fragment("<!DOCTYPE foo><group/>", "x.xml", "rules")

    def test_xml_wazuh_rejeita_texto_solto(self) -> None:
        with self.assertRaisesRegex(ValueError, "texto solto"):
            module.parse_wazuh_fragment("<group/>invalido", "x.xml", "rules")

    def test_regressao_id_duplicado_entre_arquivos(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            yaml_file = Path("deploy/interna/ferret/compose.yml")
            xml1 = Path("deploy/interna/wazuh/config/rules/um.xml")
            xml2 = Path("deploy/interna/wazuh/config/rules/dois.xml")
            for path, contents in (
                (yaml_file, "services: {}\n"),
                (xml1, '<group name="a"><rule id="110000"/></group>'),
                (xml2, '<group name="b"><rule id="110000"/></group>'),
            ):
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(contents, encoding="utf-8")
            with patch.object(module, "tracked_configs", return_value=([yaml_file], [xml1, xml2])):
                with patch("sys.stderr"):
                    with self.assertRaisesRegex(ValueError, "FAIL"):
                        module.validate_repository(root)

    def test_inventario_atual(self) -> None:
        root = Path(__file__).resolve().parents[2]
        yaml_count, xml_count = module.validate_repository(root)
        self.assertGreater(yaml_count, 20)
        self.assertGreater(xml_count, 5)


if __name__ == "__main__":
    unittest.main()
