#!/usr/bin/env python3
"""Validate historical Phase 3 kit *source*; never invoke a VM or bootstrap.

Requires a full local Git checkout in CI to resolve the immutable PIN.
"""
from __future__ import annotations

import pathlib
import re
import subprocess
import unittest

KIT = pathlib.Path(__file__).resolve().parents[1]
REPO = KIT.parents[1]
BOOTSTRAP = KIT / "bootstrap.sh"
FILES = frozenset({
    "lib/ce-common.sh",
    "ep125/ce-ep125.sh",
    "ep125/QUEUE.md",
    "ep126/ce-ep126.sh",
    "ep126/QUEUE.md",
    "README.md",
    "opensuse/ce-client.sh",
    "tests/smoke.sh",
})


def parse_manifest(src: str) -> tuple[str, dict[str, str]]:
    pin_matches = re.findall(r'(?m)^PIN="([a-f0-9]{40})"$', src)
    if len(pin_matches) != 1:
        raise ValueError("PIN_INVALID_OR_MULTIPLE")
    token = "done <<'MANIFEST'\n"
    if src.count(token) != 1:
        raise ValueError("MANIFEST_HEREDOC_MISSING_OR_MULTIPLE")
    lines = src.split(token, 1)[1].split("\nMANIFEST", 1)
    if len(lines) != 2:
        raise ValueError("MANIFEST_END_MISSING")
    entries: dict[str, str] = {}
    for row in lines[0].splitlines():
        match = re.fullmatch(r"([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*) ([a-f0-9]{40})", row)
        if match is None:
            raise ValueError("MANIFEST_ROW_INVALID")
        name, sha = match.groups()
        if name in entries or any(part in (".", "..") for part in name.split("/")):
            raise ValueError("MANIFEST_DUPLICATE_OR_TRAVERSAL")
        entries[name] = sha
    if set(entries) != FILES:
        raise ValueError("MANIFEST_FILE_SET_CHANGED")
    return pin_matches[0], entries


def git_blob_at_pin(pin: str, filename: str) -> bytes:
    checked = subprocess.run(
        ["git", "-C", str(REPO), "show", f"{pin}:ops/fase3/{filename}"],
        capture_output=True, check=True, timeout=12,
    )
    return checked.stdout


def git_hash(payload: bytes) -> str:
    checked = subprocess.run(
        ["git", "-C", str(REPO), "hash-object", "--stdin"],
        input=payload, capture_output=True, check=True, timeout=12,
    )
    return checked.stdout.decode("ascii").strip()


class Phase3BootstrapSourceContract(unittest.TestCase):
    def test_manifest_matches_exact_pinned_git_objects(self):
        pin, entries = parse_manifest(BOOTSTRAP.read_text(encoding="utf-8"))
        for filename, sha in entries.items():
            with self.subTest(filename=filename):
                frozen = git_blob_at_pin(pin, filename)
                current = (KIT / filename).read_bytes()
                self.assertEqual(git_hash(frozen), sha, "incorrect pinned Git blob SHA")
                self.assertEqual(current, frozen, "branch content drifted from PIN")

    def test_rejects_tampered_sha_in_memory(self):
        raw = BOOTSTRAP.read_text(encoding="utf-8")
        pin, entries = parse_manifest(raw)
        original = entries["tests/smoke.sh"]
        corrupted = raw.replace(
            f"tests/smoke.sh {original}",
            "tests/smoke.sh " + ("0" * 40),
            1,
        )
        _, test_entries = parse_manifest(corrupted)
        self.assertNotEqual(git_hash(git_blob_at_pin(pin, "tests/smoke.sh")),
                            test_entries["tests/smoke.sh"])

    def test_rejects_duplicate_or_traversal(self):
        src = BOOTSTRAP.read_text(encoding="utf-8")
        pin, entries = parse_manifest(src)
        self.assertEqual(len(pin), 40)
        tampered = src.replace("tests/smoke.sh " + entries["tests/smoke.sh"],
                               "../tests/smoke.sh " + entries["tests/smoke.sh"], 1)
        with self.assertRaises(ValueError):
            parse_manifest(tampered)
        doubled = src.replace("MANIFEST\n", "README.md " + entries["README.md"] + "\nMANIFEST\n", 1)
        with self.assertRaises(ValueError):
            parse_manifest(doubled)

    def test_shell_syntax_only(self):
        for path in [BOOTSTRAP, KIT / "lib/ce-common.sh",
                     KIT / "ep125/ce-ep125.sh", KIT / "ep126/ce-ep126.sh",
                     KIT / "opensuse/ce-client.sh", KIT / "tests/smoke.sh"]:
            with self.subTest(filename=str(path)):
                subprocess.run(["bash", "-n", str(path)], check=True, timeout=8)

    def test_bootstrap_failure_closed_before_download_on_wrong_hostname(self):
        # The Github-hosted runner is not an institutional VM. No HTTP call is made.
        text = BOOTSTRAP.read_text(encoding="utf-8")
        self.assertLess(text.index('[[ "$(hostname -s)" == "$EXPECTED_HOST" ]]'),
                        text.index('STAGING="$(mktemp'))
        self.assertIn('git hash-object "$STAGING/$FILE"', text)
        self.assertIn('if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then', text)
        self.assertIn("curl --fail --location --silent --show-error --proto '=https' --tlsv1.2", text)

    def test_smoke_guards_do_not_start_services(self):
        smoke = (KIT / "tests/smoke.sh").read_text(encoding="utf-8")
        self.assertIn("apply deploy restart rollback merge", smoke)
        self.assertIn("FALHA_SEGURANCA=GUARDA_HOST_EP125", smoke)
        self.assertIn("FALHA_SEGURANCA=GUARDA_HOST_EP126", smoke)
        lib = (KIT / "lib/ce-common.sh").read_text(encoding="utf-8")
        # Intentional historical limitation: local TLS probes do NOT validate peers.
        self.assertIn("--insecure", lib)
        self.assertIn("TLS_CONFIANCA=NAO_VALIDADA_NESTE_SMOKE", lib)


if __name__ == "__main__":
    unittest.main()
