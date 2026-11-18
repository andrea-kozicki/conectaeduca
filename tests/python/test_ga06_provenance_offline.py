#!/usr/bin/env python3
"""GA-06: testes negativos de proveniencia sintetica (sem imagem/credencial real)."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "scripts/evidencias/ga06_validar_proveniencia_offline.py"
spec = importlib.util.spec_from_file_location("ga06_provenance_validator", VALIDATOR)
assert spec and spec.loader
prov = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prov)

TAG = "localhost/conectaeducca/fixture:v5"
DESCRIPTOR = "b" * 64
VERSION = "2.4.3+ce.pa07.v5"
DIFF_ID = "sha256:" + "c" * 64


def package_fixture(directory: Path, *, user="1000:1000", tag=TAG, version=VERSION,
                    layers=None, manifest_present=True):
    if layers is None:
        layers = [DIFF_ID] * 7
    config = {
        "os": "linux",
        "architecture": "amd64",
        "config": {
            "User": user,
            "Entrypoint": ["/ferret-scan"],
            "Cmd": ["--web"],
            "WorkingDir": "/home/ferret",
            "Env": ["TMPDIR=/home/ferret/tmp"],
            "Labels": {"org.opencontainers.image.version": version},
        },
        "rootfs": {"type": "layers", "diff_ids": layers},
    }
    config_json = json.dumps(config, sort_keys=True, separators=(",", ":")).encode()
    conf_hash = hashlib.sha256(config_json).hexdigest()
    manifest = [{"Config": conf_hash + ".json", "RepoTags": [tag], "Layers": []}]
    tar_path = directory / "synthetic-image.tar"
    with tarfile.open(tar_path, mode="w") as archive:
        for name, data in [
            ("manifest.json", json.dumps(manifest).encode()),
            (conf_hash + ".json", config_json),
        ]:
            if not manifest_present and name == "manifest.json":
                continue
            info = tarfile.TarInfo(name)
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))
    expected = {
        "schema_version": "ga06-candidate-v1",
        "candidate_tag": TAG,
        "archive_sha256": prov.sha256_file(tar_path),
        "archive_config_sha256": conf_hash,
        "ep126_docker_descriptor_sha256": DESCRIPTOR,
        "expected_user": "1000:1000",
        "expected_version": VERSION,
        "expected_os": "linux",
        "expected_architecture": "amd64",
        "expected_rootfs_layers": 7,
    }
    inspected = {
        "Id": "sha256:" + DESCRIPTOR,
        "Descriptor": {"digest": "sha256:" + DESCRIPTOR},
        "Os": "linux",
        "Architecture": "amd64",
        "Config": config["config"],
        "RootFS": {"Layers": layers},
    }
    return tar_path, expected, inspected


class GA06ProvenanceTests(unittest.TestCase):
    def test_tar_and_docker29_inspect_synthetic_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive, expected, inspected = package_fixture(Path(tmp))
            data = prov.verify_archive(archive, expected)
            prov.verify_inspect(inspected, expected, data)

    def test_archive_tampered_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive, expected, _ = package_fixture(Path(tmp))
            with archive.open("ab") as stream:
                stream.write(b"tampered fixture only")
            with self.assertRaises(prov.ProvenanceError):
                prov.verify_archive(archive, expected)

    def test_config_digest_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive, expected, _ = package_fixture(Path(tmp))
            expected["archive_config_sha256"] = "0" * 64
            with self.assertRaises(prov.ProvenanceError):
                prov.verify_archive(archive, expected)

    def test_wrong_user_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive, expected, _ = package_fixture(Path(tmp), user="root")
            with self.assertRaises(prov.ProvenanceError):
                prov.verify_archive(archive, expected)

    def test_wrong_version_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive, expected, _ = package_fixture(Path(tmp), version="2.4.3")
            with self.assertRaises(prov.ProvenanceError):
                prov.verify_archive(archive, expected)

    def test_missing_manifest_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive, expected, _ = package_fixture(Path(tmp), manifest_present=False)
            with self.assertRaises(prov.ProvenanceError):
                prov.verify_archive(archive, expected)

    def test_wrong_tag_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive, expected, _ = package_fixture(Path(tmp), tag="fake:v0")
            with self.assertRaises(prov.ProvenanceError):
                prov.verify_archive(archive, expected)

    def test_no_rootfs_layers_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive, expected, _ = package_fixture(Path(tmp), layers=[])
            with self.assertRaises(prov.ProvenanceError):
                prov.verify_archive(archive, expected)

    def test_docker_descriptor_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive, expected, inspected = package_fixture(Path(tmp))
            data = prov.verify_archive(archive, expected)
            inspected["Id"] = "sha256:" + "d" * 64
            with self.assertRaises(prov.ProvenanceError):
                prov.verify_inspect(inspected, expected, data)

    def test_docker_layers_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive, expected, inspected = package_fixture(Path(tmp))
            data = prov.verify_archive(archive, expected)
            inspected["RootFS"]["Layers"][0] = "sha256:" + "e" * 64
            with self.assertRaises(prov.ProvenanceError):
                prov.verify_inspect(inspected, expected, data)

    def test_runtime_env_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive, expected, inspected = package_fixture(Path(tmp))
            data = prov.verify_archive(archive, expected)
            inspected["Config"]["Env"] = ["TMPDIR=/tmp"]
            with self.assertRaises(prov.ProvenanceError):
                prov.verify_inspect(inspected, expected, data)

    def test_docker_descriptor_missing_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive, expected, inspected = package_fixture(Path(tmp))
            data = prov.verify_archive(archive, expected)
            inspected["Descriptor"] = None
            with self.assertRaises(prov.ProvenanceError):
                prov.verify_inspect(inspected, expected, data)


if __name__ == "__main__":
    unittest.main()
