#!/usr/bin/env python3
"""GA-08 / PA-02: change control and restore plan for EP125.

Default is preflight only. Live operations require a private signed-off
attestation, an exact acknowledgment and a second environment interlock.
Never invoked by GitHub Actions. Never outputs Docker config or secrets.
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
import socket
import stat
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DMZ = ROOT / "deploy/dmz"
PROJECT = "conectaeduca-dmz"
BASE_FILES = (
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
CANDIDATE_FILES = (
    "compose.ga08-socket.candidate.yml",
    "compose.ga08-dual-socket.candidate.yml",
)
TARGETS = {
    "waf": "conectaeduca-dmz-waf-1",
    "nginx": "conectaeduca-dmz-nginx-1",
    "php": "conectaeduca-dmz-php-1",
}
BASE_COUNTS = {"waf": 9, "nginx": 9, "php": 10}
BIND_COUNTS = {"waf": 3, "nginx": 0, "php": 5}
CONFIG_SOURCES = {
    "/etc/nginx/conf.d/default.conf": (
        "nginx", "ga08/app-http.dual-socket.candidate.conf"
    ),
    "/usr/local/etc/php-fpm.d/zz-conectaeduca.conf": (
        "php", "ga08/zz-conectaeduca.socket.candidate.conf"
    ),
}
SOCKET_BIND = {
    "/run/conectaeduca-fpm": ("nginx", "php", 82, 82, 0o770),
    "/run/conectaeduca-http": ("waf", "nginx", 101, 101, 0o700),
}
TIMEOUT = 25


class GateError(Exception):
    pass


def require(ok: bool, reason: str) -> None:
    if not ok:
        raise GateError(reason)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(65536), b""):
            digest.update(block)
    return digest.hexdigest()


def run(args: list[str], reason: str, timeout: int = TIMEOUT) -> str:
    # Docker inspect/config may contain secrets; never include stderr/stdout
    # in a raised exception or public log.
    try:
        proc = subprocess.run(
            args, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            check=False, timeout=timeout, env=os.environ.copy(),
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise GateError(reason + "_indisponivel") from None
    require(proc.returncode == 0, reason + "_exit_" + str(proc.returncode))
    return proc.stdout


def files(count: int) -> list[Path]:
    return [DMZ / name for name in BASE_FILES[:count]]


def compose_args(sequence: list[Path]) -> list[str]:
    argv = [
        "docker", "compose",
        "--project-directory", str(DMZ),
        "-p", PROJECT,
    ]
    for file in sequence:
        require(file.is_file() and not file.is_symlink(),
                "compose_ausente_ou_symlink")
        argv.extend(["-f", str(file)])
    return argv


def get_config(sequence: list[Path]) -> dict[str, Any]:
    output = run(
        compose_args(sequence) + ["config", "--format", "json"],
        "compose_config",
    )
    try:
        obj = json.loads(output)
    except json.JSONDecodeError:
        raise GateError("compose_config_json_invalido") from None
    require(isinstance(obj, dict) and obj.get("name") == PROJECT,
            "compose_projeto_inesperado")
    return obj


def inspect_container(name: str) -> dict[str, Any]:
    raw = run(["docker", "inspect", name], "docker_inspect")
    try:
        items = json.loads(raw)
        require(isinstance(items, list) and len(items) == 1,
                "docker_inspect_formato")
        return items[0]
    except (ValueError, IndexError, TypeError):
        raise GateError("docker_inspect_json") from None


def image_id(reference: str) -> str:
    raw = run(
        ["docker", "image", "inspect", reference, "--format", "{{.Id}}"],
        "imagem_original_indisponivel",
    )
    img = raw.strip()
    require(bool(re.fullmatch(r"sha256:[0-9a-f]{64}", img)),
            "image_id_invalido")
    return img


def verify_images(entries: dict[str, Any], current: bool) -> None:
    for service, entry in entries.items():
        ref = entry.get("reference")
        pinned = entry.get("image_id")
        require(isinstance(ref, str) and ref and
                isinstance(pinned, str) and
                bool(re.fullmatch(r"sha256:[0-9a-f]{64}", pinned)),
                "manifesto_imagem_invalido")
        require(image_id(ref) == pinned, "imagem_tag_drift_" + service)
        require(image_id(pinned) == pinned, "imagem_id_ausente_" + service)
        if current:
            data = inspect_container(TARGETS[service])
            require(data.get("Image") == pinned, "imagem_runtime_drift_" + service)


def current_baseline() -> dict[str, Any]:
    result: dict[str, Any] = {}
    for service, name in TARGETS.items():
        data = inspect_container(name)
        state = data.get("State") or {}
        labels = (data.get("Config") or {}).get("Labels") or {}
        require(labels.get("com.docker.compose.project") == PROJECT,
                "projeto_runtime_divergente_" + service)
        require(labels.get("com.docker.compose.service") == service,
                "servico_runtime_divergente_" + service)
        sequence = labels.get("com.docker.compose.project.config_files", "")
        actual = [Path(x).name for x in sequence.split(",") if x]
        require(actual == list(BASE_FILES[:BASE_COUNTS[service]]),
                "ordem_compose_runtime_divergente_" + service)
        require(
            state.get("Running") is True and
            (state.get("Health") or {}).get("Status") == "healthy" and
            data.get("RestartCount") == 0,
            "baseline_nao_saudavel_" + service,
        )
        binds = sum(
            1 for mount in data.get("Mounts", [])
            if mount.get("Type") == "bind"
        )
        require(binds == BIND_COUNTS[service],
                "mount_count_drift_" + service)
        conf = data.get("Config") or {}
        img_ref = conf.get("Image")
        img_id = data.get("Image")
        result[service] = {"reference": img_ref, "image_id": img_id}
    verify_images(result, current=True)
    return result


def networks(service: dict[str, Any]) -> set[str]:
    value = service.get("networks", {})
    if isinstance(value, dict):
        return set(value)
    if isinstance(value, list):
        return set(value)
    raise GateError("redes_formato_invalido")


def bind(service: dict[str, Any], destination: str) -> dict[str, Any]:
    matches = [
        mount for mount in service.get("volumes", [])
        if isinstance(mount, dict) and mount.get("target") == destination
    ]
    require(len(matches) == 1, "bind_ausente_ou_duplicado")
    item = matches[0]
    require(item.get("type") == "bind", "mount_nao_bind")
    require(isinstance(item.get("source"), str), "bind_origem_invalida")
    return item


def approved_file(source: str, expected: Path) -> None:
    path = Path(source)
    require(path.is_absolute() and path.is_file() and not path.is_symlink(),
            "conf_candidata_nao_persistente")
    require(not any(str(path).startswith(prefix) for prefix in
                    ("/tmp/", "/var/tmp/", "/dev/shm/", "/run/")),
            "conf_candidata_temporaria")
    require(sha256(path) == sha256(expected), "conf_candidata_drift")


def check_socket_directory(path_str: str, uid: int, gid: int, mode: int) -> None:
    source = Path(path_str)
    require(source.is_absolute() and not source.is_symlink(),
            "socket_path_nao_confiavel")
    require(not any(str(source).startswith(prefix) for prefix in
                    ("/tmp/", "/var/tmp/", "/dev/shm/", "/run/")),
            "socket_path_temporario")
    try:
        meta = source.stat()
    except OSError:
        raise GateError("socket_diretorio_sem_acesso") from None
    require(stat.S_ISDIR(meta.st_mode), "socket_nao_diretorio")
    require((meta.st_uid, meta.st_gid, stat.S_IMODE(meta.st_mode)) ==
            (uid, gid, mode), "socket_owner_modo_divergente")


def check_candidate(baseline: dict[str, Any],
                    candidate: dict[str, Any]) -> None:
    base_services = baseline.get("services") or {}
    services = candidate.get("services") or {}
    require(all(x in services for x in TARGETS),
            "servico_candidato_ausente")
    waf, nginx, php = (services[x] for x in ("waf", "nginx", "php"))
    require(networks(waf) == {"waf_backend"}, "rede_waf_divergente")
    require(networks(nginx) == {"waf_backend"}, "rede_nginx_divergente")
    require(networks(php) == {"php_egress"}, "rede_php_divergente")
    require(not nginx.get("ports") and not nginx.get("expose"),
            "nginx_tcp_publicado")
    require(not php.get("ports") and not php.get("expose"),
            "php_tcp_publicado")
    require(waf.get("ports") == base_services["waf"].get("ports"),
            "waf_portas_alteradas")
    require(
        (waf.get("environment") or {}).get("BACKEND") ==
        "http://unix:/run/conectaeduca-http/nginx.sock:",
        "waf_backend_divergente",
    )
    require(
        (waf.get("environment") or {}).get("MODSEC_RULE_ENGINE") == "On",
        "modsecurity_desativado",
    )
    require(
        (waf.get("environment") or {}).get("MODSEC_AUDIT_LOG_PARTS") == "AFHZ",
        "audit_privacidade_divergente",
    )
    for name, service in services.items():
        if name not in TARGETS:
            require(service == base_services.get(name),
                    "servico_nao_relacionado_alterado")
    for name in TARGETS:
        require(services[name].get("image") == base_services[name].get("image"),
                "imagem_candidata_divergente")
    require("82" in [str(x) for x in nginx.get("group_add", [])],
            "nginx_grupo_fpm_ausente")
    for destination, (reader, writer, uid, gid, mode) in SOCKET_BIND.items():
        read_mount = bind(services[reader], destination)
        write_mount = bind(services[writer], destination)
        require(read_mount.get("source") == write_mount.get("source"),
                "socket_source_divergente")
        require(bool(read_mount.get("read_only")) and
                not write_mount.get("read_only", False),
                "socket_rw_ro_divergente")
        check_socket_directory(read_mount["source"], uid, gid, mode)
    for destination, (service, file) in CONFIG_SOURCES.items():
        source = bind(services[service], destination)
        require(bool(source.get("read_only")), "config_rw_bloqueada")
        approved_file(source["source"], DMZ / file)
    # Replaced config target must be the final dual-UNIX-listener version.
    fpm_cfg = bind(php, "/usr/local/etc/php-fpm.d/zz-conectaeduca.conf")
    require(bool(fpm_cfg.get("read_only")), "fpm_conf_rw")
    require("!override" not in json.dumps(candidate), "config_nao_resolvida")


def all_sources() -> list[Path]:
    return files(10) + [DMZ / f for f in CANDIDATE_FILES] + [
        DMZ / x for x in (
            "ga08/app-http.dual-socket.candidate.conf",
            "ga08/app-http.socket.candidate.conf",
            "ga08/zz-conectaeduca.socket.candidate.conf",
        )
    ]


def config_digest(config: dict[str, Any]) -> str:
    """Store only a digest; resolved Compose may contain sensitive values."""
    return hashlib.sha256(
        json.dumps(config, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


def source_hashes() -> dict[str, str]:
    obj: dict[str, str] = {}
    for file in all_sources():
        require(file.is_file() and not file.is_symlink(),
                "fonte_ausente_ou_symlink")
        obj[str(file.relative_to(ROOT))] = sha256(file)
    return obj


def verify_hashes(record: dict[str, str]) -> None:
    require(record == source_hashes(), "hash_arquivos_compose_drift")


def verify_approvals(path_value: str, change_id: str,
                     action: str) -> dict[str, Any]:
    require(bool(path_value), "autorizacao_nao_informada")
    approval = Path(path_value)
    require(approval.is_absolute() and approval.is_file() and
            not approval.is_symlink(), "autorizacao_arquivo_invalido")
    meta = approval.stat()
    require(meta.st_uid == os.getuid() and
            stat.S_IMODE(meta.st_mode) == 0o600,
            "autorizacao_permissoes_inseguras")
    try:
        info = json.loads(approval.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError):
        raise GateError("autorizacao_json_invalido") from None
    require(isinstance(info, dict) and info.get("change_id") == change_id,
            "autorizacao_change_id_divergente")
    required = (
        "snapshot_covers_all_ep125_disks",
        "snapshot_restore_confirmed_by_operator",
        "bind_mounts_verified_by_operator",
        "secrets_and_tls_recoverable",
        "operator_and_window_approved",
        "cross_vm_dependencies_checked",
        "socket_directories_clean",
    )
    for key in required:
        require(info.get(key) is True, "autorizacao_gate_" + key)
    require(isinstance(info.get("snapshot_id"), str) and
            len(info["snapshot_id"].strip()) >= 6,
            "snapshot_id_nao_comprovado")
    require(isinstance(info.get("approver"), str) and
            len(info["approver"].strip()) >= 3, "aprovador_ausente")
    require(info.get(action + "_approved") is True,
            "autorizacao_especifica_" + action)
    return info


def evidence_directory(change_id: str) -> Path:
    require(bool(re.fullmatch(r"GA08-[0-9]{8}-[A-Z0-9_-]{3,32}", change_id)),
            "change_id_formato_invalido")
    directory = (
        Path.home() / "ConectaEduca_Fase2_Evidencias" /
        "EP125" / "GA08" / change_id
    )
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    require(directory.is_dir() and not directory.is_symlink(),
            "evidencia_diretorio_inseguro")
    require(directory.stat().st_uid == os.getuid() and
            stat.S_IMODE(directory.stat().st_mode) == 0o700,
            "evidencia_permissoes_inseguras")
    return directory


def acquire_lock(directory: Path) -> int:
    lock_path = directory / "change.lock"
    require(not lock_path.is_symlink(), "lock_path_symlink")
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        require(os.fstat(fd).st_uid == os.getuid() and
                stat.S_IMODE(os.fstat(fd).st_mode) == 0o600,
                "lock_acl_insegura")
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise GateError("outra_operacao_ga08_em_andamento") from None
        return fd
    except BaseException:
        os.close(fd)
        raise


def write_manifest(path: Path, obj: dict[str, Any]) -> None:
    tmp = path.with_suffix(".tmp")
    require(not tmp.exists(), "manifesto_temporario_existente")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(obj, f, indent=2, sort_keys=True)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            tmp.unlink()


def read_manifest(path: Path, change_id: str) -> dict[str, Any]:
    require(path.is_file() and not path.is_symlink(),
            "manifesto_nao_encontrado")
    meta = path.stat()
    require(meta.st_uid == os.getuid() and
            stat.S_IMODE(meta.st_mode) == 0o600, "manifesto_acl_insegura")
    try:
        obj = json.loads(path.read_text())
    except (OSError, ValueError, UnicodeError):
        raise GateError("manifesto_invalido") from None
    require(isinstance(obj, dict) and
            obj.get("change_id") == change_id and
            obj.get("project") == PROJECT and
            obj.get("host") in ("ep125-pucpr", "ep125-pucpr-br"),
            "manifesto_identidade_divergente")
    return obj


def require_runtime_host() -> str:
    host = socket.gethostname().split(".")[0]
    require(host in ("ep125-pucpr", "ep125-pucpr-br"),
            "execucao_fora_da_EP125")
    require(os.geteuid() != 0, "nao_executar_shell_root")
    require(ROOT == Path("/opt/conectaeduca"),
            "checkout_institucional_incorreto")
    return host


def wait_health(service: str) -> None:
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        data = inspect_container(TARGETS[service])
        state = data.get("State") or {}
        if state.get("Running") and (state.get("Health") or {}).get("Status") == "healthy":
            return
        time.sleep(3)
    raise GateError("servico_nao_healthy_" + service)


def require_cli_interlock(args: argparse.Namespace, action: str) -> None:
    require(args.execute, "execucao_nao_solicitada")
    require(
        os.environ.get("GA08_ENABLE_LIVE_CHANGE") == "YES",
        "interlock_ambiente_fechado",
    )
    expected = ("APLICAR_GA08_NA_EP125" if action == "cutover"
                else "RESTAURAR_BASELINE_EP125")
    require(args.ack == expected, "confirmacao_interativa_ausente")


def execute_cutover(args: argparse.Namespace, host: str) -> None:
    require_cli_interlock(args, "cutover")
    approvals = verify_approvals(args.approval_file, args.change_id, "cutover")
    out_dir = evidence_directory(args.change_id)
    manifest = out_dir / "manifest.json"
    require(not manifest.exists(), "mudanca_ja_preparada_nao_repetir")
    images = current_baseline()
    baseline = get_config(files(10))
    candidate_paths = files(10) + [DMZ / p for p in CANDIDATE_FILES]
    candidate = get_config(candidate_paths)
    check_candidate(baseline, candidate)
    checksums = source_hashes()
    candidate_digest = config_digest(candidate)
    rollback_digests = {
        str(n): config_digest(get_config(files(n))) for n in (9, 10)
    }
    # Fail before mutation if any original image/tag has drifted.
    for service, cfg in baseline["services"].items():
        if service in images:
            require(cfg.get("image") == images[service]["reference"],
                    "baseline_ref_divergente_" + service)
    for service, cfg in candidate["services"].items():
        if service in images:
            require(cfg.get("image") == images[service]["reference"],
                    "candidato_ref_divergente_" + service)
    obj = {
        "change_id": args.change_id, "host": host, "project": PROJECT,
        "snapshot_id": approvals["snapshot_id"],
        "image_baseline": images,
        "source_hashes": checksums,
        "candidate_config_sha256": candidate_digest,
        "rollback_config_sha256": rollback_digests,
        "phase": "PREPARED_NO_SERVICES_CHANGED",
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    write_manifest(manifest, obj)
    print("GA08_MANIFESTO_PROTEGIDO=SIM")
    print("GA08_CUTOVER=AUTORIZADO_POR_ATESTACAO_LOCAL")
    # Sequential: each service is explicitly selected. Never compose down.
    for service in ("php", "nginx", "waf"):
        verify_hashes(checksums)
        verify_images(images, current=False)
        effective = get_config(candidate_paths)
        require(config_digest(effective) == candidate_digest,
                "config_candidata_mudou_antes_de_" + service)
        check_candidate(baseline, effective)
        obj["phase"] = "CUTOVER_STARTED_" + service
        write_manifest(manifest, obj)
        run(
            compose_args(candidate_paths) +
            ["up", "-d", "--no-deps", "--no-build", "--pull", "never",
             "--force-recreate", service],
            "cutover_up_" + service, timeout=180,
        )
        obj["phase"] = "RECREATED_" + service
        write_manifest(manifest, obj)
        wait_health(service)
        print("GA08_SERVICE_" + service.upper() + "=HEALTHY")
    obj["phase"] = "SERVICES_HEALTHY_E2E_PENDENTE"
    write_manifest(manifest, obj)
    print("GA08_CUTOVER=SERVICOS_HEALTHY")
    print("GA08_E2E_WAF_CRS_TLS_SQL_RBAC=NAO_TESTADO_POR_ESTE_SCRIPT")
    print("GA08_PA02=ABERTO_ATE_RETESTE")
    print("GA08_ROLLBACK_MANIFESTO_GUARDADO=SIM")


def execute_rollback(args: argparse.Namespace, host: str) -> None:
    require_cli_interlock(args, "rollback")
    approvals = verify_approvals(args.approval_file, args.change_id, "rollback")
    out_dir = evidence_directory(args.change_id)
    manifest = out_dir / "manifest.json"
    obj = read_manifest(manifest, args.change_id)
    require(obj.get("snapshot_id") == approvals["snapshot_id"],
            "snapshot_manifesto_divergente")
    require(obj.get("phase") != "PREPARED_NO_SERVICES_CHANGED",
            "sem_corte_nao_ha_rollback")
    verify_hashes(obj["source_hashes"])
    images = obj["image_baseline"]
    verify_images(images, current=False)
    for count in (9, 10):
        cfg = get_config(files(count))
        require(config_digest(cfg) ==
                obj["rollback_config_sha256"][str(count)],
                "config_rollback_drift_" + str(count))
        for service, entry in images.items():
            require(cfg["services"][service].get("image") == entry["reference"],
                    "rollback_imagem_compose_drift_" + service)
    # No need for the candidate's .env vars to roll back to the baseline.
    # Checked: PHP 10 (audit overlay), then Nginx and WAF 9 (runtime labels).
    for service in ("php", "nginx", "waf"):
        count = BASE_COUNTS[service]
        verify_images(images, current=False)
        require(
            config_digest(get_config(files(count))) ==
            obj["rollback_config_sha256"][str(count)],
            "config_rollback_mudou_antes_de_" + service,
        )
        obj["phase"] = "ROLLBACK_STARTED_" + service
        write_manifest(manifest, obj)
        run(
            compose_args(files(count)) +
            ["up", "-d", "--no-deps", "--no-build", "--pull", "never",
             "--force-recreate", service],
            "rollback_up_" + service, timeout=180,
        )
        obj["phase"] = "ROLLBACK_RECREATED_" + service
        write_manifest(manifest, obj)
        wait_health(service)
        print("GA08_ROLLBACK_" + service.upper() + "=HEALTHY")
    obj["phase"] = "ROLLBACK_SERVICES_HEALTHY_E2E_PENDENTE"
    write_manifest(manifest, obj)
    print("GA08_ROLLBACK=Docker_3_SERVICOS_HEALTHY")
    print("GA08_RECUPERACAO_FUNCIONAL_E2E=NAO_COMPROVADA")
    print("GA08_PA02=ABERTO")


def preflight() -> None:
    images = current_baseline()
    original = get_config(files(10))
    candidate = get_config(files(10) + [DMZ / p for p in CANDIDATE_FILES])
    check_candidate(original, candidate)
    source_hashes()
    verify_images(images, current=True)
    print("GA08_PREFLIGHT=PASS_CONFIGURACAO_E_IMAGENS")
    print("GA08_APLICACAO=NAO_EXECUTADA")
    print("GA08_ROLLBACK=NAO_EXECUTADO")
    print("GA08_G0_SNAPSHOT_AUTORIZACAO=NAO_VERIFICADOS_POR_PREFLIGHT")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--action", choices=("cutover", "rollback"), required=True)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--change-id", default="")
    parser.add_argument("--approval-file", default="")
    parser.add_argument("--ack", default="")
    args = parser.parse_args()
    try:
        host = require_runtime_host()
        if not args.execute:
            if args.action == "cutover":
                preflight()
            else:
                require(bool(args.change_id), "change_id_obrigatorio")
                obj = read_manifest(
                    evidence_directory(args.change_id) / "manifest.json",
                    args.change_id,
                )
                verify_hashes(obj["source_hashes"])
                verify_images(obj["image_baseline"], current=False)
                for n in (9, 10):
                    get_config(files(n))
                print("GA08_ROLLBACK_PREFLIGHT=PASS_SEM_MODIFICAR_SERVICOS")
            return 0
        # One operator at a time per change ID; lock held through mutation.
        directory = evidence_directory(args.change_id)
        lock_fd = acquire_lock(directory)
        try:
            if args.action == "cutover":
                execute_cutover(args, host)
            else:
                execute_rollback(args, host)
        finally:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
            os.close(lock_fd)
        return 0
    except GateError as exc:
        print("GA08_GATE=FAIL_CLOSED", file=sys.stderr)
        print("GA08_MOTIVO=" + str(exc), file=sys.stderr)
        print("GA08_ROLLBACK_AUTOMATICO=NAO", file=sys.stderr)
        return 3
    except Exception as exc:
        # Do not leak arbitrary Docker stderr, secrets or object dumps.
        print("GA08_GATE=FAIL_CLOSED", file=sys.stderr)
        print("GA08_MOTIVO=erro_inesperado_" + type(exc).__name__, file=sys.stderr)
        print("GA08_ROLLBACK_AUTOMATICO=NAO", file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
