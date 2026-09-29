#!/usr/bin/env python3
"""Bootstrap explícito e fail-closed do Security Index do Wazuh Indexer.

O ConectaEduca mantém plugins.security.allow_default_init_securityindex=false
para não cair em defaults conhecidos. Em volume novo, este helper distingue:
- security index já inicializado -> não faz mutação;
- security index explicitamente "Not initialized" -> permite APPLY confirmado;
- estado ambíguo/indisponível -> bloqueia sem executar securityadmin.

Nenhum segredo é lido ou persistido na evidência.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from datetime import datetime, timezone

SCRIPT = Path(__file__).resolve()
ROOT = SCRIPT.parents[2]
WAZUH_DIR = ROOT / "deploy/interna/wazuh"
BASE = WAZUH_DIR / "compose.yml"
HOST = WAZUH_DIR / "compose.host.yml"
INDEXER_CFG = WAZUH_DIR / "config/wazuh_indexer/wazuh.indexer.yml"
RUNTIME = WAZUH_DIR / ".runtime"
PROJECT = os.environ.get("CONECTAEDUCA_WAZUH_PROJECT", "conectaeduca-wazuh")
CONFIRM_TOKEN = "INITIALIZE_WAZUH_SECURITY_INDEX"

CONTAINER_SECURITY_DIR = "/usr/share/wazuh-indexer/config/opensearch-security"
CONTAINER_CERT_DIR = "/usr/share/wazuh-indexer/config/certs"
SECURITYADMIN = (
    "/usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh"
)
HEALTH_URL = "https://localhost:9200/_plugins/_security/health"

REQUIRED_RUNTIME = (
    RUNTIME / "internal_users.yml",
    RUNTIME / "certs/root-ca.pem",
    RUNTIME / "certs/admin.pem",
    RUNTIME / "certs/admin-key.pem",
)

def run(
    args: list[str],
    *,
    env: dict[str, str] | None = None,
    timeout: int = 30,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def compose_env() -> dict[str, str]:
    env = dict(os.environ)
    # compose.host.yml exige ambos os bindings na fase de interpolação, mesmo
    # quando apenas wazuh.indexer será iniciado. Estes defaults não publicam
    # portas do Indexer e não são usados para criar Manager/Dashboard aqui.
    env.setdefault("CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS", "127.0.0.1")
    env.setdefault("CONECTAEDUCA_WAZUH_DASHBOARD_BIND_ADDRESS", "127.0.0.1")
    return env


def compose_args(*args: str) -> list[str]:
    return [
        "docker",
        "compose",
        "-p",
        PROJECT,
        "-f",
        str(BASE),
        "-f",
        str(HOST),
        *args,
    ]


def classify_health(text: str) -> str:
    normalized = text.strip()
    lower = normalized.lower()
    try:
        payload = json.loads(normalized)
    except json.JSONDecodeError:
        payload = None

    if isinstance(payload, dict):
        status = str(payload.get("status", "")).upper()
        message = str(payload.get("message", "") or "").lower()
        if status == "UP":
            return "INITIALIZED"
        if status == "DOWN" and "not initialized" in message:
            return "NOT_INITIALIZED"

        error = payload.get("error")
        if isinstance(error, dict):
            reason = str(error.get("reason", "")).lower()
            if "security not initialized" in reason:
                return "NOT_INITIALIZED"

    if "opensearch security not initialized" in lower:
        return "NOT_INITIALIZED"
    if '"status"' in lower and '"up"' in lower:
        return "INITIALIZED"
    if '"status"' in lower and '"down"' in lower and "not initialized" in lower:
        return "NOT_INITIALIZED"
    return "UNKNOWN"


def self_test() -> int:
    cases = {
        '{"message":null,"mode":"strict","status":"UP"}': "INITIALIZED",
        '{"message":"Not initialized","mode":"strict","status":"DOWN"}': "NOT_INITIALIZED",
        '{"error":{"reason":"OpenSearch Security not initialized for cluster:monitor/health"},"status":503}': "NOT_INITIALIZED",
        "curl: (7) connection refused": "UNKNOWN",
        "": "UNKNOWN",
    }
    for raw, expected in cases.items():
        got = classify_health(raw)
        if got != expected:
            print(f"SELFTEST_FAIL classify={got} expected={expected} raw={raw!r}")
            return 1

    cmd = securityadmin_args("container-id")
    joined = " ".join(cmd)
    for needle in (
        SECURITYADMIN,
        f"-cd {CONTAINER_SECURITY_DIR}",
        f"-cacert {CONTAINER_CERT_DIR}/root-ca.pem",
        f"-cert {CONTAINER_CERT_DIR}/admin.pem",
        f"-key {CONTAINER_CERT_DIR}/admin-key.pem",
    ):
        if needle not in joined:
            print(f"SELFTEST_FAIL command_missing={needle}")
            return 1

    print("WAZUH_SECURITY_INDEX_SELFTEST=PASS")
    return 0


def securityadmin_args(container_id: str) -> list[str]:
    return [
        "docker",
        "exec",
        container_id,
        "env",
        "JAVA_HOME=/usr/share/wazuh-indexer/jdk",
        "bash",
        SECURITYADMIN,
        "-h",
        "localhost",
        "-p",
        "9200",
        "-cd",
        CONTAINER_SECURITY_DIR,
        "-icl",
        "-nhnv",
        "-cacert",
        f"{CONTAINER_CERT_DIR}/root-ca.pem",
        "-cert",
        f"{CONTAINER_CERT_DIR}/admin.pem",
        "-key",
        f"{CONTAINER_CERT_DIR}/admin-key.pem",
    ]


def preflight() -> None:
    for path in (BASE, HOST, INDEXER_CFG):
        if not path.is_file():
            raise RuntimeError(f"arquivo obrigatório ausente: {path}")

    cfg = INDEXER_CFG.read_text(encoding="utf-8")
    required = "plugins.security.allow_default_init_securityindex: false"
    if required not in cfg:
        raise RuntimeError(
            "arquitetura inesperada: auto-init não está explicitamente false"
        )

    for path in REQUIRED_RUNTIME:
        if not path.is_file() or path.stat().st_size == 0:
            raise RuntimeError(f"runtime obrigatório ausente/vazio: {path}")

    for path in (RUNTIME / "internal_users.yml", RUNTIME / "certs/admin-key.pem"):
        mode = path.stat().st_mode & 0o777
        if mode not in {0o400, 0o600}:
            raise RuntimeError(
                f"runtime sensível deve ser owner-only: {path} mode={mode:o}"
            )

    env = compose_env()
    proc = run(compose_args("config", "-q"), env=env, timeout=30)
    if proc.returncode != 0:
        raise RuntimeError(
            "docker compose config falhou: "
            + (proc.stderr.strip() or proc.stdout.strip())[:500]
        )


def service_id() -> str:
    proc = run(
        compose_args("ps", "-q", "wazuh.indexer"),
        env=compose_env(),
        timeout=20,
    )
    if proc.returncode != 0:
        return ""
    return proc.stdout.strip()


def is_running(container_id: str) -> bool:
    if not container_id:
        return False
    proc = run(
        ["docker", "inspect", "-f", "{{.State.Status}}", container_id],
        timeout=10,
    )
    return proc.returncode == 0 and proc.stdout.strip() == "running"


def health_probe(container_id: str) -> tuple[str, str]:
    proc = run(
        [
            "docker",
            "exec",
            container_id,
            "curl",
            "-ksS",
            "--connect-timeout",
            "3",
            "--max-time",
            "5",
            HEALTH_URL,
        ],
        timeout=10,
    )
    merged = (proc.stdout + "\n" + proc.stderr).strip()
    return classify_health(merged), merged


def wait_for_classified_health(
    container_id: str,
    timeout_seconds: int,
) -> tuple[str, str]:
    deadline = time.monotonic() + timeout_seconds
    last_text = ""
    while time.monotonic() <= deadline:
        state, text = health_probe(container_id)
        last_text = text
        if state in {"INITIALIZED", "NOT_INITIALIZED"}:
            return state, text
        time.sleep(3)
    return "UNKNOWN", last_text


def ensure_security_dir(container_id: str) -> None:
    proc = run(
        [
            "docker",
            "exec",
            container_id,
            "bash",
            "-c",
            (
                f"test -x {SECURITYADMIN!s} && "
                f"test -d {CONTAINER_SECURITY_DIR!s} && "
                f"test -s {CONTAINER_SECURITY_DIR!s}/internal_users.yml && "
                f"test -s {CONTAINER_CERT_DIR!s}/root-ca.pem && "
                f"test -s {CONTAINER_CERT_DIR!s}/admin.pem && "
                f"test -s {CONTAINER_CERT_DIR!s}/admin-key.pem"
            ),
        ],
        timeout=15,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            "container não contém securityadmin/config/certificados esperados"
        )


def write_evidence(lines: list[str]) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_dir = Path(
        os.environ.get("CONECTAEDUCA_OUTPUT_DIR", str(Path.home() / "Downloads"))
    )
    out_dir.mkdir(parents=True, exist_ok=True)
    report = out_dir / f"conectaeduca-wazuh-security-index-init-{stamp}.txt"
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    digest = hashlib.sha256(report.read_bytes()).hexdigest()
    sha = Path(str(report) + ".sha256")
    sha.write_text(f"{digest}  {report.name}\n", encoding="ascii")
    print(f"ARQUIVO_SAIDA={report}")
    print(f"SHA256_FILE={sha}")
    print(f"SHA256={digest}")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Bootstrap explícito do Wazuh Security Index em volume novo."
    )
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--confirm", default="")
    parser.add_argument("--timeout", type=int, default=90)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test()
    if args.timeout < 15 or args.timeout > 600:
        parser.error("--timeout deve ficar entre 15 e 600 segundos")
    if args.apply and args.confirm != CONFIRM_TOKEN:
        parser.error(
            f"--apply exige --confirm {CONFIRM_TOKEN}"
        )

    evidence = [
        "=== CONECTAEDUCA WAZUH SECURITY INDEX BOOTSTRAP ===",
        f"UTC={datetime.now(timezone.utc).isoformat()}",
        f"PROJECT={PROJECT}",
        "ALLOW_DEFAULT_INIT_SECURITYINDEX=FALSE",
        f"MODE={'APPLY' if args.apply else 'CHECK'}",
        "SECRETS_CAPTURED=NO",
    ]

    try:
        preflight()
        evidence.append("PREFLIGHT=PASS")

        container_id = service_id()
        if not is_running(container_id):
            if not args.apply:
                evidence.extend(
                    [
                        "INDEXER_RUNNING=NO",
                        "SECURITY_INDEX_STATE=UNKNOWN",
                        "NEXT=execute --apply com confirmação para iniciar somente o Indexer",
                    ]
                )
                write_evidence(evidence)
                return 2

            proc = run(
                compose_args("up", "-d", "wazuh.indexer"),
                env=compose_env(),
                timeout=max(args.timeout, 60),
            )
            if proc.returncode != 0:
                raise RuntimeError(
                    "falha ao iniciar wazuh.indexer: "
                    + (proc.stderr.strip() or proc.stdout.strip())[:500]
                )

            deadline = time.monotonic() + args.timeout
            container_id = ""
            while time.monotonic() <= deadline:
                container_id = service_id()
                if is_running(container_id):
                    break
                time.sleep(2)
            if not is_running(container_id):
                raise RuntimeError("wazuh.indexer não ficou running")

        evidence.append("INDEXER_RUNNING=YES")
        state, _ = wait_for_classified_health(container_id, args.timeout)
        evidence.append(f"SECURITY_INDEX_STATE={state}")

        if state == "INITIALIZED":
            evidence.extend(
                [
                    "SECURITYADMIN_EXECUTED=NO",
                    "WAZUH_SECURITY_INDEX_BOOTSTRAP=PASS_ALREADY_INITIALIZED",
                ]
            )
            write_evidence(evidence)
            return 0

        if state != "NOT_INITIALIZED":
            evidence.extend(
                [
                    "SECURITYADMIN_EXECUTED=NO",
                    "WAZUH_SECURITY_INDEX_BOOTSTRAP=BLOCKED_AMBIGUOUS_STATE",
                ]
            )
            write_evidence(evidence)
            return 2

        if not args.apply:
            evidence.extend(
                [
                    "SECURITYADMIN_EXECUTED=NO",
                    "WAZUH_SECURITY_INDEX_BOOTSTRAP=READY_FOR_EXPLICIT_APPLY",
                    f"CONFIRM_TOKEN={CONFIRM_TOKEN}",
                ]
            )
            write_evidence(evidence)
            return 2

        ensure_security_dir(container_id)
        proc = run(
            securityadmin_args(container_id),
            timeout=max(args.timeout, 90),
        )
        evidence.append(f"SECURITYADMIN_RC={proc.returncode}")
        if proc.returncode != 0:
            evidence.append("WAZUH_SECURITY_INDEX_BOOTSTRAP=FAIL_SECURITYADMIN")
            write_evidence(evidence)
            return 1

        state, _ = wait_for_classified_health(container_id, args.timeout)
        evidence.append(f"SECURITY_INDEX_POST_APPLY={state}")
        if state != "INITIALIZED":
            evidence.append("WAZUH_SECURITY_INDEX_BOOTSTRAP=FAIL_POST_VERIFY")
            write_evidence(evidence)
            return 1

        evidence.extend(
            [
                "SECURITYADMIN_EXECUTED=YES",
                "WAZUH_SECURITY_INDEX_BOOTSTRAP=PASS",
            ]
        )
        write_evidence(evidence)
        return 0

    except (RuntimeError, subprocess.TimeoutExpired, OSError) as exc:
        evidence.append(f"ERROR_TYPE={type(exc).__name__}")
        evidence.append("WAZUH_SECURITY_INDEX_BOOTSTRAP=FAIL")
        try:
            write_evidence(evidence)
        except OSError:
            pass
        print(f"ERRO: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
