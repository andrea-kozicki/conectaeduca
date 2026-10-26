#!/usr/bin/env python3
"""PA-03: fixtures de bypass do gate Compose, sem Docker/VM/containers."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "scripts/evidencias/checkpoint_compose_security_invariants.py"
SPEC = importlib.util.spec_from_file_location("pa03_compose_gate", TOOL)
assert SPEC and SPEC.loader
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


def compose(fragment: str) -> str:
    return "services:\n  service:\n" + "".join(
        "    " + line + "\n" for line in fragment.splitlines()
    )


class PA03ComposeInlineNegativeTests(unittest.TestCase):
    def reject(self, fragment: str, needle: str) -> None:
        failures = gate.analyze_content("deploy/lab/compose.yml", compose(fragment))
        self.assertTrue(
            any(needle in item for item in failures),
            "expected a security finding, not silent parsing: " + repr(failures),
        )

    def accept(self, fragment: str) -> None:
        self.assertEqual(
            [], gate.analyze_content("deploy/lab/compose.yml", compose(fragment))
        )

    def test_01_inline_privileged_capability_is_rejected(self):
        self.reject("cap_add: [SYS_ADMIN]", "unsupported inline")

    def test_02_inline_even_allowlisted_cap_is_not_silently_ignored(self):
        self.reject("cap_add: [CHOWN]", "unsupported inline")

    def test_03_inline_cap_drop_all_is_not_false_proof(self):
        self.reject("cap_drop: [ALL]", "unsupported inline")

    def test_04_inline_security_opt_is_not_silently_ignored(self):
        self.reject('security_opt: ["no-new-privileges:true"]', "unsupported inline")

    def test_05_inline_loopback_port_is_not_silently_ignored(self):
        self.reject('ports: ["127.0.0.1:19888:8080"]', "unsupported inline")

    def test_06_inline_wildcard_port_is_rejected(self):
        self.reject('ports: ["0.0.0.0:19888:8080"]', "wildcard bind")

    def test_07_tagged_inline_nonempty_array_is_rejected(self):
        self.reject('ports: !override ["19888:8080"]', "unsupported inline")

    def test_08_reset_with_nonempty_cap_drop_is_rejected(self):
        self.reject('cap_drop: !reset [ALL]', "unsupported inline")

    def test_09_malformed_scalar_security_list_is_rejected(self):
        self.reject("security_opt: no-new-privileges:true", "unsupported inline")

    def test_10_empty_reset_list_is_allowed(self):
        self.accept("ports: !reset []")

    def test_11_empty_override_list_is_allowed(self):
        self.accept("ports: !override []")

    def test_12_multiline_override_is_allowed(self):
        self.accept('ports: !override\n  - "127.0.0.1:19888:8080"')

    def test_13_multiline_capabilities_still_checked(self):
        self.reject("cap_add:\n  - SYS_ADMIN", "unexpected cap_add=SYS_ADMIN")

    def test_14_regular_docker_socket_reference_still_checked(self):
        self.reject(
            "volumes:\n  - /var/run/docker.sock:/var/run/docker.sock",
            "Docker socket mount/reference forbidden",
        )

    def test_15_privileged_still_rejected(self):
        self.reject("privileged: true", "privileged:true forbidden")

    def test_16_rejected_values_must_not_become_authorized_caps(self):
        data = gate.parse_services(compose("cap_add: [SYS_ADMIN]"))
        self.assertIn("cap_add", data["service"]["invalid_inline_lists"])
        self.assertEqual([], data["service"]["cap_add"])

    def test_17_original_multiline_cap_drop_allowed_without_side_effects(self):
        self.accept("cap_drop:\n  - ALL\nsecurity_opt:\n  - no-new-privileges:true")


if __name__ == "__main__":
    unittest.main()
