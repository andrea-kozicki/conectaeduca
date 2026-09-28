#!/usr/bin/env python3
from __future__ import annotations

import ast
import datetime as dt
import hashlib
import os
import re
import subprocess
from pathlib import Path

UTC = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%SZ")

PASS = 0
WARN = 0
FAIL = 0


def run(cmd: list[str], cwd: Path | None = None) -> tuple[int, str, str]:
    p = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    return p.returncode, p.stdout.rstrip(), p.stderr.rstrip()


def emit(line: str = "") -> None:
    print(line)


def passed(msg: str) -> None:
    global PASS
    PASS += 1
    emit(f"[PASS] {msg}")


def warn(msg: str) -> None:
    global WARN
    WARN += 1
    emit(f"[WARN] {msg}")


def fail(msg: str) -> None:
    global FAIL
    FAIL += 1
    emit(f"[FAIL] {msg}")


rc, root_out, _ = run(["git", "rev-parse", "--show-toplevel"])
if rc != 0:
    raise SystemExit("ERROR: execute dentro do repositorio Git")

ROOT = Path(root_out).resolve()
REPORT = Path.home() / f"conectaeduca-prefreeze-repo-gate-{UTC}.txt"

lines: list[str] = []


def capture(line: str = "") -> None:
    lines.append(line)
    emit(line)


def p2(msg: str) -> None:
    global PASS
    PASS += 1
    capture(f"[PASS] {msg}")


def w2(msg: str) -> None:
    global WARN
    WARN += 1
    capture(f"[WARN] {msg}")


def f2(msg: str) -> None:
    global FAIL
    FAIL += 1
    capture(f"[FAIL] {msg}")


capture("=== CONECTAEDUCA PREFREEZE REPO GATE ===")
capture(f"utc={UTC}")
capture(f"root={ROOT}")
capture("mode=READ_ONLY_REPOSITORY_CHECK")
capture("runtime_vm_changes=0")
capture("sudo_used=0")
capture("docker_used=0")

required = [
    "docs/BACKLOG-TECNICO.md",
    "docs/plano-testes.md",
    "docs/release/HANDOFF-FINAL.md",
    "docs/release/RETOMADA-VM-20260924.md",
    "docs/release/ROTEIRO-DEMONSTRACAO-FINAL.md",
    "docs/release/INDICE-EVIDENCIAS-FINAIS.md",
    "docs/release/CHECKLIST-FECHAMENTO-ACADEMICO.md",
    "docs/seguranca/MITRE-ATTACK-MATRIZ-FINAL.md",
    "docs/seguranca/APPSEC-BASELINE-PREFREEZE.md",
    "docs/seguranca/APPSEC-04-SNYK-REVALIDATION.md",
    "docs/seguranca/OPS01-EP126-READONLY.md",
    "docs/evidencias/suricata-eve-stats-wazuh-field-limit-20260927.md",
    "deploy/pfsense/LOGGING-WAZUH.md",
    "docs/seguranca/PENTEST-SEM-SUDO.md",
    "docs/seguranca/PENTEST-S01-S13-ZERO-SUDO.md",
    "docs/seguranca/PENTEST-COMANDOS-S01-S13.md",
    "deploy/interna/mariadb/PHPMYADMIN-READONLY.md",
    "scripts/implantacao/materializar_pentest_principal_uid.py",
    "scripts/dlp/submeter_ferret_pentest.py",
    "scripts/evidencias/gui01c_phpmyadmin_precheck.py",
    "scripts/evidencias/pentest_no_sudo_readiness.py",
    "scripts/evidencias/pentest_sem_sudo_runtime_check.py",
    "scripts/evidencias/ops01_ep126_readonly.py",
    "scripts/evidencias/pfsense_wazuh_postreboot_readonly.py",
    "scripts/evidencias/appsec04_snyk_revalidation.py",
]

capture()
capture("=== REQUIRED ARTIFACTS ===")
for rel in required:
    path = ROOT / rel
    if path.is_file():
        p2(rel)
    else:
        f2(f"missing: {rel}")

capture()
capture("=== GIT STATE ===")
rc, branch, _ = run(["git", "branch", "--show-current"], ROOT)
capture(f"branch={branch if rc == 0 else 'unknown'}")
if branch == "main":
    p2("branch main")
else:
    w2("gate final deve ser repetido na main")

rc, dirty, _ = run(["git", "status", "--short"], ROOT)
if rc == 0 and not dirty.strip():
    p2("working tree clean")
else:
    f2("working tree possui alteracoes nao commitadas")

rc, head, _ = run(["git", "rev-parse", "HEAD"], ROOT)
capture(f"head={head if rc == 0 else 'unknown'}")

capture()
capture("=== TRACKED SECRET-LIKE PATHS ===")
rc, tracked_out, _ = run(["git", "ls-files"], ROOT)
tracked = [x.strip() for x in tracked_out.splitlines() if x.strip()] if rc == 0 else []

blockers: list[str] = []
warnings: list[str] = []
for rel in tracked:
    low = rel.lower()
    parts = Path(rel).parts
    base = Path(rel).name.lower()

    if ".runtime" in parts:
        blockers.append(rel)
        continue
    if base == ".env":
        blockers.append(rel)
        continue
    if base in {"secret-id", "role-id", "root-token", "unseal-share", "recovery-share"}:
        blockers.append(rel)
        continue
    if base.endswith((".p12", ".pfx", ".jks", ".kdbx")):
        blockers.append(rel)
        continue
    if base.endswith(".key"):
        warnings.append(rel)

if blockers:
    for rel in blockers:
        f2(f"arquivo sensivel rastreado: {rel}")
else:
    p2("nenhum path sensivel proibido detectado no indice Git")

for rel in warnings:
    w2(f"revisar key-like file rastreado: {rel}")

capture()
capture("=== CONFLICT MARKERS ===")
text_ext = {
    ".md", ".txt", ".py", ".sh", ".bash", ".fish", ".yml", ".yaml", ".json",
    ".php", ".ini", ".conf", ".sql", ".toml", ".xml", ".env", ".example",
}
conflicts: list[str] = []
pattern = re.compile(r"^(<<<<<<< |=======|>>>>>>> )", re.MULTILINE)

for rel in tracked:
    path = ROOT / rel
    if not path.is_file():
        continue
    if path.suffix.lower() not in text_ext and path.name not in {"Dockerfile", "Makefile"}:
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    if pattern.search(text):
        conflicts.append(rel)

if conflicts:
    for rel in conflicts:
        f2(f"merge conflict marker: {rel}")
else:
    p2("sem marcadores de conflito em arquivos texto rastreados")

capture()
capture("=== PYTHON SYNTAX ===")
python_files = [
    "scripts/evidencias/gui01c_phpmyadmin_precheck.py",
    "scripts/evidencias/pentest_no_sudo_readiness.py",
    "scripts/evidencias/pentest_sem_sudo_runtime_check.py",
    "scripts/evidencias/ops01_ep126_readonly.py",
    "scripts/evidencias/pfsense_wazuh_postreboot_readonly.py",
    "scripts/evidencias/appsec04_snyk_revalidation.py",
    "scripts/evidencias/prefreeze_repo_gate.py",
]
for rel in python_files:
    path = ROOT / rel
    if not path.is_file():
        f2(f"python ausente: {rel}")
        continue
    try:
        source = path.read_text(encoding="utf-8")
        ast.parse(source, filename=rel)
        p2(f"syntax: {rel}")
    except (SyntaxError, UnicodeDecodeError, OSError) as exc:
        f2(f"syntax: {rel}: {exc}")

capture()
capture("=== CANONICAL CONTENT ===")
checks = {
    "docs/BACKLOG-TECNICO.md": [
        "### HOST-01",
        "### BAC-04",
        "### GUI-01C",
        "### WAZ-01",
        "### WAZ-02",
        "### APPSEC-04",
        "### PENTEST-00",
        "### FREEZE-01",
    ],
    "docs/seguranca/PENTEST-S01-S13-ZERO-SUDO.md": [
        "**S01**", "**S02**", "**S03**", "**S04**", "**S05**", "**S06**",
        "**S07**", "**S08**", "**S09**", "**S10**", "**S11**", "**S12**", "**S13**",
        "/opt/conectaeduca/deploy/interna/pentest-fim-lab.tmp",
        "submeter_ferret_pentest.py",
        "G3 — S11/S13 DLP user-writable",
    ],
    "docs/seguranca/PENTEST-COMANDOS-S01-S13.md": [
        'FIM_TEST_FILE="$REPO/deploy/interna/pentest-fim-lab.tmp/arquivo-monitorado.txt"',
        'DLP_SUBMIT="$REPO/scripts/dlp/submeter_ferret_pentest.py"',
        'python3 "$DLP_SUBMIT" "$FILE"',
    ],
    "scripts/evidencias/pentest_no_sudo_readiness.py": [
        "=== G1 CLIENT TOOLING ===",
        "=== G2 S10 FIM DROP-ZONE ===",
        "=== G3 S11/S13 FERRET DROP-ZONE ===",
        "method=shellless",
        "PENTEST_NO_SUDO_READY=",
    ],
    "scripts/evidencias/pentest_sem_sudo_runtime_check.py": [
        "=== G2/G3 LOW-PRIVILEGE PATHS ===",
        "FIM_TESTE_WRITE_EXECUTE",
        "FERRET_INBOX_WRITE_EXECUTE",
        "DOCKER_EXEC_ALLOWED_DURING_PENTEST=NO",
    ],
    "docs/seguranca/PENTEST-SEM-SUDO.md": [
        "zero dependência de sudo/root",
        "pentest_sem_sudo_runtime_check.py",
    ],
    "docs/seguranca/APPSEC-BASELINE-PREFREEZE.md": [
        "APPSEC-04=CWE-611_OPS01_XML_PARSER",
        "APPSEC04_REMEDIATION=STRICT_NON_XML_REMOTE_SCANNER",
        "NO_SNYK_SUPPRESSION=YES",
        "appsec04_snyk_revalidation.py",
    ],
    "docs/seguranca/APPSEC-04-SNYK-REVALIDATION.md": [
        "REMOTE_MAIN_QUERY=PASS",
        "SNYK_TOTAL_RESULTS=0",
        "SNYK_TARGET_CWE611_RESULTS=0",
        "APPSEC04_SNYK_REVALIDATION=PASS",
    ],
    "scripts/evidencias/appsec04_snyk_revalidation.py": [
        'TARGET = "scripts/evidencias/ops01_ep126_readonly.py"',
        'CANONICAL_REPO_SLUG = "andrea-kozicki/conectaeduca"',
        'CANONICAL_MAIN_URL = "https://github.com/andrea-kozicki/conectaeduca.git"',
        'canonical_origin_url(url: str)',
        'flags=re.IGNORECASE | re.ASCII',
        'isolated_git_env(',
        'key in {"GIT_CONFIG", "GIT_CONFIG_PARAMETERS"}',
        'env["GIT_CONFIG_NOSYSTEM"] = "1"',
        'env["GIT_CONFIG_GLOBAL"] = os.devnull',
        'env["GIT_CONFIG_COUNT"] = "0"',
        'env["GIT_NO_REPLACE_OBJECTS"] = "1"',
        '"refs/replace/"',
        "GIT_REPLACE_REFS_COUNT=",
        "GIT_REPLACE_REFS=",
        '"GIT_CONFIG_PARAMETERS":',
        '"GIT_CONFIG_KEY_0":',
        '"GIT_CONFIG_VALUE_0":',
        '"--local",',
        '"--no-includes",',
        '"--get-all",',
        '"remote.origin.url",',
        "ORIGIN_RAW_URL_COUNT=",
        'canonical_remote_main_query()',
        'tempfile.TemporaryDirectory(prefix="conectaeduca-git-remote-")',
        'env["GIT_CEILING_DIRECTORIES"] = str(tmp_path)',
        '"git", "-c", "core.fsmonitor=false", "status", "--porcelain", "--untracked-files=all"',
        '["git", "ls-files", "-v", "-z"]',
        '["git", "ls-files", "-f", "-z"]',
        "special_index_entries(",
        "raw.split(chr(0))",
        '"H normal.py" + chr(0) + "h assumed.py" + chr(0)',
        "INDEX_TRACKING_FLAGS=",
        "INDEX_FSMONITOR_FLAGS=",
        "materialize_git_snapshot(",
        '["git", "archive", "--format=tar"',
        '["git", "ls-tree", "-r", "-z", commit]',
        "SNYK_SCAN_INPUT=VERIFIED_GIT_COMMIT_SNAPSHOT",
        "SNYK_SNAPSHOT_MATERIALIZATION=PASS",
        "SNYK_SNAPSHOT_READ_ONLY=",
        "verify_materialized_snapshot(",
        "SNYK_SNAPSHOT_POSTSCAN_INTEGRITY=",
        "APPSEC04_SNYK_REVALIDATION=BLOCK_SNAPSHOT_CHANGED",
        "APPSEC05_TARGETS = {",
        '"cwe23": "CWE-23" in metadata_blob or "CWE_23" in metadata_blob',
        "SNYK_CWE23_RESULTS=",
        "SNYK_APPSEC05_TARGET_CWE23_RESULTS=",
        "APPSEC05_CWE23=",
        "APPSEC05_SNYK_REVALIDATION=",
        'SECURE_SCAN_PARENT = Path("/var/tmp")',
        "validate_secure_scan_parent(",
        "create_isolated_scan_snapshot(",
        "remove_isolated_scan_snapshot(",
        '["sudo", "-n", "-v"]',
        '"sudo", "-n", "mkdir", "--mode=0755"',
        '"--no-preserve=ownership"',
        '"--one-file-system"',
        "SNYK_SECURE_PARENT_ROOT_OWNED_STICKY=",
        "SNYK_SNAPSHOT_ISOLATION=ROOT_OWNED_UNDER_STICKY_PARENT",
        "SNYK_ROOT_SCAN_ALLOWED=NO",
        "SNYK_SNAPSHOT_ISOLATION_PROOF=PASS",
        "validate_sudo_policy_no_nopasswd(",
        '"NOPASSWD:"',
        '"!AUTHENTICATE"',
        "invalidate_sudo_before_scan(",
        '["sudo", "-K"]',
        '["sudo", "-n", "-v"]',
        "SUDO_TIMESTAMP_INVALIDATED_BEFORE_SCAN=",
        "SUDO_NONINTERACTIVE_DURING_SCAN=",
        "APPSEC04_SNYK_REVALIDATION=BLOCK_SUDO_CACHE",
        "APPSEC05_SNYK_REVALIDATION=BLOCK_SUDO_CACHE",
        "ensure_sudo_for_cleanup(",
        "SUDO_CACHE_REAPPEARED_DURING_SCAN=",
        "BLOCK_SUDO_CACHE_REAPPEARED",
        "APPSEC04_SNYK_REVALIDATION=BLOCK_ISOLATION",
        "APPSEC05_SNYK_REVALIDATION=BLOCK_ISOLATION",
        "duplicate id:",
        "inconsistent ruleId/ruleIndex",
        "REMOTE_QUERY_GIT_CONFIG_ISOLATED=YES",
        "REMOTE_QUERY_LOCAL_CONFIG_DISCOVERY=BLOCKED_BY_TEMP_CEILING",
        "WORKTREE_STATUS_FSMONITOR_DISABLED=YES",
        "ORIGIN_CANONICAL=",
        '["snyk", "code", "test", "--sarif", "--include-ignores"]',
        "SNYK_INCLUDE_IGNORES=YES",
        'payload.get("version") != "2.1.0"',
        'tool = run_item["tool"] if "tool" in run_item else None',
        'if not isinstance(tool, dict):',
        'for rule_idx, rule in enumerate(rules):',
        'if not isinstance(rule, dict):',
        'rule_id = rule.get("id")',
        'locations = result["locations"] if "locations" in result else []',
        'if not isinstance(location, dict):',
        'if not isinstance(physical, dict):',
        'if not isinstance(artifact, dict):',
        "safe_metadata_text(value: Any)",
        'unicodedata.category(ch) not in {"Cc", "Cs", "Zl", "Zp"}',
        "SNYK_INCLUDE_IGNORES=YES",
        "RAW_SARIF_PERSISTED=NO",
        "APPSEC04_SNYK_REVALIDATION=",
    ],
    "docs/evidencias/suricata-eve-stats-wazuh-field-limit-20260927.md": [
        "SURICATA_EVE_STATS_ROOT_CAUSE=CONFIRMED_OPERATIONALLY",
        "POST_ERROR_COUNT=0",
    ],
    "deploy/pfsense/LOGGING-WAZUH.md": [
        "pfsense_wazuh_postreboot_readonly.py",
        "PFSENSE_WAZUH_POSTREBOOT=READY_FOR_CORRELATED_PROBE",
        "PFSENSE_WAZUH_POSTREBOOT=CORRELATED_ALERT_PASS",
    ],
}
for rel, tokens in checks.items():
    path = ROOT / rel
    if not path.is_file():
        continue
    text = path.read_text(encoding="utf-8")
    missing = [token for token in tokens if token not in text]
    if missing:
        f2(f"{rel}: tokens ausentes: {missing}")
    else:
        p2(f"conteudo canonico presente: {rel}")

capture()
capture("=== APPSEC SNAPSHOT ISOLATION REGRESSIONS ===")
appsec_path = ROOT / "scripts/evidencias/appsec04_snyk_revalidation.py"
if appsec_path.is_file():
    appsec_text = appsec_path.read_text(encoding="utf-8")
    forbidden_snapshot_tokens = (
        "lock_snapshot_for_scan(",
        '"chown", "-R"',
        "ROOT_OWNED_DAC",
    )
    regressions = [
        token for token in forbidden_snapshot_tokens if token in appsec_text
    ]
    if regressions:
        f2(f"APPSEC snapshot isolation regressions: {regressions}")
    else:
        p2("APPSEC snapshot isolation sem chown recursivo/legacy DAC")

capture()
capture("=== BACKLOG DONE CONSISTENCY ===")
backlog_path = ROOT / "docs/BACKLOG-TECNICO.md"
if backlog_path.is_file():
    text = backlog_path.read_text(encoding="utf-8")
    sections = re.split(r"(?=^### )", text, flags=re.MULTILINE)
    contradictions: list[str] = []
    for section in sections:
        if "**Estado:** DONE" not in section:
            continue
        title = section.splitlines()[0] if section.splitlines() else "unknown"
        suspicious = [
            line.strip() for line in section.splitlines()
            if re.search(r"\b(ainda|permanece|pendente|decisao necessaria)\b", line, re.IGNORECASE)
            and "reabrir" not in line.lower()
            and "nao devem" not in line.lower()
        ]
        if suspicious:
            contradictions.append(title + " -> " + " | ".join(suspicious[:3]))
    if contradictions:
        for item in contradictions:
            w2(f"revisar DONE possivelmente contraditorio: {item}")
    else:
        p2("itens DONE sem linguagem pendente obvia")

capture()
capture("=== SUMMARY ===")
capture(f"PASS={PASS}")
capture(f"WARN={WARN}")
capture(f"FAIL={FAIL}")
capture(f"PREFREEZE_REPO_READY={'YES' if FAIL == 0 else 'NO'}")
capture("runtime_vm_changes=0")
capture("sudo_used=0")
capture("docker_used=0")

REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
digest = hashlib.sha256(REPORT.read_bytes()).hexdigest()
sha_path = Path(str(REPORT) + ".sha256")
sha_path.write_text(f"{digest}  {REPORT.name}\n", encoding="utf-8")
emit(f"REPORT={REPORT}")
emit(f"SHA256={digest}")
emit(f"SHA256_FILE={sha_path}")

raise SystemExit(0 if FAIL == 0 else 2)
