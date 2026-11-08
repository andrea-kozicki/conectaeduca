#!/usr/bin/env python3
"""CE-RC08: atualiza com controle de mudancas apenas o checkout Git da VM.

Execucao explicita (--apply). Sem sudo, docker restart/exec, git clean, hard reset,
deploy, envio de segredos ou alteracao de arquivos ja iguais ao novo HEAD.
"""
from __future__ import annotations

from datetime import datetime
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys

ROOT = Path("/opt/conectaeduca")
TARGET = "04f88d275064a005d0ffcd4f9372a371c28c32d5"
AUDIT = "deploy/dmz/compose.audit-persistent.yml"
SAN = "scripts/dlp/sanitizar_ferret.py"
VAL = "scripts/dlp/validar_eventos_ferret.py"
WAZUH = "deploy/interna/wazuh/config/rules/conectaeduca_dlp_rules.xml"

EXPECTED = {
    "EP125": {
        "host": "ep125-pucpr",
        "old": "b74ea581a0814d86a99b6b455d5569f12fa967e5",
        "dirty": set(),
        "keep": {AUDIT: "bfb1abca81b0a5f84e8ccda69c3c2da75294f2a1"},
        "changed": {AUDIT, SAN, VAL, WAZUH},
    },
    "EP126": {
        "host": "ep126-pucpr-br",
        "old": "4bf7ac688b1ea738cd158f03a20b07732cdd90a3",
        "dirty": {SAN, VAL, WAZUH},
        "keep": {
            SAN: "551accd9c2d3422b8d57428f2e21b556f1852698",
            VAL: "7b4ed11f422d4d67491f99ec5d6341f7d68958e1",
            WAZUH: "8d332c7adb8820789219c5c6e6b048eeecc178d2",
        },
        "changed": {
            ".github/workflows/repository-static-integrity.yml",
            ".gitleaks.toml",
            "composer.lock",
            AUDIT, WAZUH,
            "docs/seguranca/PA03-COMPOSE-STATIC-GATE-20261026.md",
            "docs/seguranca/PA05-RBAC-NEGATIVOS-CANDIDATURAS-20261026.md",
            SAN, VAL,
            "scripts/evidencias/checkpoint_compose_security_invariants.py",
            "src/Security/AuditLogger.php",
            "tests/Unit/AuditLoggerRedactionTest.php",
            "tests/Unit/Security/HorizontalOwnershipContractTest.php",
            "tests/python/test_pa03_compose_inline_lists.py",
        },
    },
}

class GuardError(Exception):
    pass

def abort(reason):
    raise GuardError(reason)

def cmd(args, *, cwd=None, check=True):
    p = subprocess.run(args, cwd=cwd, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, check=False)
    if check and p.returncode != 0:
        raise GuardError("COMANDO_FALHOU=" + str(args[0]) + " RC=" + str(p.returncode))
    return p

def git(*args, check=True):
    return cmd(["git", "-C", str(ROOT), *args], check=check)

def gt(*args):
    return git(*args).stdout.decode("utf-8", "replace").strip()

def paths(*args):
    return {b.decode("utf-8", "surrogateescape") for b in git(*args).stdout.split(b"\0") if b}

def blob(path):
    return gt("hash-object", "--", str(ROOT / path))

def regular(path):
    p = ROOT / path
    return p.is_file() and not p.is_symlink()

def is_inside(child, parent):
    try:
        Path(child).resolve().relative_to(Path(parent).resolve())
        return True
    except ValueError:
        return False

def check_mounts(paths_to_write):
    p = cmd(["docker", "ps", "-q"], check=False)
    if p.returncode != 0:
        abort("DOCKER_SEM_PERMISSAO_PARA_VERIFICAR_BINDS")
    ids = p.stdout.decode().split()
    if not ids:
        print("DOCKER_BINDS=SEM_CONTAINERS")
        return
    p = cmd(["docker", "inspect", "--format", "{{json .Mounts}}", *ids], check=False)
    if p.returncode != 0:
        abort("DOCKER_INSPECT_BINDS_FALHOU")
    sources = []
    for line in p.stdout.decode("utf-8", "replace").splitlines():
        for mount in json.loads(line or "[]"):
            if mount.get("Type") == "bind" and mount.get("Source"):
                sources.append(mount["Source"])
    overlaps = sum(
        1 for path in paths_to_write for source in sources
        if is_inside(ROOT / path, source)
    )
    print("DOCKER_BINDS_VERIFICADOS=" + str(len(sources)))
    print("ALTERACOES_COM_BIND_ATIVO=" + str(overlaps))
    if overlaps:
        abort("ABORTADO_PARA_PROTEGER_BIND_ATIVO")

def run():
    if sys.argv[1:] != ["--apply"]:
        abort("USE_EXPLICITAMENTE_--apply_PARA_ATUALIZAR_CHECKOUT")
    host = socket.gethostname().split(".")[0]
    vm = next((name for name, v in EXPECTED.items() if v["host"] == host), None)
    if not vm:
        abort("HOST_FORA_DO_ESCOPO")
    spec = EXPECTED[vm]
    print("=== CE-RC08 | " + vm + " | FAST_FORWARD_CONTROLADO ===")
    print("USUARIO=" + gt_whoami())
    print("DATA=" + datetime.now().astimezone().isoformat(timespec="seconds"))
    if gt("rev-parse", "--show-toplevel") != str(ROOT):
        abort("REPO_INESPERADO")
    if gt("symbolic-ref", "--short", "HEAD") != "main":
        abort("BRANCH_DIFERENTE_DE_MAIN")
    if gt("rev-parse", "HEAD") == TARGET:
        if not git("diff", "--quiet", "HEAD", "--", check=False).returncode:
            print("JA_ATUALIZADO=SIM")
            print("CE-RC08_CONCLUIDO")
            return
        abort("HEAD_ATUALIZADO_MAS_WORKTREE_DIVERGENTE")
    if gt("rev-parse", "HEAD") != spec["old"]:
        abort("HEAD_DIFERENTE_DO_INVENTARIO_CE_RC01")
    if git("diff", "--cached", "--quiet", check=False).returncode:
        abort("INDEX_COM_ALTERACOES_STAGED")
    if git("ls-files", "-u").stdout:
        abort("ARQUIVOS_EM_CONFLITO")
    dirty = paths("diff", "--no-ext-diff", "--name-only", "-z", "HEAD")
    if dirty != spec["dirty"]:
        abort("TRACKED_DIRTY_DIFERENTE_DO_CE_RC04")
    remote = gt("remote", "get-url", "origin")
    if not re.fullmatch(
        r"(?:https://(?:[^@/]+@)?github\.com/|git@github\.com:|ssh://git@github\.com/)"
        r"andrea-kozicki/conectaeduca(?:\.git)?/?", remote, flags=re.I
    ):
        abort("ORIGIN_NAO_VALIDADO_NAO_EXIBIDO")
    print("ORIGIN_VALIDADO=SIM")

    # Fetch nao altera o working tree. Um SHA novo/desconhecido interrompe o plano.
    print("GIT_FETCH_MAIN=INICIANDO")
    git("fetch", "--no-tags", "origin", "main")
    if gt("rev-parse", "FETCH_HEAD") != TARGET:
        abort("REMOTE_MAIN_MUDOU_REFAZER_PLANO")
    if git("merge-base", "--is-ancestor", spec["old"], TARGET, check=False).returncode:
        abort("HISTORICO_NAO_FAST_FORWARD")
    changed = paths("diff", "--name-only", "-z", spec["old"], TARGET)
    if changed != spec["changed"]:
        abort("ESCOPO_REMOTO_MUDOU")
    for path, expected in spec["keep"].items():
        if not regular(path) or blob(path) != expected:
            abort("BLOB_LOCAL_PRESERVADO_NAO_CONFERE=" + Path(path).name)
        if gt("rev-parse", TARGET + ":" + path) != expected:
            abort("BLOB_GITHUB_NAO_CONFERE=" + Path(path).name)
    print("BLOBS_PRESERVADOS=" + str(len(spec["keep"])))

    added = paths("diff", "--name-only", "--diff-filter=A", "-z", spec["old"], TARGET)
    for path in added:
        local = ROOT / path
        if (local.exists() or local.is_symlink()) and path not in spec["keep"]:
            abort("COLISAO_ARQUIVO_ADICIONADO_NAO_PREVISTA")
    to_restore = sorted(changed - set(spec["keep"]))
    for path in to_restore:
        if (ROOT / path).is_symlink():
            abort("SYMLINK_INESPERADO_EM_ARQUIVO_A_ATUALIZAR")
    print("ARQUIVOS_A_RESTAURAR=" + str(len(to_restore)))
    check_mounts(to_restore)

    timestamp = datetime.now().astimezone().strftime("%Y%m%d_%H%M%S")
    backup = Path.home() / (".CE-RC08_BACKUP_" + vm + "_" + timestamp)
    backup.mkdir(mode=0o700, exist_ok=False)
    for path in sorted(changed):
        source = ROOT / path
        if source.exists():
            if not regular(path):
                abort("ARQUIVO_EXISTENTE_NAO_REGULAR=" + Path(path).name)
            dest = backup / path
            dest.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            shutil.copy2(source, dest)
            if gt("hash-object", str(dest)) != blob(path):
                abort("FALHA_VERIFICACAO_BACKUP=" + Path(path).name)
    (backup / "PREVIOUS_HEAD.txt").write_text(spec["old"] + "\n", encoding="utf-8")
    os.chmod(backup / "PREVIOUS_HEAD.txt", 0o600)
    print("BACKUP_PRIVADO=" + str(backup))
    print("BACKUP_VERIFICADO=SIM")

    # Mixed altera HEAD/index, MAS NUNCA os conteudos do working tree.
    # Arquivos KEEP ja tem os bytes exatos no TARGET: permanecem intocados.
    # Os demais arquivos passam ao conteudo do TARGET somente apos o backup.
    print("ATUALIZACAO_GIT=INICIANDO")
    git("reset", "--mixed", TARGET)
    try:
        if to_restore:
            git("restore", "--worktree", "--", *to_restore)
        if gt("rev-parse", "HEAD") != TARGET:
            abort("HEAD_FINAL_DIFERENTE_DO_ALVO")
        if git("diff", "--quiet", "HEAD", "--", check=False).returncode:
            abort("WORKTREE_TRACKED_NAO_LIMPO")
        for path, expected in spec["keep"].items():
            if not regular(path) or blob(path) != expected:
                abort("BLOB_PRESERVADO_ALTERADO=" + Path(path).name)
        print("HEAD_FINAL=" + gt("rev-parse", "HEAD"))
        print("WORKTREE_TRACKED=SEM_ALTERACOES")
        print("OVERLAYS_NAO_RASTREADOS=NAO_EXCLUIDOS")
        print("SERVICOS_REINICIADOS=NAO")
        print("CE-RC08_CONCLUIDO")
    except GuardError:
        print("ATENCAO_CHECKOUT_PARCIAL_CONFERIR_BACKUP_PRIVADO")
        raise

def gt_whoami():
    return cmd(["whoami"]).stdout.decode().strip()

if __name__ == "__main__":
    try:
        run()
    except (GuardError, OSError, ValueError, json.JSONDecodeError) as exc:
        print("CE-RC08_ABORTADO=" + str(exc), file=sys.stderr)
        sys.exit(1)
