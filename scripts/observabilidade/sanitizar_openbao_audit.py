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


def follow_container(container: str, output_path: Path, docker_bin: str):
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o640)
    os.fchmod(fd, 0o640)

    since = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(seconds=2)).isoformat()

    proc = subprocess.Popen(
        [docker_bin, "logs", "--follow", "--since", since, container],
        stdout=subprocess.PIPE,
        stderr=sys.stderr,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
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


def main() -> int:
    ap = argparse.ArgumentParser()
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--stdin", action="store_true")
    mode.add_argument("--follow", action="store_true")
    ap.add_argument("--container", default="conectaeduca-openbao")
    ap.add_argument("--output")
    ap.add_argument("--docker-bin", default="/usr/bin/docker")
    args = ap.parse_args()

    if args.stdin:
        process_stream(sys.stdin, sys.stdout)
        return 0

    if not args.output:
        ap.error("--follow exige --output")

    follow_container(args.container, Path(args.output), args.docker_bin)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
