#!/usr/bin/env python3
"""CE-GA06-ALIGN01: alinhamento Compose Ferret v5, sem reinicio ou sudo."""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import urllib.request

ROOT = Path("/opt/conectaeduca")
COMPOSE = ROOT / "deploy/interna/ferret/compose.yml"
EXPECTED_HEAD = "04f88d275064a005d0ffcd4f9372a371c28c32d5"
OLD_BLOB = "9f4e17461d2179607343780fed922153050f1e86"
NEW_BLOB = "bf87c41606d96a7547ed05bd668f6b5fc242ecc4"
OLD_LINE = (
    "    image: public.ecr.aws/awslabs/ferret-scan:2.4.3@sha256:"
    "7a1b36050ae20a74632ac05b5c34e4aeb26b69836ca6703e10c1392b724b270f"
)
NEW_LINE = (
    "    image: localhost/conectaeduca/ferret-scan:2.4.3-pa07-v5-candidate\n"
    "    pull_policy: never"
)
IMAGE = "localhost/conectaeduca/ferret-scan:2.4.3-pa07-v5-candidate"
IMAGE_ID = "sha256:535ec9efb590dbaaeca41123321d773ba6d26d338686d89605492380ae9e187d"

def call(*args: str) -> str:
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()

def abort(code: str) -> None:
    print("CE-GA06-ALIGN01_ABORTADO=" + code, file=sys.stderr)
    raise SystemExit(1)

def blob(raw: bytes) -> str:
    # Git blob SHA-1 do conteudo, sem dependencia do arquivo ser rastreado.
    return hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()

def main() -> None:
    print("=== CE-GA06-ALIGN01 — FERRET V5: COMPOSE + CLI ===", flush=True)
    print("USUARIO=" + call("whoami"))
    print("DATA=" + dt.datetime.now().astimezone().isoformat(timespec="seconds"))
    if sys.argv[1:] != ["--apply"]:
        abort("EXIGE_--apply")
    if os.geteuid() == 0 or call("whoami") != "andrea.kiew":
        abort("EXECUTAR_SEM_SUDO_COM_ANDREA")
    if socket.gethostname().split(".")[0] != "ep126-pucpr-br":
        abort("HOST_INCORRETO")
    if call("git", "-C", str(ROOT), "rev-parse", "HEAD") != EXPECTED_HEAD:
        abort("GIT_HEAD_DIVERGENTE")
    if not COMPOSE.is_file() or COMPOSE.is_symlink():
        abort("COMPOSE_INVALIDO")
    metadata = COMPOSE.stat()
    if metadata.st_uid != os.geteuid() or not os.access(COMPOSE.parent, os.W_OK):
        abort("PERMISSAO_ATOMICA_INSUFICIENTE")
    original = COMPOSE.read_bytes()
    original_blob = blob(original)
    if original_blob == NEW_BLOB:
        print("CONFIG_JA_ALINHADA=SIM")
        print("CE-GA06-ALIGN01_CONCLUIDO")
        return
    if original_blob != OLD_BLOB:
        abort("COMPOSE_BASE_DIVERGENTE")
    if original.count(OLD_LINE.encode()) != 1:
        abort("IMAGEM_BASE_AUSENTE_OU_DUPLICADA")
    proposed = original.replace(OLD_LINE.encode(), NEW_LINE.encode(), 1)
    if blob(proposed) != NEW_BLOB:
        abort("CONTEUDO_CANDIDATO_NAO_APROVADO")

    # Guardas de runtime: v5 precisa estar funcionando, sem tocar no servico.
    try:
        candidate_id = call("docker", "image", "inspect", IMAGE, "--format", "{{.Id}}")
        cid = call("docker", "compose", "-f", str(COMPOSE), "ps", "-q", "ferret")
        runtime_id = call("docker", "inspect", cid, "--format", "{{.Image}}")
        with urllib.request.urlopen("http://127.0.0.1:18082/health", timeout=6) as rsp:
            health = json.load(rsp)
    except (subprocess.CalledProcessError, OSError, ValueError) as exc:
        abort("RUNTIME_NAO_VERIFICAVEL_" + type(exc).__name__)
    if candidate_id != IMAGE_ID or runtime_id != IMAGE_ID:
        abort("IMAGEM_V5_NAO_ESTA_ATIVA_OU_DIVERGE")
    if (
        health.get("status") != "healthy"
        or health.get("service") != "ferret-scan-web"
        or str(health.get("version")) != "2.4.3+ce.pa07.v5"
    ):
        abort("HEALTH_V5_INCOMPATIVEL")
    print("RUNTIME_V5=CONFIRMADO")

    # Backup privado. Nenhum conteudo bruto enviado ao terminal ou GitHub.
    timestamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = Path.home() / (".CE-GA06-ALIGN01_BACKUP_" + timestamp)
    try:
        backup_dir.mkdir(mode=0o700)
    except OSError:
        abort("CRIACAO_BACKUP_FALHOU")
    copy = backup_dir / "compose.yml"
    shutil.copyfile(COMPOSE, copy)
    copy.chmod(0o600)
    if blob(copy.read_bytes()) != OLD_BLOB:
        abort("BACKUP_DIVERGENTE")
    print("BACKUP_COMPOSE=VERIFICADO")
    print("BACKUP_PRIVADO=" + str(backup_dir))

    temp_path = None
    try:
        fd, name = tempfile.mkstemp(prefix=".ce-ga06-align-", suffix=".tmp", dir=COMPOSE.parent)
        temp_path = Path(name)
        with os.fdopen(fd, "wb") as handle:
            handle.write(proposed)
            handle.flush()
            os.fsync(handle.fileno())
        temp_path.chmod(stat.S_IMODE(metadata.st_mode))
        if blob(temp_path.read_bytes()) != NEW_BLOB:
            abort("TEMPORARIO_DIVERGENTE")
        # Uma unica validacao de configuracao, sem up/run/recreate.
        subprocess.run(
            ["docker", "compose", "-f", str(temp_path), "config", "--quiet"],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        os.replace(temp_path, COMPOSE)
        temp_path = None
        if blob(COMPOSE.read_bytes()) != NEW_BLOB:
            abort("ARQUIVO_FINAL_DIVERGENTE")
        image_selection = call(
            "docker", "compose", "-f", str(COMPOSE), "config", "--images"
        )
        if image_selection != IMAGE:
            abort("IMAGEM_COMPOSE_INESPERADA")
    except (OSError, subprocess.CalledProcessError) as exc:
        abort("ALINHAMENTO_NAO_CONCLUIDO_" + type(exc).__name__)
    finally:
        if temp_path is not None:
            try:
                temp_path.unlink(missing_ok=True)
            except OSError:
                pass
    print("COMPOSE_IMAGEM=FERRET_V5")
    print("PULL_POLICY=NEVER")
    print("CONFIG_COMPOSE=VALIDADA")
    print("CLI_BASH_FISH_SELECAO=V5_PELO_COMPOSE")
    print("BOOTSTRAP_FISH_SELECAO=V5_PELO_COMPOSE")
    print("GIT_TRACKED_COMPOSE=MODIFICADO_INTENCIONALMENTE")
    print("CONTEINER_RECRIADO=NAO")
    print("SERVICOS_REINICIADOS=NAO")
    print("CE-GA06-ALIGN01_CONCLUIDO")

if __name__ == "__main__":
    main()
