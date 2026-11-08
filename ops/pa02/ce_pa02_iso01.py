#!/usr/bin/env python3
"""CE-PA02-ISO01: valida arquivo docker save e executa smoke isolado das 3 imagens.

Nao realiza docker image load, docker compose, montagem de volumes, restart
nem altera contêineres existentes. Nao é ensaio de rollback real.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import stat
import subprocess
import sys
import tarfile

ROOT = Path("/opt/conectaeduca")
BACKUP = Path(
    "/home/andrea.kiew/.local/share/conectaeduca/pa02-recovery/"
    "CE-PA02-RC01-20261108-183146"
)
PROJECT = "conectaeduca-dmz"
SERVICES = ("php", "nginx", "waf")
PATCH_IMAGE = "conectaeduca/php-fpm:pa05-10328ab6"
MAX_CACHED_META_BYTES = 20 * 1024 * 1024


class GateError(Exception):
    pass


def fail(code: str) -> None:
    raise GateError(code)


def run(args: list[str], timeout: int = 50) -> str:
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        fail("COMANDO_INDISPONIVEL")
    if p.returncode:
        fail("COMANDO_NAO_PASSOU")
    return p.stdout.strip()


def safe_file(path: Path) -> None:
    if (path.is_symlink() or not path.is_file()
            or path.stat().st_uid != os.geteuid()
            or stat.S_IMODE(path.stat().st_mode) != 0o600):
        fail("ARQUIVO_PRIVADO_INVALIDO")


def current_image(service: str) -> tuple[str, str]:
    ids = run([
        "docker", "ps", "-q",
        "--filter", "label=com.docker.compose.project=" + PROJECT,
        "--filter", "label=com.docker.compose.service=" + service,
    ]).splitlines()
    if len(ids) != 1:
        fail("CONTAINER_NAO_UNICO_" + service)
    values = json.loads(run(["docker", "inspect", ids[0]]))
    if not isinstance(values, list) or len(values) != 1:
        fail("INSPECT_INVALIDO_" + service)
    data = values[0]
    st = data.get("State", {})
    if (st.get("Running") is not True
            or (st.get("Health") or {}).get("Status") != "healthy"):
        fail("BASELINE_NAO_HEALTHY_" + service)
    ref = data["Config"]["Image"]
    iid = data["Image"]
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", iid):
        fail("IMAGE_ID_INVALIDO_" + service)
    if run(["docker", "image", "inspect", ref, "--format", "{{.Id}}"]) != iid:
        fail("TAG_RUNTIME_DIVERGENTE_" + service)
    return (ref, iid)


def inspect_tar_archive(archive: Path, expected: dict[str, str]) -> None:
    """Faz parsing stream e confere que configs Docker e layers existem no tar."""
    hashes: dict[str, str] = {}
    sizes: dict[str, int] = {}
    metas: dict[str, bytes] = {}
    meta_used = 0
    count = 0
    # tarfile stream descompacta sem gravar qualquer arquivo no host.
    try:
        with tarfile.open(archive, mode="r|gz") as stream:
            for item in stream:
                count += 1
                if count > 100000:
                    fail("ARQUIVO_TAR_ENTRADAS_EXCESSIVAS")
                if not item.isfile():
                    continue
                if item.name in hashes:
                    fail("ARQUIVO_TAR_NOME_DUPLICADO")
                if item.name.startswith("/") or ".." in Path(item.name).parts:
                    fail("ARQUIVO_TAR_NOME_INSEGURO")
                fd = stream.extractfile(item)
                if fd is None:
                    fail("ARQUIVO_TAR_ENTRADA_ILEGIVEL")
                h = hashlib.sha256()
                keep = item.size <= 1024 * 1024 and meta_used + item.size <= MAX_CACHED_META_BYTES
                saved = bytearray() if keep else None
                total = 0
                while True:
                    chunk = fd.read(1024 * 1024)
                    if not chunk:
                        break
                    h.update(chunk)
                    total += len(chunk)
                    if saved is not None:
                        saved.extend(chunk)
                if total != item.size:
                    fail("ARQUIVO_TAR_ENTRADA_TRUNCADA")
                hashes[item.name] = h.hexdigest()
                sizes[item.name] = item.size
                if saved is not None:
                    metas[item.name] = bytes(saved)
                    meta_used += len(saved)
    except (tarfile.TarError, EOFError, OSError) as ex:
        fail("ARQUIVO_TAR_INVALIDO_" + type(ex).__name__)
    if "manifest.json" not in metas:
        fail("ARQUIVO_TAR_MANIFEST_AUSENTE")
    try:
        rows = json.loads(metas["manifest.json"].decode("utf-8"))
    except (UnicodeError, ValueError):
        fail("ARQUIVO_TAR_MANIFEST_INVALIDO")
    if not isinstance(rows, list) or len(rows) != len(expected):
        fail("ARQUIVO_TAR_IMAGENS_NAO_UNICAS")
    by_tag: dict[str, dict] = {}
    for row in rows:
        if not isinstance(row, dict):
            fail("ARQUIVO_TAR_ROW_INVALIDA")
        config = row.get("Config")
        layers = row.get("Layers")
        tags = row.get("RepoTags") or []
        if (not isinstance(config, str) or config not in hashes
                or not isinstance(layers, list) or not layers
                or not isinstance(tags, list)):
            fail("ARQUIVO_TAR_CONFIG_OU_LAYERS_AUSENTES")
        for layer in layers:
            if not isinstance(layer, str) or layer not in sizes or sizes[layer] == 0:
                fail("ARQUIVO_TAR_LAYER_AUSENTE")
        for tag in tags:
            if tag in by_tag:
                fail("ARQUIVO_TAR_TAG_DUPLICADA")
            by_tag[tag] = row
    if set(by_tag) != set(expected):
        fail("ARQUIVO_TAR_TAGS_DIVERGENTES")
    # Com backend containerd, ImageID pode ser manifest/index digest, nao
    # hash do config JSON. Validar SHA do config por seu nome no TAR,
    # SHA de cada layer pelos rootfs.diff_ids e diffids do runtime.
    for tag, image_id in expected.items():
        config = by_tag[tag]["Config"]
        digest = hashes[config]
        if Path(config).name != digest+".json":
            fail("ARQUIVO_CONFIG_NOME_SHA256_DIVERGENTE")
        if config not in metas:
            fail("ARQUIVO_CONFIG_JSON_INACESSIVEL")
        try:
            cfg=json.loads(metas[config].decode("utf-8"))
            diffids=cfg["rootfs"]["diff_ids"]
        except (KeyError,TypeError,ValueError,UnicodeError):
            fail("ARQUIVO_CONFIG_ROOTFS_INVALIDO")
        layers=by_tag[tag]["Layers"]
        if (not isinstance(diffids,list) or len(diffids)!=len(layers) or
            any(not isinstance(d,str) or not re.fullmatch(r"sha256:[a-f0-9]{64}",d)
                for d in diffids)):
            fail("ARQUIVO_CONFIG_DIFFIDS_INVALIDOS")
        for layer,diffid in zip(layers,diffids):
            if "sha256:"+hashes[layer]!=diffid:
                fail("ARQUIVO_LAYER_DIFFID_DIVERGENTE")
        runtime_layers=json.loads(run([
            "docker","image","inspect",tag,
            "--format","{{json .RootFS.Layers}}",
        ]))
        if not isinstance(runtime_layers,list) or runtime_layers!=diffids:
            fail("ARQUIVO_ROOTFS_RUNTIME_DIVERGENTE")
    print("ISO01_DOCKER_SAVE_MANIFEST=PASS")
    print("ISO01_CONFIG_NOME_SHA256=PASS")
    print("ISO01_LAYERS_DIFFIDS_SHA256=PASS")
    print("ISO01_ROOTFS_RUNTIME_DIFFIDS=PASS")


def isolated_smoke(service: str, image_ref: str) -> None:
    uid = "82:82" if service == "php" else "101:101"
    cmd = "php -v >/dev/null 2>&1" if service == "php" else "nginx -v >/dev/null 2>&1"
    if service == "php":
        cmd += " && php -l /var/www/conectaeduca/src/Repository/InscricaoRepository.php >/dev/null 2>&1"
        cmd += " && php -l /var/www/conectaeduca/src/Service/InscricaoService.php >/dev/null 2>&1"
        cmd += " && php -l /var/www/conectaeduca/src/Controller/InscricaoController.php >/dev/null 2>&1"
    try:
        p = subprocess.run([
            "docker", "run", "--rm", "--pull", "never",
            "--network", "none", "--read-only", "--user", uid,
            "--cap-drop", "ALL", "--security-opt", "no-new-privileges:true",
            "--pids-limit", "32", "--entrypoint", "/bin/sh",
            image_ref, "-ec", cmd,
        ], capture_output=True, text=True, timeout=40)
    except (OSError, subprocess.TimeoutExpired):
        fail("SANDBOX_INDISPONIVEL_" + service)
    if p.returncode:
        fail("SANDBOX_BINARIO_NAO_PASSOU_" + service)
    print("ISO01_SANDBOX_" + service.upper() + "=PASS")


def main() -> None:
    print("=== CE-PA02-ISO01 — ENSAIO ISOLADO SEM CORTE ===")
    print("DATA=" + dt.datetime.now().astimezone().isoformat(timespec="seconds"))
    if sys.argv[1:] != ["--check"]:
        fail("EXIGE_--check")
    if os.geteuid() == 0 or run(["whoami"]) != "andrea.kiew":
        fail("USUARIO_INCORRETO_OU_ROOT")
    if socket.gethostname().split(".")[0] not in ("ep125-pucpr", "ep125-pucpr-br"):
        fail("HOST_INCORRETO")
    if run(["git", "-C", str(ROOT), "rev-parse", "HEAD"]) != (
            "04f88d275064a005d0ffcd4f9372a371c28c32d5"):
        fail("GIT_HEAD_DIVERGENTE")
    if (not BACKUP.is_dir() or BACKUP.is_symlink()
            or BACKUP.stat().st_uid != os.geteuid()
            or stat.S_IMODE(BACKUP.stat().st_mode) != 0o700):
        fail("PACOTE_PRIVADO_INVALIDO")
    archive = BACKUP / "docker-images.tar.gz"
    manifest_path = BACKUP / "manifest.json"
    safe_file(archive)
    safe_file(manifest_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if (manifest.get("type") != "CE-PA02-RC01_LOCAL_DOCKER_RECOVERY"
            or manifest.get("project") != PROJECT):
        fail("MANIFEST_RC01_INVALIDO")
    services = manifest.get("services")
    if not isinstance(services, dict) or set(services) != set(SERVICES):
        fail("MANIFEST_RC01_SERVICOS_INVALIDOS")
    expected: dict[str, str] = {}
    for svc in SERVICES:
        ref, iid = current_image(svc)
        old = services[svc]
        if (old.get("image_ref") != ref or old.get("image_id") != iid
                or old.get("container_id") is None):
            fail("BASELINE_DIVERGENTE_" + svc)
        expected[ref] = iid
    if len(expected) != 3 or services["php"]["image_ref"] != PATCH_IMAGE:
        fail("IMAGENS_NAO_UNICAS_OU_PA05_AUSENTE")
    print("ISO01_BASELINE_3_SERVICOS=HEALTHY")
    # DRY01 ja verificou SHA-256 do arquivo inteiro e manifest. Aqui
    # conferimos config/diffID/rootfs, sem equiparar digest OCI a config.
    inspect_tar_archive(archive, expected)
    for service in SERVICES:
        isolated_smoke(service, services[service]["image_ref"])
    print("ISO01_SEM_REDE_SEM_VOLUMES_SEM_SEGREDOS=SIM")
    print("ISO01_DOCKER_LOAD_EXECUTADO=NAO")
    print("ISO01_DOCKER_COMPOSE_EXECUTADO=NAO")
    print("ISO01_PRODUCAO_RECRIADA=NAO")
    print("ISO01_ROLLBACK_REAL_ENSAIADO=NAO")
    print("ISO01_VM_VOLUMES_BANCO_RESTAURADOS=NAO")
    print("CE-PA02-ISO01_CONCLUIDO")


if __name__ == "__main__":
    try:
        main()
    except GateError as exc:
        print("CE-PA02-ISO01_ABORTADO=" + str(exc), file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, KeyError, TypeError, PermissionError) as exc:
        print("CE-PA02-ISO01_ABORTADO=" + type(exc).__name__, file=sys.stderr)
        sys.exit(1)
