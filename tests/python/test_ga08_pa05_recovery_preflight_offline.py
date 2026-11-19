#!/usr/bin/env python3
"""Offline contract for the EP125 11+3 Compose source inventory."""
from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/ga08-pa05-recovery-preflight-ep125.py"
spec = importlib.util.spec_from_file_location("ga08_pa05_readonly", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class PA05RecoveryInventoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.repo = root / "opt/conectaeduca"
        self.home = root / "home/operadora"
        self.paths = mod.expected_paths(self.repo, self.home)
        for path in self.paths:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("# fonte sintetica de teste\n", encoding="utf-8")
        label = ",".join(str(p) for p in self.paths)
        self.snapshots = {
            name: {
                "project": mod.PROJECT,
                "service": name,
                "image": mod.EXPECTED_IMAGES[name],
                "files": label,
                "state": "running",
                "health": "healthy",
                "restarts": "0",
            }
            for name in mod.CONTAINERS
        }

    def test_exact_14_active_and_11_rollback_files(self):
        result = mod.analyze_runtime(self.snapshots, self.repo, self.home)
        self.assertEqual(result["current_compose_count"], 14)
        self.assertEqual(result["baseline_compose_count"], 11)
        self.assertEqual(result["ga08_overlay_count"], 3)

    def test_all_three_containers_must_have_same_order(self):
        paths = list(self.paths)
        paths[11], paths[12] = paths[12], paths[11]
        self.snapshots["waf"]["files"] = ",".join(str(p) for p in paths)
        with self.assertRaisesRegex(mod.PreflightError, "compose_ordem_divergente_waf"):
            mod.analyze_runtime(self.snapshots, self.repo, self.home)

    def test_pa05_must_not_be_omitted_or_reordered(self):
        paths = list(self.paths)
        del paths[10]
        for entry in self.snapshots.values():
            entry["files"] = ",".join(str(p) for p in paths)
        with self.assertRaisesRegex(mod.PreflightError, "compose_quantidade_divergente"):
            mod.analyze_runtime(self.snapshots, self.repo, self.home)

    def test_php_pa05_image_cannot_be_downgraded(self):
        self.snapshots["php"]["image"] = "conectaeduca/php-fpm:old"
        with self.assertRaisesRegex(mod.PreflightError, "imagem_divergente_php"):
            mod.analyze_runtime(self.snapshots, self.repo, self.home)

    def test_waf_and_nginx_image_pins_are_checked(self):
        for service in ("waf", "nginx"):
            with self.subTest(service=service):
                original = self.snapshots[service]["image"]
                self.snapshots[service]["image"] = "unapproved:latest"
                with self.assertRaisesRegex(mod.PreflightError, "imagem_divergente_" + service):
                    mod.analyze_runtime(self.snapshots, self.repo, self.home)
                self.snapshots[service]["image"] = original

    def test_missing_symlinked_or_other_home_source_fails_closed(self):
        source = self.paths[10]
        source.unlink()
        with self.assertRaisesRegex(mod.PreflightError, "compose_fonte_inacessivel_11"):
            mod.analyze_runtime(self.snapshots, self.repo, self.home)
        source.symlink_to(self.paths[9])
        with self.assertRaisesRegex(mod.PreflightError, "compose_fonte_inacessivel_11"):
            mod.analyze_runtime(self.snapshots, self.repo, self.home)
        source.unlink()
        source.write_text("restored")
        other = self.home / "different" / mod.PA05
        other.parent.mkdir(parents=True, exist_ok=True)
        other.write_text("unapproved")
        for entry in self.snapshots.values():
            entry["files"] = entry["files"].replace(str(source), str(other))
        with self.assertRaisesRegex(mod.PreflightError, "compose_origem_nao_aprovada"):
            mod.analyze_runtime(self.snapshots, self.repo, self.home)

    def test_stopped_unhealthy_or_restarted_container_is_not_accepted(self):
        for name, field, value, reason in (
            ("php", "state", "exited", "servico_nao_saudavel_php"),
            ("nginx", "health", "unhealthy", "servico_nao_saudavel_nginx"),
            ("waf", "restarts", "1", "restarts_divergentes_waf"),
        ):
            with self.subTest(name=name, field=field):
                old = self.snapshots[name][field]
                self.snapshots[name][field] = value
                with self.assertRaisesRegex(mod.PreflightError, reason):
                    mod.analyze_runtime(self.snapshots, self.repo, self.home)
                self.snapshots[name][field] = old

    def test_no_runtime_mutators_or_unfiltered_inspect(self):
        content = SCRIPT.read_text(encoding="utf-8")
        for prohibited in ("docker compose up", "docker compose down", "docker exec", "--execute"):
            self.assertNotIn(prohibited, content)
        with mock.patch.object(mod, "docker_field") as field:
            field.return_value = "mock"
            mod.get_runtime()
            self.assertEqual(field.call_count, 21)


if __name__ == "__main__":
    unittest.main()
