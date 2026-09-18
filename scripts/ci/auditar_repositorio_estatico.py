#!/usr/bin/env python3
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]

PASS = 0
WARN = 0
FAIL = 0


def mark(kind: str, message: str) -> None:
    global PASS, WARN, FAIL
    if kind == "PASS":
        PASS += 1
    elif kind == "WARN":
        WARN += 1
    elif kind == "FAIL":
        FAIL += 1
    print(f"[{kind}] {message}")


def tracked_files() -> list[Path]:
    cp = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        capture_output=True,
        check=True,
    )
    return [
        ROOT / item.decode("utf-8")
        for item in cp.stdout.split(b"\0")
        if item
    ]


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def check_empty_files(files: list[Path]) -> None:
    bad = []
    for path in files:
        if not path.is_file():
            continue
        if path.stat().st_size != 0:
            continue
        if path.name == ".gitkeep":
            continue
        bad.append(rel(path))

    if bad:
        for item in bad:
            mark("FAIL", f"arquivo rastreado vazio sem função explícita: {item}")
    else:
        mark("PASS", "nenhum arquivo rastreado vazio fora de .gitkeep")


def check_secret_hygiene(files: list[Path]) -> None:
    bad = []

    for path in files:
        item = rel(path)

        if re.search(r"(^|/)\.runtime(/|$)", item):
            bad.append((item, ".runtime rastreado"))
            continue

        name = path.name
        if name == ".env":
            bad.append((item, ".env real rastreado"))
            continue

        if name.startswith(".env.") and name not in {
            ".env.example",
            ".env.test.example",
        }:
            bad.append((item, "arquivo .env não permitido rastreado"))
            continue

        if re.search(r"\.(pem|key|p12|pfx)$", item, re.I):
            if not (
                item.startswith("tests/")
                or item.startswith("scripts/evidencias/")
            ):
                bad.append((item, "chave/keystore rastreado fora de fixture"))

    if bad:
        for item, reason in bad:
            mark("FAIL", f"{reason}: {item}")
    else:
        mark("PASS", "nenhum runtime/.env real/chave privada indevida rastreada")


def check_workflows(files: list[Path]) -> None:
    workflows = [
        p for p in files
        if rel(p).startswith(".github/workflows/")
        and p.suffix in {".yml", ".yaml"}
    ]

    if not workflows:
        mark("WARN", "nenhum workflow GitHub Actions encontrado")
        return

    action_ref = re.compile(r"^\s*-?\s*uses:\s*([^\s#]+)")
    checkout_sha = re.compile(r"^[0-9a-f]{40}$")

    for path in workflows:
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()

        if re.search(r"runs-on:\s*[^\n]*-latest\b", text):
            mark("FAIL", f"runner flutuante '*-latest': {rel(path)}")

        for idx, line in enumerate(lines):
            m = action_ref.match(line)
            if not m:
                continue

            value = m.group(1)
            if value.startswith("./"):
                continue

            if "@" not in value:
                mark("FAIL", f"GitHub Action sem ref: {rel(path)}:{idx + 1}")
                continue

            action, ref_value = value.rsplit("@", 1)
            if not checkout_sha.fullmatch(ref_value):
                mark(
                    "FAIL",
                    f"GitHub Action não pinada por SHA: "
                    f"{rel(path)}:{idx + 1} ({action}@{ref_value})",
                )

            if action == "actions/checkout":
                window = "\n".join(lines[idx + 1: idx + 8])
                if not re.search(
                    r"persist-credentials:\s*false\b",
                    window,
                ):
                    mark(
                        "FAIL",
                        f"checkout sem persist-credentials:false: "
                        f"{rel(path)}:{idx + 1}",
                    )

    mark("PASS", f"workflows auditados={len(workflows)}")


def check_operational_modes(files: list[Path]) -> None:
    cp = subprocess.run(
        ["git", "ls-files", "--stage"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )

    modes: dict[str, str] = {}
    for raw in cp.stdout.splitlines():
        if "\t" not in raw:
            continue
        meta, path = raw.split("\t", 1)
        mode = meta.split()[0]
        modes[path] = mode

    expected = [
        rel(path)
        for path in files
        if path.suffix in {".sh", ".py"}
        and (
            rel(path).startswith("scripts/")
            or rel(path).startswith("deploy/")
        )
    ]

    bad = [
        (path, modes.get(path, "UNKNOWN"))
        for path in expected
        if modes.get(path) != "100755"
    ]

    if bad:
        for path, mode in bad:
            mark(
                "FAIL",
                f"script operacional sem modo executável 100755: {path} mode={mode}",
            )
    else:
        mark("PASS", f"modo executável confirmado em {len(expected)} scripts operacionais")


def check_python(files: list[Path]) -> None:
    python_files = [p for p in files if p.suffix == ".py"]

    with tempfile.TemporaryDirectory(prefix="conectaeduca-pycache-") as td:
        env = os.environ.copy()
        env["PYTHONPYCACHEPREFIX"] = td

        failures = 0
        for path in python_files:
            cp = subprocess.run(
                [sys.executable, "-m", "py_compile", str(path)],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
            )
            if cp.returncode != 0:
                failures += 1
                mark(
                    "FAIL",
                    f"Python inválido: {rel(path)}: "
                    f"{(cp.stderr or cp.stdout).strip()}",
                )

    if failures == 0:
        mark("PASS", f"Python py_compile aprovado em {len(python_files)} arquivos")


def check_shell(files: list[Path]) -> None:
    shell_files = [p for p in files if p.suffix == ".sh"]

    bash = shutil.which("bash")
    sh = shutil.which("sh")

    if not bash or not sh:
        mark("FAIL", "bash/sh indisponível para auditoria")
        return

    failures = 0
    skipped = 0

    for path in shell_files:
        first = ""
        try:
            first = path.read_text(
                encoding="utf-8",
                errors="replace",
            ).splitlines()[0]
        except IndexError:
            failures += 1
            mark("FAIL", f"script shell vazio: {rel(path)}")
            continue

        if "bash" in first:
            shell = bash
        elif re.search(r"(^|/)sh\b", first):
            shell = sh
        else:
            skipped += 1
            mark(
                "WARN",
                f"shebang shell não reconhecido; syntax check omitido: {rel(path)}",
            )
            continue

        cp = subprocess.run(
            [shell, "-n", str(path)],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        if cp.returncode != 0:
            failures += 1
            mark(
                "FAIL",
                f"shell syntax inválida: {rel(path)}: "
                f"{(cp.stderr or cp.stdout).strip()}",
            )

    if failures == 0:
        mark(
            "PASS",
            f"shell syntax aprovada em {len(shell_files) - skipped} arquivos "
            f"(omitidos={skipped})",
        )


def check_json(files: list[Path]) -> None:
    json_files = [p for p in files if p.suffix == ".json"]
    failures = 0

    for path in json_files:
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            failures += 1
            mark("FAIL", f"JSON inválido: {rel(path)}: {exc}")

    if failures == 0:
        mark("PASS", f"JSON válido em {len(json_files)} arquivos")


def check_structured_formats(files: list[Path]) -> None:
    xml_files = [p for p in files if p.suffix.lower() == ".xml"]
    toml_files = [p for p in files if p.suffix.lower() == ".toml"]

    xml_failures = 0
    for path in xml_files:
        try:
            ET.parse(path)
        except Exception as exc:
            xml_failures += 1
            mark("FAIL", f"XML inválido: {rel(path)}: {exc}")

    if xml_failures == 0:
        mark("PASS", f"XML válido em {len(xml_files)} arquivos")

    toml_failures = 0
    for path in toml_files:
        try:
            with path.open("rb") as fh:
                tomllib.load(fh)
        except Exception as exc:
            toml_failures += 1
            mark("FAIL", f"TOML inválido: {rel(path)}: {exc}")

    if toml_failures == 0:
        mark("PASS", f"TOML válido em {len(toml_files)} arquivos")


def check_markdown_links(files: list[Path]) -> None:
    markdown_files = [p for p in files if p.suffix.lower() == ".md"]
    link_re = re.compile(r"!?(?:\[[^\]]*\])\(([^)]+)\)")
    broken: list[tuple[str, int, str]] = []

    for path in markdown_files:
        text = path.read_text(encoding="utf-8", errors="replace")
        for number, line in enumerate(text.splitlines(), 1):
            for match in link_re.finditer(line):
                raw = match.group(1).strip()
                if not raw:
                    continue

                if raw.startswith("<") and ">" in raw:
                    raw = raw[1:raw.index(">")].strip()
                else:
                    raw = raw.split()[0].strip()

                target = raw.split("#", 1)[0]
                if not target:
                    continue

                if re.match(
                    r"^(?:https?://|mailto:|data:|ui://|sandbox:)",
                    target,
                    re.I,
                ):
                    continue

                # Caminhos absolutos em documentação normalmente descrevem
                # runtime do host, não links relativos ao repositório.
                if target.startswith("/"):
                    continue

                candidate = (path.parent / target).resolve()
                try:
                    candidate.relative_to(ROOT)
                except ValueError:
                    broken.append((rel(path), number, raw))
                    continue

                if not candidate.exists():
                    broken.append((rel(path), number, raw))

    if broken:
        for doc, number, target in broken:
            mark(
                "FAIL",
                f"link Markdown local quebrado: {doc}:{number} -> {target}",
            )
    else:
        mark("PASS", f"links Markdown locais válidos em {len(markdown_files)} documentos")


def check_compose_invariants(files: list[Path]) -> None:
    compose_files = [
        p for p in files
        if p.suffix in {".yml", ".yaml"}
        and p.name.startswith("compose")
        and rel(p).startswith("deploy/")
    ]

    host_network_allowlist = {
        "deploy/interna/twingate/compose.yml",
    }

    failures = 0

    for path in compose_files:
        item = rel(path)
        text = path.read_text(encoding="utf-8", errors="replace")

        for number, line in enumerate(text.splitlines(), 1):
            if re.match(r"^\s*privileged:\s*true\s*(?:#.*)?$", line):
                failures += 1
                mark("FAIL", f"Compose privileged:true: {item}:{number}")

            if "/var/run/docker.sock" in line:
                failures += 1
                mark("FAIL", f"Compose monta docker.sock: {item}:{number}")

            if re.match(r"^\s*network_mode:\s*host\s*(?:#.*)?$", line):
                if item not in host_network_allowlist:
                    failures += 1
                    mark(
                        "FAIL",
                        f"network_mode:host fora da allowlist: {item}:{number}",
                    )

            m = re.match(r"^\s*image:\s*([^#\s]+)", line)
            if m and re.search(r":latest(?:@|$)", m.group(1)):
                failures += 1
                mark("FAIL", f"imagem Compose usa :latest: {item}:{number}")

    if failures == 0:
        mark(
            "PASS",
            f"invariantes Compose aprovadas em {len(compose_files)} arquivos",
        )


def check_script_antipatterns(files: list[Path]) -> None:
    script_files = [
        p for p in files
        if p.suffix in {".sh", ".py", ".php", ".fish"}
        and (
            rel(p).startswith("scripts/")
            or rel(p).startswith("deploy/")
        )
        # Evita self-match nas regex/descrições deste próprio detector.
        and rel(p) != "scripts/ci/auditar_repositorio_estatico.py"
    ]

    checks = [
        (
            re.compile(r"\bsudo\s+-s\b"),
            "shell root persistente via sudo -s",
        ),
        (
            re.compile(r"\bsudo\s+su(?:\s|$)"),
            "shell root persistente via sudo su",
        ),
        (
            re.compile(r"\bchmod\s+0?777\b"),
            "chmod 777",
        ),
        (
            re.compile(r"\b(?:chmod|chown)\b[^#\n]*\|\|\s*true"),
            "falha de chmod/chown suprimida com || true",
        ),
    ]

    found = 0

    permission_targets = list(script_files)
    makefile = ROOT / "Makefile"
    if makefile in files:
        permission_targets.append(makefile)

    for path in permission_targets:
        text = path.read_text(encoding="utf-8", errors="replace")
        for number, line in enumerate(text.splitlines(), 1):
            for pattern, reason in checks:
                if pattern.search(line):
                    found += 1
                    mark(
                        "FAIL",
                        f"{reason}: {rel(path)}:{number}",
                    )

    if found == 0:
        mark("PASS", "nenhum antipadrão de privilégio/permissão nos scripts auditados")


def main() -> int:
    print("=== ConectaEduca — auditoria estática do repositório ===")
    print(f"ROOT={ROOT}")

    files = tracked_files()
    print(f"TRACKED_FILES={len(files)}")

    check_empty_files(files)
    check_secret_hygiene(files)
    check_workflows(files)
    check_operational_modes(files)
    check_python(files)
    check_shell(files)
    check_json(files)
    check_structured_formats(files)
    check_markdown_links(files)
    check_compose_invariants(files)
    check_script_antipatterns(files)

    final = "FAIL" if FAIL else ("WARN" if WARN else "PASS")
    print("")
    print("=== SUMMARY ===")
    print(f"PASS={PASS}")
    print(f"WARN={WARN}")
    print(f"FAIL={FAIL}")
    print(f"FINAL={final}")

    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())