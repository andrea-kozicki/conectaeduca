#!/usr/bin/env python3
"""Read-only EP125 custody evidence collector: offline regression tests."""

from __future__ import annotations

import importlib.util
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

SCRIPT = (Path(__file__).resolve().parents[2] / "scripts" /
          "ga08-pa05-v2-custody-inventory-ep125.py")
spec = importlib.util.spec_from_file_location("ga08_pa05_v2_custody", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)


class CustodyInventoryTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.tmp = Path(temp.name)

    def test_known_image_ids_only(self):
        expected = "sha256:" + "d" * 64
        seen = []

        def read(argv, **kwargs):
            seen.append(argv)
            return SimpleNamespace(returncode=0, stdout=(expected + "\n").encode(),
                                   stderr=b"SECRET_DO_NOT_PRINT")

        with mock.patch.object(mod.subprocess, "run", side_effect=read):
            self.assertEqual(mod.local_image_id("conectaeduca/nginx:dmz"), expected)
        self.assertEqual(seen[0][:4], ["docker", "image", "inspect", "--format"])
        self.assertNotIn("Config.Env", seen[0])
        with self.assertRaisesRegex(mod.InventoryError, "imagem_referencia_nao_aprovada"):
            mod.local_image_id("private/unapproved:latest")

    def test_image_inspect_bad_output_no_raw_leak(self):
        with mock.patch.object(mod.subprocess, "run", return_value=SimpleNamespace(
            returncode=1, stdout=b"SECRET_DO_NOT_PRINT",
            stderr=b"SECRET_DO_NOT_PRINT")):
            with self.assertRaisesRegex(mod.InventoryError, "imagem_local_indisponivel"):
                mod.local_image_id("conectaeduca/waf:dmz")

    def test_peer_is_pinned_before_running_code(self):
        download = self.tmp / "Downloads"
        download.mkdir()
        fake = download / mod.PEER_NAME
        fake.write_text("print('SECRET_DO_NOT_PRINT')\n")
        fake.chmod(0o600)
        with mock.patch.object(mod.runpy, "run_path") as run_script:
            with self.assertRaisesRegex(mod.InventoryError, "biblioteca_hash_divergente"):
                mod.load_peer(self.tmp)
            run_script.assert_not_called()

    def test_collector_checks_parity_and_sources_without_values(self):
        files = tuple(self.tmp / f"compose-{idx}.yml" for idx in range(14))
        image = "sha256:" + "e" * 64
        snapshots = {
            s: {"Config": {"Image": tag}, "Image": image}
            for s, tag in (("php", "conectaeduca/php-fpm:pa05-10328ab6"),
                           ("nginx", "conectaeduca/nginx:dmz"),
                           ("waf", "conectaeduca/waf:dmz"))
        }
        interp = {
            "load_verified_library": lambda home: {"inspect_runtime": lambda: snapshots},
            "approved_compose_paths": lambda s, lib, home: files,
            "secure_digest": lambda path, limit, suffix: "a" * 64,
        }
        peer = {
            "compose_version": lambda: "5.7.0",
            "verified_peer": lambda home: interp,
            "report": lambda home, obj: [dict.fromkeys(mod.SERVICES, "IGUAL")]
                                         * 2,
            "check_no_service_env_files": lambda paths: None,
        }
        with mock.patch.object(mod, "local_image_id", return_value=image):
            result = mod.collect(self.tmp, peer)
        self.assertEqual(result["context_count"], 2)
        self.assertEqual(result["service_parity_count"], 6)
        self.assertEqual(len(result["source_hashes"]), 14)
        self.assertEqual(set(result["images"]), {"php", "nginx", "waf"})

    def test_mismatch_fails_closed_before_source_collection(self):
        peer = {
            "compose_version": lambda: "5.7.0",
            "verified_peer": lambda home: {},
            "report": lambda home, obj: [dict.fromkeys(mod.SERVICES, "DIFERENTE")]
                                         * 2,
        }
        with self.assertRaisesRegex(mod.InventoryError, "hash_runtime_nao_comprovado"):
            mod.collect(self.tmp, peer)

    def test_main_emits_only_aggregate_counts(self):
        private = {
            "context_count": 2, "service_parity_count": 6,
            "source_hashes": {"01": "SECRET_DO_NOT_PRINT"},
            "images": {"php": {"image_id": "SECRET_DO_NOT_PRINT"}},
            "compose_count": 14,
        }
        with (mock.patch.object(mod.socket, "gethostname", return_value="ep125-pucpr"),
              mock.patch.object(mod.os, "geteuid", return_value=1000),
              mock.patch.object(mod, "load_peer", return_value={}),
              mock.patch.object(mod, "collect", return_value=private)):
            log = io.StringIO()
            with redirect_stdout(log):
                self.assertEqual(mod.main(), 0)
        result = log.getvalue()
        self.assertIn("FONTES_COMPOSE=14_SHA256_EM_MEMORIA", result)
        self.assertIn("MANIFESTO_V2_CRIADO=NAO", result)
        self.assertIn("ROLLBACK_HABILITADO=NAO", result)
        self.assertNotIn("SECRET_DO_NOT_PRINT", result)

    def test_source_has_no_mutation_driver(self):
        source = SCRIPT.read_text()
        for forbidden in ('"up"', '"down"', '"--execute"',
                          '"--force-recreate"', "write_text(", "write_bytes(",
                          "os.replace(", "print(proc.stderr)", "print(proc.stdout)"):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
