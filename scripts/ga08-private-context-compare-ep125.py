#!/usr/bin/env python3
"""GA08 EP125: compare private context references with current Docker metadata.

Reads two protected JSON files per change ID in memory, without printing
their values. Docker inspect is read-only; its raw output is never displayed.
No Compose config/up/down, no environment exports, no filesystem writes.
This comparison never authorizes use of the legacy 9/10-file rollback driver.
"""

from __future__ import annotations

import json
import os
import re
import socket
import stat
import subprocess
from pathlib import Path
from typing import Any


REPO = Path("/opt/conectaeduca")
ROOT_NAME = "ConectaEduca_Fase2_Evidencias/EP125/GA08"
CHANGE_ID = re.compile(r"GA08-[0-9]{8}-[A-Z0-9_-]{3,32}\Z")
MAX_RECORDS = 100
MAX_FILE_BYTES = 20000
PROJECT = "conectaeduca-dmz"
TARGETS = {
    "php": "conectaeduca-dmz-php-1",
    "nginx": "conectaeduca-dmz-nginx-1",
    "waf": "conectaeduca-dmz-waf-1",
}
IMAGES = {
    "php": "conectaeduca/php-fpm:pa05-10328ab6",
    "nginx": "conectaeduca/nginx:dmz",
    "waf": "conectaeduca/waf:dmz",
}
COMPOSE_ORDER = (
    "compose.yml", "compose.database.yml", "compose.app-secrets.yml",
    "compose.waf.yml", "compose.waf-tls.yml", "compose.waf-policy.yml",
    "compose.host.yml", "compose.vm.yml", "compose.database-tls.yml",
    "compose.audit-persistent.yml", "compose.pa05-10328ab6.yml",
    "compose.ga08-socket.candidate.yml",
    "compose.ga08-dual-socket.candidate.yml",
    "compose.ga08-runtimefix.candidate.yml",
)
GA08_KEYS = {
    "CONECTAEDUCA_GA08_SOCKET_DIR",
    "CONECTAEDUCA_GA08_HTTP_SOCKET_DIR",
    "CONECTAEDUCA_GA08_NGINX_CONF",
    "CONECTAEDUCA_GA08_NGINX_HTTP_UNIX_CONF",
    "CONECTAEDUCA_GA08_FPM_CONF",
}
REFERENCE_KEYS = {
    "CONECTAEDUCA_DB_HOST", "CONECTAEDUCA_DB_PORT",
    "CONECTAEDUCA_APP_URL", "CONECTAEDUCA_DB_PASSWORD_FILE",
    "CONECTAEDUCA_PRIVATE_KEY_FILE", "CONECTAEDUCA_PUBLIC_KEY_FILE",
    "CONECTAEDUCA_DB_TLS_CA_FILE", "CONECTAEDUCA_WAF_TLS_CERT_FILE",
    "CONECTAEDUCA_WAF_TLS_KEY_FILE", "CONECTAEDUCA_STACK_SECRET_GID",
    "CONECTAEDUCA_WAF_BIND_ADDRESS", "CONECTAEDUCA_HTTP_PORT",
    "CONECTAEDUCA_HTTPS_PORT",
} | GA08_KEYS
SECRET_MOUNTS = {
    "CONECTAEDUCA_DB_PASSWORD_FILE": ("php", "conectaeduca_db_password"),
    "CONECTAEDUCA_PRIVATE_KEY_FILE": ("php", "conectaeduca_private_key"),
    "CONECTAEDUCA_PUBLIC_KEY_FILE": ("php", "conectaeduca_public_key"),
    "CONECTAEDUCA_DB_TLS_CA_FILE": ("php", "conectaeduca_db_tls_ca"),
    "CONECTAEDUCA_WAF_TLS_CERT_FILE": ("waf", "waf_tls_cert"),
    "CONECTAEDUCA_WAF_TLS_KEY_FILE": ("waf", "waf_tls_key"),
}


class GateError(Exception):
    pass


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise GateError(reason)


def private_root(home: Path) -> Path:
    return home / ROOT_NAME


def owned_dir(path: Path, *, exact_700: bool) -> None:
    require(not path.is_symlink() and path.is_dir(), "diretorio_indisponivel")
    meta = path.stat()
    mode = stat.S_IMODE(meta.st_mode)
    require(meta.st_uid == os.getuid(), "diretorio_proprietario_divergente")
    require(mode == 0o700 if exact_700 else not (mode & 0o022),
            "diretorio_permissao_insegura")


def records(root: Path) -> list[Path]:
    owned_dir(root, exact_700=False)
    found: list[Path] = []
    for index, item in enumerate(root.iterdir(), start=1):
        require(index <= MAX_RECORDS, "muitos_registros")
        if item.is_symlink() or not CHANGE_ID.fullmatch(item.name):
            continue
        if item.is_dir():
            owned_dir(item, exact_700=True)
            found.append(item)
    require(bool(found), "registro_ausente")
    return sorted(found, key=lambda path: path.name)


def read_private_json(path: Path) -> dict[str, Any]:
    """Open a regular 0600 file with O_NOFOLLOW; never echo its bytes."""
    fd = -1
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        meta = os.fstat(fd)
        require(stat.S_ISREG(meta.st_mode) and meta.st_nlink == 1,
                "arquivo_nao_regular")
        require(meta.st_uid == os.getuid() and
                stat.S_IMODE(meta.st_mode) == 0o600,
                "arquivo_permissao_insegura")
        require(0 < meta.st_size <= MAX_FILE_BYTES, "arquivo_tamanho_invalido")
        with os.fdopen(fd, "rb") as handle:
            fd = -1
            raw = handle.read(MAX_FILE_BYTES + 1)
        require(len(raw) <= MAX_FILE_BYTES, "arquivo_tamanho_invalido")
        parsed = json.loads(raw)
        require(isinstance(parsed, dict), "json_estrutura_invalida")
        return parsed
    except (OSError, ValueError, UnicodeError):
        raise GateError("json_privado_indisponivel") from None
    finally:
        if fd >= 0:
            os.close(fd)


def context_references(obj: dict[str, Any], change_id: str) -> dict[str, str]:
    require(obj.get("format") == 1 and obj.get("change_id") == change_id,
            "contexto_identidade_divergente")
    require(obj.get("host") in ("ep125-pucpr", "ep125-pucpr-br"),
            "contexto_host_divergente")
    refs = obj.get("references")
    require(isinstance(refs, dict) and set(refs) == REFERENCE_KEYS,
            "contexto_chaves_divergentes")
    for key, value in refs.items():
        require(isinstance(value, str) and bool(value) and len(value) <= 4096
                and not any(ch in value for ch in "\n\r\x00"),
                "contexto_valor_formato_invalido")
        if key in GA08_KEYS | set(SECRET_MOUNTS):
            require(Path(value).is_absolute(), "contexto_caminho_relativo")
    return refs


def inspect_runtime() -> dict[str, dict[str, Any]]:
    snapshots: dict[str, dict[str, Any]] = {}
    for service, container in TARGETS.items():
        try:
            proc = subprocess.run(
                ["docker", "inspect", "--type", "container", container],
                capture_output=True, text=True, check=False, timeout=15,
            )
            require(proc.returncode == 0, "docker_inspect_indisponivel")
            body = json.loads(proc.stdout)
        except (OSError, ValueError, TypeError, subprocess.TimeoutExpired):
            raise GateError("docker_inspect_indisponivel") from None
        require(isinstance(body, list) and len(body) == 1 and
                isinstance(body[0], dict), "docker_inspect_invalido")
        item = body[0]
        cfg = item.get("Config") or {}
        labels = cfg.get("Labels") or {}
        state = item.get("State") or {}
        require(labels.get("com.docker.compose.project") == PROJECT and
                labels.get("com.docker.compose.service") == service,
                "runtime_identidade_divergente")
        require(cfg.get("Image") == IMAGES[service],
                "runtime_imagem_divergente")
        require(state.get("Status") == "running" and
                (state.get("Health") or {}).get("Status") == "healthy",
                "runtime_nao_saudavel")
        files = labels.get("com.docker.compose.project.config_files")
        require(isinstance(files, str) and
                tuple(Path(x).name for x in files.split(",")) == COMPOSE_ORDER,
                "runtime_compose_divergente")
        snapshots[service] = item
    return snapshots


def mount_source(container: dict[str, Any], target: str) -> str | None:
    mounts = [mount for mount in (container.get("Mounts") or [])
              if mount.get("Type") == "bind" and mount.get("Destination") == target]
    if len(mounts) != 1:
        return None
    source = mounts[0].get("Source")
    return source if isinstance(source, str) and Path(source).is_absolute() else None


def runtime_references(snapshot: dict[str, dict[str, Any]]) -> dict[str, str | None]:
    php = snapshot["php"]
    waf = snapshot["waf"]
    nginx = snapshot["nginx"]
    raw_env = (php.get("Config") or {}).get("Env") or []
    env = dict(pair.split("=", 1) for pair in raw_env
               if isinstance(pair, str) and "=" in pair)
    refs: dict[str, str | None] = {
        "CONECTAEDUCA_DB_HOST": env.get("DB_HOST"),
        "CONECTAEDUCA_DB_PORT": env.get("DB_PORT"),
        "CONECTAEDUCA_APP_URL": env.get("APP_URL"),
    }
    for key, (service, name) in SECRET_MOUNTS.items():
        refs[key] = mount_source(snapshot[service], "/run/secrets/" + name)

    def groups(obj: dict[str, Any]) -> set[str]:
        raw = (obj.get("HostConfig") or {}).get("GroupAdd") or []
        return {str(v) for v in raw if re.fullmatch(r"[0-9]+", str(v))}

    gids = groups(php) & groups(waf)
    refs["CONECTAEDUCA_STACK_SECRET_GID"] = (
        next(iter(gids)) if len(gids) == 1 else None
    )
    portbinds = (waf.get("HostConfig") or {}).get("PortBindings") or {}

    def port(key: str, expected: str) -> str | None:
        items = [x for x in (portbinds.get(key) or [])
                 if str(x.get("HostPort", "")) == expected]
        if len(items) != 1:
            return None
        return items[0].get("HostIp") or "0.0.0.0"

    http_ip = port("8080/tcp", "80")
    https_ip = port("8443/tcp", "443")
    same_bind = bool(http_ip and https_ip and http_ip == https_ip)
    refs["CONECTAEDUCA_WAF_BIND_ADDRESS"] = http_ip if same_bind else None
    refs["CONECTAEDUCA_HTTP_PORT"] = "80" if same_bind else None
    refs["CONECTAEDUCA_HTTPS_PORT"] = "443" if same_bind else None

    fpm_php = mount_source(php, "/run/conectaeduca-fpm")
    fpm_nginx = mount_source(nginx, "/run/conectaeduca-fpm")
    http_nginx = mount_source(nginx, "/run/conectaeduca-http")
    http_waf = mount_source(waf, "/run/conectaeduca-http")
    refs["CONECTAEDUCA_GA08_SOCKET_DIR"] = (
        fpm_php if fpm_php and fpm_php == fpm_nginx else None
    )
    refs["CONECTAEDUCA_GA08_HTTP_SOCKET_DIR"] = (
        http_nginx if http_nginx and http_nginx == http_waf else None
    )
    refs["CONECTAEDUCA_GA08_NGINX_HTTP_UNIX_CONF"] = mount_source(
        nginx, "/etc/nginx/conf.d/default.conf"
    )
    refs["CONECTAEDUCA_GA08_FPM_CONF"] = mount_source(
        php, "/usr/local/etc/php-fpm.d/zz-conectaeduca.conf"
    )
    # The initial NGINX_CONF is shadowed by the later dual-socket overlay;
    # it cannot be attested from current container mounts.
    return refs


def compare_references(
    recorded: dict[str, str], live: dict[str, str | None]
) -> tuple[int, int, int]:
    match = mismatch = unknown = 0
    for key in sorted(REFERENCE_KEYS - {"CONECTAEDUCA_GA08_NGINX_CONF"}):
        actual = live.get(key)
        if actual is None:
            unknown += 1
        elif recorded[key] == actual:
            match += 1
        else:
            mismatch += 1
    return match, mismatch, unknown


def manifest_class(manifest: dict[str, Any], change_id: str) -> str:
    if manifest.get("change_id") != change_id or manifest.get("project") != PROJECT:
        return "IDENTIDADE_DIVERGENTE"
    digests = manifest.get("rollback_config_sha256")
    if not isinstance(digests, dict):
        return "SEM_DIGESTS"
    if not all(isinstance(value, str) and
               re.fullmatch(r"[0-9a-fA-F]{64}", value)
               for value in digests.values()):
        return "DIGESTS_INVALIDOS"
    if set(digests) == {"9", "10"}:
        return "LEGADO_9_10"
    if "11" in digests:
        return "11_PRESENTE_NAO_ATESTADO"
    return "MODELO_DESCONHECIDO"


def main() -> int:
    print("=== CE-GA08 | CONTEXTO PRIVADO VS RUNTIME | EP125 ===")
    try:
        require(socket.gethostname().split(".")[0] in
                ("ep125-pucpr", "ep125-pucpr-br"), "host_nao_ep125")
        require(os.geteuid() != 0, "nao_executar_com_root")
        require(REPO.is_dir(), "checkout_ausente")
        snapshots = inspect_runtime()
        live = runtime_references(snapshots)
        found = records(private_root(Path.home()))
        print("RUNTIME_14_COMPOSE=CONFIRMADO")
        print("RUNTIME_3_SERVICOS=HEALTHY")
        print("REFERENCIAS_COMPARAVEIS=17")
        print("GA08_NGINX_CONF_SOBREPOSTA=NAO_COMPROVAVEL_PELO_RUNTIME")
        for index, directory in enumerate(found, start=1):
            context = read_private_json(directory / "runtime-refs.json")
            manifest = read_private_json(directory / "manifest.json")
            refs = context_references(context, directory.name)
            match, mismatch, unknown = compare_references(refs, live)
            model = manifest_class(manifest, directory.name)
            print("=== REGISTRO_" + f"{index:02d}" + " ===")
            print("ID_DATA=" + directory.name[5:13])
            print("CONTEXTO_ESTRUTURA=PASS")
            print("CONTEXTO_REFERENCIAS=18")
            print("REFERENCIAS_MATCH=" + str(match))
            print("REFERENCIAS_DIVERGENTES=" + str(mismatch))
            print("REFERENCIAS_NAO_COMPROVADAS=" + str(unknown + 1))
            print("MANIFESTO_MODELO=" + model)
            print("ROLLBACK_PA05_APROVADO=NAO")
        print("REGISTROS_ANALISADOS=" + str(len(found)))
        print("DIAGNOSTICO=PASS_SOMENTE_LEITURA")
        return 0
    except GateError as error:
        print("DIAGNOSTICO=FAIL_CLOSED")
        print("MOTIVO=" + str(error))
        return 3
    except Exception:
        print("DIAGNOSTICO=FAIL_CLOSED")
        print("MOTIVO=erro_inesperado")
        return 3
    finally:
        print("CAMINHOS_E_VALORES_PRIVADOS_EXIBIDOS=NAO")
        print("ARQUIVOS_MODIFICADOS=NAO")
        print("SERVICOS_MODIFICADOS=NAO")
        print("DRIVER_DE_ROLLBACK_HABILITADO=NAO")
        print("=== FIM ===")


if __name__ == "__main__":
    raise SystemExit(main())
