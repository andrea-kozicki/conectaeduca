#!/usr/bin/env python3
"""Reconcilia HOME_NET do Suricata na EP125 de forma fail-closed.

CHECK é somente leitura. APPLY exige confirmação literal, cria backup,
valida o candidato com suricata -T, aplica atomicamente, reinicia somente
Suricata e faz rollback se qualquer gate pós-mudança falhar.
"""

from __future__ import annotations

import argparse
import datetime as dt
import difflib
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import socket
import stat as statmod
import subprocess
import sys
import tempfile

VERSION = "1.0.2"
DEFAULT_CONFIG = Path("/etc/suricata/suricata.yaml")
DEFAULT_BACKUP_DIR = Path("/var/backups/conectaeduca/suricata")
DEFAULT_HOME_NET = "192.168.6.32/28"
DEFAULT_HOSTS = frozenset({"ep125-pucpr", "conectaeduca-dmz"})

LOG: list[str] = []
PASS = WARN = FAIL = 0


class ReconcileError(RuntimeError):
    pass


def emit(message: str = "") -> None:
    print(message, flush=True)
    LOG.append(message)


def passed(message: str) -> None:
    global PASS
    PASS += 1
    emit(f"[PASS] {message}")


def warned(message: str) -> None:
    global WARN
    WARN += 1
    emit(f"[WARN] {message}")


def failed(message: str) -> None:
    global FAIL
    FAIL += 1
    emit(f"[FAIL] {message}")


def run(argv: list[str], timeout: int = 60) -> subprocess.CompletedProcess[str]:
    emit("[CMD] " + " ".join(subprocess.list2cmdline([part]) for part in argv))
    proc = subprocess.run(
        argv,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        timeout=timeout,
    )
    emit(f"[RC] {proc.returncode}")
    if proc.stdout:
        emit(proc.stdout.rstrip())
    return proc


def sudo_read_bytes(path: Path) -> bytes:
    """Lê arquivo protegido via sudo sem registrar seu conteúdo na evidência."""
    emit(f"[CMD] sudo cat -- {path} (conteúdo suprimido)")
    proc = subprocess.run(
        ["sudo", "cat", "--", str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=60,
    )
    emit(f"[RC] {proc.returncode}")
    if proc.returncode:
        stderr = proc.stderr.decode("utf-8", errors="replace").strip()
        if stderr:
            emit(stderr)
        raise ReconcileError(f"leitura privilegiada falhou para {path}")
    emit(f"[READ_BYTES] {len(proc.stdout)}")
    return proc.stdout


def sudo_config_metadata(path: Path) -> tuple[int, int, str]:
    """Obtém lstat seguro do arquivo protegido via sudo.

    Retorna uid, gid e modo octal. Rejeita symlink e qualquer tipo não regular.
    """
    proc = run(["sudo", "stat", "-c", "%f|%u|%g|%a", "--", str(path)])
    if proc.returncode:
        raise ReconcileError(f"stat privilegiado falhou para {path}")
    fields = proc.stdout.strip().splitlines()[-1].split("|")
    if len(fields) != 4:
        raise ReconcileError("stat privilegiado retornou formato inesperado")
    raw_mode = int(fields[0], 16)
    if statmod.S_ISLNK(raw_mode):
        raise ReconcileError("suricata.yaml não pode ser symlink")
    if not statmod.S_ISREG(raw_mode):
        raise ReconcileError("suricata.yaml precisa ser arquivo regular")
    uid = int(fields[1])
    gid = int(fields[2])
    mode = f"{int(fields[3], 8):04o}"
    emit(f"CONFIG_METADATA=uid:{uid},gid:{gid},mode:{mode}")
    return uid, gid, mode


def indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def ignored(line: str) -> bool:
    stripped = line.strip()
    return not stripped or stripped.startswith("#")


def section_end(lines: list[str], start: int, base_indent: int) -> int:
    for index in range(start + 1, len(lines)):
        if ignored(lines[index]):
            continue
        if indent(lines[index]) <= base_indent:
            return index
    return len(lines)


def render_candidate(text: str, expected_cidr: str) -> tuple[str, dict[str, object]]:
    network = ipaddress.ip_network(expected_cidr, strict=True)
    if network.version != 4:
        raise ReconcileError("HOME_NET acadêmico deve ser IPv4")

    lines = text.splitlines(keepends=True)
    vars_idx = [
        i
        for i, line in enumerate(lines)
        if indent(line) == 0
        and re.match(r"^vars:\s*(?:#.*)?(?:\r?\n)?$", line)
    ]
    if len(vars_idx) != 1:
        raise ReconcileError(f"STRUCTURAL_FAIL top-level vars={len(vars_idx)}")
    v = vars_idx[0]
    v_end = section_end(lines, v, 0)

    address_candidates = [
        i
        for i in range(v + 1, v_end)
        if not ignored(lines[i])
        and re.match(r"^\s+address-groups:\s*(?:#.*)?(?:\r?\n)?$", lines[i])
    ]
    if not address_candidates:
        raise ReconcileError("STRUCTURAL_FAIL address-groups ausente")
    min_address_indent = min(indent(lines[i]) for i in address_candidates)
    direct_address = [
        i for i in address_candidates if indent(lines[i]) == min_address_indent
    ]
    if len(direct_address) != 1:
        raise ReconcileError(
            f"STRUCTURAL_FAIL direct address-groups={len(direct_address)}"
        )
    a = direct_address[0]
    a_end = section_end(lines, a, indent(lines[a]))

    home_matches: list[tuple[int, re.Match[str]]] = []
    pattern = re.compile(
        r"^(?P<indent>\s*)HOME_NET:\s*(?P<value>.*?)(?P<comment>\s+#.*)?(?P<nl>\r?\n)?$"
    )
    for i in range(a + 1, a_end):
        match = pattern.match(lines[i])
        if match:
            home_matches.append((i, match))
    if len(home_matches) != 1:
        raise ReconcileError(f"STRUCTURAL_FAIL HOME_NET={len(home_matches)}")

    h, match = home_matches[0]
    current = match.group("value").strip()
    expected_value = f'"[{network.with_prefixlen}]"'
    comment = match.group("comment") or ""
    newline = match.group("nl") or "\n"
    replacement = (
        f"{match.group('indent')}HOME_NET: {expected_value}{comment}{newline}"
    )

    candidate_lines = list(lines)
    candidate_lines[h] = replacement
    candidate = "".join(candidate_lines)
    return candidate, {
        "vars_line": v + 1,
        "address_groups_line": a + 1,
        "home_net_line": h + 1,
        "current": current,
        "expected": expected_value,
        "changed": candidate != text,
    }


def validate_diff(original: str, candidate: str, meta: dict[str, object]) -> None:
    diff = list(
        difflib.unified_diff(
            original.splitlines(),
            candidate.splitlines(),
            n=0,
        )
    )
    removed = [x[1:] for x in diff if x.startswith("-") and not x.startswith("---")]
    added = [x[1:] for x in diff if x.startswith("+") and not x.startswith("+++")]

    if not meta["changed"]:
        if removed or added:
            raise ReconcileError("CANDIDATE_FAIL idempotência divergente")
        return

    if len(removed) != 1 or len(added) != 1:
        raise ReconcileError(
            f"CANDIDATE_FAIL diff inesperado removed={len(removed)} added={len(added)}"
        )
    if "HOME_NET:" not in removed[0] or "HOME_NET:" not in added[0]:
        raise ReconcileError("CANDIDATE_FAIL alteração fora de HOME_NET")
    if str(meta["expected"]) not in added[0]:
        raise ReconcileError("CANDIDATE_FAIL valor esperado ausente")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def trusted_evidence_directory() -> Path:
    """Retorna o home do UID real sem aceitar caminho de CLI/ambiente."""
    try:
        directory = Path(pwd.getpwuid(os.getuid()).pw_dir).resolve(strict=True)
    except (KeyError, OSError) as exc:
        raise ReconcileError("home do usuário real não pôde ser resolvido") from exc
    if not directory.is_dir():
        raise ReconcileError("home do usuário real não é diretório")
    return directory


def write_new_text_file(path: Path, content: str, mode: int = 0o644) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(path, flags, mode)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", closefd=True) as handle:
            fd = -1
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
    finally:
        if fd >= 0:
            os.close(fd)


def write_evidence(action: str) -> tuple[Path, Path, str]:
    directory = trusted_evidence_directory()
    raw_host = socket.gethostname().split(".")[0]
    host_tag = raw_host if raw_host in DEFAULT_HOSTS else "unknown-host"
    action_tag = "apply" if action == "apply" else "check"
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%SZ")
    report = directory / (
        f"conectaeduca-suricata-homenet-{action_tag}-{host_tag}-{stamp}-pid{os.getpid()}.txt"
    )
    payload = "\n".join(LOG) + "\n"
    digest = sha256_bytes(payload.encode("utf-8"))
    write_new_text_file(report, payload)
    checksum = report.with_name(report.name + ".sha256")
    write_new_text_file(checksum, f"{digest}  {report.name}\n")
    return report, checksum, digest


def require_host() -> None:
    host = socket.gethostname().split(".")[0]
    emit(f"HOST={host}")
    if host not in DEFAULT_HOSTS:
        raise ReconcileError(f"host fora do boundary EP125: {host}")


def sudo_sha256(path: Path) -> str:
    proc = run(["sudo", "sha256sum", "--", str(path)])
    if proc.returncode:
        raise ReconcileError(f"sha256sum falhou para {path}")
    return proc.stdout.split()[0]


def config_test(config: Path) -> None:
    proc = run(["sudo", "suricata", "-T", "-c", str(config)], timeout=120)
    if proc.returncode:
        raise ReconcileError("suricata -T reprovou a configuração")


def service_active() -> None:
    proc = run(["systemctl", "is-active", "--quiet", "suricata"])
    if proc.returncode:
        raise ReconcileError("suricata.service não está active")


def apply_candidate(
    config: Path,
    candidate: Path,
    uid: int,
    gid: int,
    mode: str,
) -> None:
    staged = config.with_name(config.name + f".conectaeduca-{os.getpid()}.tmp")
    proc = run(
        [
            "sudo",
            "install",
            "-o",
            str(uid),
            "-g",
            str(gid),
            "-m",
            mode,
            str(candidate),
            str(staged),
        ]
    )
    if proc.returncode:
        raise ReconcileError("não foi possível materializar candidato")
    proc = run(["sudo", "mv", "-f", "--", str(staged), str(config)])
    if proc.returncode:
        raise ReconcileError("promoção atômica do candidato falhou")


def self_test() -> int:
    sample = """vars:
  address-groups:
    HOME_NET: "[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"
    EXTERNAL_NET: "!$HOME_NET"

outputs:
  - eve-log:
      enabled: yes
"""
    candidate, meta = render_candidate(sample, DEFAULT_HOME_NET)
    validate_diff(sample, candidate, meta)
    if 'HOME_NET: "[192.168.6.32/28]"' not in candidate:
        raise SystemExit("SELF_TEST_FAIL expected HOME_NET missing")
    candidate2, meta2 = render_candidate(candidate, DEFAULT_HOME_NET)
    validate_diff(candidate, candidate2, meta2)
    if meta2["changed"]:
        raise SystemExit("SELF_TEST_FAIL reconciler not idempotent")

    duplicate = sample.replace(
        '    EXTERNAL_NET: "!$HOME_NET"',
        '    HOME_NET: "[10.0.0.0/8]"\n    EXTERNAL_NET: "!$HOME_NET"',
    )
    try:
        render_candidate(duplicate, DEFAULT_HOME_NET)
    except ReconcileError:
        pass
    else:
        raise SystemExit("SELF_TEST_FAIL duplicate HOME_NET accepted")

    print("SELF_TEST_SURICATA_HOMENET=APROVADO")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", nargs="?", choices=("check", "apply"), default="check")
    parser.add_argument(
        "--config",
        type=Path,
        default=Path(os.environ.get("CONECTAEDUCA_SURICATA_CONFIG", DEFAULT_CONFIG)),
    )
    parser.add_argument(
        "--expected-home-net",
        default=os.environ.get("CONECTAEDUCA_SURICATA_HOME_NET", DEFAULT_HOME_NET),
    )
    parser.add_argument(
        "--backup-dir",
        type=Path,
        default=Path(
            os.environ.get(
                "CONECTAEDUCA_SURICATA_BACKUP_DIR",
                DEFAULT_BACKUP_DIR,
            )
        ),
    )
    parser.add_argument("--confirm", default="")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    emit("=== SURICATA HOME_NET RECONCILIATION ===")
    emit(f"VERSION={VERSION}")
    emit(f"ACTION={args.action}")
    emit(f"CONFIG={args.config}")
    emit(f"EXPECTED_HOME_NET={args.expected_home_net}")
    emit("SECRET_VALUES_LOGGED=0")

    mutation_started = False
    rollback_used = False
    backup: Path | None = None
    candidate_path: Path | None = None

    try:
        require_host()
        if os.geteuid() == 0:
            raise ReconcileError(
                "não execute em shell root; use usuário normal com sudo pontual"
            )
        if shutil.which("sudo") is None:
            raise ReconcileError("sudo ausente; configuração protegida não pode ser lida")

        config_uid, config_gid, config_mode = sudo_config_metadata(args.config)
        original_bytes = sudo_read_bytes(args.config)
        original = original_bytes.decode("utf-8")
        candidate, meta = render_candidate(original, args.expected_home_net)
        validate_diff(original, candidate, meta)
        emit("HOME_NET_META=" + json.dumps(meta, sort_keys=True))

        if not meta["changed"]:
            passed("HOME_NET já está no valor esperado.")
            service_active()
            passed("Suricata está active.")
            if shutil.which("sudo") and shutil.which("suricata"):
                config_test(args.config)
                passed("suricata -T aprovado.")
            else:
                warned("sudo/suricata ausente; config-test live não executado no CHECK.")
        elif args.action == "check":
            failed("HOME_NET diverge do valor esperado; APPLY não executado.")
        else:
            if args.confirm != "APPLY":
                raise ReconcileError("APPLY exige --confirm APPLY")
            for command in ("sudo", "suricata", "systemctl"):
                if shutil.which(command) is None:
                    raise ReconcileError(f"comando obrigatório ausente: {command}")

            service_active()
            args.backup_dir = args.backup_dir.resolve()
            backup = args.backup_dir / (
                f"suricata.yaml.pre-homenet-{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%d-%H%M%SZ')}.bak"
            )
            proc = run(["sudo", "install", "-d", "-o", "root", "-g", "root", "-m", "0700", str(args.backup_dir)])
            if proc.returncode:
                raise ReconcileError("não foi possível criar diretório de backup")
            proc = run(["sudo", "cp", "-a", "--", str(args.config), str(backup)])
            if proc.returncode:
                raise ReconcileError("backup do suricata.yaml falhou")
            original_sha = sha256_bytes(original_bytes)
            backup_sha = sudo_sha256(backup)
            emit(f"ORIGINAL_SHA256={original_sha}")
            emit(f"BACKUP_SHA256={backup_sha}")
            if backup_sha != original_sha:
                raise ReconcileError("hash do backup diverge do original")
            passed("Backup íntegro criado.")

            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                prefix="conectaeduca-suricata-homenet-",
                suffix=".yaml",
                delete=False,
            ) as handle:
                handle.write(candidate)
                candidate_path = Path(handle.name)
            os.chmod(candidate_path, 0o600)

            config_test(candidate_path)
            passed("Candidato aprovado por suricata -T.")

            apply_candidate(
                args.config,
                candidate_path,
                config_uid,
                config_gid,
                config_mode,
            )
            mutation_started = True
            proc = run(["sudo", "systemctl", "restart", "suricata"])
            if proc.returncode:
                raise ReconcileError("restart do Suricata falhou")
            service_active()

            post_uid, post_gid, post_mode = sudo_config_metadata(args.config)
            if (post_uid, post_gid, post_mode) != (
                config_uid,
                config_gid,
                config_mode,
            ):
                raise ReconcileError(
                    "metadados do suricata.yaml mudaram durante a promoção"
                )
            post = sudo_read_bytes(args.config).decode("utf-8")
            post_candidate, post_meta = render_candidate(post, args.expected_home_net)
            validate_diff(post, post_candidate, post_meta)
            if post_meta["changed"]:
                raise ReconcileError("HOME_NET pós-apply ainda diverge")
            config_test(args.config)
            passed("HOME_NET reconciliado e Suricata validado após restart.")

    except (OSError, ReconcileError, subprocess.TimeoutExpired, UnicodeDecodeError) as exc:
        failed(f"{type(exc).__name__}: {exc}")
        if mutation_started and backup is not None:
            warned("Falha pós-mudança; iniciando rollback.")
            rollback = run(["sudo", "cp", "-a", "--", str(backup), str(args.config)])
            restart = run(["sudo", "systemctl", "restart", "suricata"])
            rollback_used = rollback.returncode == 0 and restart.returncode == 0
            emit(f"ROLLBACK_USED={1 if rollback_used else 0}")
            if rollback_used:
                warned("Rollback aplicado; validar estado live antes de nova tentativa.")
            else:
                failed("Rollback automático não pôde ser confirmado.")
    finally:
        if candidate_path is not None:
            try:
                candidate_path.unlink(missing_ok=True)
            except OSError:
                pass

    final = "FAIL" if FAIL else ("WARN" if WARN else "PASS")
    emit("")
    emit("=== SUMMARY ===")
    emit(f"PASS={PASS}")
    emit(f"WARN={WARN}")
    emit(f"FAIL={FAIL}")
    emit(f"FINAL={final}")
    emit(f"MUTATION_STARTED={1 if mutation_started else 0}")
    emit(f"ROLLBACK_USED={1 if rollback_used else 0}")
    if args.action == "apply":
        emit("LIVE_VALIDATION_REQUIRED=YES")

    report, checksum, digest = write_evidence(args.action)
    print(f"EVIDENCE_FILE={report}")
    print(f"SHA256={digest}")
    print(f"SHA256_FILE={checksum}")
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
