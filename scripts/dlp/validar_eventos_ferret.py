#!/usr/bin/env python3
"""Valida o contrato JSONL minimizado do DLP ConectaEduca."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

HEX64_RE = re.compile(r"^[0-9a-f]{64}$")
REPO_ROOT = Path(__file__).resolve().parents[2]
EVENTS_DIR = REPO_ROOT / "deploy/interna/ferret/.runtime/events"
COMMON_KEYS = {
    "schema_version", "event_type", "source", "source_version", "observed_at",
    "scan_id", "file_id", "sanitization_profile",
}
SUMMARY_KEYS = COMMON_KEYS | {
    "files_processed", "files_skipped", "total_findings", "emitted_findings", "high", "medium",
    "low", "suppressed", "duration_seconds", "source_report_shape", "stats_complete",
}
FINDING_KEYS = COMMON_KEYS | {
    "finding_index", "validator", "finding_type", "confidence_level", "confidence",
    "line_number", "secret_type", "detection_method", "environment_type",
}
PROHIBITED_KEYS = {"text", "filename", "match", "content", "original_text", "snippet"}


def fail(message: str) -> "NoReturn":
    print(f"ERRO: {message}", file=sys.stderr)
    raise SystemExit(2)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--min-findings", type=int, default=0)
    p.add_argument("--max-findings", type=int)
    p.add_argument("--forbid-substring")
    return p.parse_args()


def resolve_event_path(value: str) -> Path:
    """Seleciona apenas evento ja existente dentro do runtime fixo.

    A entrada da CLI e tratada como identificador textual. O caminho retornado
    vem da enumeracao do diretorio EVENTS_DIR, nunca de concatenacao com input.
    """
    try:
        base = EVENTS_DIR.resolve(strict=True)
        repo = REPO_ROOT.resolve(strict=True)
        entries = tuple(base.iterdir())
    except OSError as exc:
        fail(f"--input invalido: {exc}")

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

    fail("--input deve identificar arquivo regular existente dentro de .runtime/events")


def iter_keys(value: Any):
    if isinstance(value, dict):
        for key, child in value.items():
            yield key
            yield from iter_keys(child)
    elif isinstance(value, list):
        for child in value:
            yield from iter_keys(child)


def main() -> int:
    args = parse_args()
    path = resolve_event_path(args.input)
    raw = path.read_text(encoding="utf-8")
    if args.forbid_substring and args.forbid_substring in raw:
        fail("substring proibida encontrada no JSONL")

    events = []
    for line_no, line in enumerate(raw.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError as exc:
            fail(f"linha {line_no}: JSON inválido: {exc}")
        if not isinstance(event, dict):
            fail(f"linha {line_no}: evento deve ser objeto")
        events.append(event)

    if not events:
        fail("JSONL sem eventos")

    summaries = [e for e in events if e.get("event_type") == "dlp_scan_summary"]
    findings = [e for e in events if e.get("event_type") == "dlp_finding"]

    if len(summaries) != 1:
        fail(f"esperado 1 summary; encontrado(s) {len(summaries)}")

    summary = summaries[0]
    if summary.get("emitted_findings") != len(findings):
        fail("summary.emitted_findings diverge da quantidade de dlp_finding")

    report_shape = summary.get("source_report_shape")
    if report_shape != "object":
        fail("summary.source_report_shape deve ser object no baseline Ferret 2.4.3")
    if summary.get("stats_complete") is not True:
        fail("summary.stats_complete deve ser true no baseline Ferret 2.4.3")

    if len(findings) < args.min_findings:
        fail(f"findings={len(findings)} abaixo do mínimo {args.min_findings}")
    if args.max_findings is not None and len(findings) > args.max_findings:
        fail(f"findings={len(findings)} acima do máximo {args.max_findings}")

    for idx, event in enumerate(events, start=1):
        keys = set(event)
        event_type = event.get("event_type")
        if event_type not in {"dlp_scan_summary", "dlp_finding"}:
            fail(f"evento {idx}: event_type inesperado")
        allowed = SUMMARY_KEYS if event_type == "dlp_scan_summary" else FINDING_KEYS
        unknown = keys - allowed
        if unknown:
            fail(f"evento {idx}: campo(s) fora da allowlist: {sorted(unknown)}")

        prohibited = set(iter_keys(event)) & PROHIBITED_KEYS
        if prohibited:
            fail(f"evento {idx}: campo(s) proibido(s): {sorted(prohibited)}")

        if event.get("schema_version") != "1":
            fail(f"evento {idx}: schema_version inesperado")
        if event.get("source") != "ferret-scan":
            fail(f"evento {idx}: source inesperado")
        if event.get("source_version") != "2.4.3":
            fail(f"evento {idx}: source_version inesperado")
        if event.get("sanitization_profile") != "conectaeduca-allowlist-v1":
            fail(f"evento {idx}: sanitization_profile inesperado")
        if not HEX64_RE.fullmatch(str(event.get("file_id", ""))):
            fail(f"evento {idx}: file_id inválido")

    print(f"OK: contrato JSONL válido; summaries=1 findings={len(findings)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
