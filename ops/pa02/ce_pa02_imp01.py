#!/usr/bin/env python3
"""CE-PA02-IMP01 — ensaio de importacao do RC01 em OCI LAYOUT PRIVADO.

Requer skopeo ja instalado. Somente transportes docker-archive: -> oci:.
Nunca conecta docker-daemon: nem altera imagens, contêineres ou Compose.
"""
from __future__ import annotations

import datetime as dt
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
GIT_HEAD = "04f88d275064a005d0ffcd4f9372a371c28c32d5"
PROJECT = "conectaeduca-dmz"
SERVICES = ("php", "nginx", "waf")
PA05_IMAGE = "conectaeduca/php-fpm:pa05-10328ab6"
BACKUP = Path(
    "/home/andrea.kiew/.local/share/conectaeduca/pa02-recovery/"
    "CE-PA02-RC01-20261108-183146"
)
DEST_PARENT = BACKUP.parent
ONE_GIB = 1024**3

class GateError(Exception):
    pass

def fail(reason: str) -> None:
    raise GateError(reason)

def capture(args: list[str], timeout: int = 50) -> str:
    try:
        p = subprocess.run(args, check=False, capture_output=True,
                           text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        fail("COMANDO_INDISPONIVEL")
    if p.returncode:
        fail("COMANDO_FALHOU")
    return p.stdout.strip()

def private(path: Path, mode: int, directory: bool = False) -> None:
    if (path.is_symlink() or not (path.is_dir() if directory else path.is_file())
        or path.stat().st_uid != os.geteuid()
        or stat.S_IMODE(path.stat().st_mode) != mode):
        fail("BACKUP_PERMISSOES_INVALIDAS")

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for part in iter(lambda: f.read(1024 * 1024), b""):
            h.update(part)
    return h.hexdigest()

def read_json(path: Path, limit: int = 4 * 1024 * 1024) -> dict:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > limit:
        fail("OCI_JSON_INVALIDO")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeError):
        fail("OCI_JSON_LEITURA_INVALIDA")
    if not isinstance(value, dict):
        fail("OCI_JSON_OBJETO_INVALIDO")
    return value

def current(service: str) -> tuple[str, str, int, list[str]]:
    ids = capture([
        "docker", "ps", "-q", "--filter",
        "label=com.docker.compose.project=" + PROJECT,
        "--filter", "label=com.docker.compose.service=" + service
    ]).splitlines()
    if len(ids) != 1:
        fail("CONTÊINER_NAO_UNICO_" + service)
    container = json.loads(capture(["docker", "inspect", ids[0]]))[0]
    state = container.get("State", {})
    if state.get("Running") is not True or (state.get("Health") or {}).get("Status") != "healthy":
        fail("SERVICO_NAO_HEALTHY_" + service)
    ref = container["Config"]["Image"]
    iid = container["Image"]
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", iid):
        fail("IMAGE_ID_INVALIDO_" + service)
    raw = json.loads(capture(["docker", "image", "inspect", ref]))[0]
    if raw.get("Id") != iid:
        fail("TAG_DIVERGENTE_" + service)
    layers = (raw.get("RootFS") or {}).get("Layers")
    if not isinstance(layers, list) or not layers:
        fail("ROOTFS_NAO_ENCONTRADO_" + service)
    return ref, iid, int(raw.get("Size") or 0), layers

def verify_oci(directory: Path, tag: str, expected_layers: list[str]) -> None:
    """Verifica o index, o manifest e blobs por SHA, sem usar Docker."""
    layout = read_json(directory / "oci-layout")
    if layout.get("imageLayoutVersion") != "1.0.0":
        fail("OCI_LAYOUT_VERSAO_INVALIDA")
    index = read_json(directory / "index.json")
    entries = index.get("manifests")
    if index.get("schemaVersion") != 2 or not isinstance(entries, list) or len(entries) != 1:
        fail("OCI_INDEX_INVALIDO")
    entry = entries[0]
    if (not isinstance(entry, dict) or
        (entry.get("annotations") or {}).get("org.opencontainers.image.ref.name") != tag):
        fail("OCI_TAG_LOCAL_INVALIDA")

    def blob(descriptor: dict) -> Path:
        if not isinstance(descriptor, dict):
            fail("OCI_DESCRIPTOR_INVALIDO")
        digest = descriptor.get("digest")
        size = descriptor.get("size")
        if (not isinstance(digest, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest)
            or not isinstance(size, int) or size <= 0):
            fail("OCI_DESCRIPTOR_DIGEST_INVALIDO")
        path = directory / "blobs" / "sha256" / digest[7:]
        if path.is_symlink() or not path.is_file() or path.stat().st_size != size:
            fail("OCI_BLOB_AUSENTE")
        if sha256_file(path) != digest[7:]:
            fail("OCI_BLOB_HASH_INVALIDO")
        return path

    manifest = read_json(blob(entry))
    if manifest.get("schemaVersion") != 2:
        fail("OCI_MANIFEST_INVALIDO")
    config = read_json(blob(manifest.get("config")))
    rootfs = (config.get("rootfs") or {}).get("diff_ids")
    if rootfs != expected_layers:
        fail("OCI_ROOTFS_NAO_CORRESPONDE_RUNTIME")
    layers = manifest.get("layers")
    if not isinstance(layers, list) or not layers:
        fail("OCI_SEM_CAMADAS")
    for item in layers:
        blob(item)
    print("IMP01_OCI_" + tag.upper() + "_INTEGRIDADE=PASS", flush=True)

def main() -> None:
    os.umask(0o077)
    print("=== CE-PA02-IMP01 — IMPORTACAO OCI PRIVADA ===", flush=True)
    print("DATA=" + dt.datetime.now().astimezone().isoformat(timespec="seconds"))
    if sys.argv[1:] != ["--isolated"]:
        fail("EXIGE_--isolated")
    if os.geteuid() == 0 or capture(["whoami"]) != "andrea.kiew":
        fail("USUARIO_INCORRETO")
    if socket.gethostname().split(".")[0] not in ("ep125-pucpr", "ep125-pucpr-br"):
        fail("HOST_INCORRETO")
    if capture(["git", "-C", str(ROOT), "rev-parse", "HEAD"]) != GIT_HEAD:
        fail("GIT_HEAD_DIVERGENTE")
    exe = shutil.which("skopeo")
    if not exe:
        print("FERRAMENTA_SKOPEO=NAO_INSTALADA")
        fail("SKOPEO_AUSENTE_NAO_INSTALAR_AUTOMATICAMENTE")
    capture([exe, "--version"])
    print("FERRAMENTA_SKOPEO=DISPONIVEL")

    private(BACKUP, 0o700, directory=True)
    private(DEST_PARENT, 0o700, directory=True)
    archive = BACKUP / "docker-images.tar.gz"
    manifest_file = BACKUP / "manifest.json"
    private(archive, 0o600)
    private(manifest_file, 0o600)
    manifest = read_json(manifest_file)
    if (manifest.get("type") != "CE-PA02-RC01_LOCAL_DOCKER_RECOVERY"
        or manifest.get("project") != PROJECT
        or manifest.get("git_head") != GIT_HEAD):
        fail("BACKUP_MANIFEST_NAO_CONFIAVEL")
    archive_sha = manifest.get("images_archive_sha256")
    if (not isinstance(archive_sha, str)
        or not re.fullmatch(r"[a-f0-9]{64}", archive_sha)
        or sha256_file(archive) != archive_sha):
        fail("BACKUP_SHA256_DIVERGENTE")
    print("PACOTE_RC01_SHA256=PASS")

    old = manifest.get("services")
    if not isinstance(old, dict) or set(old) != set(SERVICES):
        fail("MANIFEST_SERVICOS_NAO_COMPLETO")
    runtime = {}
    for service in SERVICES:
        runtime[service] = current(service)
        ref, iid, _, _ = runtime[service]
        if old[service].get("image_ref") != ref or old[service].get("image_id") != iid:
            fail("BASELINE_ALTERADA_" + service)
    if runtime["php"][0] != PA05_IMAGE or len({runtime[s][0] for s in SERVICES}) != 3:
        fail("IMAGENS_OBRIGATORIAS_DIVERGENTES")
    print("BASELINE_IMAGENS_RUNTIME=PASS")
    # Skopeo pode precisar expandir temporariamente o TAR e gravar OCI blobs.
    # Limite de espaco conservador antes de QUALQUER arquivo grande.
    estimate = max(2 * ONE_GIB,
                   archive.stat().st_size * 2
                   + sum(max(0, runtime[s][2]) for s in SERVICES) * 2
                   + ONE_GIB)
    available = shutil.disk_usage(DEST_PARENT).free
    if available < estimate:
        print("DISCO_LIVRE_GIB=" + str(round(available/ONE_GIB, 2)))
        print("DISCO_REQUERIDO_ESTIMADO_GIB=" + str(round(estimate/ONE_GIB, 2)))
        fail("DISCO_INSUFICIENTE_NAO_COPIAR")
    print("DISCO_PRECHECK=PASS")

    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    dest = DEST_PARENT / ("CE-PA02-IMP01-" + stamp)
    if dest.exists() or dest.is_symlink():
        fail("DESTINO_JA_EXISTE")
    dest.mkdir(mode=0o700)
    temp = dest / "tmp"
    temp.mkdir(mode=0o700)
    print("DESTINO_PRIVADO_CRIADO=SIM")
    env = os.environ.copy()
    env["TMPDIR"] = str(temp)
    for service in SERVICES:
        if shutil.disk_usage(dest).free < ONE_GIB:
            fail("RESERVA_DISCO_ESGOTADA_" + service)
        target = dest / ("oci-" + service)
        target.mkdir(mode=0o700)
        source = "docker-archive:" + str(archive) + ":" + runtime[service][0]
        output = "oci:" + str(target) + ":" + service
        try:
            proc = subprocess.run([exe, "copy", source, output],
                                  capture_output=True, text=True, check=False,
                                  env=env, timeout=480)
        except (OSError, subprocess.TimeoutExpired):
            fail("SKOPEO_IMPORTACAO_FALHOU_" + service)
        if proc.returncode:
            # Nunca imprimir stderr/stdout (metadados internos da imagem).
            fail("SKOPEO_COPY_FALHOU_" + service)
        verify_oci(target, service, runtime[service][3])
        print("IMP01_OCI_" + service.upper() + "_CONVERSAO=PASS", flush=True)

    print("IMP01_OCI_LAYOUTS_CONSTRUIDOS=3")
    print("DIRETORIO_ISOLADO=" + str(dest))
    print("CONVERSAO_USOU_DOCKER_DAEMON=NAO")
    print("DOCKER_IMAGE_LOAD_EXECUTADO=NAO")
    print("DOCKER_COMPOSE_EXECUTADO=NAO")
    print("CONTEINERES_PRODUCAO_RECRIADOS=NAO")
    print("ROLLBACK_DE_SERVICOS_ENSAIADO=NAO")
    print("VOLUMES_BANCO_SEGREDOS_RESTAURADOS=NAO")
    print("G0_APROVADO=NAO")
    print("CE-PA02-IMP01_CONCLUIDO")

if __name__ == "__main__":
    try:
        main()
    except GateError as exc:
        print("CE-PA02-IMP01_ABORTADO=" + str(exc), file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, TypeError, KeyError) as exc:
        print("CE-PA02-IMP01_ABORTADO=" + type(exc).__name__,
              file=sys.stderr)
        sys.exit(1)
