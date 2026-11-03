#!/usr/bin/env python3
"""GA-06: valida custodia de docker-archive e descritor Docker 29 sem executar Docker.

O script so le entradas internas do TAR (sem extracao), JSON de manifesto e
docker image inspect opcional. Nunca imprime ENV, arquivos brutos ou secrets.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = ROOT / "deploy/interna/ferret/pa07-v5/GA06_CANDIDATE_PROVENANCE.json"


class ProvenanceError(ValueError):
    pass


def require(ok: bool, problem: str) -> None:
    if not ok:
        raise ProvenanceError(problem)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_tar_member(archive: tarfile.TarFile, name: str, max_size: int = 1024 * 1024) -> bytes:
    require(bool(name) and not name.startswith("/") and ".." not in Path(name).parts,
            "nome inseguro dentro do archive")
    member = archive.getmember(name)
    require(member.isfile() and member.size <= max_size, "entrada TAR ausente, grande ou nao regular")
    stream = archive.extractfile(member)
    require(stream is not None, "nao foi possivel ler entrada TAR")
    with stream:
        payload = stream.read(max_size + 1)
    require(len(payload) <= max_size, "entrada TAR excedeu limite")
    return payload


def load_json_bytes(data: bytes) -> object:
    try:
        return json.loads(data)
    except (ValueError, UnicodeDecodeError) as exc:
        raise ProvenanceError("JSON de configuracao/manifesto invalido") from exc


def verify_archive(path: Path, expected: dict) -> dict:
    require(path.is_file(), "TAR nao encontrado")
    require(sha256_file(path) == expected["archive_sha256"], "TAR_SHA256 divergente")
    try:
        with tarfile.open(path, mode="r:*") as archive:
            manifest = load_json_bytes(read_tar_member(archive, "manifest.json"))
            require(isinstance(manifest, list) and len(manifest) == 1, "manifesto nao contem imagem unica")
            row = manifest[0]
            require(isinstance(row, dict), "registro manifesto invalido")
            require(row.get("RepoTags") == [expected["candidate_tag"]], "tag archive nao corresponde")
            config_path = row.get("Config")
            require(isinstance(config_path, str) and
                    re.fullmatch(r"[0-9a-f]{64}\.json", config_path) is not None,
                    "nome config JSON inesperado")
            config_bytes = read_tar_member(archive, config_path)
            config_hash = hashlib.sha256(config_bytes).hexdigest()
            require(config_hash == expected["archive_config_sha256"], "config SHA256 divergente")
            # Docker archive can use a path named after the config digest; check both.
            require(config_path == config_hash + ".json", "nome do config diferente do seu conteudo")
            data = load_json_bytes(config_bytes)
            require(isinstance(data, dict), "config nao e objeto")
            conf = data.get("config") or {}
            rootfs = data.get("rootfs") or {}
            require(isinstance(conf, dict) and isinstance(rootfs, dict), "estrutura config invalida")
            require(conf.get("User") == expected["expected_user"], "UID/GID divergente")
            labels = conf.get("Labels") or {}
            require(isinstance(labels, dict) and
                    labels.get("org.opencontainers.image.version") == expected["expected_version"],
                    "versao divergente")
            require(data.get("os") == expected["expected_os"] and
                    data.get("architecture") == expected["expected_architecture"],
                    "plataforma divergente")
            layers = rootfs.get("diff_ids")
            require(isinstance(layers, list) and
                    len(layers) == expected["expected_rootfs_layers"] and
                    all(isinstance(d, str) and re.fullmatch(r"sha256:[0-9a-f]{64}", d)
                        for d in layers),
                    "camadas rootfs invalidas")
            return {"config": conf, "rootfs_diff_ids": layers, "os": data["os"],
                    "architecture": data["architecture"]}
    except (OSError, tarfile.TarError, KeyError) as exc:
        raise ProvenanceError("archive invalido ou incompleto") from exc


def verify_inspect(inspect_data: object, expected: dict, archive_data: dict) -> None:
    if isinstance(inspect_data, list):
        require(len(inspect_data) == 1, "inspect deve conter imagem unica")
        inspect_data = inspect_data[0]
    require(isinstance(inspect_data, dict), "inspect JSON nao e objeto")
    image_id = "sha256:" + expected["ep126_docker_descriptor_sha256"]
    require(inspect_data.get("Id") == image_id, "Docker Image ID divergente")
    descriptor = inspect_data.get("Descriptor") or {}
    require(isinstance(descriptor, dict) and descriptor.get("digest") == image_id,
            "digest do descritor Docker 29 divergente")
    conf = inspect_data.get("Config") or {}
    require(isinstance(conf, dict), "config docker inspect invalida")
    require(conf.get("User") == expected["expected_user"], "user Docker divergente")
    labels = conf.get("Labels") or {}
    require(isinstance(labels, dict) and
            labels.get("org.opencontainers.image.version") == expected["expected_version"],
            "versao Docker divergente")
    require(inspect_data.get("Os") == archive_data["os"] and
            inspect_data.get("Architecture") == archive_data["architecture"],
            "plataforma Docker divergente")
    rootfs = inspect_data.get("RootFS") or {}
    require(isinstance(rootfs, dict) and
            rootfs.get("Layers") == archive_data["rootfs_diff_ids"],
            "camadas Docker divergentes")
    # Comparar campos operacionais, sem expor os valores.
    for key in ("User", "Entrypoint", "Cmd", "WorkingDir", "Env", "Labels"):
        require(conf.get(key) == archive_data["config"].get(key),
                "metadados operacionais Docker divergentes")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--inspect-json", type=Path,
                        help="export Docker inspect sob custodia, nunca publicar ENV")
    args = parser.parse_args()

    try:
        expected = json.loads(args.manifest.read_text(encoding="utf-8"))
        require(isinstance(expected, dict) and
                expected.get("schema_version") == "ga06-candidate-v1", "manifesto inesperado")
        data = verify_archive(args.archive, expected)
        print("GA06_TAR_E_CONFIG=PASS")
        if args.inspect_json is not None:
            inspect = json.loads(args.inspect_json.read_text(encoding="utf-8"))
            verify_inspect(inspect, expected, data)
            print("GA06_DOCKER_DESCRIPTOR_E_ROOTFS=PASS")
        else:
            print("GA06_DOCKER_DESCRIPTOR_E_ROOTFS=NAO_TESTADO")
        print("GA06_PROVENIENCIA=PASS")
        return 0
    except (OSError, ValueError, KeyError) as exc:
        print("GA06_PROVENIENCIA=FAIL", file=sys.stderr)
        print(f"MOTIVO={exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
