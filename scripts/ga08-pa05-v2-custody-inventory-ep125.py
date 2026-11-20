#!/usr/bin/env python3
"""GA08/PA05 EP125: read-only custody inventory for a future private v2 manifest.

Reuses three previously reviewed and SHA-256 pinned private diagnostics.
Requires the six Compose runtime hash comparisons to match. It computes
source and image digests only in memory; prints counts and statuses only.

This is deliberately NOT a private-manifest generator. It never reads secret
file *contents*, writes a file, invokes Compose up/down, or enables rollback.
"""

from __future__ import annotations

import hashlib
import os
import re
import runpy
import socket
import stat
import subprocess
from pathlib import Path
from typing import Any

PEER_NAME = "ga08-runtime-hash-parity-ep125.py"
PEER_SHA256 = "8e215f3828c465b1d0245e8480acb64292147fb0681efbb1eda893848417a5b8"
IMAGE_HASH = re.compile(r"sha256:[0-9a-f]{64}\Z")
SERVICES = ("php", "nginx", "waf")


class InventoryError(Exception):
    pass


def require(ok: bool, reason: str) -> None:
    if not ok:
        raise InventoryError(reason)


def load_peer(home: Path) -> dict[str, Any]:
    """Pin the reviewed hash-parity module *before* executing its source."""
    path = home / "Downloads" / PEER_NAME
    fd = -1
    try:
        require(path.is_absolute() and path.resolve(strict=True) == path,
                "biblioteca_caminho_inseguro")
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        metadata = os.fstat(fd)
        require(stat.S_ISREG(metadata.st_mode) and metadata.st_nlink == 1 and
                metadata.st_uid in (0, os.getuid()) and
                not (stat.S_IMODE(metadata.st_mode) & 0o022) and
                0 < metadata.st_size <= 100_000, "biblioteca_permissoes_invalidas")
        with os.fdopen(fd, "rb") as input_file:
            fd = -1
            data = input_file.read(100_001)
        require(len(data) <= 100_000 and
                hashlib.sha256(data).hexdigest() == PEER_SHA256,
                "biblioteca_hash_divergente")
    except (OSError, RuntimeError, ValueError):
        raise InventoryError("biblioteca_indisponivel") from None
    finally:
        if fd >= 0:
            os.close(fd)
    try:
        return runpy.run_path(str(path), run_name="ga08_hash_parity_library")
    except Exception:
        raise InventoryError("biblioteca_indisponivel") from None


def local_image_id(reference: str) -> str:
    """Read only an allowlisted Docker image ID; never inspect Env or secrets."""
    require(isinstance(reference, str) and
            reference in ("conectaeduca/php-fpm:pa05-10328ab6",
                          "conectaeduca/nginx:dmz", "conectaeduca/waf:dmz"),
            "imagem_referencia_nao_aprovada")
    try:
        proc = subprocess.run(
            ["docker", "image", "inspect", "--format", "{{.Id}}", reference],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        raise InventoryError("imagem_local_indisponivel") from None
    require(proc.returncode == 0, "imagem_local_indisponivel")
    try:
        result = proc.stdout.decode("ascii").strip()
    except UnicodeError:
        raise InventoryError("imagem_id_invalido") from None
    require(bool(IMAGE_HASH.fullmatch(result)), "imagem_id_invalido")
    return result


def collect(home: Path, peer: dict[str, Any]) -> dict[str, Any]:
    """Gather only in-memory attestable fields of a possible v2 manifest.

    No real manifest is assembled: missing snapshot and approved config-model
    digests are intentionally not guessed or silently declared valid.
    """
    require(peer["compose_version"]() == "5.7.0", "compose_versao_divergente")
    interp = peer["verified_peer"](home)
    comparisons = peer["report"](home, interp)
    require(len(comparisons) == 2 and all(
        item.get(service) == "IGUAL" for item in comparisons
        for service in SERVICES
    ), "hash_runtime_nao_comprovado")

    lib = interp["load_verified_library"](home)
    snapshots = lib["inspect_runtime"]()
    sources = interp["approved_compose_paths"](snapshots, lib, home)
    peer["check_no_service_env_files"](sources)
    require(len(sources) == 14, "compose_fontes_invalidas")
    digests: dict[str, str] = {}
    for index, source in enumerate(sources, start=1):
        digest = interp["secure_digest"](source, limit=1_000_000,
                                          suffix=".yml")
        require(re.fullmatch(r"[0-9a-f]{64}", digest) is not None,
                "compose_digest_invalido")
        digests[f"{index:02d}"] = digest

    images: dict[str, dict[str, str]] = {}
    for service in SERVICES:
        container = snapshots[service]
        meta = container.get("Config") or {}
        reference = meta.get("Image")
        running_id = container.get("Image")
        require(isinstance(running_id, str) and
                IMAGE_HASH.fullmatch(running_id), "imagem_runtime_invalida")
        require(local_image_id(reference) == running_id,
                "imagem_tag_runtime_divergente")
        images[service] = {"reference": reference, "image_id": running_id}

    # Private material never leaves this process. No host paths, hashes,
    # environment values or image IDs appear in the printed summary.
    return {
        "context_count": len(comparisons),
        "service_parity_count": len(comparisons) * len(SERVICES),
        "source_hashes": digests,
        "images": images,
        "compose_count": len(sources),
    }


def main() -> int:
    print("=== CE-GA08 | CUSTODIA PARCIAL MANIFESTO V2 | EP125 ===")
    try:
        require(socket.gethostname().split(".")[0] in
                ("ep125-pucpr", "ep125-pucpr-br"), "host_incorreto")
        require(os.geteuid() != 0, "nao_executar_root")
        result = collect(Path.home(), load_peer(Path.home()))
        print("CONTEXTOS_PRIVADOS=" + str(result["context_count"]) + "_VALIDADOS")
        print("HASHES_SERVICO=" + str(result["service_parity_count"]) + "_MATCH")
        print("FONTES_COMPOSE=" + str(result["compose_count"]) + "_SHA256_EM_MEMORIA")
        print("IMAGENS=" + str(len(result["images"])) + "_IDS_LOCAIS_CONFERIDOS")
        print("DIGEST_CONFIG_11_14=NAO_RECOLHIDO")
        print("SNAPSHOT_ATUAL=NAO_ATESTADO")
        print("SEGREDOS_RECUPERAVEIS=NAO_COMPROVADO")
        print("COLETOR_V2=PASS_CUSTODIA_PARCIAL_SOMENTE_LEITURA")
        return 0
    except InventoryError as error:
        print("COLETOR_V2=FAIL_CLOSED")
        print("MOTIVO=" + str(error))
        return 3
    except Exception:
        print("COLETOR_V2=FAIL_CLOSED")
        print("MOTIVO=erro_inesperado")
        return 3
    finally:
        print("CAMINHOS_HASHES_IDS_E_VALORES_EXIBIDOS=NAO")
        print("MANIFESTO_V2_CRIADO=NAO")
        print("ARQUIVOS_MODIFICADOS=NAO")
        print("SERVICOS_MODIFICADOS=NAO")
        print("ROLLBACK_HABILITADO=NAO")
        print("=== FIM ===")


if __name__ == "__main__":
    raise SystemExit(main())
