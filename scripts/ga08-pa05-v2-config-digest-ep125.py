#!/usr/bin/env python3
"""EP125: compare full, privately interpolated Compose 11/14 digests in memory.

Requires a SHA-256 vetted copy of the earlier read-only custody inventory.
The collector verifies runtime, 14 source files and three image IDs before
this script computes canonical model SHA-256 for both protected contexts.

Resolved Compose JSON may contain sensitive environment *references* and
values; it is never printed, persisted, or returned to the caller.
No secret file contents, Docker Compose up/down, or rollback operations.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import runpy
import socket
import stat
import subprocess
from pathlib import Path
from typing import Any

PEER = "ga08-pa05-v2-custody-inventory-ep125.py"
PEER_SHA256 = "cad5a6ad8b378fcfa69f9da25f3f1592f6dc918f392dea02f726a624e6a98409"
DMZ = Path("/opt/conectaeduca/deploy/dmz")
PROJECT = "conectaeduca-dmz"
PHP_PA05 = "conectaeduca/php-fpm:pa05-10328ab6"
MAX_CONFIG_BYTES = 2_000_000
HEX64 = re.compile(r"[0-9a-f]{64}\Z")


class DigestError(Exception):
    pass


def require(ok: bool, reason: str) -> None:
    if not ok:
        raise DigestError(reason)


def trusted_peer(home: Path) -> dict[str, Any]:
    """Reject a changed library before runpy can execute its contents."""
    path = home / "Downloads" / PEER
    fd = -1
    try:
        require(path.is_absolute() and path.resolve(strict=True) == path,
                "biblioteca_caminho_inseguro")
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        meta = os.fstat(fd)
        require(stat.S_ISREG(meta.st_mode) and meta.st_nlink == 1 and
                meta.st_uid in (0, os.getuid()) and
                not (stat.S_IMODE(meta.st_mode) & 0o022) and
                0 < meta.st_size <= 100_000, "biblioteca_permissoes_invalidas")
        with os.fdopen(fd, "rb") as handle:
            fd = -1
            data = handle.read(100_001)
        require(len(data) <= 100_000 and
                hashlib.sha256(data).hexdigest() == PEER_SHA256,
                "biblioteca_hash_divergente")
    except (OSError, ValueError, RuntimeError):
        raise DigestError("biblioteca_indisponivel") from None
    finally:
        if fd >= 0:
            os.close(fd)
    try:
        return runpy.run_path(str(path), run_name="ce_v2_custody_library")
    except Exception:
        raise DigestError("biblioteca_indisponivel") from None


def canonical_digest(obj: dict[str, Any]) -> str:
    """Match v1 canonical JSON digest semantics, without rendering to logs."""
    return hashlib.sha256(json.dumps(obj, sort_keys=True,
        separators=(",", ":"), ensure_ascii=True).encode("utf-8")).hexdigest()


def resolved_digest(sources: tuple[Path, ...], refs: dict[str, str],
                    count: int) -> str:
    require(len(sources) == 14 and count in (11, 14),
            "compose_quantidade_invalida")
    environment = os.environ.copy()
    environment.update(refs)
    environment.pop("COMPOSE_ENV_FILES", None)
    environment["COMPOSE_DISABLE_ENV_FILE"] = "1"
    command = ["docker", "compose", "--project-directory", str(DMZ),
               "-p", PROJECT]
    for source in sources[:count]:
        command.extend(["-f", str(source)])
    command.extend(["config", "--format", "json"])
    try:
        proc = subprocess.run(command, cwd=DMZ, env=environment,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              timeout=50, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise DigestError("compose_config_indisponivel") from None
    require(proc.returncode == 0 and
            0 < len(proc.stdout) <= MAX_CONFIG_BYTES,
            "compose_config_falhou")
    try:
        data = json.loads(proc.stdout)
    except (ValueError, UnicodeError, TypeError):
        raise DigestError("compose_json_invalido") from None
    require(isinstance(data, dict) and data.get("name") == PROJECT and
            isinstance(data.get("services"), dict),
            "compose_modelo_invalido")
    for service in ("php", "nginx", "waf"):
        require(service in data["services"], "compose_servico_ausente")
    require(data["services"]["php"].get("image") == PHP_PA05,
            "php_pa05_nao_preservado")
    return canonical_digest(data)


def record_envs(home: Path, custody: dict[str, Any]
                ) -> tuple[tuple[Path, ...], list[dict[str, str]]]:
    """Reconstruct private refs only from verified, immutable runtime mounts."""
    hash_peer = custody["load_peer"](home)
    interpolation = hash_peer["verified_peer"](home)
    library = interpolation["load_verified_library"](home)
    snapshots = library["inspect_runtime"]()
    sources = interpolation["approved_compose_paths"](
        snapshots, library, home)
    hash_peer["check_no_service_env_files"](sources)
    live = library["runtime_references"](snapshots)
    records = library["records"](library["private_root"](home))
    require(len(records) == 2 and
            {entry.name[5:13] for entry in records} == {"20261103", "20261104"},
            "contextos_inesperados")
    refs_list: list[dict[str, str]] = []
    for entry in records:
        context = library["read_private_json"](entry / "runtime-refs.json")
        refs = library["context_references"](context, entry.name)
        manifest = library["read_private_json"](entry / "manifest.json")
        require(library["manifest_class"](manifest, entry.name) == "LEGADO_9_10",
                "manifesto_inesperado")
        require(library["compare_references"](refs, live) == (15, 2, 0),
                "referencias_runtime_divergentes")
        effective = dict(refs)
        for key in interpolation["CONFIG_KEYS"]:
            current = live.get(key)
            require(isinstance(current, str) and
                    interpolation["secure_digest"](
                        Path(refs[key]), limit=65_536, suffix=".conf") ==
                    interpolation["secure_digest"](
                        Path(current), limit=65_536, suffix=".conf"),
                    "config_conteudo_divergente")
            effective[key] = current
        refs_list.append(effective)
    return sources, refs_list


def analyze(home: Path, custody: dict[str, Any]) -> dict[str, Any]:
    """Return hashes in memory; public output receives only equal/not equal."""
    # Revalidate SHA-pinned inputs, 6/6 service hashes and 3 local image IDs.
    material = custody["collect"](home, custody["load_peer"](home))
    require(material["context_count"] == 2 and
            material["service_parity_count"] == 6 and
            material["compose_count"] == 14 and
            len(material["source_hashes"]) == 14 and
            len(material["images"]) == 3, "custodia_insuficiente")
    sources, contexts = record_envs(home, custody)
    require(len(contexts) == 2, "contextos_incompletos")
    digest_rows: list[dict[str, str]] = []
    for env in contexts:
        digest_rows.append({
            "baseline11": resolved_digest(sources, env, 11),
            "active14": resolved_digest(sources, env, 14),
        })
    match11 = digest_rows[0]["baseline11"] == digest_rows[1]["baseline11"]
    match14 = digest_rows[0]["active14"] == digest_rows[1]["active14"]
    return {"models": 4, "baseline_identical": match11,
            "active_identical": match14, "php_pa05": True}


def main() -> int:
    print("=== CE-GA08 | DIGEST CONFIGURACAO PRIVADA V2 | EP125 ===")
    try:
        require(socket.gethostname().split(".")[0] in
                ("ep125-pucpr", "ep125-pucpr-br") and os.geteuid() != 0,
                "host_ou_usuario_invalido")
        result = analyze(Path.home(), trusted_peer(Path.home()))
        print("CONFIG_MODELOS_INTERPOLADOS=" + str(result["models"]))
        print("BASELINE11_ENTRE_CONTEXTOS=" + (
            "IGUAL" if result["baseline_identical"] else "DIFERENTE"))
        print("ATIVO14_ENTRE_CONTEXTOS=" + (
            "IGUAL" if result["active_identical"] else "DIFERENTE"))
        print("PHP_PA05_PRESERVADO=" + ("SIM" if result["php_pa05"] else "NAO"))
        ok = result["baseline_identical"] and result["active_identical"]
        print("DIGEST_V2=" + ("PASS_EM_MEMORIA" if ok else
                              "DIVERGENCIA_SEM_MUTACAO"))
        return 0 if ok else 3
    except DigestError as error:
        print("DIGEST_V2=FAIL_CLOSED")
        print("MOTIVO=" + str(error))
        return 3
    except Exception:
        print("DIGEST_V2=FAIL_CLOSED")
        print("MOTIVO=erro_inesperado")
        return 3
    finally:
        print("CONFIG_JSON_E_VALORES_EXIBIDOS=NAO")
        print("DIGESTS_E_CAMINHOS_EXIBIDOS=NAO")
        print("ARQUIVOS_MODIFICADOS=NAO")
        print("SERVICOS_MODIFICADOS=NAO")
        print("MANIFESTO_V2_CRIADO=NAO")
        print("ROLLBACK_HABILITADO=NAO")
        print("=== FIM ===")


if __name__ == "__main__":
    raise SystemExit(main())
