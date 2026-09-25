#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import subprocess
from collections import defaultdict
from pathlib import Path

SAFE_CAP_ADD = {
    "CHOWN",
    "DAC_OVERRIDE",
    "FOWNER",
    "SETGID",
    "SETUID",
}

HOST_NETWORK_ALLOWLIST = {
    ("deploy/interna/twingate/compose.yml", "connector"),
}

REQUIRED_NNP = {
    ("deploy/dmz/compose.yml", "php"),
    ("deploy/dmz/compose.yml", "nginx"),
    ("deploy/dmz/compose.waf.yml", "waf"),
    ("deploy/interna/openbao/compose.yml", "openbao"),
    ("deploy/interna/bacula/compose.bacularis-readonly.yml", "bacularis"),
    ("deploy/interna/mariadb/compose.phpmyadmin.yml", "phpmyadmin"),
    ("deploy/interna/mariadb/compose.runtime-hardening.yml", "mariadb"),
    ("deploy/interna/ferret/compose.yml", "ferret"),
    ("deploy/interna/twingate/compose.yml", "connector"),
    ("deploy/interna/wazuh/compose.host.yml", "wazuh.manager"),
    ("deploy/interna/wazuh/compose.host.yml", "wazuh.indexer"),
    ("deploy/interna/wazuh/compose.host.yml", "wazuh.dashboard"),
}

REQUIRED_CAP_DROP_ALL = {
    ("deploy/interna/openbao/compose.yml", "openbao"),
    ("deploy/interna/bacula/compose.bacularis-readonly.yml", "bacularis"),
    ("deploy/interna/mariadb/compose.phpmyadmin.yml", "phpmyadmin"),
    ("deploy/interna/mariadb/compose.runtime-hardening.yml", "mariadb"),
    ("deploy/interna/ferret/compose.yml", "ferret"),
    ("deploy/interna/wazuh/compose.host.yml", "wazuh.indexer"),
    ("deploy/interna/wazuh/compose.host.yml", "wazuh.dashboard"),
}

ADMIN_PORT_CONTRACTS = {
    ("deploy/interna/openbao/compose.yml", "openbao"): {
        "127.0.0.1:18200:8200",
    },
    ("deploy/interna/bacula/compose.bacularis-readonly.yml", "bacularis"): {
        "127.0.0.1:9097:9097",
    },
    ("deploy/interna/mariadb/compose.phpmyadmin.yml", "phpmyadmin"): {
        "127.0.0.1:9443:8443",
    },
    ("deploy/interna/ferret/compose.yml", "ferret"): {
        "${FERRET_BIND_ADDRESS:-127.0.0.1}:${FERRET_WEB_PORT:-18082}:8080",
    },
    ("deploy/interna/wazuh/compose.lab.yml", "wazuh.dashboard"): {
        "127.0.0.1:8443:5601",
    },
    ("deploy/lab/mailpit/compose.yml", "mailpit"): {
        "127.0.0.1:11025:1025",
        "127.0.0.1:18025:8025",
    },
}

FAIL_CLOSED_BIND_MARKERS = {
    "deploy/dmz/compose.host.yml": {
        "CONECTAEDUCA_WAF_BIND_ADDRESS:?defina CONECTAEDUCA_WAF_BIND_ADDRESS",
    },
    "deploy/interna/mariadb/compose.host.yml": {
        "CONECTAEDUCA_DB_BIND_ADDRESS:?defina CONECTAEDUCA_DB_BIND_ADDRESS",
    },
    "deploy/interna/wazuh/compose.host.yml": {
        "CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS:?defina CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS",
        "CONECTAEDUCA_WAZUH_DASHBOARD_BIND_ADDRESS:?defina CONECTAEDUCA_WAZUH_DASHBOARD_BIND_ADDRESS",
    },
}

LIST_KEYS = {"cap_add", "cap_drop", "security_opt", "ports"}
SERVICE_RE = re.compile(r"^  ([A-Za-z0-9_.-]+):(?:\s*(?:#.*)?)?$")
KEY_RE = re.compile(r"^(\s+)([A-Za-z0-9_.-]+):(?:\s*(.*))?$")
TRUE_RE = re.compile(r"^(?:true|['\"]true['\"])$", re.IGNORECASE)


def strip_item(value: str) -> str:
    value = value.strip()
    if value.startswith("-"):
        value = value[1:].strip()
    if (
        len(value) >= 2
        and value[0] == value[-1]
        and value[0] in {"'", '"'}
    ):
        value = value[1:-1]
    return value.strip()


def parse_services(text: str) -> dict[str, dict[str, object]]:
    services: dict[str, dict[str, object]] = defaultdict(
        lambda: {
            "cap_add": [],
            "cap_drop": [],
            "security_opt": [],
            "ports": [],
            "network_mode": None,
            "privileged": None,
        }
    )

    in_services = False
    current_service: str | None = None
    current_list: str | None = None
    list_indent = -1

    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue

        indent = len(raw) - len(raw.lstrip(" "))
        stripped = raw.strip()

        if indent == 0:
            in_services = stripped == "services:"
            current_service = None
            current_list = None
            continue

        if not in_services:
            continue

        sm = SERVICE_RE.match(raw)
        if sm:
            current_service = sm.group(1)
            current_list = None
            services[current_service]
            continue

        if current_service is None:
            continue

        if current_list is not None and indent <= list_indent:
            current_list = None

        if current_list is not None and indent > list_indent and stripped.startswith("-"):
            services[current_service][current_list].append(strip_item(stripped))
            continue

        km = KEY_RE.match(raw)
        if not km:
            continue

        key = km.group(2)
        value = (km.group(3) or "").strip()

        if key in LIST_KEYS:
            current_list = key
            list_indent = indent
            # Inline [] / !override [] intentionally yields an empty list here.
            continue

        if key == "network_mode":
            services[current_service]["network_mode"] = strip_item(value)
        elif key == "privileged":
            services[current_service]["privileged"] = strip_item(value)

    return dict(services)


def analyze_content(rel: str, text: str) -> list[str]:
    failures: list[str] = []
    services = parse_services(text)

    for line_no, raw in enumerate(text.splitlines(), 1):
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue

        if "/var/run/docker.sock" in stripped or "/run/docker.sock" in stripped:
            failures.append(f"{rel}:{line_no}: Docker socket mount/reference forbidden")

        if "0.0.0.0:" in stripped or ":-0.0.0.0" in stripped:
            failures.append(f"{rel}:{line_no}: wildcard bind 0.0.0.0 forbidden")

    for service, props in services.items():
        identity = (rel, service)

        privileged = str(props["privileged"] or "")
        if privileged and TRUE_RE.fullmatch(privileged):
            failures.append(f"{rel}:{service}: privileged:true forbidden")

        network_mode = str(props["network_mode"] or "")
        if network_mode == "host" and identity not in HOST_NETWORK_ALLOWLIST:
            failures.append(
                f"{rel}:{service}: network_mode:host not in explicit allowlist"
            )

        cap_add = {str(x).upper() for x in props["cap_add"]}
        unexpected = sorted(cap_add - SAFE_CAP_ADD)
        if unexpected:
            failures.append(
                f"{rel}:{service}: unexpected cap_add={','.join(unexpected)}"
            )

        if cap_add and "ALL" not in {str(x).upper() for x in props["cap_drop"]}:
            failures.append(
                f"{rel}:{service}: cap_add requires cap_drop:ALL baseline"
            )

        if identity in REQUIRED_NNP:
            opts = {str(x).lower() for x in props["security_opt"]}
            if "no-new-privileges:true" not in opts:
                failures.append(
                    f"{rel}:{service}: required no-new-privileges:true missing"
                )

        if identity in REQUIRED_CAP_DROP_ALL:
            drops = {str(x).upper() for x in props["cap_drop"]}
            if "ALL" not in drops:
                failures.append(f"{rel}:{service}: required cap_drop:ALL missing")

        expected_ports = ADMIN_PORT_CONTRACTS.get(identity)
        if expected_ports is not None:
            actual = {str(x) for x in props["ports"]}
            missing = sorted(expected_ports - actual)
            extras = sorted(actual - expected_ports)
            if missing:
                failures.append(
                    f"{rel}:{service}: admin loopback port contract missing={missing}"
                )
            if extras:
                failures.append(
                    f"{rel}:{service}: unexpected published admin ports={extras}"
                )

    for marker in FAIL_CLOSED_BIND_MARKERS.get(rel, set()):
        if marker not in text:
            failures.append(f"{rel}: fail-closed bind marker missing: {marker}")

    return failures


def tracked_compose_files(root: Path) -> list[Path]:
    raw = subprocess.check_output(
        [
            "git",
            "-C",
            str(root),
            "ls-files",
            "-z",
            "deploy/**/compose*.yml",
            "deploy/**/compose*.yaml",
        ]
    )
    return [
        root / item.decode()
        for item in raw.split(b"\0")
        if item
    ]


def self_test() -> int:
    bad = """services:
  bad:
    privileged: true
    network_mode: host
    cap_add:
      - SYS_ADMIN
    ports:
      - "0.0.0.0:9999:9999"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
"""
    failures = analyze_content("deploy/test/compose.yml", bad)
    required_fragments = {
        "privileged:true forbidden",
        "network_mode:host not in explicit allowlist",
        "unexpected cap_add=SYS_ADMIN",
        "cap_add requires cap_drop:ALL baseline",
        "wildcard bind 0.0.0.0 forbidden",
        "Docker socket mount/reference forbidden",
    }
    for fragment in required_fragments:
        if not any(fragment in item for item in failures):
            raise SystemExit(f"SELFTEST FAIL: detector missing {fragment}")

    allowed = """services:
  connector:
    network_mode: host
    security_opt:
      - no-new-privileges:true
"""
    if analyze_content("deploy/interna/twingate/compose.yml", allowed):
        raise SystemExit("SELFTEST FAIL: Twingate host-network allowlist rejected")

    print("COMPOSE_SECURITY_INVARIANTS_SELFTEST=PASS")
    return 0


def scan_repo() -> int:
    root = Path(
        subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            text=True,
        ).strip()
    )
    files = tracked_compose_files(root)
    failures: list[str] = []
    services_count = 0

    for path in files:
        rel = path.relative_to(root).as_posix()
        text = path.read_text(encoding="utf-8")
        services_count += len(parse_services(text))
        failures.extend(analyze_content(rel, text))

    # Contracts must refer to real service/file pairs, otherwise a renamed/deleted
    # baseline could silently weaken the test.
    observed = set()
    for path in files:
        rel = path.relative_to(root).as_posix()
        for service in parse_services(path.read_text(encoding="utf-8")):
            observed.add((rel, service))

    for identity in sorted(
        REQUIRED_NNP
        | REQUIRED_CAP_DROP_ALL
        | set(ADMIN_PORT_CONTRACTS)
        | HOST_NETWORK_ALLOWLIST
    ):
        if identity not in observed:
            failures.append(
                f"{identity[0]}:{identity[1]}: security contract points to missing service"
            )

    for rel in FAIL_CLOSED_BIND_MARKERS:
        if not (root / rel).is_file():
            failures.append(f"{rel}: fail-closed bind contract points to missing file")

    if failures:
        for item in sorted(set(failures)):
            print(f"FALHA       {item}")
        print(f"COMPOSE_SECURITY_INVARIANTS=BLOCK failures={len(set(failures))}")
        return 1

    print(
        "COMPOSE_SECURITY_INVARIANTS=PASS "
        f"files={len(files)} services={services_count}"
    )
    print("PRIVILEGED_TRUE=0")
    print("DOCKER_SOCKET_REFERENCES=0")
    print("UNAPPROVED_HOST_NETWORK=0")
    print("UNEXPECTED_CAP_ADD=0")
    print("ADMIN_PORT_CONTRACTS=PASS")
    print("NO_NEW_PRIVILEGES_CONTRACTS=PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    return self_test() if args.self_test else scan_repo()


if __name__ == "__main__":
    raise SystemExit(main())
