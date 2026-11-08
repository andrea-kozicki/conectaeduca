#!/usr/bin/env python3
"""CE-PA05-DEP02: build de patch PHP sobre imagem ativa e cutover restrito com rollback.
Executar na EP125 como usuario andrea.kiew com --apply, sem sudo.
Nao exibe conteudos de secrets, variaveis, logs ou outros servicos.
"""
from __future__ import annotations
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time
import urllib.request

ROOT = Path("/opt/conectaeduca")
DMZ = ROOT / "deploy/dmz"
HEAD = "04f88d275064a005d0ffcd4f9372a371c28c32d5"
PATCH_COMMIT = "10328ab6d67d59325c2ea3b707a5dce660c2bb8f"
BASE_IMAGE = "conectaeduca/php-fpm:dmz"
BASE_ID = "sha256:3c8b6fe0c9905ddfe13c5b5b5fc408726bdff89290a1a99a74abb912d9a609f4"
PATCH_IMAGE = "conectaeduca/php-fpm:pa05-10328ab6"
PROJECT = "conectaeduca-dmz"
FILES = [
    "compose.yml", "compose.database.yml", "compose.app-secrets.yml",
    "compose.waf.yml", "compose.waf-tls.yml", "compose.waf-policy.yml",
    "compose.host.yml", "compose.vm.yml", "compose.database-tls.yml",
    "compose.audit-persistent.yml",
]
FILES = [str(DMZ / name) for name in FILES]
PATCHES = {
    "src/Repository/InscricaoRepository.php":
        ("99388b33154eb67109d866cb2d1920a85effcd37",
         "538e59a2c7690cc53c5f71ff0ca54286c2a0ba5c"),
    "src/Service/InscricaoService.php":
        ("0c56f3b392c427d868205ab6db51361e8719c2bb",
         "4d0031e97ab7daa8b4b4edff3ffddad97898c6f3"),
    "src/Controller/InscricaoController.php":
        ("c549acf4435fcf87036d987c94d88d31bfd7df9d",
         "451d97936c8f2ae6d82ab47a932fbcb36365a496"),
}
MOUNTS = {
    "CONECTAEDUCA_DB_PASSWORD_FILE": ("php", "/run/secrets/conectaeduca_db_password"),
    "CONECTAEDUCA_PRIVATE_KEY_FILE": ("php", "/run/secrets/conectaeduca_private_key"),
    "CONECTAEDUCA_PUBLIC_KEY_FILE": ("php", "/run/secrets/conectaeduca_public_key"),
    "CONECTAEDUCA_DB_TLS_CA_FILE": ("php", "/run/secrets/conectaeduca_db_tls_ca"),
    "CONECTAEDUCA_WAF_TLS_CERT_FILE": ("waf", "/run/secrets/waf_tls_cert"),
    "CONECTAEDUCA_WAF_TLS_KEY_FILE": ("waf", "/run/secrets/waf_tls_key"),
}
WORK = Path.home() / ".local/share/conectaeduca/pa05-deploy-10328ab6"
OVERLAY = Path.home() / ".config/conectaeduca/pa05/compose.pa05-10328ab6.yml"
CHANGED = False
BASELINE = {}
CANDIDATE_ID = ""
ENV = {}
LOGDIR = WORK / "logs"

def fail(code: str) -> None:
    print("CE-PA05-DEP02_ABORTADO=" + code, file=sys.stderr, flush=True)
    raise RuntimeError(code)

def gitblob(raw: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(raw)).encode() + bytes([0]) + raw).hexdigest()

def cmd(args: list[str], *, env: dict | None = None, log: str | None = None) -> str:
    try:
        proc = subprocess.run(
            args, env=env, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=180
        )
    except (OSError, subprocess.TimeoutExpired):
        fail("COMANDO_NAO_EXECUTADO")
    if log and LOGDIR.is_dir():
        p = LOGDIR / log
        p.write_text(proc.stdout + "\n" + proc.stderr, encoding="utf-8")
        p.chmod(0o600)
    if proc.returncode != 0:
        fail("COMANDO_FALHOU_" + args[0].upper().replace("/", "_"))
    return proc.stdout.strip()

def inspect_container(cid: str) -> dict:
    return json.loads(cmd(["docker", "inspect", cid]))[0]

def single_service(service: str) -> dict:
    ids = cmd([
        "docker", "ps", "-q", "-f", "label=com.docker.compose.project=" + PROJECT,
        "-f", "label=com.docker.compose.service=" + service
    ]).splitlines()
    if len(ids) != 1:
        fail("SERVICO_NAO_UNICO_" + service)
    return inspect_container(ids[0])

def env_map(container: dict) -> dict[str, str]:
    return dict(row.split("=", 1) for row in container["Config"].get("Env", []) if "=" in row)

def mount_map(container: dict) -> dict[str, dict]:
    return {row["Destination"]: row for row in container.get("Mounts", [])}

def compose_args(extra: bool) -> list[str]:
    files = FILES + ([str(OVERLAY)] if extra else [])
    args = ["docker", "compose", "-p", PROJECT]
    for file in files:
        args += ["-f", file]
    return args

def config(extra: bool) -> dict:
    return json.loads(cmd(compose_args(extra) + ["config", "--format", "json"], env=ENV))

def health(cid: str, expected_id: str) -> bool:
    for _ in range(15):
        try:
            actual = inspect_container(cid)
            if (actual["Image"] == expected_id
                and actual["State"].get("Running") is True
                and actual["State"].get("Health", {}).get("Status") == "healthy"):
                return True
        except Exception:
            pass
        time.sleep(2)
    return False

def apply_compose(extra: bool, phase: str) -> None:
    args = compose_args(extra) + [
        "up", "-d", "--no-deps", "--no-build", "--pull", "never",
        "--force-recreate", "php",
    ]
    cmd(args, env=ENV, log=phase + ".private.log")

def rollback() -> None:
    print("ROLLBACK_PA05=INICIADO", flush=True)
    try:
        if cmd(["docker", "image", "inspect", BASE_IMAGE, "--format", "{{.Id}}"]) != BASE_ID:
            print("ROLLBACK_PA05=BASE_IMAGE_DIVERGENTE", flush=True)
            return
        apply_compose(False, "rollback")
        restored = single_service("php")
        if health(restored["Id"], BASE_ID):
            print("ROLLBACK_PA05=BASELINE_HEALTHY", flush=True)
        else:
            print("ROLLBACK_PA05=REQUIERE_INTERVENCAO", flush=True)
    except Exception:
        print("ROLLBACK_PA05=FALHOU_REQUER_INTERVENCAO", flush=True)

def main() -> None:
    global CHANGED, BASELINE, CANDIDATE_ID, ENV
    os.umask(0o077)
    print("=== CE-PA05-DEP02 — CUTOVER PHP RESTRITO EP125 ===", flush=True)
    print("USUARIO=" + cmd(["whoami"]))
    print("DATA=" + dt.datetime.now().astimezone().isoformat(timespec="seconds"))
    if sys.argv[1:] != ["--apply"]:
        fail("EXIGE_--apply")
    if os.geteuid() == 0 or cmd(["whoami"]) != "andrea.kiew":
        fail("USUARIO_INCORRETO_OU_ROOT")
    if socket.gethostname().split(".")[0] != "ep125-pucpr":
        fail("HOST_INCORRETO")
    if cmd(["git", "-C", str(ROOT), "rev-parse", "HEAD"]) != HEAD:
        fail("GIT_HEAD_DIVERGENTE")
    for path in FILES:
        if not Path(path).is_file():
            fail("OVERLAY_COMPOSE_AUSENTE")
    php = single_service("php")
    waf = single_service("waf")
    nginx = single_service("nginx")
    BASELINE = {"php": php, "waf": waf, "nginx": nginx}
    labels = php["Config"]["Labels"]
    if (labels.get("com.docker.compose.project.config_files", "").split(",") != FILES
        or labels.get("com.docker.compose.project.working_dir") != str(DMZ)
        or php["Image"] != BASE_ID):
        fail("RUNTIME_BASELINE_DIVERGENTE")
    if cmd(["docker", "image", "inspect", BASE_IMAGE, "--format", "{{.Id}}"]) != BASE_ID:
        fail("TAG_BASELINE_ALTERADA")
    for c in (php, waf, nginx):
        if (c["State"].get("Health", {}).get("Status") != "healthy"):
            fail("SERVICO_BASELINE_NAO_HEALTHY")
    if any(x["Destination"].startswith("/var/www/conectaeduca/src")
           for x in php.get("Mounts", [])):
        fail("SRC_MONTADO_NAO_CONTIDO_NA_IMAGEM")
    print("RUNTIME_BASELINE=CONFIRMADO")
    print("COMPOSE_ATIVO=10_ARQUIVOS")

    runtime = {"php": php, "waf": waf}
    env = os.environ.copy()
    for name, (svc, dest) in MOUNTS.items():
        m = mount_map(runtime[svc]).get(dest)
        if not m or m.get("Type") != "bind" or not Path(m.get("Source", "")).is_absolute():
            fail("ORIGEM_SECRET_INDISPONIVEL_" + name)
        env[name] = m["Source"]

    pv = env_map(php)
    for key, source in {
        "CONECTAEDUCA_DB_HOST": "DB_HOST",
        "CONECTAEDUCA_DB_PORT": "DB_PORT",
        "CONECTAEDUCA_APP_URL": "APP_URL",
    }.items():
        if not pv.get(source):
            fail("ENV_RUNTIME_AUSENTE_" + source)
        env[key] = pv[source]
    groups = php["HostConfig"].get("GroupAdd") or []
    waf_groups = waf["HostConfig"].get("GroupAdd") or []
    if len(groups) != 1 or groups != waf_groups or not str(groups[0]).isdigit():
        fail("GRUPO_SECRETS_NAO_UNICO")
    env["CONECTAEDUCA_STACK_SECRET_GID"] = str(groups[0])
    ports = waf["HostConfig"].get("PortBindings") or {}
    http = (ports.get("8080/tcp") or [])
    https = (ports.get("8443/tcp") or [])
    if len(http) != 1 or len(https) != 1:
        fail("PORTAS_WAF_NAO_UNICAS")
    if (not http[0].get("HostIp") or
        http[0].get("HostIp") != https[0].get("HostIp") or
        not str(http[0].get("HostPort", "")).isdigit() or
        not str(https[0].get("HostPort", "")).isdigit()):
        fail("BIND_WAF_DIVERGENTE")
    env["CONECTAEDUCA_WAF_BIND_ADDRESS"] = http[0]["HostIp"]
    env["CONECTAEDUCA_HTTP_PORT"] = http[0]["HostPort"]
    env["CONECTAEDUCA_HTTPS_PORT"] = https[0]["HostPort"]
    env["CONECTAEDUCA_SOURCE_COMMIT"] = HEAD
    for key in ("COMPOSE_FILE", "COMPOSE_PROJECT_NAME", "COMPOSE_PROFILES"):
        env.pop(key, None)
    ENV = env

    # Confirmar que os dez arquivos efetivos descrevem o ambiente instalado
    # antes de criar/recriar qualquer coisa; nenhum valor e impresso.
    base_cfg = config(False)
    svc = base_cfg["services"]["php"]
    if svc.get("image") != BASE_IMAGE or svc.get("read_only") is not True:
        fail("MODELO_PHP_INCONSISTENTE")
    for key in ("DB_HOST", "DB_PORT", "APP_URL"):
        if str(svc.get("environment", {}).get(key)) != pv[key]:
            fail("CONFIG_RUNTIME_ENV_DIVERGENTE")
    mounts = svc.get("volumes") or []
    if not any(x.get("target") == "/var/www/conectaeduca/storage/logs"
               and x.get("type") == "bind" for x in mounts if isinstance(x, dict)):
        fail("PERSISTENCIA_AUDIT_NAO_PRESENTE")
    print("COMPOSE_E_SECRETS=RECONCILIADOS_SEM_EXPOSICAO", flush=True)

    # Copiar a versao original apenas para prova de cadeia de custodia.
    WORK.mkdir(parents=True, exist_ok=True)
    WORK.chmod(0o700)
    LOGDIR.mkdir(exist_ok=True)
    LOGDIR.chmod(0o700)
    context = WORK / "context"
    context.mkdir(exist_ok=True)
    context.chmod(0o700)
    for rel, (old_hash, new_hash) in PATCHES.items():
        src = ROOT / rel
        if gitblob(src.read_bytes()) != old_hash:
            fail("CHECKOUT_BASE_DIVERGENTE_" + Path(rel).name)
        extracted = WORK / ("running-" + Path(rel).name)
        cmd(["docker", "cp", php["Id"] + ":/var/www/conectaeduca/" + rel, str(extracted)])
        if gitblob(extracted.read_bytes()) != old_hash:
            fail("IMAGE_BASE_CODE_DIVERGENTE_" + Path(rel).name)
        url = (
            "https://raw.githubusercontent.com/andrea-kozicki/conectaeduca/"
            + PATCH_COMMIT + "/" + rel
        )
        try:
            with urllib.request.urlopen(url, timeout=20) as response:
                payload = response.read(256 * 1024)
        except Exception:
            fail("DOWNLOAD_PATCH_FALHOU_" + Path(rel).name)
        if gitblob(payload) != new_hash:
            fail("PATCH_HASH_DIVERGENTE_" + Path(rel).name)
        target = context / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
        target.chmod(0o600)
    print("PATCH_3_ARQUIVOS=HASHES_CONFIRMADOS", flush=True)

    dockerfile = context / "Dockerfile"
    dockerfile.write_text(
        "FROM " + BASE_IMAGE + "\n" +
        "LABEL io.conectaeduca.pa05.source=\"" + PATCH_COMMIT + "\"\n" +
        "".join(
            "COPY --chown=82:82 --chmod=0644 " + rel
            + " /var/www/conectaeduca/" + rel + "\n"
            for rel in PATCHES
        ), encoding="utf-8"
    )
    dockerfile.chmod(0o600)
    if cmd(["docker", "image", "ls", "-q", PATCH_IMAGE]):
        fail("TAG_CANDIDATA_JA_EXISTE")
    print("BUILD_CANDIDATA=INICIANDO", flush=True)
    cmd([
        "docker", "build", "--pull=false", "--network=none",
        "--tag", PATCH_IMAGE, "--file", str(dockerfile), str(context),
    ], log="build.private.log")
    CANDIDATE_ID = cmd(["docker", "image", "inspect", PATCH_IMAGE, "--format", "{{.Id}}"])
    if CANDIDATE_ID == BASE_ID or not CANDIDATE_ID.startswith("sha256:"):
        fail("CANDIDATA_ID_INVALIDO")
    for rel in PATCHES:
        cmd([
            "docker", "run", "--rm", "--network", "none", "--entrypoint", "php",
            PATCH_IMAGE, "-l", "/var/www/conectaeduca/" + rel,
        ], log="php-syntax.private.log")
    print("IMAGEM_CANDIDATA=CRIADA")
    print("PHP_SINTAXE=PASS")

    OVERLAY.parent.mkdir(parents=True, exist_ok=True)
    OVERLAY.parent.chmod(0o700)
    if OVERLAY.exists():
        fail("OVERLAY_OPERACIONAL_PREEXISTENTE")
    OVERLAY.write_text(
        "services:\n  php:\n    build: !reset null\n"
        "    image: " + PATCH_IMAGE + "\n"
        "    pull_policy: never\n",
        encoding="utf-8",
    )
    OVERLAY.chmod(0o600)
    patched = config(True)
    proposed = patched["services"]["php"]
    normal = dict(svc)
    amended = dict(proposed)
    for ignore in ("image", "build", "pull_policy"):
        normal.pop(ignore, None)
        amended.pop(ignore, None)
    if normal != amended or proposed.get("image") != PATCH_IMAGE:
        fail("COMPOSE_PROPOSTO_ALTEROU_OUTROS_ATRIBUTOS")
    if cmd(compose_args(True) + ["config", "--images"], env=ENV).splitlines().count(PATCH_IMAGE) != 1:
        fail("SELECAO_IMAGEM_NAO_UNICA")
    print("COMPOSE_CANDIDATA=PASS")
    print("SERVICOS_AFETADOS=APENAS_PHP")
    print("OVERLAY_PERSISTENTE=" + str(OVERLAY))

    # A unica interrupcao e a substituicao da imagem do container PHP.
    try:
        CHANGED = True
        apply_compose(True, "cutover")
        newest = single_service("php")
        if not health(newest["Id"], CANDIDATE_ID):
            fail("SAUDE_PHP_CANDIDATA_NAO_CONFIRMADA")
        for name in ("waf", "nginx"):
            if single_service(name)["Id"] != BASELINE[name]["Id"]:
                fail("CONTAINER_ADJACENTE_ALTERADO_" + name)
        before_mounts = {d: m["Source"] for d, m in mount_map(php).items()}
        after_mounts = {d: m["Source"] for d, m in mount_map(newest).items()}
        if before_mounts != after_mounts:
            fail("MOUNT_APOS_CUTOVER_DIVERGENTE")
        if (newest["HostConfig"].get("ReadonlyRootfs") != php["HostConfig"].get("ReadonlyRootfs")
            or newest["HostConfig"].get("CapDrop") != php["HostConfig"].get("CapDrop")
            or newest["HostConfig"].get("GroupAdd") != php["HostConfig"].get("GroupAdd")):
            fail("GUARDAS_RUNTIME_DIVERGENTES")
    except BaseException:
        rollback()
        raise
    CHANGED = False
    print("DEPLOY_PHP_PA05=CONFIRMADO")
    print("PHP_HEALTH=HEALTHY")
    print("AUDIT_BIND_E_SECRETS=PRESERVADOS")
    print("WAF_NGINX_RECRIADOS=NAO")
    print("ROLLBACK_BASELINE=PREPARADO_NAO_ENSAIADO")
    print("GIT_TRACKED=NAO_MODIFICADO")
    print("RETTESTE_BOLA=AINDA_NAO_EXECUTADO")
    print("CE-PA05-DEP02_CONCLUIDO")

if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(1)
