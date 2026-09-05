#!/usr/bin/env python3
"""Converte relatório JSON bruto do Ferret em eventos JSONL minimizados para SIEM.

O contrato é deliberadamente allowlist-only: campos como results[].text,
results[].filename e metadata não aprovados nunca são propagados.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

FERRET_VERSION = "2.4.3"
SCHEMA_VERSION = "1"
HEX64_RE = re.compile(r"^[0-9a-f]{64}$")

REPO_ROOT = Path(__file__).resolve().parents[2]
FERRET_RUNTIME = REPO_ROOT / "deploy/interna/ferret/.runtime"
RAW_REPORTS_DIR = FERRET_RUNTIME / "reports/raw"
EVENTS_DIR = FERRET_RUNTIME / "events"


def die(message: str) -> "NoReturn":
    print(f"ERRO: {message}", file=sys.stderr)
    raise SystemExit(2)


def safe_text(value: Any, *, field: str, max_len: int = 128, allow_empty: bool = True) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        die(f"campo {field} deve ser string")
    cleaned = "".join(ch for ch in value if ch >= " " and ch != "\x7f").strip()
    if not allow_empty and not cleaned:
        die(f"campo {field} não pode ser vazio")
    return cleaned[:max_len]


def safe_int(value: Any, *, field: str, minimum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        die(f"campo {field} deve ser inteiro")
    if minimum is not None and value < minimum:
        die(f"campo {field} deve ser >= {minimum}")
    return value


def safe_float(value: Any, *, field: str, minimum: float | None = None) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        die(f"campo {field} deve ser numérico")
    result = float(value)
    if minimum is not None and result < minimum:
        die(f"campo {field} deve ser >= {minimum}")
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="relatorio JSON bruto do Ferret")
    parser.add_argument("--output", required=True, help="arquivo JSONL minimizado")
    parser.add_argument("--file-id", required=True, help="SHA-256 do artefato analisado")
    return parser.parse_args()


def _from_repo(value: str) -> Path:
    candidate = Path(value).expanduser()
    if not candidate.is_absolute():
        candidate = REPO_ROOT / candidate
    return candidate


def resolve_input_path(value: str) -> Path:
    """Resolve somente arquivos que ja existem na area raw aprovada.

    O argumento da CLI nunca e convertido em Path nem concatenado com uma base.
    Ele funciona apenas como chave de comparacao contra arquivos descobertos
    diretamente no diretorio runtime fixo. Isso elimina traversal por construcao.
    """
    try:
        base = RAW_REPORTS_DIR.resolve(strict=True)
        repo = REPO_ROOT.resolve(strict=True)
        entries = tuple(base.iterdir())
    except OSError as exc:
        die(f"--input invalido: {exc}")

    for entry in entries:
        if entry.is_symlink() or not entry.is_file():
            continue

        try:
            resolved = entry.resolve(strict=True)
        except OSError:
            continue

        accepted = {entry.name, str(resolved)}
        try:
            accepted.add(str(resolved.relative_to(repo)))
        except ValueError:
            pass

        if value in accepted:
            return resolved

    die("--input deve identificar arquivo regular existente dentro de .runtime/reports/raw")


def resolve_output_path(value: str) -> Path:
    candidate = _from_repo(value)

    # O diretorio events e criado pelo bootstrap/pipeline antes desta chamada.
    try:
        base = EVENTS_DIR.resolve(strict=True)
        parent = candidate.parent.resolve(strict=True)
    except OSError as exc:
        die(f"--output invalido: {exc}")

    if not parent.is_relative_to(base):
        die("--output deve permanecer dentro de .runtime/events")

    if candidate.exists() and candidate.is_symlink():
        die("--output nao pode ser link simbolico")

    if candidate.name in {"", ".", ".."}:
        die("--output possui nome invalido")

    return parent / candidate.name


def load_report(path: Path) -> tuple[dict[str, Any], str, bool]:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        die(f"não foi possível ler {path}: {exc}")

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        die(f"JSON inválido em {path}: {exc}")

    if not isinstance(data, dict):
        die("raiz do relatório Ferret 2.4.3 deve ser objeto JSON")
    if not isinstance(data.get("results"), list):
        die("relatório Ferret sem results[]")
    if not isinstance(data.get("stats"), dict):
        die("relatório Ferret sem stats{}")
    return data, "object", True


def build_events(
    data: dict[str, Any], file_id: str, source_report_shape: str, stats_complete: bool
) -> list[dict[str, Any]]:
    if not HEX64_RE.fullmatch(file_id):
        die("--file-id deve ser SHA-256 hexadecimal de 64 caracteres")

    results = data["results"]
    stats = data["stats"]
    observed_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    scan_id = str(uuid.uuid4())

    summary = {
        "schema_version": SCHEMA_VERSION,
        "event_type": "dlp_scan_summary",
        "source": "ferret-scan",
        "source_version": FERRET_VERSION,
        "observed_at": observed_at,
        "scan_id": scan_id,
        "file_id": file_id,
        "files_processed": safe_int(stats.get("files_processed", 0), field="stats.files_processed", minimum=0),
        "files_skipped": safe_int(stats.get("files_skipped", 0), field="stats.files_skipped", minimum=0),
        "total_findings": safe_int(stats.get("total_findings", 0), field="stats.total_findings", minimum=0),
        "emitted_findings": len(results),
        "high": safe_int(stats.get("high", 0), field="stats.high", minimum=0),
        "medium": safe_int(stats.get("medium", 0), field="stats.medium", minimum=0),
        "low": safe_int(stats.get("low", 0), field="stats.low", minimum=0),
        "suppressed": safe_int(stats.get("suppressed", 0), field="stats.suppressed", minimum=0),
        "duration_seconds": safe_float(stats.get("duration_seconds", 0.0), field="stats.duration_seconds", minimum=0.0),
        "source_report_shape": source_report_shape,
        "stats_complete": stats_complete,
        "sanitization_profile": "conectaeduca-allowlist-v1",
    }

    events: list[dict[str, Any]] = [summary]

    for index, item in enumerate(results, start=1):
        if not isinstance(item, dict):
            die(f"results[{index - 1}] deve ser objeto")

        metadata = item.get("metadata")
        if metadata is None:
            metadata = {}
        if not isinstance(metadata, dict):
            die(f"results[{index - 1}].metadata deve ser objeto")

        event = {
            "schema_version": SCHEMA_VERSION,
            "event_type": "dlp_finding",
            "source": "ferret-scan",
            "source_version": FERRET_VERSION,
            "observed_at": observed_at,
            "scan_id": scan_id,
            "finding_index": index,
            "file_id": file_id,
            "validator": safe_text(item.get("validator", ""), field="results[].validator"),
            "finding_type": safe_text(item.get("type", ""), field="results[].type"),
            "confidence_level": safe_text(item.get("confidence_level", ""), field="results[].confidence_level"),
            "confidence": safe_int(item.get("confidence", 0), field="results[].confidence", minimum=0),
            "line_number": safe_int(item.get("line_number", 0), field="results[].line_number", minimum=0),
            "secret_type": safe_text(metadata.get("secret_type", ""), field="results[].metadata.secret_type"),
            "detection_method": safe_text(metadata.get("detection_method", ""), field="results[].metadata.detection_method"),
            "environment_type": safe_text(metadata.get("environment_type", ""), field="results[].metadata.environment_type"),
            "sanitization_profile": "conectaeduca-allowlist-v1",
        }
        events.append(event)

    return events


def append_jsonl(path: Path, events: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.umask(0o077)

    payload = "".join(json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n" for event in events)

    flags = os.O_WRONLY | os.O_CREAT | os.O_APPEND
    flags |= getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags, 0o600)
    try:
        with os.fdopen(fd, "a", encoding="utf-8", closefd=False) as handle:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    finally:
        os.close(fd)


def main() -> int:
    args = parse_args()
    input_path = resolve_input_path(args.input)
    output_path = resolve_output_path(args.output)

    data, source_report_shape, stats_complete = load_report(input_path)
    events = build_events(data, args.file_id, source_report_shape, stats_complete)
    append_jsonl(output_path, events)

    findings = sum(1 for event in events if event["event_type"] == "dlp_finding")
    print(f"OK: evento(s) DLP sanitizados: summary=1 findings={findings}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
