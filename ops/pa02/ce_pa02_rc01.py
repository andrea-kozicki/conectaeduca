#!/usr/bin/env python3
"""CE-PA02-RC01 — ponto de retorno LOCAL Docker/Compose, EP125.
Sem sudo, Docker restart/up/down, scan, backup de segredos ou dados de volumes.
Nao equivale a snapshot ou restore testado. Usa apenas Docker image save.
"""
from __future__ import annotations

import datetime as dt
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import stat
import subprocess
import sys

ROOT = Path("/opt/conectaeduca")
DMZ = ROOT / "deploy/dmz"
PROJECT = "conectaeduca-dmz"
HEAD = "04f88d275064a005d0ffcd4f9372a371c28c32d5"
PA05 = "conectaeduca/php-fpm:pa05-10328ab6"
PA05_OVERLAY = Path(
    "/home/andrea.kiew/.config/conectaeduca/pa05/compose.pa05-10328ab6.yml"
)
FILES = [DMZ / name for name in (
    "compose.yml", "compose.database.yml", "compose.app-secrets.yml",
    "compose.waf.yml", "compose.waf-tls.yml", "compose.waf-policy.yml",
    "compose.host.yml", "compose.vm.yml", "compose.database-tls.yml",
    "compose.audit-persistent.yml",
)] + [PA05_OVERLAY]
SERVICES = ("php", "nginx", "waf")
DEST = Path.home() / ".local/share/conectaeduca/pa02-recovery"
RESERVE = 1024 * 1024 * 1024

class Abort(Exception):
    pass

def fail(code: str) -> None:
    raise Abort(code)

def capture(args: list[str]) -> str:
    try:
        p = subprocess.run(args, check=False, capture_output=True, text=True, timeout=40)
    except (OSError, subprocess.TimeoutExpired):
        fail("COMANDO_NAO_DISPONIVEL")
    if p.returncode:
        # Nao imprimir stdout/stderr; podem conter detalhes de runtime.
        fail("COMANDO_FALHOU")
    return p.stdout.strip()

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            part = f.read(1024 * 1024)
            if not part:
                break
            h.update(part)
    return h.hexdigest()

def private_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=False, mode=0o700)
    path.chmod(0o700)

def inspect_one(service: str) -> dict:
    ids = capture([
        "docker", "ps", "-q",
        "--filter", "label=com.docker.compose.project=" + PROJECT,
        "--filter", "label=com.docker.compose.service=" + service,
    ]).splitlines()
    if len(ids) != 1:
        fail("CONTAINER_NAO_UNICO_" + service)
    data = json.loads(capture(["docker", "inspect", ids[0]]))
    if not isinstance(data, list) or len(data) != 1:
        fail("INSPECT_INVALIDO_" + service)
    row = data[0]
    st = row.get("State", {})
    if st.get("Running") is not True or (st.get("Health") or {}).get("Status") != "healthy":
        fail("CONTAINER_NAO_HEALTHY_" + service)
    labels = row.get("Config", {}).get("Labels", {})
    if (labels.get("com.docker.compose.project") != PROJECT
            or labels.get("com.docker.compose.service") != service):
        fail("LABELS_DIVERGENTES_" + service)
    ref = row.get("Config", {}).get("Image", "")
    image_id = row.get("Image", "")
    if not ref or not re.fullmatch(r"sha256:[0-9a-f]{64}", image_id):
        fail("IMAGEM_INVALIDA_" + service)
    img = json.loads(capture(["docker", "image", "inspect", ref]))[0]
    if img.get("Id") != image_id:
        fail("TAG_REAPONTADA_" + service)
    return {
        "name": service,
        "image_ref": ref,
        "image_id": image_id,
        "image_size_bytes": int(img.get("Size") or 0),
        "container_id": row["Id"],
        "config_files_label": labels.get("com.docker.compose.project.config_files"),
        "mounts": [
            {"type": x.get("Type"), "destination": x.get("Destination"),
             "source": x.get("Source")}
            for x in row.get("Mounts", [])
        ],
    }

def save_images(path: Path, refs: list[str]) -> None:
    partial = path.with_suffix(path.suffix + ".partial")
    proc = None
    try:
        proc = subprocess.Popen(["docker", "image", "save", *refs],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        assert proc.stdout is not None
        with partial.open("xb") as raw:
            os.chmod(partial, 0o600)
            with gzip.GzipFile(fileobj=raw, mode="wb", compresslevel=1) as zipped:
                shutil.copyfileobj(proc.stdout, zipped, length=1024 * 1024)
        proc.stdout.close()
        if proc.wait(timeout=60) != 0:
            fail("DOCKER_SAVE_FALHOU")
        if partial.stat().st_size == 0:
            fail("ARQUIVO_IMAGENS_VAZIO")
        # Validacao completa do CRC do gzip; nao interpreta conteudos privados.
        with gzip.open(partial, "rb") as gz, open(os.devnull, "wb") as sink:
            shutil.copyfileobj(gz, sink, length=1024 * 1024)
        os.replace(partial, path)
    except (OSError, EOFError, gzip.BadGzipFile, subprocess.TimeoutExpired):
        fail("IMAGENS_NAO_EXPORTADAS_OU_INVALIDAS")
    finally:
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait()
        if partial.exists():
            partial.unlink()

def main() -> None:
    os.umask(0o077)
    print("=== CE-PA02-RC01 — PACOTE LOCAL DE RETORNO ===", flush=True)
    print("DATA=" + dt.datetime.now().astimezone().isoformat(timespec="seconds"))
    if sys.argv[1:] != ["--save"]:
        fail("EXIGE_--save")
    if os.geteuid() == 0 or capture(["whoami"]) != "andrea.kiew":
        fail("USUARIO_INCORRETO_OU_ROOT")
    if socket.gethostname().split(".")[0] not in ("ep125-pucpr", "ep125-pucpr-br"):
        fail("HOST_INCORRETO")
    if capture(["git", "-C", str(ROOT), "rev-parse", "HEAD"]) != HEAD:
        fail("GIT_HEAD_DIVERGENTE")
    for path in FILES:
        if not path.is_file() or path.is_symlink() or not os.access(path, os.R_OK):
            fail("COMPOSE_INACESSIVEL_" + path.name)
    state = {name: inspect_one(name) for name in SERVICES}
    if state["php"]["image_ref"] != PA05:
        fail("PHP_PA05_NAO_ESTA_ATIVO")
    if state["php"]["config_files_label"] != ",".join(str(x) for x in FILES):
        fail("COMPOSE_LABEL_NAO_INCLUI_PA05")
    if not any(x["destination"] == "/var/www/conectaeduca/storage/logs"
               for x in state["php"]["mounts"]):
        fail("AUDITORIA_PERSISTENTE_AUSENTE")
    print("RUNTIME_3_SERVICOS=HEALTHY")
    print("PHP_PA05_E_11_COMPOSE=CONFIRMADOS")
    print("AUDITORIA_BIND=PRESENTE")

    unique = {}
    for data in state.values():
        unique[data["image_id"]] = data
    estimated = sum(max(0, item["image_size_bytes"]) for item in unique.values())
    if estimated <= 0:
        fail("TAMANHOS_IMAGENS_INVALIDOS")
    DEST.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    DEST.parent.chmod(0o700)
    DEST.mkdir(mode=0o700, exist_ok=True)
    if DEST.is_symlink() or stat.S_IMODE(DEST.stat().st_mode) != 0o700:
        fail("DIRETORIO_DESTINO_NAO_PRIVADO")
    free = shutil.disk_usage(DEST).free
    if free < int(estimated * 1.2) + RESERVE:
        print("ESPACO_LIVRE_GIB=" + str(round(free / 1024**3, 2)))
        print("ESPACO_ESTIMADO_GIB=" + str(round(estimated / 1024**3, 2)))
        fail("ESPACO_INSUFICIENTE_NAO_EXPORTAR")
    print("ESPACO_PARA_EXPORTAR=PASS")

    folder = DEST / ("CE-PA02-RC01-" + dt.datetime.now().strftime("%Y%m%d-%H%M%S"))
    if folder.exists():
        fail("BACKUP_ID_JA_EXISTE")
    private_dir(folder)
    saved = folder / "compose"
    private_dir(saved)
    manifest = {
        "type": "CE-PA02-RC01_LOCAL_DOCKER_RECOVERY",
        "created_at": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "git_head": HEAD,
        "project": PROJECT,
        "services": state,
        "compose_order": [str(x) for x in FILES],
        "compose_sha256": {},
        "images_archive": "docker-images.tar.gz",
        "scope": "Docker images + Compose; NO secret content, databases, volumes, or hypervisor snapshot",
    }
    for i, path in enumerate(FILES, 1):
        destination = saved / (f"{i:02d}-" + path.name)
        shutil.copyfile(path, destination)
        destination.chmod(0o600)
        if sha256(path) != sha256(destination):
            fail("COPIA_COMPOSE_DIVERGENTE")
        manifest["compose_sha256"][str(path)] = sha256(destination)
    print("BACKUP_11_COMPOSE=PASS")

    archive = folder / "docker-images.tar.gz"
    save_images(archive, [item["image_ref"] for item in unique.values()])
    manifest["images_archive_sha256"] = sha256(archive)
    manifest["images_archive_size_bytes"] = archive.stat().st_size
    metadata = folder / "manifest.json"
    with metadata.open("x", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
    metadata.chmod(0o600)
    if json.loads(metadata.read_text(encoding="utf-8")).get(
        "images_archive_sha256"
    ) != sha256(archive):
        fail("MANIFEST_INTEGRIDADE_FALHOU")
    print("IMAGENS_EXPORTADAS=3_SERVICOS")
    print("ARQUIVO_COMPACTADO_INTEGRIDADE=PASS")
    print("MANIFEST_INTEGRIDADE=PASS")
    print("BACKUP_PRIVADO=" + str(folder))
    print("CONTEUDO_SECRETS_COPIADO=NAO")
    print("VOLUMES_E_BANCO_COPIADOS=NAO")
    print("SNAPSHOT_HIPERVISOR=NAO")
    print("RESTARTS_E_SERVICOS_MODIFICADOS=NAO")
    print("RECUPERACAO_DE_SERVICO=PREPARADA_NAO_ENSAIADA")
    print("CE-PA02-RC01_CONCLUIDO")

if __name__ == "__main__":
    try:
        main()
    except Abort as exc:
        print("CE-PA02-RC01_ABORTADO=" + str(exc), file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, json.JSONDecodeError, PermissionError) as exc:
        print("CE-PA02-RC01_ABORTADO=" + type(exc).__name__, file=sys.stderr)
        sys.exit(1)
