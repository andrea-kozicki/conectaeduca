#!/usr/bin/env python3
"""Read-only GA08/PA05 recovery inventory for the deployed EP125 stack.

No Docker Compose up/down, no Docker exec, no logs, no secret contents, no
filesystem writes. An optional Compose config check has interpolation and
service env-file resolution disabled, with stdout/stderr suppressed.
This is NOT an executable rollback driver or approval.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import socket
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path("/opt/conectaeduca")
DMZ = REPO_ROOT / "deploy/dmz"
PROJECT = "conectaeduca-dmz"
CONTAINERS = {
    "php": "conectaeduca-dmz-php-1",
    "nginx": "conectaeduca-dmz-nginx-1",
    "waf": "conectaeduca-dmz-waf-1",
}
EXPECTED_IMAGES = {
    "php": "conectaeduca/php-fpm:pa05-10328ab6",
    "nginx": "conectaeduca/nginx:dmz",
    "waf": "conectaeduca/waf:dmz",
}
BASE = (
    "compose.yml",
    "compose.database.yml",
    "compose.app-secrets.yml",
    "compose.waf.yml",
    "compose.waf-tls.yml",
    "compose.waf-policy.yml",
    "compose.host.yml",
    "compose.vm.yml",
    "compose.database-tls.yml",
    "compose.audit-persistent.yml",
)
PA05 = "compose.pa05-10328ab6.yml"
GA08 = (
    "compose.ga08-socket.candidate.yml",
    "compose.ga08-dual-socket.candidate.yml",
    "compose.ga08-runtimefix.candidate.yml",
)
EXPECTED_ORDER = BASE + (PA05,) + GA08
# SHA-256 of the exact GA08 candidates reviewed in PR #217 (19/11/2026).
# HOME-hosted runtime copies are accepted only if they match these bytes.
# Do not replace this pinning with a comparison of two mutable local copies.
APPROVED_GA08_SHA256 = {
    "compose.ga08-socket.candidate.yml":
        "5e6ce7dbab62b104a1448a84e23690c86d07ceccbbf36bfad9b8b91fb344dadc",
    "compose.ga08-dual-socket.candidate.yml":
        "fbf5c3aac42e02c40d09cf2fc0e19ccf634570a0d2049b2fbbceb4e49d191d51",
    "compose.ga08-runtimefix.candidate.yml":
        "9fb109e9b2da4b397c43c541d7120a68b682cc745eb6b3298061d5927e3aeb84",
}


class PreflightError(Exception):
    pass


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise PreflightError(reason)


def expected_paths(repo_root: Path, home: Path) -> tuple[Path, ...]:
    dmz = repo_root / "deploy/dmz"
    pa05 = home / ".config/conectaeduca/pa05" / PA05
    return tuple(dmz / name for name in BASE) + (pa05,) + tuple(
        dmz / name for name in GA08
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(65536), b""):
                digest.update(block)
    except OSError:
        raise PreflightError("ga08_candidato_ilegivel") from None
    return digest.hexdigest()


def analyze_runtime(
    snapshots: dict[str, dict[str, Any]], repo_root: Path, home: Path,
    *, check_sources: bool = True,
) -> dict[str, Any]:
    """Verify exact identities and Compose ordering; retain paths in memory."""
    required_paths = expected_paths(repo_root, home)
    actual_reference: tuple[Path, ...] | None = None

    for service in ("php", "nginx", "waf"):
        entry = snapshots.get(service)
        require(isinstance(entry, dict), "container_metadata_ausente_" + service)
        require(entry.get("project") == PROJECT, "projeto_divergente_" + service)
        require(entry.get("service") == service, "servico_divergente_" + service)
        require(entry.get("image") == EXPECTED_IMAGES[service],
                "imagem_divergente_" + service)
        require(entry.get("state") == "running" and entry.get("health") == "healthy",
                "servico_nao_saudavel_" + service)
        require(str(entry.get("restarts")) == "0", "restarts_divergentes_" + service)

        label = entry.get("files")
        require(isinstance(label, str) and label and "\n" not in label,
                "compose_label_invalido_" + service)
        filenames = label.split(",")
        require(len(filenames) == 14 and all(filenames),
                "compose_quantidade_divergente_" + service)
        paths = tuple(Path(name) for name in filenames)
        require(all(path.is_absolute() for path in paths),
                "compose_caminho_nao_absoluto_" + service)
        require(tuple(path.name for path in paths) == EXPECTED_ORDER,
                "compose_ordem_divergente_" + service)
        # Entries 01-11 have exact, approved locations. GA08 12-14 may be
        # runtime custody copies below HOME; their content is verified below.
        require(paths[:11] == required_paths[:11],
                "compose_origem_base_nao_aprovada_" + service)
        for index in range(11, 14):
            ga08_path = paths[index]
            require(
                ga08_path == required_paths[index] or
                (ga08_path != home and ga08_path.is_relative_to(home)),
                "compose_origem_ga08_nao_aprovada_" + str(index + 1),
            )
        if actual_reference is None:
            actual_reference = paths
        else:
            require(paths == actual_reference, "compose_lista_diferente_" + service)

    if check_sources:
        require(actual_reference is not None, "compose_lista_vazia")
        for index, path in enumerate(actual_reference):
            require(path.is_file() and not path.is_symlink(),
                    "compose_fonte_inacessivel_" + str(index + 1))
            try:
                canonical = path.resolve(strict=True)
            except OSError:
                raise PreflightError("compose_fonte_inacessivel_" + str(index + 1)) from None
            require(canonical == path,
                    "compose_origem_symlink_" + str(index + 1))
            if index >= 11:
                # Candidate overlays are non-secret files. Their on-disk
                # bytes must match the reviewed PR, never a mutable local
                # reference only. Private HOME copies must be operator-owned
                # and not writable by group/others.
                if path != required_paths[index]:
                    meta = path.stat()
                    require(meta.st_uid == os.getuid() and
                            not (stat.S_IMODE(meta.st_mode) & 0o022),
                            "ga08_home_acl_insegura_" + str(index + 1))
                require(sha256_file(path) == APPROVED_GA08_SHA256[GA08[index - 11]],
                        "ga08_candidato_hash_divergente_" + str(index + 1))

    return {
        "current_compose_count": len(EXPECTED_ORDER),
        "baseline_compose_count": len(BASE) + 1,
        "ga08_overlay_count": len(GA08),
        "services": len(CONTAINERS),
        "sources_checked": check_sources,
        "ga08_hashes_checked": check_sources,
    }


def docker_field(container: str, template: str) -> str:
    """Request only an allowlisted Docker field, never full inspect output."""
    try:
        process = subprocess.run(
            ["docker", "inspect", "--type", "container", "--format", template,
             container],
            capture_output=True, text=True, timeout=10, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        raise PreflightError("docker_indisponivel") from None
    require(process.returncode == 0, "docker_inspect_falhou")
    value = process.stdout.strip()
    require("\n" not in value and "\r" not in value,
            "docker_campo_invalido")
    return value


def get_runtime() -> dict[str, dict[str, Any]]:
    fields = {
        "project": '{{index .Config.Labels "com.docker.compose.project"}}',
        "service": '{{index .Config.Labels "com.docker.compose.service"}}',
        "files": '{{index .Config.Labels "com.docker.compose.project.config_files"}}',
        "image": "{{.Config.Image}}",
        "state": "{{.State.Status}}",
        "health": '{{if .State.Health}}{{.State.Health.Status}}{{else}}sem_healthcheck{{end}}',
        "restarts": "{{.RestartCount}}",
    }
    return {
        service: {key: docker_field(container, template)
                  for key, template in fields.items()}
        for service, container in CONTAINERS.items()
    }


def check_compose_structure(
    snapshots: dict[str, dict[str, Any]], repo_root: Path,
) -> None:
    """Validate both models without variable/env-file resolution or output."""
    files_label = snapshots["php"]["files"]
    paths = tuple(Path(path) for path in files_label.split(","))
    require(len(paths) == 14, "compose_lista_incompleta")
    for count in (11, 14):
        command = [
            "docker", "compose", "--project-directory", str(repo_root / "deploy/dmz"),
            "-p", PROJECT,
        ]
        for path in paths[:count]:
            command.extend(["-f", str(path)])
        command.extend([
            "config", "--no-interpolate", "--no-env-resolution", "--quiet",
        ])
        try:
            process = subprocess.run(
                command, capture_output=True, text=True, timeout=40,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            raise PreflightError("compose_config_indisponivel_" + str(count)) from None
        # Compose output could include paths or variable values on failure;
        # neither stdout nor stderr is printed or retained in evidence.
        require(process.returncode == 0,
                "compose_config_sem_interpolacao_falhou_" + str(count))


def require_host() -> None:
    require(socket.gethostname().split(".")[0] in
            ("ep125-pucpr", "ep125-pucpr-br"), "host_nao_ep125")
    require(os.geteuid() != 0, "nao_executar_com_root")
    require(REPO_ROOT.is_dir(), "checkout_institucional_ausente")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-compose", action="store_true",
                        help="tambem validar a sintaxe Compose 11/14 sem interpolacao")
    args = parser.parse_args()
    try:
        require_host()
        snapshots = get_runtime()
        summary = analyze_runtime(snapshots, REPO_ROOT, Path.home())
        if args.check_compose:
            check_compose_structure(snapshots, REPO_ROOT)
    except PreflightError as exc:
        print("CE_GA08_PA05_PREFLIGHT=FAIL_CLOSED")
        print("MOTIVO=" + str(exc))
        print("SERVICOS_MODIFICADOS=NAO")
        return 3
    except Exception:
        # Never echo private paths, Docker stderr, labels or environment.
        print("CE_GA08_PA05_PREFLIGHT=FAIL_CLOSED")
        print("MOTIVO=erro_inesperado")
        print("SERVICOS_MODIFICADOS=NAO")
        return 3

    print("=== CE-GA08-PA05 | RECONCILIACAO SOMENTE LEITURA ===")
    print("RUNTIME_COMPOSE=" + str(summary["current_compose_count"]) + "_MATCH")
    print("ROLLBACK_BASE_COMPOSE=" + str(summary["baseline_compose_count"]) + "_IDENTIFICADOS")
    print("GA08_OVERLAYS=" + str(summary["ga08_overlay_count"]) + "_IDENTIFICADOS")
    print("CONTAINERS=" + str(summary["services"]) + "_HEALTHY")
    print("FONTES_LOCALIZADAS=14")
    print("GA08_CANDIDATOS_SHA256=3_MATCH")
    if args.check_compose:
        print("COMPOSE11_SINTAXE_SEM_INTERPOLACAO=PASS")
        print("COMPOSE14_SINTAXE_SEM_INTERPOLACAO=PASS")
        print("CONFIG_EFETIVA_INTERPOLADA=NAO_COMPROVADA")
    print("CE_GA08_PA05_PREFLIGHT=PASS_METADATA_E_FONTES")
    print("ROLLBACK_FUNCIONAL=NAO_ENSAIADO")
    print("DRIVER_DE_MUTACAO=NAO_HABILITADO")
    print("SERVICOS_MODIFICADOS=NAO")
    print("=== FIM ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
