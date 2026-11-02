#!/usr/bin/env python3
"""GA-07: contrato de template + rotação sintética em diretório temporário.

NUNCA acessa o audit.log institucional; não valida UID 82, Wazuh ou retenção.
O teste funcional é exclusivamente com usuário corrente e arquivo fictício.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = ROOT / "deploy/dmz/logrotate/php-audit.logrotate.conf.in"
REAL_LOG = "/var/log/conectaeduca/php-audit/audit.log"
TOKENS = {
    "@GA07_ROTATION_TRIGGER@",
    "@GA07_RETENTION_GENERATIONS@",
    "@GA07_PRIVILEGE_DIRECTIVE@",
    "@GA07_FILE_OWNER@",
    "@GA07_FILE_GROUP@",
    "@GA07_ARCHIVE_POLICY@",
}


class GA07LogrotateTemplate(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.template = TEMPLATE.read_text(encoding="utf-8")

    def test_template_nao_ativavel_sem_politica(self) -> None:
        self.assertEqual(self.template.count(REAL_LOG + " {"), 1)
        for token in TOKENS:
            with self.subTest(token=token):
                self.assertIn(token, self.template)
        self.assertEqual(set(re.findall(r"@GA07_[A-Z_]+@", self.template)), TOKENS)
        self.assertTrue(TEMPLATE.name.endswith(".conf.in"))

    def test_invariantes_de_integridade_e_privacidade(self) -> None:
        self.assertIn("create 0600 @GA07_FILE_OWNER@ @GA07_FILE_GROUP@", self.template)
        self.assertIn("    notifempty\n", self.template)
        body = self.template.split(REAL_LOG + " {", 1)[1]
        for forbidden in ("copytruncate", "missingok", "postrotate", "prerotate",
                          "olddir", "shred", "mail ", "su 82 82", "chmod 777"):
            with self.subTest(keyword=forbidden):
                self.assertNotIn(forbidden, body)
        self.assertIsNone(re.search(r"(?m)^\s*(daily|weekly|monthly|hourly|yearly|minutes)\b", body))
        self.assertIsNone(re.search(r"(?m)^\s*rotate\s+\d+", body))

    def test_rotacao_real_somente_fixture_privada(self) -> None:
        rotate_binary = shutil.which("logrotate")
        self.assertIsNotNone(rotate_binary, "Ambiente CI deve prover logrotate")
        with tempfile.TemporaryDirectory(prefix="ga07-offline-") as tmp:
            work = Path(tmp)
            log = work / "audit-sintetico.log"
            config = work / "logrotate.synthetic.conf"
            state = work / "logrotate.synthetic.state"
            before = "GA07_FAKE_EVENT_BEFORE\n"
            after = "GA07_FAKE_EVENT_AFTER\n"
            log.write_text(before, encoding="utf-8")
            log.chmod(0o600)
            text = self.template.replace(REAL_LOG, str(log))
            replacements = {
                "@GA07_ROTATION_TRIGGER@": "size 1",
                "@GA07_RETENTION_GENERATIONS@": "2",
                "@GA07_PRIVILEGE_DIRECTIVE@": "",
                # A fixture roda com a identidade corrente, sem chown e SEM UID 82.
                "create 0600 @GA07_FILE_OWNER@ @GA07_FILE_GROUP@": "create 0600",
                "@GA07_ARCHIVE_POLICY@": "nocompress",
            }
            for old, new in replacements.items():
                text = text.replace(old, new)
            self.assertIsNone(re.search(r"@GA07_[A-Z_]+@", text))
            self.assertNotIn(REAL_LOG, text)
            config.write_text(text, encoding="utf-8")
            config.chmod(0o600)

            def rotate() -> None:
                proc = subprocess.run(
                    [rotate_binary, "--force", "--state", str(state), str(config)],
                    text=True, capture_output=True, timeout=15, check=False,
                )
                self.assertEqual(proc.returncode, 0, (proc.stdout + proc.stderr)[-2000:])

            rotate()
            self.assertEqual((work / "audit-sintetico.log.1").read_text(), before)
            self.assertEqual(log.stat().st_mode & 0o777, 0o600)
            self.assertEqual((log.stat().st_uid, log.stat().st_gid),
                             (os.getuid(), os.getgid()))
            log.write_text(after, encoding="utf-8")
            rotate()
            self.assertEqual((work / "audit-sintetico.log.2").read_text(), before)
            self.assertEqual((work / "audit-sintetico.log.1").read_text(), after)
            self.assertEqual(log.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
