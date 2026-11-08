#!/usr/bin/env python3
"""CE-GA06-ALIGN01: promove launchers Ferret v5, sem sudo ou restart."""
from __future__ import annotations

import datetime as dt
import hashlib
import os
from pathlib import Path
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
from urllib.request import urlopen

ROOT = Path("/opt/conectaeduca")
HEAD = "04f88d275064a005d0ffcd4f9372a371c28c32d5"
PINNED_REF = "f1db1c43b3dcfbfd29589142af19e66209e5cede"
BASE = ROOT / "deploy/interna/ferret/compose.yml"
OVERLAY = ROOT / "deploy/interna/ferret/pa07-v5/compose.pa07-v5.override.yml"
DROPIN = Path(
    "/etc/systemd/system/conectaeduca-ferret-healthcheck.service.d/"
    "90-ga06-ferret-v5.conf"
)
V5_IMAGE = "localhost/conectaeduca/ferret-scan:2.4.3-pa07-v5-candidate"
V5_ID = "sha256:535ec9efb590dbaaeca41123321d773ba6d26d338686d89605492380ae9e187d"
ORIGINALS = {
    "scripts/dlp/processar_inbox_ferret.sh": (
        "777141f950a980317ccb2f3b1922c48855a49829",
        "d980a038243876ad853b374d0e9895bc19e9e77e",
    ),
    "scripts/dlp/processar_inbox_ferret.fish": (
        "1c417a3c7841b75995b95883e0fbc007a54d099a",
        "ef71366206ae9ee655a89fffb2a2299fd898204d",
    ),
    "scripts/bootstrap/subir_ferret.fish": (
        "cb74a487c93e556c19ad877d933ebd60261e09f6",
        "b3535947424a143e27a3cec6009cec4ee2538b6a",
    ),
}

def abort(code: str) -> None:
    print("CE-GA06-ALIGN01_ABORTADO=" + code, file=sys.stderr, flush=True)
    raise SystemExit(1)

def git_blob(data: bytes) -> str:
    header = b"blob " + str(len(data)).encode() + bytes([0])
    return hashlib.sha1(header + data).hexdigest()

def call(*args: str) -> str:
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()

def atomic_write(path: Path, data: bytes, mode: int) -> None:
    fd, name = tempfile.mkstemp(prefix=".ce-ga06-align-", dir=path.parent)
    tmp = Path(name)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        tmp.chmod(mode)
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)

def main() -> None:
    print("=== CE-GA06-ALIGN01 — CLI E BOOTSTRAP FERRET V5 ===", flush=True)
    print("USUARIO=" + call("whoami"))
    print("DATA=" + dt.datetime.now().astimezone().isoformat(timespec="seconds"))
    if sys.argv[1:] != ["--apply"]:
        abort("EXIGE_--apply")
    if os.geteuid() == 0 or call("whoami") != "andrea.kiew":
        abort("EXECUTAR_COM_USUARIO_NORMAL")
    if socket.gethostname().split(".")[0] != "ep126-pucpr-br":
        abort("HOST_INCORRETO")
    if call("git", "-C", str(ROOT), "rev-parse", "HEAD") != HEAD:
        abort("HEAD_DIVERGENTE")
    if git_blob(BASE.read_bytes()) != "9f4e17461d2179607343780fed922153050f1e86":
        abort("COMPOSE_BASE_DIVERGENTE")
    if git_blob(OVERLAY.read_bytes()) != "decf0a8b5d5b18b6122b4afcc12a17e5ee5627f2":
        abort("OVERRIDE_V5_DIVERGENTE")
    if not DROPIN.is_file() or DROPIN.is_symlink():
        abort("MONITOR_V5_NAO_INSTALADO")
    if git_blob(DROPIN.read_bytes()) != "82114898db5b576dcfd84d85b91be88debee9261":
        abort("DROPIN_V5_DIVERGENTE")
    try:
        candidate_id = call("docker", "image", "inspect", V5_IMAGE, "--format", "{{.Id}}")
        cid = call("docker", "compose", "-f", str(BASE), "ps", "-q", "ferret")
        runtime_id = call("docker", "inspect", cid, "--format", "{{.Image}}")
    except subprocess.CalledProcessError:
        abort("FERRET_RUNTIME_NAO_VERIFICAVEL")
    if candidate_id != V5_ID or runtime_id != V5_ID:
        abort("FERRET_V5_NAO_ESTA_ATIVO")
    print("RUNTIME_WEB_V5=CONFIRMADO")

    # Validar os tres arquivos em memoria antes de modificar qualquer caminho.
    fetched: dict[str, bytes] = {}
    original: dict[str, bytes] = {}
    attrs: dict[str, int] = {}
    pending: list[str] = []
    for relative, (baseline_hash, approved_hash) in ORIGINALS.items():
        path = ROOT / relative
        if not path.is_file() or path.is_symlink():
            abort("SCRIPT_LOCAL_INVALIDO_" + path.name)
        metadata = path.stat()
        if metadata.st_uid != os.getuid() or not os.access(path.parent, os.W_OK):
            abort("PERMISSOES_SCRIPT_INSUFICIENTES_" + path.name)
        old = path.read_bytes()
        current_hash = git_blob(old)
        if current_hash not in (baseline_hash, approved_hash):
            abort("SCRIPT_LOCAL_DIVERGENTE_" + path.name)
        original[relative] = old
        attrs[relative] = stat.S_IMODE(metadata.st_mode)
        if current_hash != approved_hash:
            pending.append(relative)
            url = (
                "https://raw.githubusercontent.com/andrea-kozicki/conectaeduca/"
                + PINNED_REF + "/" + relative
            )
            try:
                with urlopen(url, timeout=20) as response:
                    new_data = response.read()
            except Exception as exc:
                abort("DOWNLOAD_FALHOU_" + path.name + "_" + type(exc).__name__)
            if git_blob(new_data) != approved_hash:
                abort("HASH_REMOTO_DIVERGENTE_" + path.name)
            fetched[relative] = new_data

    if not pending:
        print("SCRIPTS_JA_ALINHADOS=SIM")
        print("CE-GA06-ALIGN01_CONCLUIDO")
        return

    backup_dir = Path.home() / (
        ".CE-GA06_ALIGN01_BACKUP_" + dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    )
    try:
        backup_dir.mkdir(mode=0o700)
    except OSError:
        abort("BACKUP_DIR_FALHOU")
    for relative, data in original.items():
        destination = backup_dir / Path(relative).name
        destination.write_bytes(data)
        destination.chmod(0o600)
        if git_blob(destination.read_bytes()) != git_blob(data):
            abort("BACKUP_INTEGRO_NAO_COMPROVADO")
    print("BACKUP_SCRIPTS=VERIFICADO")
    print("BACKUP_PRIVADO=" + str(backup_dir))

    changed: list[str] = []
    try:
        for relative in pending:
            path = ROOT / relative
            atomic_write(path, fetched[relative], attrs[relative])
            changed.append(relative)
            if git_blob(path.read_bytes()) != ORIGINALS[relative][1]:
                raise RuntimeError("POST_WRITE_HASH_FALHOU_" + path.name)
    except Exception as exc:
        restored = True
        for relative in reversed(changed):
            try:
                atomic_write(ROOT / relative, original[relative], attrs[relative])
                if git_blob((ROOT / relative).read_bytes()) != git_blob(original[relative]):
                    restored = False
            except Exception:
                restored = False
        print("ROLLBACK_SCRIPTS=" + ("PASS" if restored else "FALHOU_VERIFICAR_BACKUP"))
        abort("PROMOCAO_NAO_CONCLUIDA_" + type(exc).__name__)
    print("SCRIPTS_ATUALIZADOS=" + str(len(changed)))
    print("OVERRIDE_ATIVO_POR_MONITOR_V5=SIM")
    print("CLI_BASH_FISH=ALINHADOS")
    print("BOOTSTRAP_FISH=ALINHADO")
    print("COMPOSE_BASE_ALTERADO=NAO")
    print("WORKTREE_TRACKED=MODIFICACOES_CONTROLADAS_NA_EP126")
    print("DADOS_DLP_ALTERADOS=NAO")
    print("CONTÊINER_RECRIADO=NAO")
    print("SERVICOS_REINICIADOS=NAO")
    print("CE-GA06-ALIGN01_CONCLUIDO")

if __name__ == "__main__":
    main()
