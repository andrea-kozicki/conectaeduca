#!/usr/bin/env python3
"""Fail-closed, no-mutation regression suite for PA05-aware recovery v2."""

from __future__ import annotations

import copy
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/ga08-pa05-recovery-v2-contract.py"
spec = importlib.util.spec_from_file_location("ga08_pa05_recovery_v2_contract", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)


def fixture() -> dict:
    return {
        "format": 2, "change_id": "GA08-20261120-SIMULACAO",
        "host": "ep125-pucpr", "project": mod.PROJECT,
        "restore_target": "PA05_BASE_11", "private_context_id":
            "GA08-20261104-TESTE",
        "compose": {"baseline11": list(mod.BASE), "active14": list(mod.ACTIVE)},
        "source_sha256": {k: "a" * 64 for k in mod.SOURCE_KEYS},
        "config_sha256": {"baseline11": "b" * 64, "active14": "c" * 64},
        "images": {service: {"reference": image, "image_id": "sha256:" + "d" * 64}
                   for service, image in mod.IMAGES.items()},
        "snapshot": {"reference": "ubuntu.33", "coverage_attested": False,
                     "restoration_confirmed": False},
        "verification": {
            "source_custody_verified": False,
            "interpolation_11_14_passed": True,
            "hash_runtime_14_passed": True,
            "offline_failure_suite_passed": False,
            "controlled_restore_rehearsed": False,
            "functional_e2e_passed": False,
        },
        "approval": {"operator_window_approved": False,
                     "secrets_recoverable": False,
                     "cross_vm_dependencies_checked": False},
        "state": "CANDIDATE_ONLY",
    }


class RecoveryV2ContractTests(unittest.TestCase):
    def test_exact_baseline_and_active_order(self):
        data = fixture()
        self.assertIsNone(mod.validate_manifest(data))
        self.assertEqual(len(data["compose"]["baseline11"]), 11)
        self.assertEqual(len(data["compose"]["active14"]), 14)
        self.assertEqual(data["compose"]["baseline11"][-1],
                         "compose.pa05-10328ab6.yml")

    def test_rejects_old_9_10_and_pa05_downgrade(self):
        data = fixture()
        data["compose"]["baseline11"] = list(mod.BASE)[:10]
        with self.assertRaisesRegex(mod.ContractError, "compose_modelo_divergente"):
            mod.validate_manifest(data)
        data = fixture()
        data["images"]["php"]["reference"] = "conectaeduca/php-fpm:legacy"
        with self.assertRaisesRegex(mod.ContractError, "imagem_id_ou_referencia"):
            mod.validate_manifest(data)

    def test_rejects_wrong_hashes_and_extra_secret_fields(self):
        data = fixture()
        data["config_sha256"]["baseline11"] = "not-a-sha"
        with self.assertRaisesRegex(mod.ContractError, "hash_config_invalidos"):
            mod.validate_manifest(data)
        data = fixture()
        data["secret_value"] = "TOP_SECRET_SHOULD_NEVER_PRINT"
        with self.assertRaisesRegex(mod.ContractError, "manifesto_campos_invalidos"):
            mod.validate_manifest(data)

    def test_boolean_only_attestations_and_no_auto_approval(self):
        data = fixture()
        data["approval"]["operator_window_approved"] = "true"
        with self.assertRaisesRegex(mod.ContractError, "aprovacao_estado_invalido"):
            mod.validate_manifest(data)
        self.assertIn("ensaio_recuperacao", mod.readiness_reasons(fixture()))
        ready = fixture()
        for section in ("verification", "approval"):
            for key in ready[section]:
                ready[section][key] = True
        for key in ("coverage_attested", "restoration_confirmed"):
            ready["snapshot"][key] = True
        self.assertEqual(mod.readiness_reasons(ready), ())

    def test_simulated_failure_halts_before_each_step(self):
        for index, step in enumerate(mod.STEPS):
            state, completed = mod.simulate(fail_at=step)
            self.assertEqual(state, "ABORTED_FAIL_CLOSED")
            self.assertEqual(completed, mod.STEPS[:index])
            self.assertNotIn(step, completed)
        final, steps = mod.simulate()
        self.assertEqual(final, "E2E_REQUIRES_REAL_EVIDENCE")
        self.assertEqual(steps, mod.STEPS)

    def test_protected_manifest_permissions_and_no_value_disclosure(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "manifest.json"
            data = fixture()
            path.write_text(json.dumps(data))
            path.chmod(0o600)
            self.assertEqual(mod.read_protected_manifest(path), data)
            path.chmod(0o644)
            with self.assertRaisesRegex(mod.ContractError,
                                        "manifesto_permissoes_invalidas"):
                mod.read_protected_manifest(path)
            path.chmod(0o600)
            link = Path(root) / "link.json"
            link.symlink_to(path)
            with self.assertRaises(mod.ContractError):
                mod.read_protected_manifest(link)

    def test_cli_execute_always_fail_closed_without_accessing_docker(self):
        with mock.patch.object(mod.os, "geteuid", return_value=1000):
            log = io.StringIO()
            with redirect_stdout(log):
                self.assertEqual(mod.main(["--execute"]), 3)
        self.assertIn("CONTRATO_V2=FAIL_CLOSED", log.getvalue())
        self.assertIn("ROLLBACK_EXECUTAVEL=NAO", log.getvalue())

    def test_offline_cli_never_claims_actual_recovery(self):
        with mock.patch.object(mod.os, "geteuid", return_value=1000):
            log = io.StringIO()
            with redirect_stdout(log):
                self.assertEqual(mod.main([]), 0)
        self.assertIn("BASELINE_PA05=11_ARQUIVOS", log.getvalue())
        self.assertIn("RUNTIME_GA08=14_ARQUIVOS", log.getvalue())
        self.assertIn("E2E_REQUIRES_REAL_EVIDENCE", log.getvalue())
        self.assertIn("SERVICOS_MODIFICADOS=NAO", log.getvalue())

    def test_source_excludes_container_mutations_and_writes(self):
        text = SCRIPT.read_text(encoding="utf-8")
        for forbidden in ("subprocess", "os.system", "docker compose",
                          '"up"', '"down"', "write_text", "os.replace",
                          '"--force-recreate"', "print(obj)"):
            self.assertNotIn(forbidden, text)


if __name__ == "__main__":
    unittest.main()
