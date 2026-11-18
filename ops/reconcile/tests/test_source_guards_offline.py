#!/usr/bin/env python3
"""Source-level fail-closed checks for CE-RC01/02/04, no VM access."""
from __future__ import annotations

import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
RC01 = ROOT / "ops/reconcile/ce-rc01.sh"
RC02 = ROOT / "ops/reconcile/ce-rc02.sh"
RC04 = ROOT / "ops/reconcile/ce-rc04.py"


class ReconcileSourceOnlyTests(unittest.TestCase):
    def test_shell_syntax_and_python_compilation(self):
        for file in (RC01, RC02):
            with self.subTest(file=file.name):
                subprocess.run(["bash", "-n", str(file)], check=True, timeout=8)
        source = RC04.read_text(encoding="utf-8")
        compile(source, str(RC04), "exec")

    def test_wrong_hostname_blocks_bash_before_git_or_docker(self):
        with tempfile.TemporaryDirectory() as temp:
            bin_dir = Path(temp)
            spy = bin_dir / "called.txt"
            for command in ("hostname", "git", "docker", "systemctl"):
                executable = bin_dir / command
                if command == "hostname":
                    executable.write_text("#!/bin/sh\nprintf 'ci-wrong-host\\n'\n")
                else:
                    executable.write_text("#!/bin/sh\nprintf called >> " + str(spy) + "\nexit 77\n")
                executable.chmod(0o700)
            env = {**os.environ, "PATH": str(bin_dir) + ":" + os.environ["PATH"]}
            for cmd in (["bash", str(RC01), "EP125"], ["bash", str(RC01), "EP126"],
                        ["bash", str(RC02)]):
                with self.subTest(cmd=cmd):
                    proc = subprocess.run(cmd, env=env, text=True,
                                          capture_output=True, timeout=8, check=False)
                    self.assertNotEqual(proc.returncode, 0)
                    self.assertIn("ABORTADO_HOST", proc.stderr)
            self.assertFalse(spy.exists(), "A wrong host must not access Git/Docker")

    def test_rc04_wrong_hostname_fails_before_git(self):
        with patch("socket.gethostname", return_value="ci-wrong-host"), \
             patch("subprocess.run", side_effect=AssertionError("Git call forbidden")):
            with self.assertRaises(SystemExit) as result:
                runpy.run_path(str(RC04), run_name="__main__")
            self.assertIn("ABORTADO_HOST_FORA_ESCOPO", str(result.exception))

    def test_rc01_never_prints_tracked_file_paths(self):
        code = RC01.read_text(encoding="utf-8")
        self.assertIn("NOMES_TRACKED_NAO_PUBLICADOS=SIM", code)
        self.assertIn("ALTERACOES_CATEGORIA[%s]", code)
        self.assertIn("GIT_OPTIONAL_LOCKS=0", code)
        self.assertNotIn("ALTERADO_%03d", code)
        self.assertNotIn('printf \'ALTERADO_%03d=%s', code)
        self.assertIn("--no-ext-diff", code)

    def test_historical_main_sha_labeled_as_not_current(self):
        code = RC01.read_text(encoding="utf-8")
        self.assertIn("BASELINE_MAIN_VERIFICADA_2026-11-08=", code)
        self.assertIn("SHA_REMOTE_ESTATICA", code)
        self.assertIn("nao representa necessariamente HEAD atual", code)

    def test_rc02_names_hidden_and_inspect_template_limited(self):
        code = RC02.read_text(encoding="utf-8")
        self.assertIn("ARQUIVOS_NOMES_PRIVADOS=NAO_EXIBIDOS", code)
        self.assertIn("docker inspect --format", code)
        self.assertNotIn("docker inspect --format '{{json", code)
        self.assertNotIn("docker exec", code)

    def test_rc04_only_hashes_not_raw_content(self):
        code = RC04.read_text(encoding="utf-8")
        self.assertIn("hash-object", code)
        self.assertIn("GIT_OPTIONAL_LOCKS", code)
        self.assertIn("SEGREDOS_EXIBIDOS=NAO", code)
        self.assertNotIn("git reset", code)
        self.assertNotIn("docker compose", code)
        self.assertNotIn("docker exec", code)


if __name__ == "__main__":
    unittest.main()
