#!/usr/bin/env python3
"""Offline safety contract: GA08 launch discovery reads metadata, not secrets."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/ga08-env-provenance-inventory-ep125.py"
spec = importlib.util.spec_from_file_location("ga08_env_inventory_offline", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)


class GA08EnvProvenanceInventoryTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)

    def create(self, name, text="SENSITIVE_VALUE_DO_NOT_PRINT"):
        item = self.root / name
        item.parent.mkdir(parents=True, exist_ok=True)
        item.write_text(text, encoding="utf-8")
        return item

    def test_names_and_metadata_only_without_opening_contents(self):
        self.create("ga08-cutover.sh")
        self.create("subdir/pa05-deploy.py")
        self.create("random.sql")
        self.create(".env.production")
        with mock.patch("builtins.open", side_effect=AssertionError("read forbidden")):
            candidates, env_count, state = mod.scan("DOWNLOADS", self.root, 2)
        self.assertEqual(state, "COMPLETO")
        self.assertEqual(env_count, 1)
        self.assertEqual(sorted(item.name for item in candidates),
                         ["ga08-cutover.sh", "pa05-deploy.py"])
        self.assertTrue(all(item.opaque_id and item.modified_day for item in candidates))
        self.assertNotIn("SENSITIVE_VALUE", repr(candidates))

    def test_private_script_name_is_redacted(self):
        self.assertEqual(mod.public_name("ga08-private-token.txt"), "REDACTED")
        self.assertEqual(mod.public_name("pa05 senha.sh"), "REDACTED")
        self.assertEqual(mod.public_name("ga08\ncutover.sh"), "ga08_cutover.sh")

    def test_env_files_are_counted_but_names_never_displayed(self):
        self.create(".env")
        self.create(".env.prod")
        self.create("secret-export.env")
        candidates, count, status = mod.scan("HOME_CE_CONFIG", self.root, 1)
        self.assertEqual(status, "COMPLETO")
        self.assertEqual(count, 3)
        self.assertFalse(candidates)

    def test_symlinks_are_ignored(self):
        outside = self.create("nested/ga08-deploy.sh")
        link = self.root / "ga08-symlink.sh"
        link.symlink_to(outside)
        candidates, env_count, status = mod.scan("DOWNLOADS", self.root, 0)
        self.assertEqual(status, "COMPLETO")
        self.assertEqual(env_count, 0)
        self.assertFalse(candidates)

    def test_root_symlink_is_not_followed(self):
        outside = self.root / "target"
        outside.mkdir()
        linked = self.root / "linked"
        linked.symlink_to(outside, target_is_directory=True)
        candidates, count, status = mod.scan("DOWNLOADS", linked, 3)
        self.assertEqual((candidates, count, status),
                         ([], 0, "RAIZ_SYMLINK_IGNORADA"))

    def test_scan_cannot_expand_to_entire_home(self):
        home = self.root / "home/andrea"
        repo = self.root / "opt/conectaeduca"
        self.assertNotIn(home, [path for _, path, _ in mod.roots(repo, home)])
        self.assertNotIn(Path("/"), [path for _, path, _ in mod.roots(repo, home)])

    def test_limit_fails_closed(self):
        self.create("ga08-one.sh")
        self.create("ga08-two.sh")
        with mock.patch.object(mod, "MAX_ENTRIES_PER_ROOT", 1):
            with self.assertRaisesRegex(mod.InventoryError, "limite_entradas"):
                mod.scan("DOWNLOADS", self.root, 1)

    def test_source_has_no_runtime_or_file_content_operations(self):
        source = SCRIPT.read_text(encoding="utf-8")
        for prohibited in (
            "subprocess.run", "docker inspect", ".read_text(",
            ".read_bytes(", "shell_history", ".bash_history", "docker compose",
        ):
            self.assertNotIn(prohibited, source)


if __name__ == "__main__":
    unittest.main()
