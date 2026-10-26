#!/usr/bin/env python3
"""GA-06.C: testes offline com fixtures sinteticas; nao acessa Docker/VM/.runtime real."""
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SANITIZER = ROOT / "scripts/dlp/sanitizar_ferret.py"
PROCESSOR = ROOT / "scripts/dlp/processar_inbox_ferret.sh"
spec = importlib.util.spec_from_file_location("ferret_sanitizer_ga06", SANITIZER)
assert spec and spec.loader
san = importlib.util.module_from_spec(spec)
spec.loader.exec_module(san)
FILE_ID = "a" * 64
FAKE_SENTINEL = "FAKE_DLP_SECRET_123_NOT_REAL"


def fake_report(results=None, stats=None):
    return {
        "results": [] if results is None else results,
        "stats": {} if stats is None else stats,
    }


class FerretSanitizerOffline(unittest.TestCase):
    def assert_rejected(self, callback):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                callback()

    def test_o01_valid_empty_scan_is_summary_only(self):
        events = san.build_events(fake_report(), FILE_ID, "object", True)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["event_type"], "dlp_scan_summary")
        self.assertEqual(events[0]["emitted_findings"], 0)
        self.assertEqual(events[0]["file_id"], FILE_ID)

    def test_o02_minimization_drops_raw_secret_and_filename(self):
        finding = {
            "type": "synthetic",
            "validator": "fixture",
            "confidence": 84,
            "line_number": 1,
            "text": FAKE_SENTINEL,
            "filename": "/tmp/dont-leak.txt",
            "metadata": {
                "secret_type": "fake_key",
                "detection_method": "fixture",
                "environment_type": "test",
                "unapproved_secret": FAKE_SENTINEL,
            },
        }
        events = san.build_events(fake_report([finding], {"total_findings": 1}), FILE_ID, "object", True)
        self.assertEqual(len(events), 2)
        self.assertEqual(events[1]["finding_type"], "synthetic")
        serialized = json.dumps(events, allow_nan=False)
        self.assertNotIn(FAKE_SENTINEL, serialized)
        self.assertNotIn("filename", serialized)
        self.assertNotIn("unapproved_secret", serialized)

    def test_o03_missing_or_malformed_report_schema_rejected(self):
        for obj in [
            {}, {"results": []}, {"stats": {}},
            {"results": {}, "stats": {}}, {"results": [], "stats": []},
            {"results": None, "stats": {}}, {"results": [], "stats": None},
        ]:
            with self.subTest(obj=obj):
                with tempfile.TemporaryDirectory() as tmp:
                    candidate = Path(tmp) / "fake.json"
                    candidate.write_text(json.dumps(obj), encoding="utf-8")
                    self.assert_rejected(lambda: san.load_report(candidate))

    def test_o04_invalid_numeric_fields_fail_closed(self):
        for bad_conf in [True, -1, 1.5, "100"]:
            with self.subTest(bad_conf=bad_conf):
                finding = {"type": "synthetic", "confidence": bad_conf}
                self.assert_rejected(
                    lambda: san.build_events(fake_report([finding]), FILE_ID, "object", True)
                )
        self.assert_rejected(
            lambda: san.build_events(fake_report([], {"files_processed": -1}), FILE_ID, "object", True)
        )

    def test_o05_truncated_json_rejected_without_emitting_event(self):
        with tempfile.TemporaryDirectory() as tmp:
            report = Path(tmp) / "truncated.json"
            events = Path(tmp) / "events.jsonl"
            report.write_text('{"results":[', encoding="utf-8")
            self.assert_rejected(lambda: san.load_report(report))
            self.assertFalse(events.exists())

    def test_o06_two_scans_have_independent_identifiers(self):
        first = san.build_events(fake_report(), FILE_ID, "object", True)[0]
        second = san.build_events(fake_report(), FILE_ID, "object", True)[0]
        self.assertNotEqual(first["scan_id"], second["scan_id"])
        self.assertEqual(first["schema_version"], second["schema_version"])

    def test_o07_compatibility_version_is_stable_pending_wazuh_review(self):
        # source_version representa protocolo upstream 2.4.3 nesta revisao;
        # provenance do build v5 e gate separado, nao falsamente aprovado.
        events = san.build_events(fake_report(), FILE_ID, "object", True)
        self.assertEqual(events[0]["source_version"], "2.4.3")
        self.assertNotIn("source_build", events[0])

    def test_non_finite_and_huge_duration_rejected(self):
        for duration in [float("nan"), float("inf"), float("-inf"), 10**400]:
            with self.subTest(repr=repr(duration)[:28]):
                self.assert_rejected(
                    lambda: san.build_events(
                        fake_report([], {"duration_seconds": duration}), FILE_ID, "object", True
                    )
                )

    def test_jsonl_is_allowlist_only_and_private(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "synthetic-events.jsonl"
            events = san.build_events(fake_report(), FILE_ID, "object", True)
            san.append_jsonl(path, events)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["event_type"], "dlp_scan_summary")

    def test_reject_invalid_file_id(self):
        self.assert_rejected(lambda: san.build_events(fake_report(), "not-sha256", "object", True))


class FerretBashCleanupOffline(unittest.TestCase):
    def test_processor_bash_syntax(self):
        subprocess.run(["bash", "-n", str(PROCESSOR)], check=True, capture_output=True, text=True)

    def test_real_cleanup_function_removes_fake_tmp_files(self):
        # Extrai SOMENTE uma funcao de limpeza do script real; nao o executa.
        text = PROCESSOR.read_text(encoding="utf-8")
        match = re.search(r"(?ms)^cleanup_active_temp_files\(\) \{\n.*?^\}\n", text)
        self.assertIsNotNone(match)
        with tempfile.TemporaryDirectory() as root:
            a, b = Path(root) / "out.tmp", Path(root) / "err.tmp"
            a.write_text(FAKE_SENTINEL, encoding="utf-8")
            b.write_text("erro sintetico", encoding="utf-8")
            code = (
                "set -euo pipefail\n"
                "ACTIVE_TEMP_FILES=(" + shlex.quote(str(a)) + " " + shlex.quote(str(b)) + ")\n"
                + match.group(0)
                + "\ncleanup_active_temp_files\n"
                + "[[ ! -e " + shlex.quote(str(a)) + " && ! -e " + shlex.quote(str(b)) + " ]]\n"
            )
            subprocess.run(["bash", "-c", code], check=True, capture_output=True, text=True)
            self.assertFalse(a.exists())
            self.assertFalse(b.exists())

    def test_json_validation_explicitly_guards_cleanup(self):
        processor = PROCESSOR.read_text(encoding="utf-8")
        self.assertIn('if ! python3 - "$raw_tmp" <<\'PY\'', processor)
        self.assertIn('echo "ERRO: stdout do Ferret não é JSON válido."', processor)
        self.assertIn("trap cleanup_all EXIT", processor)


if __name__ == "__main__":
    unittest.main()
