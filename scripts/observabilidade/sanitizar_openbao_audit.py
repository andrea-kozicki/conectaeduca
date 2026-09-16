#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ALLOWED_KEYS = (
    "schema_version",
    "source",
    "event_type",
    "timestamp",
    "audit_type",
    "operation",
    "path_class",
    "result",
)

RFC3339 = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$")
SAFE_OPERATION = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")

# O bridge possui uma única fonte e um único destino operacionais. Eles não são
# parâmetros livres: isso evita trocar o executável do subprocess ou redirecionar
# o serviço para um arquivo arbitrário.
DOCKER_BIN = "/usr/bin/docker"
OPENBAO_CONTAINER = "conectaeduca-openbao"
REPO_ROOT = Path(__file__).resolve().parents[2]
EVENT_DIR = REPO_ROOT / "deploy/interna/openbao/.runtime/events"
EVENT_FILE = EVENT_DIR / "openbao-audit.jsonl"


def classify_path(path: str) -> str:
    path = (path or "").strip().lstrip("/")
    if path == "auth/approle/login":
        return "auth_approle_login"
    if path == "secret/data/conectaeduca/smtp":
        return "kv_smtp"
    if path.startswith("secret/data/conectaeduca/"):
        return "kv_conectaeduca_other"
    if path == "sys/health":
        return "sys_health"
    if path.startswith("sys/generate-root"):
        return "sys_generate_root"
    if path.startswith("auth/"):
        return "auth_other"
    if path.startswith("secret/"):
        return "kv_other"
    if path.startswith("sys/"):
        return "sys_other"
    return "other"


def safe_timestamp(value: object) -> str:
    if isinstance(value, str) and len(value) <= 64 and RFC3339.match(value):
        return value
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def safe_operation(value: object) -> str:
    if isinstance(value, str):
        value = value.strip().lower()
        if SAFE_OPERATION.match(value):
            return value
    return "unknown"


def derive_result(event: dict) -> str:
    if event.get("error"):
        return "error"

    response = event.get("response")
    if isinstance(response, dict):
        data = response.get("data")
        if isinstance(data, dict) and data.get("error"):
            return "error"

    auth = event.get("auth")
    if isinstance(auth, dict):
        policy = auth.get("policy_results")
        if isinstance(policy, dict):
            allowed = policy.get("allowed")
            if allowed is True:
                return "allowed"
            if allowed is False:
                return "denied"

    if event.get("type") == "response":
        return "completed"
    return "unknown"


def sanitize(event: dict) -> dict | None:
    audit_type = event.get("type")
    if audit_type not in ("request", "response"):
        return None

    req = event.get("request")
    if not isinstance(req, dict):
        req = {}

    result = {
        "schema_version": "1",
        "source": "openbao-audit",
        "event_type": "openbao_audit",
        "timestamp": safe_timestamp(event.get("time")),
        "audit_type": audit_type,
        "operation": safe_operation(req.get("operation")),
        "path_class": classify_path(str(req.get("path") or "")),
        "result": derive_result(event),
    }

    if tuple(result.keys()) != ALLOWED_KEYS:
        raise RuntimeError("allowlist de campos foi alterada")
    return result


def process_stream(stream, output):
    for raw in stream:
        line = raw.strip()
        if not line.startswith("{"):
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        clean = sanitize(event)
        if clean is None:
            continue
        output.write(json.dumps(clean, ensure_ascii=False, separators=(",", ":")) + "\n")
        output.flush()


def _open_event_file() -> int:
    EVENT_DIR.mkdir(parents=True, exist_ok=True)
    if EVENT_DIR.is_symlink():
        raise RuntimeError("diretório de eventos não pode ser symlink")

    flags = os.O_WRONLY | os.O_CREAT | os.O_APPEND
    flags |= getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(EVENT_FILE, flags, 0o640)
    os.fchmod(fd, 0o640)
    return fd


def follow_container() -> None:
    if not os.path.isfile(DOCKER_BIN) or not os.access(DOCKER_BIN, os.X_OK):
        raise RuntimeError(f"docker indisponível no caminho confiável: {DOCKER_BIN}")

    fd = _open_event_file()
    since = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(seconds=2)).isoformat()

    # O projeto suporta Python >= 3.10. As regras de compatibilidade abaixo
    # sinalizam apenas que `errors=` e `encoding=` exigem Python >= 3.6;
    # portanto são N/A para o runtime suportado. A supressão é restrita a
    # essas duas regras e não desativa verificações de segurança do subprocess.
    proc = subprocess.Popen(  # nosemgrep: python36-compatibility-Popen1, python36-compatibility-Popen2
        [DOCKER_BIN, "logs", "--follow", "--since", since, OPENBAO_CONTAINER],
        stdout=subprocess.PIPE,
        stderr=sys.stderr,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
        shell=False,
    )

    try:
        with os.fdopen(fd, "a", encoding="utf-8", buffering=1) as out:
            assert proc.stdout is not None
            process_stream(proc.stdout, out)
    finally:
        if proc.poll() is None:
            proc.terminate()
        rc = proc.wait(timeout=10)
        if rc not in (0, -15):
            raise SystemExit(rc)


def _legacy_exact(expected: str, option: str):
    """Aceita apenas o valor histórico exato durante a migração da unit systemd."""
    def validate(value: str) -> str:
        if value != expected:
            raise argparse.ArgumentTypeError(f"{option} não aceita valor customizado")
        return expected
    return validate


def main() -> int:
    ap = argparse.ArgumentParser()
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--stdin", action="store_true")
    mode.add_argument("--follow", action="store_true")

    # Compatibilidade temporária com a unit já instalada. Os valores são
    # validados contra constantes e deliberadamente NÃO alimentam nenhum sink.
    ap.add_argument(
        "--container",
        type=_legacy_exact(OPENBAO_CONTAINER, "--container"),
        help=argparse.SUPPRESS,
    )
    ap.add_argument(
        "--output",
        type=_legacy_exact(str(EVENT_FILE), "--output"),
        help=argparse.SUPPRESS,
    )
    ap.add_argument(
        "--docker-bin",
        type=_legacy_exact(DOCKER_BIN, "--docker-bin"),
        help=argparse.SUPPRESS,
    )
    args = ap.parse_args()

    if args.stdin:
        process_stream(sys.stdin, sys.stdout)
        return 0

    follow_container()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
