#!/usr/bin/env python3
"""GA08/PA05 v2 recovery CONTRACT: private-manifest check and offline simulation.

No Docker CLI, no host writes and NO executable rollback. Even --execute is
always rejected. This module specifies the safe 14-active -> 11-PA05 baseline
contract and validates private evidence before a future, separately reviewed
driver may be designed. It never displays private values or digests.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import socket
import stat
import sys
from pathlib import Path
from typing import Any


PROJECT = "conectaeduca-dmz"
BASE = (
    "compose.yml", "compose.database.yml", "compose.app-secrets.yml",
    "compose.waf.yml", "compose.waf-tls.yml", "compose.waf-policy.yml",
    "compose.host.yml", "compose.vm.yml", "compose.database-tls.yml",
    "compose.audit-persistent.yml", "compose.pa05-10328ab6.yml",
)
GA08 = (
    "compose.ga08-socket.candidate.yml",
    "compose.ga08-dual-socket.candidate.yml",
    "compose.ga08-runtimefix.candidate.yml",
)
ACTIVE = BASE + GA08
IMAGES = {
    "php": "conectaeduca/php-fpm:pa05-10328ab6",
    "nginx": "conectaeduca/nginx:dmz",
    "waf": "conectaeduca/waf:dmz",
}
HEX64 = re.compile(r"[0-9a-f]{64}\Z")
CHANGE_ID = re.compile(r"GA08-[0-9]{8}-[A-Z0-9_-]{3,32}\Z")
PRIVATE_CONTEXT_ID = re.compile(r"GA08-[0-9]{8}-[A-Z0-9_-]{3,32}\Z")
SOURCE_KEYS = tuple(f"{n:02d}" for n in range(1, 15))
SNAPSHOT_ID = re.compile(r"[A-Za-z0-9_.:-]{6,100}\Z")
STEPS = (
    "CHECK_PRECONDITIONS", "VERIFY_SOURCE_AND_CONFIG_DIGESTS",
    "VERIFY_PINNED_PA05_IMAGES", "ACQUIRE_PROJECT_LOCK",
    "RESTORE_PHP_WITH_11_FILES", "WAIT_PHP_HEALTH",
    "RESTORE_NGINX_WITH_11_FILES", "WAIT_NGINX_HEALTH",
    "RESTORE_WAF_WITH_11_FILES", "WAIT_WAF_HEALTH",
    "VERIFY_HTTPS_CRS_PHP_SQL_ISOLATION", "RECORD_OPERATOR_RESULT",
)


class ContractError(Exception):
    pass


def require(ok: bool, reason: str) -> None:
    if not ok:
        raise ContractError(reason)


def strict_keys(obj: Any, required: set[str], reason: str) -> dict[str, Any]:
    require(isinstance(obj, dict) and set(obj) == required, reason)
    return obj


def validate_manifest(data: Any) -> None:
    """Check an *untrusted, private* v2 manifest without reading runtime data.

    A syntactically valid manifest never implies approval for execution.
    """
    obj = strict_keys(data, {
        "format", "change_id", "host", "project", "restore_target",
        "private_context_id", "compose", "source_sha256", "config_sha256",
        "images", "snapshot", "verification", "approval", "state",
    }, "manifesto_campos_invalidos")
    require(obj["format"] == 2 and obj["project"] == PROJECT and
            obj["host"] in ("ep125-pucpr", "ep125-pucpr-br") and
            obj["restore_target"] == "PA05_BASE_11" and
            obj["state"] == "CANDIDATE_ONLY", "manifesto_identidade_invalida")
    require(isinstance(obj["change_id"], str) and
            CHANGE_ID.fullmatch(obj["change_id"]), "change_id_invalido")
    require(isinstance(obj["private_context_id"], str) and
            PRIVATE_CONTEXT_ID.fullmatch(obj["private_context_id"]),
            "contexto_privado_id_invalido")
    compose = strict_keys(obj["compose"], {"baseline11", "active14"},
                          "compose_modelo_invalido")
    require(type(compose["baseline11"]) is list and
            tuple(compose["baseline11"]) == BASE and
            type(compose["active14"]) is list and
            tuple(compose["active14"]) == ACTIVE,
            "compose_modelo_divergente")
    sources = strict_keys(obj["source_sha256"], set(SOURCE_KEYS),
                          "hash_fontes_campos_invalidos")
    require(all(isinstance(v, str) and HEX64.fullmatch(v)
                for v in sources.values()), "hash_fontes_invalidos")
    configs = strict_keys(obj["config_sha256"], {"baseline11", "active14"},
                          "hash_config_campos_invalidos")
    require(all(isinstance(v, str) and HEX64.fullmatch(v)
                for v in configs.values()), "hash_config_invalidos")
    images = strict_keys(obj["images"], set(IMAGES), "imagens_campos_invalidos")
    for service, expected in IMAGES.items():
        image = strict_keys(images[service], {"reference", "image_id"},
                            "imagem_campos_invalidos")
        require(image["reference"] == expected and
                isinstance(image["image_id"], str) and
                image["image_id"].startswith("sha256:") and
                HEX64.fullmatch(image["image_id"][7:]),
                "imagem_id_ou_referencia_divergente")
    snapshot = strict_keys(obj["snapshot"], {
        "reference", "coverage_attested", "restoration_confirmed"
    }, "snapshot_campos_invalidos")
    require(isinstance(snapshot["reference"], str) and
            SNAPSHOT_ID.fullmatch(snapshot["reference"]),
            "snapshot_referencia_invalida")
    require(type(snapshot["coverage_attested"]) is bool and
            type(snapshot["restoration_confirmed"]) is bool,
            "snapshot_estado_invalido")
    verified = strict_keys(obj["verification"], {
        "source_custody_verified", "interpolation_11_14_passed",
        "hash_runtime_14_passed", "offline_failure_suite_passed",
        "controlled_restore_rehearsed", "functional_e2e_passed",
    }, "validacao_campos_invalidos")
    require(all(type(value) is bool for value in verified.values()),
            "validacao_estado_invalido")
    approval = strict_keys(obj["approval"], {
        "operator_window_approved", "secrets_recoverable",
        "cross_vm_dependencies_checked",
    }, "aprovacao_campos_invalidos")
    require(all(type(value) is bool for value in approval.values()),
            "aprovacao_estado_invalido")


def readiness_reasons(obj: dict[str, Any]) -> tuple[str, ...]:
    """Return only public gate names. Never return the private values."""
    validate_manifest(obj)
    required = {
        "snapshot_cobertura": obj["snapshot"]["coverage_attested"],
        "snapshot_restauracao": obj["snapshot"]["restoration_confirmed"],
        "custodia_fontes": obj["verification"]["source_custody_verified"],
        "interpolacao": obj["verification"]["interpolation_11_14_passed"],
        "hash_runtime": obj["verification"]["hash_runtime_14_passed"],
        "falhas_offline": obj["verification"]["offline_failure_suite_passed"],
        "ensaio_recuperacao": obj["verification"]["controlled_restore_rehearsed"],
        "e2e_funcional": obj["verification"]["functional_e2e_passed"],
        "janela_aprovada": obj["approval"]["operator_window_approved"],
        "segredos_recuperaveis": obj["approval"]["secrets_recoverable"],
        "dependencias_ep126": obj["approval"]["cross_vm_dependencies_checked"],
    }
    return tuple(name for name, passed in required.items() if not passed)


def simulate(*, fail_at: str | None = None) -> tuple[str, tuple[str, ...]]:
    """Pure sequence model; cannot invoke a container operation."""
    require(fail_at is None or fail_at in STEPS, "falha_simulada_invalida")
    completed = []
    for step in STEPS:
        if step == fail_at:
            return "ABORTED_FAIL_CLOSED", tuple(completed)
        completed.append(step)
    return "E2E_REQUIRES_REAL_EVIDENCE", tuple(completed)


def read_protected_manifest(path: Path) -> dict[str, Any]:
    fd = -1
    try:
        require(path.is_absolute() and path.resolve(strict=True) == path,
                "manifesto_caminho_inseguro")
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        meta = os.fstat(fd)
        require(stat.S_ISREG(meta.st_mode) and meta.st_nlink == 1 and
                meta.st_uid == os.getuid() and
                stat.S_IMODE(meta.st_mode) == 0o600 and
                0 < meta.st_size <= 65_536, "manifesto_permissoes_invalidas")
        with os.fdopen(fd, "rb") as handle:
            fd = -1
            content = handle.read(65_537)
        require(len(content) <= 65_536, "manifesto_tamanho_invalido")
        obj = json.loads(content)
        validate_manifest(obj)
        return obj
    except (OSError, ValueError, UnicodeError, RuntimeError):
        raise ContractError("manifesto_privado_indisponivel") from None
    finally:
        if fd >= 0:
            os.close(fd)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-manifest", type=Path,
                        help="validar manifesto v2 preexistente privado 0600")
    parser.add_argument("--simulate-failure", choices=STEPS)
    parser.add_argument("--execute", action="store_true",
                        help="sempre recusado: nao existe driver de mutacao v2")
    args = parser.parse_args(argv)
    print("=== CE-GA08 | CONTRATO RECUPERACAO V2 PA05 ===")
    try:
        require(not args.execute, "mutacao_v2_nao_implementada")
        require(os.geteuid() != 0, "nao_executar_root")
        if args.check_manifest is not None:
            require(socket.gethostname().split(".")[0] in
                    ("ep125-pucpr", "ep125-pucpr-br"), "host_incorreto")
            obj = read_protected_manifest(args.check_manifest)
            pending = readiness_reasons(obj)
            print("MANIFESTO_V2=ESTRUTURA_VALIDA")
            print("GATES_PENDENTES=" + str(len(pending)))
            print("APROVACAO_OPERACIONAL=NAO_ATTESTADA_PELO_SCRIPT")
        state, completed = simulate(fail_at=args.simulate_failure)
        print("BASELINE_PA05=11_ARQUIVOS")
        print("RUNTIME_GA08=14_ARQUIVOS")
        print("SEQUENCIA_OFFLINE=" + state)
        print("PASSOS_SIMULADOS=" + str(len(completed)))
        print("CONTRATO_V2=PASS_SOMENTE_LEITURA")
        return 0
    except ContractError as error:
        print("CONTRATO_V2=FAIL_CLOSED")
        print("MOTIVO=" + str(error))
        return 3
    except Exception:
        print("CONTRATO_V2=FAIL_CLOSED")
        print("MOTIVO=erro_inesperado")
        return 3
    finally:
        print("MANIFESTOS_MODIFICADOS=NAO")
        print("SERVICOS_MODIFICADOS=NAO")
        print("ROLLBACK_EXECUTAVEL=NAO")
        print("=== FIM ===")


if __name__ == "__main__":
    sys.exit(main())
