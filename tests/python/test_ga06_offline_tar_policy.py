#!/usr/bin/env python3
"""GA-06: rejeicoes de politica ao admitir um unico override de TAR local."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "scripts/evidencias/ga06_validar_politica_tar.py"
spec = importlib.util.spec_from_file_location("ga06_offline_policy", MODULE)
assert spec and spec.loader
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


class GA06OfflineTarPolicy(unittest.TestCase):
    def run_case(self, *, change_manifest=None, change_override=None, valid=True):
        data = json.loads(policy.MANIFEST.read_text(encoding="utf-8"))
        override = policy.OVERRIDE.read_text(encoding="utf-8")
        if change_manifest is not None:
            change_manifest(data)
        if change_override is not None:
            override = change_override(override)
        with tempfile.TemporaryDirectory(prefix="ga06-policy-") as tmp:
            manifest = Path(tmp) / "manifest.json"
            compose = Path(tmp) / "compose.yml"
            manifest.write_text(json.dumps(data), encoding="utf-8")
            compose.write_text(override, encoding="utf-8")
            if valid:
                policy.verify(manifest, compose)
            else:
                with self.assertRaises(policy.PolicyError):
                    policy.verify(manifest, compose)

    def test_01_manifest_and_override_known_pass(self):
        self.run_case()

    def test_02_archive_digest_tamper_is_rejected(self):
        self.run_case(change_manifest=lambda d: d.update(
            archive_sha256="0" * 64), valid=False)

    def test_03_config_digest_tamper_is_rejected(self):
        self.run_case(change_manifest=lambda d: d.update(
            archive_config_sha256="0" * 64), valid=False)

    def test_04_descriptor_digest_tamper_is_rejected(self):
        self.run_case(change_manifest=lambda d: d.update(
            ep126_docker_descriptor_sha256="0" * 64), valid=False)

    def test_05_altered_image_tag_is_rejected(self):
        self.run_case(change_override=lambda s: s.replace(
            policy.LOCAL_TAG, "localhost/conectaeduca/ferret-scan:latest"), valid=False)

    def test_06_default_pull_is_rejected(self):
        self.run_case(change_override=lambda s: s.replace(
            "pull_policy: never", "pull_policy: missing"), valid=False)

    def test_07_removed_pull_policy_is_rejected(self):
        self.run_case(change_override=lambda s: s.replace(
            "    pull_policy: never\n", ""), valid=False)

    def test_08_extra_host_port_is_rejected(self):
        self.run_case(change_override=lambda s: s + "    ports:\n      - '0.0.0.0:8080:8080'\n",
                      valid=False)

    def test_09_extra_build_is_rejected(self):
        self.run_case(change_override=lambda s: s + "    build: .\n", valid=False)

    def test_10_unexpected_group_user_is_rejected(self):
        self.run_case(change_manifest=lambda d: d.update(
            expected_user="0:0"), valid=False)

    def test_11_wrong_provenance_kind_is_rejected(self):
        self.run_case(change_manifest=lambda d: d.update(
            artifact_kind="docker-registry"), valid=False)

    def test_12_parametrized_image_is_rejected(self):
        self.run_case(change_override=lambda s: s.replace(
            policy.LOCAL_TAG, "${FERRET_PA07_V5_IMAGE}"), valid=False)


if __name__ == "__main__":
    unittest.main()
