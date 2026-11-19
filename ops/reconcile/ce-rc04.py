#!/usr/bin/env python3
"""CE-RC04: compara fingerprints Git com PRs existentes, sem revelar conteúdo."""
import datetime
import os
from pathlib import Path
import socket
import subprocess
import sys

ROOT = Path("/opt/conectaeduca")
HOSTS = {"ep125-pucpr": "EP125", "ep126-pucpr-br": "EP126"}
HOST = socket.gethostname().split(".")[0]
VM = HOSTS.get(HOST)
if VM is None:
    sys.exit("ABORTADO_HOST_FORA_ESCOPO")
os.environ["GIT_OPTIONAL_LOCKS"] = "0"

def git(*args):
    return subprocess.run(
        ["git", "-C", str(ROOT), *args],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    ).stdout

try:
    top = git("rev-parse", "--show-toplevel").decode().strip()
except (OSError, subprocess.CalledProcessError):
    sys.exit("ABORTADO_GIT_INDISPONIVEL")
if top != str(ROOT):
    sys.exit("ABORTADO_REPO_DIFERENTE")

def fingerprint(path):
    """Identificador do blob Git; nao imprime nome privado nem conteudo."""
    source = ROOT / path
    if source.is_symlink():
        return "SYMLINK_NAO_LIDO"
    try:
        if not source.is_file():
            return "AUSENTE"
        if source.stat().st_size > 1024 * 1024:
            return "ARQUIVO_GRANDE_NAO_LIDO"
        return git("hash-object", "--", str(source)).decode().strip()
    except (OSError, subprocess.CalledProcessError):
        return "INACESSIVEL"

# Hashes dos blobs verificados no GitHub, nao de arquivos coletados das VMs.
ITEMS = {
    "EP125": [
        ("AUDIT_PERSISTENT_PR203", "deploy/dmz/compose.audit-persistent.yml",
         "bfb1abca81b0a5f84e8ccda69c3c2da75294f2a1", None),
        ("GA08_DUAL_SOCKET_PR217", "deploy/dmz/compose.ga08-dual-socket.candidate.yml",
         "ee2e8583f72cb5f88760f601d9b409124b37bf7e", None),
        ("GA08_RUNTIMEFIX_PR217", "deploy/dmz/compose.ga08-runtimefix.candidate.yml",
         "9306a6f69c069ca9bfa82a44469b3690d7208f0e", None),
        ("GA08_SOCKET_PR217", "deploy/dmz/compose.ga08-socket.candidate.yml",
         "e86ec91deb2d9fe59244b78145b4c546f0cf67d7", None),
    ],
    "EP126": [
        ("DLP_SANITIZADOR_PR207", "scripts/dlp/sanitizar_ferret.py",
         "551accd9c2d3422b8d57428f2e21b556f1852698",
         "8cbd26f5781634e5a7f5b437044b349b15f26684"),
        ("DLP_VALIDADOR_PR207", "scripts/dlp/validar_eventos_ferret.py",
         "7b4ed11f422d4d67491f99ec5d6341f7d68958e1",
         "65f31ac73fd056745f223df2960d1bb3a509f5b2"),
        ("WAZUH_DLP_PR206", "deploy/interna/wazuh/config/rules/conectaeduca_dlp_rules.xml",
         "8d332c7adb8820789219c5c6e6b048eeecc178d2",
         "8b274a73aacca4d0e842a99146d645ad5be6a4ee"),
        ("FERRET_V5_OVERRIDE_PR207", None,
         "decf0a8b5d5b18b6122b4afcc12a17e5ee5627f2", None),
    ],
}

print(f"=== CE-RC04 | {VM} | PR_FINGERPRINTS_READ_ONLY ===")
print(subprocess.check_output(["whoami"], text=True).strip())
print(datetime.datetime.now().astimezone().isoformat(timespec="seconds"))
untracked = []
if VM == "EP126":
    try:
        untracked = [
            p.decode("utf-8", "surrogateescape")
            for p in git("ls-files", "--others", "--exclude-standard", "-z",
                         "--", "deploy/interna").split(b"\0") if p
        ]
    except (OSError, subprocess.CalledProcessError):
        print("UNTRACKED_LISTA=INACESSIVEL")

for label, target, expected_pr, expected_main in ITEMS[VM]:
    if target is None:
        matches = [p for p in untracked if Path(p).name == "compose.pa07-v5.override.yml"]
        if len(matches) != 1:
            print(f"{label}=CANDIDATOS_{len(matches)}_SEM_COMPARACAO")
            continue
        target = matches[0]  # caminho privado nunca e impresso
    found = fingerprint(target)
    if len(found) != 40 or any(c not in "0123456789abcdef" for c in found):
        print(f"{label}={found}")
        continue
    status = "MATCH_PR" if found == expected_pr else "DIFF_PR"
    if expected_main is not None:
        status += "_MAIN_" + ("MATCH" if found == expected_main else "DIFF")
    print(f"{label}={status}")

print("SEGREDOS_EXIBIDOS=NAO")
print("GIT_MODIFICADO=NAO")
print("RUNTIME_MODIFICADO=NAO")
print("CE-RC04_CONCLUIDO")
