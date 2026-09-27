#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shlex
import socket
import subprocess
import sys

from ops01_ep126_readonly import (
    exact_receiver_block_count,
    has_exact_udp_listener,
    read_topology,
    valid_ipv4,
)

EXPECTED_HOSTS = {"ep126-pucpr", "conectaeduca-interna"}
DEFAULT_WINDOW_MINUTES = 30
UTC = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%SZ")


def run(cmd: list[str], timeout: int = 20) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(
            cmd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return 127, "", f"{type(exc).__name__}: {exc}"
    return proc.returncode, proc.stdout.rstrip(), proc.stderr.rstrip()


def secure_write_new(path: Path, data: str) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    flags |= getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags, 0o600)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            fd = -1
            handle.write(data)
    finally:
        if fd >= 0:
            os.close(fd)


def parse_timestamp(value: object) -> dt.datetime | None:
    if not isinstance(value, str) or not value:
        return None
    normalized = value.replace("Z", "+00:00")
    try:
        parsed = dt.datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def safe_event_metadata(
    record: dict,
    *,
    marker: str,
    pfsense_ip: str,
) -> dict[str, object]:
    full_log = str(record.get("full_log", ""))
    serialized = json.dumps(record, sort_keys=True, ensure_ascii=False)
    rule = record.get("rule") if isinstance(record.get("rule"), dict) else {}
    decoder = (
        record.get("decoder")
        if isinstance(record.get("decoder"), dict)
        else {}
    )
    predecoder = (
        record.get("predecoder")
        if isinstance(record.get("predecoder"), dict)
        else {}
    )
    location = str(record.get("location", ""))
    decoder_name = str(decoder.get("name", ""))
    program_name = str(predecoder.get("program_name", ""))

    marker_match = bool(marker and marker in serialized)
    pfsense_hint = any(
        (
            bool(pfsense_ip and pfsense_ip in serialized),
            "pfsense" in decoder_name.lower(),
            "filterlog" in full_log.lower(),
            "dpinger" in full_log.lower(),
            "unbound" in full_log.lower(),
            "filterlog" in program_name.lower(),
            "dpinger" in program_name.lower(),
            "unbound" in program_name.lower(),
        )
    )

    return {
        "timestamp": str(record.get("timestamp", "")),
        "rule_id": str(rule.get("id", "")),
        "rule_level": str(rule.get("level", "")),
        "decoder": decoder_name,
        "program_name": program_name,
        "location": location,
        "marker_match": marker_match,
        "pfsense_hint": pfsense_hint,
        "full_log_sha256": hashlib.sha256(
            full_log.encode("utf-8", errors="replace")
        ).hexdigest(),
    }


def analyze_json_lines(
    text: str,
    *,
    cutoff: dt.datetime,
    marker: str,
    pfsense_ip: str,
) -> tuple[list[dict[str, object]], int]:
    selected: list[dict[str, object]] = []
    parse_errors = 0

    for raw in text.splitlines():
        if not raw.strip():
            continue
        try:
            record = json.loads(raw)
        except json.JSONDecodeError:
            parse_errors += 1
            continue
        if not isinstance(record, dict):
            continue

        timestamp = parse_timestamp(record.get("timestamp"))
        if timestamp is None or timestamp < cutoff:
            continue

        metadata = safe_event_metadata(
            record,
            marker=marker,
            pfsense_ip=pfsense_ip,
        )
        if metadata["marker_match"] or metadata["pfsense_hint"]:
            selected.append(metadata)

    return selected, parse_errors


def docker_prefix() -> list[str] | None:
    for prefix in (["docker"], ["sudo", "-n", "docker"]):
        rc, out, _ = run(
            prefix + ["version", "--format", "{{.Server.Version}}"],
            timeout=8,
        )
        if rc == 0 and out.strip():
            return prefix
    return None


def docker_run(
    prefix: list[str],
    args: list[str],
    timeout: int = 20,
) -> tuple[int, str, str]:
    return run(prefix + args, timeout=timeout)


def find_manager(prefix: list[str]) -> str | None:
    rc, out, _ = docker_run(
        prefix,
        ["ps", "--format", "{{.Names}}\t{{.Label \"com.docker.compose.service\"}}"],
    )
    if rc != 0:
        return None

    matches = []
    for line in out.splitlines():
        parts = line.split("\t", 1)
        if len(parts) != 2:
            continue
        name, service = parts
        if service == "wazuh.manager":
            matches.append(name)
    return matches[0] if len(matches) == 1 else None


def self_test() -> int:
    now = dt.datetime(2026, 9, 27, 1, 0, tzinfo=dt.timezone.utc)
    sample = "\n".join(
        [
            json.dumps(
                {
                    "timestamp": "2026-09-27T00:50:00+0000",
                    "rule": {"id": "100001", "level": 5},
                    "decoder": {"name": "pfsense"},
                    "full_log": "filterlog: harmless marker CE-PF-123",
                }
            ),
            "{malformed",
            json.dumps(
                {
                    "timestamp": "2026-09-26T23:00:00+0000",
                    "rule": {"id": "1"},
                    "full_log": "filterlog: old CE-PF-123",
                }
            ),
        ]
    )
    events, errors = analyze_json_lines(
        sample,
        cutoff=now - dt.timedelta(minutes=30),
        marker="CE-PF-123",
        pfsense_ip="192.168.6.49",
    )
    if len(events) != 1 or errors != 1:
        raise SystemExit("SELFTEST FAIL: filtro temporal/json")
    if not events[0]["marker_match"] or not events[0]["pfsense_hint"]:
        raise SystemExit("SELFTEST FAIL: marcador/hint pfSense")
    if "full_log" in events[0]:
        raise SystemExit("SELFTEST FAIL: payload bruto exposto")

    receiver = (
        "<remote><connection>syslog</connection><port>514</port>"
        "<protocol>udp</protocol><allowed-ips>192.168.6.49</allowed-ips></remote>"
    )
    if exact_receiver_block_count(receiver, "192.168.6.49") != 1:
        raise SystemExit("SELFTEST FAIL: receiver exato")

    ss_fixture = "UNCONN 0 0 192.168.6.50:5514 0.0.0.0:*\n"
    if not has_exact_udp_listener(ss_fixture, "192.168.6.50", 5514):
        raise SystemExit("SELFTEST FAIL: listener exato")

    print("PFSENSE_WAZUH_POSTREBOOT_SELFTEST=PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Diagnóstico read-only pfSense -> Wazuh pós-reboot na EP126. "
            "Sem --marker comprova readiness; com --marker tenta fechar "
            "correlação analítica do evento já gerado externamente."
        )
    )
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument(
        "--topology",
        type=Path,
        default=Path("/etc/conectaeduca/vms/topologia.env"),
    )
    parser.add_argument("--manager-bind")
    parser.add_argument("--pfsense-ip")
    parser.add_argument("--marker", default="")
    parser.add_argument(
        "--window-minutes",
        type=int,
        default=DEFAULT_WINDOW_MINUTES,
    )
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    host = socket.gethostname().split(".")[0]
    if host not in EXPECTED_HOSTS:
        raise SystemExit(
            f"FALHA: executar somente na EP126; host atual={host}"
        )
    if args.window_minutes < 1 or args.window_minutes > 240:
        raise SystemExit("FALHA: --window-minutes deve estar entre 1 e 240")

    topology = read_topology(args.topology)
    manager_bind = (
        args.manager_bind
        or topology.get("CONECTAEDUCA_INTERNA_IPV4")
        or ""
    )
    pfsense_ip = (
        args.pfsense_ip
        or topology.get("CONECTAEDUCA_PFSENSE_IPV4")
        or ""
    )
    if not valid_ipv4(manager_bind) or not valid_ipv4(pfsense_ip):
        raise SystemExit(
            "FALHA: bind do Manager/IP do pfSense não puderam ser validados"
        )

    marker = args.marker.strip()
    if marker and any(char in marker for char in "\r\n\x00"):
        raise SystemExit("FALHA: marker contém caractere inválido")

    now = dt.datetime.now(dt.timezone.utc)
    cutoff = now - dt.timedelta(minutes=args.window_minutes)
    report = (
        Path.home()
        / f"conectaeduca-pfsense-wazuh-postreboot-{host}-{UTC}.txt"
    )
    sha_path = Path(str(report) + ".sha256")
    lines: list[str] = []

    def emit(message: str = "") -> None:
        lines.append(message)
        print(message)

    emit("=== CONECTAEDUCA — PFSENSE -> WAZUH POST-REBOOT READ-ONLY ===")
    emit(f"HOST={host}")
    emit(f"UTC={now.isoformat()}")
    emit(f"WINDOW_MINUTES={args.window_minutes}")
    emit(f"CUTOFF_UTC={cutoff.isoformat()}")
    emit(f"MANAGER_BIND={manager_bind}")
    emit(f"PFSENSE_IPV4={pfsense_ip}")
    emit(f"MARKER_SUPPLIED={'YES' if marker else 'NO'}")
    emit("RUNTIME_CONFIG_MUTATIONS=0")
    emit("SERVICE_RESTARTS=0")
    emit("NETWORK_TRAFFIC_INJECTION=0")
    emit("RAW_SYSLOG_PERSISTED=0")
    emit("FULL_LOG_PERSISTED=0")
    emit()

    rc_ss, ss_out, ss_err = run(["ss", "-lunH"])
    listener_ok = (
        rc_ss == 0
        and has_exact_udp_listener(ss_out, manager_bind, 5514)
    )
    emit(f"HOST_UDP5514_EXACT={'PASS' if listener_ok else 'FAIL'}")
    if not listener_ok and ss_err:
        emit(f"HOST_UDP5514_ERROR={type(ss_err).__name__}")

    prefix = docker_prefix()
    if prefix is None:
        emit("DOCKER_ACCESS=FAIL")
        readiness = False
        manager = None
    else:
        emit("DOCKER_ACCESS=PASS")
        emit(f"DOCKER_PREFIX={shlex.join(prefix)}")
        manager = find_manager(prefix)
        readiness = manager is not None

    if manager is None:
        emit("MANAGER_DISCOVERY=FAIL")
        state_ok = binding_ok = receiver_ok = False
        logall = logall_json = "UNKNOWN"
        alert_events: list[dict[str, object]] = []
        archive_events: list[dict[str, object]] = []
        alert_parse_errors = archive_parse_errors = 0
    else:
        emit(f"MANAGER={manager}")
        rc_state, state, _ = docker_run(
            prefix,
            [
                "inspect",
                "-f",
                "{{.State.Status}}|{{if .State.Health}}"
                "{{.State.Health.Status}}{{else}}none{{end}}",
                manager,
            ],
        )
        state_ok = rc_state == 0 and state == "running|healthy"
        emit(f"MANAGER_STATE={state}")
        emit(f"MANAGER_HEALTH={'PASS' if state_ok else 'FAIL'}")

        rc_port, port_out, _ = docker_run(
            prefix,
            ["port", manager, "514/udp"],
        )
        expected_binding = f"{manager_bind}:5514"
        binding_ok = (
            rc_port == 0
            and expected_binding in port_out.splitlines()
        )
        emit(f"DOCKER_514_TO_5514={'PASS' if binding_ok else 'FAIL'}")

        rc_remote, remote_out, _ = docker_run(
            prefix,
            [
                "exec",
                manager,
                "sh",
                "-c",
                "sed -n '/<remote>/,/<\\/remote>/p' "
                "/var/ossec/etc/ossec.conf 2>/dev/null",
            ],
        )
        remote_count = (
            exact_receiver_block_count(remote_out, pfsense_ip)
            if rc_remote == 0
            else 0
        )
        receiver_ok = remote_count == 1
        emit(f"PFSENSE_RECEIVER_EXACT_MATCHES={remote_count}")
        emit(f"PFSENSE_RECEIVER_CONFIG={'PASS' if receiver_ok else 'FAIL'}")

        rc_global, global_out, _ = docker_run(
            prefix,
            [
                "exec",
                manager,
                "sh",
                "-c",
                "grep -E '<logall>|<logall_json>' "
                "/var/ossec/etc/ossec.conf 2>/dev/null || true",
            ],
        )
        global_low = global_out.lower() if rc_global == 0 else ""
        logall = "YES" if "<logall>yes</logall>" in global_low else "NO"
        logall_json = (
            "YES"
            if "<logall_json>yes</logall_json>" in global_low
            else "NO"
        )
        emit(f"WAZUH_LOGALL={logall}")
        emit(f"WAZUH_LOGALL_JSON={logall_json}")

        rc_alerts, alerts_text, _ = docker_run(
            prefix,
            [
                "exec",
                manager,
                "sh",
                "-c",
                "tail -n 20000 /var/ossec/logs/alerts/alerts.json "
                "2>/dev/null || true",
            ],
            timeout=30,
        )
        alert_events, alert_parse_errors = analyze_json_lines(
            alerts_text if rc_alerts == 0 else "",
            cutoff=cutoff,
            marker=marker,
            pfsense_ip=pfsense_ip,
        )

        archive_events = []
        archive_parse_errors = 0
        if logall_json == "YES":
            rc_arch, archives_text, _ = docker_run(
                prefix,
                [
                    "exec",
                    manager,
                    "sh",
                    "-c",
                    "tail -n 20000 /var/ossec/logs/archives/archives.json "
                    "2>/dev/null || true",
                ],
                timeout=30,
            )
            archive_events, archive_parse_errors = analyze_json_lines(
                archives_text if rc_arch == 0 else "",
                cutoff=cutoff,
                marker=marker,
                pfsense_ip=pfsense_ip,
            )

    emit()
    emit("=== SANITIZED MANAGER CORRELATION ===")
    emit(f"ALERT_JSON_PARSE_ERRORS={alert_parse_errors}")
    emit(f"ALERT_PFSENSE_CANDIDATES={len(alert_events)}")
    alert_marker = [event for event in alert_events if event["marker_match"]]
    emit(f"ALERT_MARKER_MATCHES={len(alert_marker)}")
    emit(f"ARCHIVE_JSON_PARSE_ERRORS={archive_parse_errors}")
    emit(f"ARCHIVE_PFSENSE_CANDIDATES={len(archive_events)}")
    archive_marker = [
        event for event in archive_events if event["marker_match"]
    ]
    emit(f"ARCHIVE_MARKER_MATCHES={len(archive_marker)}")

    for index, event in enumerate(alert_events[-10:], start=1):
        emit(
            "ALERT_META_"
            f"{index}="
            + json.dumps(event, sort_keys=True, ensure_ascii=False)
        )
    for index, event in enumerate(archive_events[-10:], start=1):
        emit(
            "ARCHIVE_META_"
            f"{index}="
            + json.dumps(event, sort_keys=True, ensure_ascii=False)
        )

    readiness = (
        readiness
        and listener_ok
        and state_ok
        and binding_ok
        and receiver_ok
    )

    emit()
    emit("=== VERDICT ===")
    if not readiness:
        verdict = "BLOCKED_BEFORE_CORRELATED_PROBE"
        rc = 2
    elif not marker:
        verdict = "READY_FOR_CORRELATED_PROBE"
        rc = 0
    elif alert_marker:
        verdict = "CORRELATED_ALERT_PASS"
        rc = 0
    elif archive_marker:
        verdict = "REACHED_MANAGER_WITHOUT_ALERT"
        rc = 2
    elif logall_json != "YES":
        verdict = "NOT_CLOSED_NO_ALERT_ARCHIVE_DISABLED"
        rc = 2
    else:
        verdict = "NOT_CLOSED_MARKER_NOT_FOUND"
        rc = 2

    emit(f"PFSENSE_WAZUH_POSTREBOOT={verdict}")
    emit(
        "ABSENCE_FROM_ARCHIVE_PROVES_NO_INGESTION="
        + ("NO" if logall_json != "YES" else "ONLY_WITHIN_OBSERVED_WINDOW")
    )
    emit("RUNTIME_CONFIG_MUTATIONS=0")
    emit("SERVICE_RESTARTS=0")
    emit("NETWORK_TRAFFIC_INJECTION=0")
    emit("RAW_SYSLOG_PERSISTED=0")
    emit("FULL_LOG_PERSISTED=0")

    data = "\n".join(lines) + "\n"
    secure_write_new(report, data)
    digest = hashlib.sha256(report.read_bytes()).hexdigest()
    secure_write_new(sha_path, f"{digest}  {report.name}\n")

    print(f"REPORT={report}")
    print(f"SHA256={digest}")
    print(f"SHA256_FILE={sha_path}")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
