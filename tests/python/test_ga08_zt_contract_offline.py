#!/usr/bin/env python3
"""GA-08 + Fase 3: testes estaticos do contrato WAF/bridge e matriz Twingate.

Nao executa Docker/Compose, nao conecta ao tenant Twingate e nao altera VMs.
Acesso via rede e combinacao real de overlays requerem teste operacional.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "deploy/dmz/compose.yml"
WAF = ROOT / "deploy/dmz/compose.waf.yml"
HOST = ROOT / "deploy/dmz/compose.host.yml"
CONNECTOR = ROOT / "deploy/interna/twingate/compose.yml"
MATRIX = ROOT / "docs/seguranca/FASE3-MATRIZ-ACESSO-TWINGATE.md"
GA08 = ROOT / "docs/seguranca/GA08-PA02-MATRIZ-FLUXOS-ISOLAMENTO-20261025.md"
DESIGN = ROOT / "docs/seguranca/FASE3-ARQUITETURA-ZERO-TRUST-GRUPOS-RECURSOS.md"


def file_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def matrix_rows(text: str) -> dict[str, list[str]]:
    rows = {}
    for line in text.splitlines():
        if not line.startswith("|"):
            continue
        columns = [col.strip().replace("**", "") for col in line.strip().strip("|").split("|")]
        if len(columns) != 9 or not columns[0] or columns[0] in ("ID", "---"):
            continue
        if set(columns[0]) <= {"-", ":", " "}:
            continue
        rows[columns[0].split(" ", 1)[0].rstrip("*")] = columns
    return rows


class GA08WafBridgeContract(unittest.TestCase):
    def test_base_nginx_lab_binding_is_loopback_only(self):
        base = file_text(BASE)
        self.assertIn('"127.0.0.1:8088:8080"', base)
        self.assertNotRegex(base, r'(?m)^\s*-\s*["\']?(?:0\.0\.0\.0:)?8088:8080["\']?\s*$')

    def test_waf_overlay_reset_removes_host_binding(self):
        waf = file_text(WAF)
        # Controle de fonte, nao afirmacao sobre docker compose config resolvido.
        self.assertRegex(waf, r'(?ms)^\s{2}nginx:\s*\n\s{4}ports:\s*!reset\s*\[\]')
        self.assertRegex(waf, r'(?ms)^\s{2}nginx:\s*.*?\n\s{4}expose:\s*\n\s*-\s*["\']?8080["\']?')
        self.assertNotIn('"0.0.0.0:8088:8080"', waf)

    def test_waf_targets_internal_nginx_only(self):
        waf = file_text(WAF)
        self.assertIn('BACKEND: "http://nginx:8080"', waf)
        self.assertRegex(waf, r'(?ms)^\s{2}waf:.*?\n\s{4}ports:')
        self.assertIn("no-new-privileges:true", waf)

    def test_host_overlay_does_not_publish_nginx_again(self):
        host = file_text(HOST)
        self.assertIn("CONECTAEDUCA_WAF_BIND_ADDRESS", host)
        self.assertNotRegex(host, r'(?m)^\s{2}nginx:')
        self.assertNotIn("8088:8080", host)

    def test_documented_bridge_risk_remains_open(self):
        text = file_text(GA08)
        self.assertIn("GA08-N1", text)
        self.assertIn("GA08-N2", text)
        self.assertIn("Nginx upstream", text)
        self.assertIn("NÃO", text)
        self.assertIn("host→bridge", text)


class ZeroTrustAccessContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = file_text(MATRIX)
        cls.rows = matrix_rows(cls.text)

    def test_matrix_has_expected_headers(self):
        header = next(line for line in self.text.splitlines() if line.startswith("| ID |"))
        self.assertIn("TG-OPERACAO", header)
        self.assertIn("TG-SEGURANCA", header)
        self.assertIn("TG-ADMIN", header)
        self.assertIn("TG-BACKUP", header)
        self.assertIn("Sem grupo", header)

    def test_admin_private_never_public(self):
        r = self.rows["ADMIN-PHP-PRIVADO"]
        self.assertIn("DENY", r[3])
        self.assertIn("ALLOW + MFA", r[6])
        self.assertIn("DENY", r[8])
        self.assertIn("a projetar", r[1])

    def test_siem_and_backup_only_named_roles(self):
        soc = self.rows["SOC-WAZUH"]
        backup = self.rows["BK-BACULARIS"]
        self.assertIn("ALLOW + MFA", soc[5])
        self.assertIn("DENY", soc[4])
        self.assertIn("DENY", soc[8])
        self.assertIn("ALLOW + MFA", backup[7])
        self.assertIn("DENY", backup[5])
        self.assertIn("DENY", backup[8])

    def test_no_resources_for_secret_stores_db_catalog(self):
        for id_ in ("OPENBAO", "APP-MARIADB", "BACULA-INTERNO"):
            r = self.rows[id_]
            self.assertIn("Nenhum Resource", r[2])
            self.assertIn("DENY", r[3])
            self.assertIn("DENY", r[8])

    def test_no_implicit_private_access_without_group(self):
        for id_, row in self.rows.items():
            if id_ != "WEB-PUBLIC":
                self.assertNotIn("ALLOW", row[8],
                                 f"Resource {id_} foi liberado para sem grupo")

    def test_public_443_is_not_twingate_admin_isolation(self):
        public = self.rows["WEB-PUBLIC"]
        self.assertIn("TCP443", public[2])
        self.assertIn("ALLOW", public[3])
        self.assertIn("não isola /admin", self.rows["WEB-ZT-TESTE"][6])
        self.assertIn("isolamento de rede admin como", self.text)

    def test_ssh_access_is_minimal_not_permanent_blanket(self):
        ep125 = self.rows["MGMT-EP125-SSH"]
        ep126 = self.rows["MGMT-EP126-SSH"]
        self.assertIn("TCP22", ep125[2])
        self.assertIn("TCP22", ep126[2])
        self.assertIn("DENY", ep125[4])
        self.assertIn("ALLOW", ep125[6])
        self.assertIn("se autorização", ep126[4])

    def test_twingate_connector_source_is_minimal(self):
        text = file_text(CONNECTOR)
        self.assertRegex(text, r'image:\s*twingate/connector@sha256:[0-9a-f]{64}')
        self.assertIn("network_mode: host", text)
        self.assertIn("no-new-privileges:true", text)
        self.assertIn("- twingate", text)
        self.assertNotRegex(text, r'(?m)^\s{4}ports:')
        self.assertNotRegex(text, r'(?m)^\s{4}volumes:')
        self.assertNotIn("/var/run/docker.sock", text)

    def test_documents_do_not_claim_endpoint_is_live(self):
        design = file_text(DESIGN)
        self.assertIn("NÃO implantada", design)
        self.assertIn("não existe no baseline", design)
        self.assertIn("não caminhos HTTP", design)


if __name__ == "__main__":
    unittest.main()
