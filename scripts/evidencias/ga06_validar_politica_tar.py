#!/usr/bin/env python3
"""GA-06: excecao de CI ESTREITA para override opt-in do docker-archive local.

Este gate valida politica estatica e custodia documentada; NAO atesta os bytes
do TAR (indisponiveis no GitHub Actions), aprova mudanca institucional ou
permite implantar sem verificar o TAR e a imagem no host autorizado.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "deploy/interna/ferret/pa07-v5/GA06_CANDIDATE_PROVENANCE.json"
OVERRIDE = ROOT / "deploy/interna/ferret/pa07-v5/compose.pa07-v5.override.yml"

# Custodia dos resultados de 25/10. Sao objetos DISTINTOS, nao digest de registry.
APPROVED = {
    "archive_sha256": "5786c56b47d7bb93604126e30cfbfb4fc549f5b1f791262fbe591555ead785a2",
    "archive_config_sha256": "1fab3fc1c35e4e33210cfd306364dc3ce672d16cd33f0505d51214647e6033ce",
    "ep126_docker_descriptor_sha256": "535ec9efb590dbaaeca41123321d773ba6d26d338686d89605492380ae9e187d",
}
LOCAL_TAG = "localhost/conectaeduca/ferret-scan:2.4.3-pa07-v5-candidate"


class PolicyError(ValueError):
    pass


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise PolicyError(reason)


def verify(manifest_path: Path, override_path: Path) -> None:
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    require(isinstance(data, dict), "manifesto nao e um objeto")
    for key, expected in {
        "schema_version": "ga06-candidate-v1",
        "artifact_kind": "docker-archive-local",
        "candidate_tag": LOCAL_TAG,
        "expected_user": "1000:1000",
        "expected_version": "2.4.3+ce.pa07.v5",
        "expected_os": "linux",
        "expected_architecture": "amd64",
        "expected_rootfs_layers": 7,
    }.items():
        require(type(data.get(key)) is type(expected) and data[key] == expected,
                "manifesto divergente: " + key)
    for key, digest in APPROVED.items():
        value = data.get(key)
        require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value)
                and value == digest, "digest de custodia divergente: " + key)
    require(len(set(APPROVED.values())) == 3, "digests de objetos distintos conflitam")

    # O override e propositadamente MINIMALISTA: so servico Ferret, image
    # literal de custodia e pull_policy never. Rejeitar qualquer outro campo
    # impede incluir volumes, portas, build, entrypoint, mounts e permissoes.
    lines = []
    for raw in override_path.read_text(encoding="utf-8").splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        lines.append(raw.rstrip())
    require(lines == [
        "services:",
        "  ferret:",
        "    image: " + LOCAL_TAG,
        "    pull_policy: never",
    ], "override nao respeita o contrato restrito image+pull_policy")
    require("@sha256:" not in LOCAL_TAG, "nao rotular digest de registry inventado")
    require(":latest" not in LOCAL_TAG, "tag latest proibida")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=MANIFEST)
    parser.add_argument("--override", type=Path, default=OVERRIDE)
    args = parser.parse_args()
    try:
        verify(args.manifest, args.override)
    except (OSError, ValueError, KeyError) as exc:
        print(f"GA06_OFFLINE_TAR_POLICY=FAIL reason={exc}", file=sys.stderr)
        return 1
    print("GA06_OFFLINE_TAR_POLICY=PASS scope=opt-in-path-only")
    print("GA06_TAR_BYTES_VERIFIED_IN_CI=NAO")
    print("GA06_INSTITUTIONAL_DEPLOY_APPROVAL=PENDENTE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
