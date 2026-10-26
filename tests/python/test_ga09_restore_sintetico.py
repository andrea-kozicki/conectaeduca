#!/usr/bin/env python3
"""GA-09: testes estritamente ficticios em TemporaryDirectory, sem Bacula."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/evidencias/ga09_verificar_restore_sintetico.py"
SPEC = importlib.util.spec_from_file_location("ga09_restore", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
ga09 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ga09)


class GA09RestoreIntegrityOffline(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ga09-synthetic-")
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.source = root / "reference"
        self.restored = root / "recovered"
        self.source.mkdir()
        self.restored.mkdir()

    def put(self, relative, data=b"fictional-data"):
        for directory in (self.source, self.restored):
            path = directory / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    def rejected(self, reason):
        with self.assertRaises(ga09.IntegrityError) as cm:
            ga09.verify(self.source, self.restored)
        self.assertEqual(str(cm.exception), reason)

    def test_01_identical_regular_file_passes(self):
        self.put("sample.txt", b"fictional-only")
        self.assertEqual(ga09.verify(self.source, self.restored), (1, 14))

    def test_02_two_nested_files_pass(self):
        self.put("folder/a.txt", b"one")
        self.put("folder/b.txt", b"two")
        self.assertEqual(ga09.verify(self.source, self.restored), (2, 6))

    def test_03_modified_content_fails(self):
        self.put("sample.txt", b"alpha")
        (self.restored / "sample.txt").write_bytes(b"omega")
        self.rejected("conteudo_ou_tamanho_divergente")

    def test_04_truncated_file_fails(self):
        self.put("sample.txt", b"some fictitious payload")
        (self.restored / "sample.txt").write_bytes(b"some")
        self.rejected("conteudo_ou_tamanho_divergente")

    def test_05_file_missing_fails(self):
        self.put("sample.txt")
        (self.restored / "sample.txt").unlink()
        self.rejected("sem_arquivos_para_comparar")

    def test_06_unexpected_extra_file_fails(self):
        self.put("sample.txt")
        (self.restored / "extra.txt").write_bytes(b"other")
        self.rejected("inventario_arquivos_divergente")

    def test_07_source_symlink_file_rejected(self):
        self.put("sample.txt")
        (self.source / "alias.txt").symlink_to("sample.txt")
        self.rejected("link_simbolico_proibido")

    def test_08_restored_symlink_file_rejected(self):
        self.put("sample.txt")
        (self.restored / "alias.txt").symlink_to("sample.txt")
        self.rejected("link_simbolico_proibido")

    def test_09_symlink_directory_rejected(self):
        self.put("sample.txt")
        (self.source / "alias").symlink_to(self.restored, target_is_directory=True)
        self.rejected("link_simbolico_proibido")

    def test_10_hardlink_rejected(self):
        self.put("sample.txt")
        os.link(self.source / "sample.txt", self.source / "other.txt")
        self.rejected("hardlink_proibido")

    def test_11_empty_trees_do_not_prove_restore(self):
        self.rejected("sem_arquivos_para_comparar")

    def test_12_same_directory_rejected(self):
        self.put("sample.txt")
        with self.assertRaisesRegex(ga09.IntegrityError, "raizes_iguais_ou_aninhadas"):
            ga09.verify(self.source, self.source)

    def test_13_nested_roots_rejected(self):
        self.put("sample.txt")
        nested = self.source / "nested"
        nested.mkdir()
        with self.assertRaisesRegex(ga09.IntegrityError, "raizes_iguais_ou_aninhadas"):
            ga09.verify(self.source, nested)

    def test_14_extra_empty_directory_rejected(self):
        self.put("sample.txt")
        (self.restored / "extra").mkdir()
        self.rejected("estrutura_diretorios_divergente")

    def test_15_large_fixture_rejected_before_hash(self):
        self.put("sample.txt")
        with open(self.source / "huge.bin", "wb") as fp:
            fp.truncate(ga09.MAX_FILE_BYTES + 1)
        self.rejected("arquivo_maior_que_limite")

    @unittest.skipUnless(hasattr(os, "mkfifo"), "requires POSIX FIFO")
    def test_16_special_file_rejected(self):
        self.put("sample.txt")
        os.mkfifo(self.source / "fixture-fifo")
        self.rejected("tipo_nao_regular")

    def test_17_symlink_root_rejected(self):
        self.put("sample.txt")
        alias = self.source.parent / "alias"
        alias.symlink_to(self.source, target_is_directory=True)
        with self.assertRaises(ga09.IntegrityError):
            ga09.verify(alias, self.restored)

    def test_18_cli_requires_explicit_synthetic_confirmation(self):
        self.put("sample.txt")
        cmd = [sys.executable, str(SCRIPT), "--source", str(self.source),
               "--restored", str(self.restored)]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertIn("confirmacao_sintetica_ausente", result.stderr)
        self.assertNotIn(str(self.source), result.stderr)

    def test_19_cli_does_not_print_paths_or_contents(self):
        self.put("private-fictitious.txt", b"GA09 not a secret")
        cmd = [sys.executable, str(SCRIPT), "--synthetic", "--source", str(self.source),
               "--restored", str(self.restored)]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("GA09_RESTORE_VERIFY=PASS", result.stdout)
        self.assertIn("GA09_BACULA_RESTORE_EXECUTED=NAO", result.stdout)
        self.assertNotIn("private-fictitious", result.stdout)
        self.assertNotIn("GA09 not a secret", result.stdout)
        self.assertNotIn(str(self.source), result.stdout)

    def test_20_cli_does_not_mutate_source_or_restore(self):
        self.put("sample.txt", b"synthetic-content")
        src_before = (self.source / "sample.txt").stat()
        dest_before = (self.restored / "sample.txt").stat()
        self.assertEqual(ga09.verify(self.source, self.restored)[0], 1)
        self.assertEqual(src_before.st_mtime_ns, (self.source / "sample.txt").stat().st_mtime_ns)
        self.assertEqual(dest_before.st_mtime_ns, (self.restored / "sample.txt").stat().st_mtime_ns)


if __name__ == "__main__":
    unittest.main()
