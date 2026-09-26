#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import os
import shlex
import socket
import subprocess
from pathlib import Path

UTC = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%SZ")
HOST = socket.gethostname().split(".")[0]
PASS = 0
WARN = 0
BLOCK = 0
LINES: list[str] = []


def emit(line: str = "") -> None:
    LINES.append(line)
    print(line)


def passed(message: str) -> None:
    global PASS
    PASS += 1
    emit(f"[PASS] {message}")


def warn(message: str) -> None:
    global WARN
    WARN += 1
    emit(f"[WARN] {message}")


def block(message: str) -> None:
    global BLOCK
    BLOCK += 1
    emit(f"[BLOCK] {message}")


def run(cmd: list[str], timeout: int = 12) -> tuple[int, str, str]:
    emit(f"$ {shlex.join(cmd)}")
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
        emit(f"rc=127")
        emit(f"stderr={type(exc).__name__}: {exc}")
        return 127, "", str(exc)

    out = proc.stdout.rstrip()
    err = proc.stderr.rstrip()
    emit(f"rc={proc.returncode}")
    if out:
        emit(out)
    if err:
        emit(f"stderr={err}")
    return proc.returncode, out, err


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


def git_root() -> Path:
    proc = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if proc.returncode != 0:
        raise SystemExit("FALHA: execute dentro do repositorio ConectaEduca")
    return Path(proc.stdout.strip()).resolve()


def docker_prefix() -> list[str] | None:
    probes = [
        ["docker"],
        ["sudo", "-n", "docker"],
    ]
    for prefix in probes:
        try:
            proc = subprocess.run(
                prefix + ["version", "--format", "{{.Server.Version}}"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=5,
                check=False,
            )
        except (OSError, subprocess.SubprocessError):
            continue
        if proc.returncode == 0:
            return prefix
    return None


def docker_run(prefix: list[str], args: list[str]) -> tuple[int, str, str]:
    return run(prefix + args)


def find_manager(prefix: list[str]) -> str | None:
    rc, out, _ = docker_run(
        prefix,
        ["ps", "-a", "--format", "{{.Names}}\t{{.Image}}"],
    )
    if rc != 0:
        return None

    candidates: list[str] = []
    for line in out.splitlines():
        parts = line.split("\t", 1)
        if len(parts) != 2:
            continue
        name, image = parts
        low = f"{name} {image}".lower()
        if "wazuh.manager" in low or "wazuh-manager" in low:
            candidates.append(name)

    if len(candidates) == 1:
        return candidates[0]
    if candidates:
        warn("mais de um candidato Wazuh Manager: " + ",".join(candidates))
        return candidates[0]
    return None


def self_test() -> int:
    sample = [
        'wazuh.manager-1\twazuh/wazuh-manager:4.14.7',
        'wazuh.indexer-1\twazuh/wazuh-indexer:4.14.7',
    ]
    candidates = []
    for line in sample:
        name, image = line.split("\t", 1)
        low = f"{name} {image}".lower()
        if "wazuh.manager" in low or "wazuh-manager" in low:
            candidates.append(name)
    if candidates != ["wazuh.manager-1"]:
        raise SystemExit("SELFTEST FAIL: detector do Manager")
    print("OPS01_EP126_READONLY_SELFTEST=PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Preflight read-only da EP126 para OPS-01."
    )
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()

    root = git_root()
    home = Path.home().resolve()
    report = home / f"conectaeduca-ops01-ep126-readonly-{HOST}-{UTC}.txt"
    sha_path = Path(str(report) + ".sha256")

    emit("=== CONECTAEDUCA OPS-01 EP126 READ-ONLY PREFLIGHT ===")
    emit(f"HOST={HOST}")
    emit(f"UTC={UTC}")
    emit(f"REPO={root}")
    emit("RUNTIME_MUTATIONS=0")
    emit("NETWORK_TRAFFIC_INJECTION=0")
    emit("SUDO_SHELL=0")
    emit("PURPOSE=preparar gates live pfSense/Wazuh, Rootcheck, NTP e WAF 110300")
    emit()

    emit("=== GIT / HOST ===")
    rc, branch, _ = run(["git", "-C", str(root), "branch", "--show-current"])
    rc_head, head, _ = run(["git", "-C", str(root), "rev-parse", "HEAD"])
    rc_status, status, _ = run(["git", "-C", str(root), "status", "--porcelain=v1"])
    if rc == 0 and branch == "main":
        passed("checkout em main")
    else:
        warn("checkout final deve ser repetido em main")
    if rc_status == 0 and not status.strip():
        passed("worktree limpa")
    else:
        warn("worktree nao esta limpa")
    if rc_head == 0:
        emit(f"GIT_HEAD={head}")

    rc_kernel, kernel, _ = run(["uname", "-r"])
    if rc_kernel == 0:
        emit(f"KERNEL={kernel}")
    emit(f"REBOOT_REQUIRED={'YES' if Path('/var/run/reboot-required').exists() else 'NO'}")
    emit()

    emit("=== TIME / NTP ===")
    rc_time, time_out, _ = run(
        [
            "timedatectl", "show",
            "-p", "NTP",
            "-p", "NTPSynchronized",
            "-p", "TimeUSec",
            "--value",
        ]
    )
    run(["systemctl", "is-active", "systemd-timesyncd.service"])
    run(["ip", "route", "get", "185.125.190.56"])
    synced = "yes" in time_out.lower().splitlines() if rc_time == 0 else False
    if synced:
        passed("NTP sincronizado")
    else:
        warn("NTP nao comprovado; manter TIME-01 como risco temporal aceito")
    emit()

    emit("=== HOST SYSLOG RECEIVER ===")
    rc_ss, ss_out, _ = run(["ss", "-lun"])
    udp5514 = rc_ss == 0 and ":5514" in ss_out
    if udp5514:
        passed("listener UDP/5514 presente no host")
    else:
        block("listener UDP/5514 nao encontrado no host")
    emit()

    prefix = docker_prefix()
    if prefix is None:
        block(
            "Docker indisponivel ao usuario e via sudo -n; se necessario rode "
            "sudo -v antes do preflight, sem usar sudo -s"
        )
        manager = None
    else:
        emit("DOCKER_PREFIX=" + shlex.join(prefix))
        manager = find_manager(prefix)

    manager_ready = False
    receiver_config_ok = False
    rule110300_defined = False
    rootcheck_refs = False
    rootcheck_bases = False

    if prefix is not None and manager:
        emit()
        emit("=== WAZUH MANAGER RUNTIME ===")
        emit(f"WAZUH_MANAGER_CONTAINER={manager}")
        rc_state, state, _ = docker_run(
            prefix,
            [
                "inspect", "-f",
                "{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}no-health{{end}}",
                manager,
            ],
        )
        manager_ready = rc_state == 0 and state.startswith("running ")
        if manager_ready:
            passed(f"Wazuh Manager runtime={state}")
        else:
            block(f"Wazuh Manager nao comprovado running/healthy: {state or 'unknown'}")

        docker_run(prefix, ["port", manager])

        emit()
        emit("=== PFSENSE -> WAZUH RECEIVER CONFIG ===")
        rc_remote, remote_out, _ = docker_run(
            prefix,
            [
                "exec", manager, "sh", "-c",
                "grep -n -E '<remote>|</remote>|<connection>|<port>|<protocol>|<allowed-ips>' "
                "/var/ossec/etc/ossec.conf 2>/dev/null",
            ],
        )
        low_remote = remote_out.lower()
        receiver_config_ok = (
            rc_remote == 0
            and "syslog" in low_remote
            and ">514<" in low_remote
            and "udp" in low_remote
            and "allowed-ips" in low_remote
        )
        if receiver_config_ok:
            passed("receiver syslog/UDP/514 com allowed-ips encontrado")
        else:
            block("configuracao canônica do receiver syslog nao comprovada")

        emit()
        emit("=== ROOTCHECK / GRUPO DMZ ===")
        rc_group, group_out, _ = docker_run(
            prefix,
            [
                "exec", manager, "sh", "-c",
                "printf '%s\\n' '--- files ---'; "
                "find /var/ossec/etc/shared/conectaeduca-dmz -maxdepth 1 -type f "
                "-printf '%f\\n' 2>/dev/null | sort; "
                "printf '%s\\n' '--- rootcheck refs ---'; "
                "grep -n -E 'rootcheck|rootkit_files|rootkit_trojans|check_(files|trojans|ports)' "
                "/var/ossec/etc/shared/conectaeduca-dmz/agent.conf 2>/dev/null",
            ],
        )
        group_low = group_out.lower()
        rootcheck_refs = (
            rc_group == 0
            and "rootkit_files" in group_low
            and "rootkit_trojans" in group_low
        )
        rootcheck_bases = (
            "rootkit_files" in group_low
            and "rootkit_trojans" in group_low
            and any(
                token in group_low
                for token in ("rootkit_files.txt", "rootkit_trojans.txt")
            )
        )
        if rootcheck_refs and rootcheck_bases:
            passed("bases e referencias Rootcheck aparentam materializadas no grupo DMZ")
        else:
            warn("WAZ-02 ainda requer remediacao manager-side de bases/referencias Rootcheck")

        emit()
        emit("=== WAF RULE 110300 ===")
        rc_rule, rule_out, _ = docker_run(
            prefix,
            [
                "exec", manager, "sh", "-c",
                "grep -R -n -E '<id>[[:space:]]*110300[[:space:]]*</id>|110300' "
                "/var/ossec/etc/rules 2>/dev/null | head -20",
            ],
        )
        rule110300_defined = rc_rule == 0 and "110300" in rule_out
        if rule110300_defined:
            passed("rule 110300 encontrada no ruleset ativo")
        else:
            block("rule 110300 nao encontrada no ruleset ativo")

        rc_alert, alert_count, _ = docker_run(
            prefix,
            [
                "exec", manager, "sh", "-c",
                "grep -Ec '"id"[[:space:]]*:[[:space:]]*"110300"' "
                "/var/ossec/logs/alerts/alerts.json 2>/dev/null || true",
            ],
        )
        if rc_alert == 0:
            emit(f"RULE110300_ALERT_COUNT_CURRENT={alert_count or '0'}")
    elif prefix is not None:
        block("container Wazuh Manager nao localizado")

    emit()
    emit("=== READINESS CLASSIFICATION ===")
    if udp5514 and receiver_config_ok and manager_ready:
        emit("PFSENSE_WAZUH_POSTREBOOT=READY_FOR_LIVE_CORRELATED_PROBE")
    else:
        emit("PFSENSE_WAZUH_POSTREBOOT=BLOCKED_BEFORE_LIVE_PROBE")

    if rule110300_defined and manager_ready:
        emit("WAF_RULE110300=READY_FOR_EP125_CORRELATED_PROBE")
    else:
        emit("WAF_RULE110300=BLOCKED_BEFORE_LIVE_PROBE")

    if rootcheck_refs and rootcheck_bases:
        emit("WAZ02_ROOTCHECK_MANAGER_SIDE=READY_FOR_AGENT_VALIDATION")
    else:
        emit("WAZ02_ROOTCHECK_MANAGER_SIDE=REMEDIATION_PENDING")

    emit("NTP_UPSTREAM=REVIEW_TIME01_ACCEPTED_RISK_AND_PATH")
    emit()
    emit("=== SUMMARY ===")
    emit(f"PASS={PASS}")
    emit(f"WARN={WARN}")
    emit(f"BLOCK={BLOCK}")
    emit(
        "OPS01_EP126_READONLY="
        + ("PASS_WITH_LIVE_GATES_PENDING" if BLOCK == 0 else "BLOCK")
    )
    emit("RUNTIME_MUTATIONS=0")
    emit("NETWORK_TRAFFIC_INJECTION=0")

    data = "\n".join(LINES) + "\n"
    secure_write_new(report, data)
    digest = hashlib.sha256(report.read_bytes()).hexdigest()
    secure_write_new(sha_path, f"{digest}  {report.name}\n")
    print(f"REPORT={report}")
    print(f"SHA256={digest}")
    print(f"SHA256_FILE={sha_path}")

    return 0 if BLOCK == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
