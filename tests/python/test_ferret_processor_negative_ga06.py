#!/usr/bin/env python3
"""GA-06: fluxo NEGATIVO real de process_one com Docker/sudo simulados.

Executa o corpo da funcao de producao em bash com dependencias mockadas.
Nao executa o preambulo de producao (PREP, sudo, Docker, volumes reais).
Todos os paths, uploads, saidas e temporarios ficam em TemporaryDirectory.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]
PROCESSOR = REPO / "scripts/dlp/processar_inbox_ferret.sh"
HASH = "a" * 64


def function_from_script(contents: str, name: str) -> str:
    pattern = rf"(?ms)^{re.escape(name)}\(\) \{{\n.*?^\}}\n"
    match = re.search(pattern, contents)
    if match is None:
        raise AssertionError(f"Funcao {name} ausente ou modificada")
    return match.group(0)


class ProcessorNegativeOffline(unittest.TestCase):
    def run_case(self, *, stdout: str, scan_rc: int = 0, expected_error: str):
        contents = PROCESSOR.read_text(encoding="utf-8")
        pieces = [
            function_from_script(contents, name)
            for name in ("cleanup_active_temp_files", "cleanup_active_snapshots",
                         "cleanup_all", "process_one")
        ]
        with tempfile.TemporaryDirectory(prefix="ga06-negative-") as workspace:
            root = Path(workspace)
            for folder in ("tmp", "inbox", "state/incoming", "reports/raw", "events"):
                (root / folder).mkdir(parents=True, exist_ok=True)
            fake_file = root / "inbox/fixture.txt"
            fake_file.write_text("fixture sintética sem credenciais", encoding="utf-8")

            def q(value: object) -> str:
                return shlex.quote(str(value))

            # Recusa qualquer execucao de comandos reais nao previstos no mock.
            # as_ferret e sudo sao FUNCOES Bash locais no subprocesso de testes.
            setup = f"""set -euo pipefail
umask 077
export TMPDIR={q(root / 'tmp')}
INBOX={q(root / 'inbox')}
STAGING={q(root / 'state/incoming')}
RAW_DIR={q(root / 'reports/raw')}
EVENTS_FILE={q(root / 'events/dlp.jsonl')}
LEDGER_FILE={q(root / 'state/processed.sha256')}
RUN_LEDGER_FILE={q(root / 'state/processed-runs.tsv')}
CONFIG={q(root / 'fixture-ferret.yaml')}
SUPPRESSIONS={q(root / 'fixture-suppressions.yaml')}
SNAPSHOTTER={q(root / 'mock-snapshotter.py')}
SANITIZER={q(root / 'mock-sanitizer.py')}
FERRET_UID=1000
FERRET_SCAN_MEMORY_LIMIT=1280m
FERRET_SCAN_CPU_LIMIT=2.00
FORCE=0
IMAGE='fixture/ferret:never-pull'
ACTIVE_SNAPSHOTS=()
ACTIVE_TEMP_FILES=()
MOCK_STDOUT={q(stdout)}
MOCK_SCAN_RC={scan_rc}

as_ferret() {{
  if [[ "${{1:-}}" == python3 ]]; then
    [[ "${{2:-}}" == "$SNAPSHOTTER" ]] || return 97
    [[ "$snapshot_path" == "$STAGING"/.snapshot-* ]] || return 97
    : > "$snapshot_path"
    printf '{HASH}\\n'
    return 0
  fi
  case "${{1:-}}" in
    test|grep|rm|stat|touch|chmod) "$@" ;;
    *) printf 'MOCK_UNEXPECTED_AS_FERRET=1\\n' >&2; return 97 ;;
  esac
}}

docker() {{
  [[ "${{1:-}}" == run ]] || return 97
  printf '%s' "$MOCK_STDOUT"
  printf 'erro fictício controlado\\n' >&2
  return "$MOCK_SCAN_RC"
}}

sudo() {{
  printf 'MOCK_SUDO_REACHED=1\\n' >&2
  return 97
}}
"""
            # O processador e chamado em contexto condicional igual ao original.
            # Sem mock de sudo com permissao real, nao ha efeito institucional.
            run = """
trap cleanup_all EXIT
if process_one "$INBOX/fixture.txt"; then
  echo 'MOCK_UNEXPECTED_SUCCESS=1' >&2
  exit 88
fi
echo 'EXPECTED_FAILURE=PASS'
"""
            shell = setup + "\n".join(pieces) + "\n" + run
            env = {
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                "HOME": str(root),
                "TMPDIR": str(root / "tmp"),
                "LC_ALL": "C.UTF-8",
            }
            p = subprocess.run(
                ["bash", "-c", shell], cwd=root, env=env,
                capture_output=True, text=True, timeout=12, check=False
            )
            self.assertEqual(p.returncode, 0, f"stdout={p.stdout}\nstderr={p.stderr}")
            self.assertIn("EXPECTED_FAILURE=PASS", p.stdout)
            self.assertIn(expected_error, p.stderr)
            self.assertNotIn("MOCK_UNEXPECTED_AS_FERRET", p.stderr)
            self.assertNotIn("MOCK_UNEXPECTED_SUCCESS", p.stderr)
            self.assertEqual(list((root / "tmp").iterdir()), [], "Temporarios brutos nao limpos")
            self.assertEqual(list((root / "state/incoming").iterdir()), [], "Snapshot nao limpo")
            self.assertEqual(list((root / "reports/raw").iterdir()), [], "Raw nao deveria existir")
            self.assertEqual(list((root / "events").iterdir()), [], "Evento SIEM nao deveria existir")
            self.assertFalse((root / "state/processed.sha256").exists(), "Ledger falso")
            self.assertFalse((root / "state/processed-runs.tsv").exists(), "Run ledger falso")

    def test_scanner_nonzero_fails_closed(self):
        self.run_case(stdout='{"results":[],"stats":{}}',
                      scan_rc=13, expected_error="Ferret falhou")

    def test_scanner_invalid_json_fails_closed(self):
        self.run_case(stdout='{"results": [', expected_error="JSON válido")

    def test_scanner_invalid_schema_fails_closed(self):
        self.run_case(stdout='{"results":[]}', expected_error="JSON válido")

    def test_sudo_install_failure_fails_closed(self):
        self.run_case(stdout='{"results":[],"stats":{}}',
                      expected_error="nao foi possivel instalar relatorio bruto")


if __name__ == "__main__":
    unittest.main()
