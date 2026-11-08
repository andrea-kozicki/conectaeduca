#!/usr/bin/env python3
"""CE-PA02-CUT01 — corte GA08 dual Unix, rollback COMPATIVEL COM PA05.
Por padrao apenas prepara um contexto privativo. Requer nova aprovacao G0 e
snapshot posterior ao PA05 para permitir --apply. Nenhum sudo.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import ssl
import stat
import subprocess
import sys
import time
import urllib.request

ROOT = Path("/opt/conectaeduca")
DMZ = ROOT / "deploy/dmz"
HEAD = "04f88d275064a005d0ffcd4f9372a371c28c32d5"
PA05_IMAGE = "conectaeduca/php-fpm:pa05-10328ab6"
PA05_OVERLAY = Path("/home/andrea.kiew/.config/conectaeduca/pa05/compose.pa05-10328ab6.yml")
BASE = [str(DMZ / item) for item in (
    "compose.yml", "compose.database.yml", "compose.app-secrets.yml",
    "compose.waf.yml", "compose.waf-tls.yml", "compose.waf-policy.yml",
    "compose.host.yml", "compose.vm.yml", "compose.database-tls.yml",
    "compose.audit-persistent.yml",
)] + [str(PA05_OVERLAY)]
REF = "aa67a149ddcd14fdcbb28a66ea8785ac77579047"
ASSETS = {
    "compose.ga08-socket.candidate.yml": "e86ec91deb2d9fe59244b78145b4c546f0cf67d7",
    "compose.ga08-dual-socket.candidate.yml": "ee2e8583f72cb5f88760f601d9b409124b37bf7e",
    "compose.ga08-runtimefix.candidate.yml": "9306a6f69c069ca9bfa82a44469b3690d7208f0e",
    "ga08/app-http.dual-socket.candidate.conf": "d659dcabf1123c1b8b4b38bc4b381bf34a0d34f2",
    "ga08/zz-conectaeduca.socket.candidate.conf": "a1f3f8212f754f005473d8ad2d5d49bfcc5514a1",
}
CANDIDATES = list(ASSETS)[:3]
ROOT_CONTEXT = Path("/home/andrea.kiew/.local/share/conectaeduca/pa02")
LOCAL_RECOVERY_DIR = Path("/home/andrea.kiew/.local/share/conectaeduca/pa02-recovery")
MIN_SNAPSHOT = dt.datetime.fromisoformat("2026-11-08T17:40:01-03:00")
PROJECT = "conectaeduca-dmz"
SERVICE = ("php", "nginx", "waf")
SECRET_MOUNTS = {
    "CONECTAEDUCA_DB_PASSWORD_FILE": ("php", "/run/secrets/conectaeduca_db_password"),
    "CONECTAEDUCA_PRIVATE_KEY_FILE": ("php", "/run/secrets/conectaeduca_private_key"),
    "CONECTAEDUCA_PUBLIC_KEY_FILE": ("php", "/run/secrets/conectaeduca_public_key"),
    "CONECTAEDUCA_DB_TLS_CA_FILE": ("php", "/run/secrets/conectaeduca_db_tls_ca"),
    "CONECTAEDUCA_WAF_TLS_CERT_FILE": ("waf", "/run/secrets/waf_tls_cert"),
    "CONECTAEDUCA_WAF_TLS_KEY_FILE": ("waf", "/run/secrets/waf_tls_key"),
}
_CONTEXT: Path | None = None
_ENV: dict[str, str] = {}

class GateError(Exception):
    pass

def fail(reason: str) -> None:
    raise GateError(reason)

def git_blob(raw: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(raw)).encode() + bytes([0]) + raw).hexdigest()

def perms(path: Path, mode: int) -> None:
    if not path.is_file() or path.is_symlink() or stat.S_IMODE(path.stat().st_mode) != mode:
        fail("ARQUIVO_PRIVADO_AUSENTE_OU_MODO_INCORRETO")

def write_json(path: Path, data: dict) -> None:
    if path.is_symlink():
        fail("ARQUIVO_SIMBOLICO_RECUSADO")
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    fd = os.open(path, flags, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(data, stream, sort_keys=True, indent=2)
            stream.flush()
            os.fsync(stream.fileno())
    finally:
        path.chmod(0o600)

def load_json(path: Path) -> dict:
    perms(path, 0o600)
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        fail("ARQUIVO_JSON_INVALIDO")
    return {}

def run(args: list[str], *, env: dict[str,str] | None = None,
        timeout: int = 100) -> str:
    try:
        p = subprocess.run(args, capture_output=True, text=True,
                           env=env, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired):
        fail("COMANDO_INDISPONIVEL")
    if p.returncode:
        # Jamais imprimir stdout/stderr de Docker Compose: podem conter env.
        fail("COMANDO_FALHOU_" + args[0].split("/")[-1])
    return p.stdout.strip()

def inspect(cid: str) -> dict:
    return json.loads(run(["docker", "inspect", cid]))[0]

def current() -> dict[str,dict]:
    result = {}
    for service in SERVICE:
        ids = run(["docker", "ps", "-q",
                   "--filter", "label=com.docker.compose.project=" + PROJECT,
                   "--filter", "label=com.docker.compose.service=" + service]).splitlines()
        if len(ids) != 1:
            fail("SERVICO_NAO_UNICO_" + service)
        data = inspect(ids[0])
        state = data.get("State", {})
        if state.get("Running") is not True or (state.get("Health") or {}).get("Status") != "healthy":
            fail("SERVICO_NAO_HEALTHY_" + service)
        labels = data["Config"]["Labels"]
        if (labels.get("com.docker.compose.project") != PROJECT or
                labels.get("com.docker.compose.service") != service):
            fail("LABEL_SERVICO_DIVERGENTE_" + service)
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", data.get("Image", "")):
            fail("IMAGE_ID_INVALIDO_" + service)
        result[service] = data
    return result

def env_of(data: dict) -> dict[str,str]:
    return dict(row.split("=", 1) for row in data["Config"].get("Env", []) if "=" in row)

def origin(data: dict, target: str) -> str:
    matches = [m for m in data.get("Mounts", []) if m.get("Destination") == target
               and m.get("Type") == "bind"]
    if len(matches) != 1 or not Path(matches[0]["Source"]).is_absolute():
        fail("MOUNT_ORIGEM_NAO_UNICA")
    return matches[0]["Source"]

def new_environment(containers: dict[str,dict], assets: Path) -> dict[str,str]:
    # Somente valores de parametros operacionais e CAMINHOS dos segredos.
    env = os.environ.copy()
    for key, (name,target) in SECRET_MOUNTS.items():
        env[key] = origin(containers[name], target)
    php, waf = containers["php"], containers["waf"]
    pv = env_of(php)
    for key, entry in (
        ("CONECTAEDUCA_DB_HOST", "DB_HOST"),
        ("CONECTAEDUCA_DB_PORT", "DB_PORT"),
        ("CONECTAEDUCA_APP_URL", "APP_URL"),
    ):
        if not pv.get(entry):
            fail("ENV_RUNTIME_AUSENTE_" + entry)
        env[key] = pv[entry]
    groups = php["HostConfig"].get("GroupAdd") or []
    if (len(groups) != 1 or groups != (waf["HostConfig"].get("GroupAdd") or [])
            or not str(groups[0]).isdigit()):
        fail("GID_SECRETS_DIVERGENTE")
    env["CONECTAEDUCA_STACK_SECRET_GID"] = str(groups[0])
    ports = waf["HostConfig"].get("PortBindings") or {}
    p80, p443 = ports.get("8080/tcp") or [], ports.get("8443/tcp") or []
    if (len(p80) != 1 or len(p443) != 1 or
            p80[0].get("HostIp") != p443[0].get("HostIp") or
            not p80[0].get("HostIp") or
            not p80[0].get("HostPort", "").isdigit() or
            not p443[0].get("HostPort", "").isdigit()):
        fail("PORTAS_WAF_DIVERGENTES")
    env["CONECTAEDUCA_WAF_BIND_ADDRESS"] = p80[0]["HostIp"]
    env["CONECTAEDUCA_HTTP_PORT"] = p80[0]["HostPort"]
    env["CONECTAEDUCA_HTTPS_PORT"] = p443[0]["HostPort"]
    env["CONECTAEDUCA_SOURCE_COMMIT"] = HEAD
    env.update({
        "CONECTAEDUCA_GA08_SOCKET_DIR": "/var/lib/conectaeduca-ga08/fpm",
        "CONECTAEDUCA_GA08_HTTP_SOCKET_DIR": "/var/lib/conectaeduca-ga08/http",
        "CONECTAEDUCA_GA08_FPM_CONF": str(assets/"ga08/zz-conectaeduca.socket.candidate.conf"),
        "CONECTAEDUCA_GA08_NGINX_CONF": str(assets/"ga08/app-http.dual-socket.candidate.conf"),
        "CONECTAEDUCA_GA08_NGINX_HTTP_UNIX_CONF": str(assets/"ga08/app-http.dual-socket.candidate.conf"),
    })
    for key in ("COMPOSE_FILE", "COMPOSE_PROJECT_NAME", "COMPOSE_PROFILES"):
        env.pop(key, None)
    return env

def compose(extra: list[str]) -> list[str]:
    args = ["docker", "compose", "--project-directory", str(DMZ), "-p", PROJECT]
    for path in BASE + extra:
        args.extend(["-f", path])
    return args

def model(extra: list[str], env: dict[str,str]) -> dict:
    return json.loads(run(compose(extra) + ["config", "--format", "json"], env=env))

def fetch_assets(context: Path) -> None:
    for name, expected in ASSETS.items():
        target = context / "assets" / name
        if target.exists():
            if target.is_symlink() or git_blob(target.read_bytes()) != expected:
                fail("ASSET_LOCAL_DIVERGENTE_" + target.name)
            continue
        url = ("https://raw.githubusercontent.com/andrea-kozicki/conectaeduca/"
               + REF + "/deploy/dmz/" + name)
        try:
            with urllib.request.urlopen(url, timeout=20) as response:
                blob = response.read(1024 * 1024)
        except (OSError, ValueError):
            fail("ASSET_DOWNLOAD_FALHOU_" + target.name)
        if git_blob(blob) != expected:
            fail("ASSET_HASH_FALHOU_" + target.name)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(blob)
        target.chmod(0o644)

def assert_config(base: dict, candidate: dict) -> None:
    for name in SERVICE:
        a = base["services"][name]
        b = candidate["services"][name]
        if a.get("image") != b.get("image"):
            fail("IMAGEM_ALTERADA_PELO_GA08_" + name)
    if base["services"]["php"].get("image") != PA05_IMAGE:
        fail("NAO_PRESERVOU_IMAGEM_PA05")
    php = candidate["services"]["php"]
    nginx = candidate["services"]["nginx"]
    waf = candidate["services"]["waf"]
    if php.get("expose") or nginx.get("expose") or nginx.get("ports"):
        fail("UPSTREAM_TCP_PUBLICADO")
    if set(php.get("networks", {})) != {"php_egress"}:
        fail("REDE_PHP_INESPERADA")
    if set(nginx.get("networks", {})) != {"waf_backend"} or set(waf.get("networks", {})) != {"waf_backend"}:
        fail("REDE_WAF_NGINX_INESPERADA")
    if "unix:/run/conectaeduca-http/nginx.sock:" not in str(waf.get("environment", {}).get("BACKEND", "")):
        fail("BACKEND_WAF_NAO_UNIX")
    if not any(str(x).startswith("/run:") for x in nginx.get("tmpfs", [])):
        fail("TMPFS_RUN_CANONICO_AUSENTE")
    if any(str(x).startswith("/var/run:") for x in nginx.get("tmpfs", [])):
        fail("TMPFS_VAR_RUN_INDEVIDO")
    # A auditoria PHP e um BIND, mas credenciais Docker Compose ficam em
    # services.php.secrets e no top-level secrets, NAO em .volumes.
    audit_target="/var/www/conectaeduca/storage/logs"
    for name,svc in (("BASE",base["services"]["php"]),("CANDIDATO",php)):
        aud=[v for v in svc.get("volumes",[]) if isinstance(v,dict)
             and v.get("target")==audit_target]
        if len(aud)!=1 or aud[0].get("type")!="bind" or aud[0].get("read_only") is True:
            fail("AUDITORIA_BIND_AUSENTE_"+name)
    before_audit=next(v for v in base["services"]["php"]["volumes"]
                      if isinstance(v,dict) and v.get("target")==audit_target)
    after_audit=next(v for v in php["volumes"]
                     if isinstance(v,dict) and v.get("target")==audit_target)
    if before_audit!=after_audit:
        fail("AUDITORIA_BIND_ALTERADO")
    # A candidata NAO pode alterar a definicao/arquivo dos secrets nem as
    # autorizacoes de qualquer servico. O overlay GA08 trata apenas sockets.
    if base.get("secrets",{})!=candidate.get("secrets",{}):
        fail("DEFINICOES_SECRETS_ALTERADAS")
    for name in SERVICE:
        if base["services"][name].get("secrets",[])!=candidate["services"][name].get("secrets",[]):
            fail("SECRETS_SERVICO_ALTERADOS_"+name)
    required={
        "conectaeduca_db_password", "conectaeduca_db_tls_ca",
        "conectaeduca_private_key", "conectaeduca_public_key",
    }
    refs=php.get("secrets",[])
    if (not isinstance(refs,list) or
        not all(isinstance(item,dict) for item in refs) or
        not required.issubset({item.get("source") for item in refs}) or
        not required.issubset(set(candidate.get("secrets",{})))):
        fail("SECRETS_PHP_OBRIGATORIOS_AUSENTES")
    old_env=base["services"]["php"].get("environment",{})
    new_env=php.get("environment",{})
    for key in ("DB_PASS_FILE","DB_SSL_CA","PRIVATE_KEY_PATH","PUBLIC_KEY_PATH"):
        if not old_env.get(key) or new_env.get(key)!=old_env[key]:
            fail("CAMINHO_SECRET_ENV_ALTERADO_"+key)
    print("AUDITORIA_BIND=INTEGRIDADE_PASS")
    print("SECRETS_PHP=INTEGRIDADE_PASS")
    for name in ("php", "nginx", "waf"):
        if base["services"][name].get("read_only") != candidate["services"][name].get("read_only"):
            fail("READONLY_DIVERGENTE_" + name)

def socket_roots() -> None:
    # Owner UID101/0700 e UID82/0770 impedem a usuaria do host de
    # atravessar os diretorios. .exists()/.is_symlink() do arquivo FILHO
    # podem levantar PermissionError, mesmo com stat() do diretorio PASS.
    # Verificamos o socket dentro de um sandbox RO, usando o UID do servico
    # e a imagem exata ja ativa. Nao executar chmod, sudo ou remover sockets.
    running=current()
    for name, service, uid, gid, mode, sock in (
        ("http", "nginx", 101, 101, 0o700, "nginx.sock"),
        ("fpm", "php", 82, 82, 0o770, "php-fpm.sock"),
    ):
        directory=Path("/var/lib/conectaeduca-ga08")/name
        if not directory.is_dir() or directory.is_symlink():
            fail("SOCKET_DIR_INVALIDO_"+name)
        st=directory.stat()
        if (st.st_uid,st.st_gid,stat.S_IMODE(st.st_mode))!=(uid,gid,mode):
            fail("SOCKET_DIR_IDENTIDADE_DIVERGENTE_"+name)
        cmd=[
            "docker","run","--rm","--pull","never","--network","none",
            "--read-only","--user",f"{uid}:{gid}",
            "--cap-drop","ALL",
            "--security-opt","no-new-privileges:true",
            "--pids-limit","32",
            "--mount",f"type=bind,src={directory},dst=/ga08-sock,readonly",
            "--entrypoint","/bin/sh",running[service]["Image"],
            "-ec",'test ! -e "/ga08-sock/$1" && test ! -L "/ga08-sock/$1"',
            "sh",sock,
        ]
        try:
            p=subprocess.run(cmd,capture_output=True,text=True,timeout=35,
                             check=False)
        except (OSError,subprocess.TimeoutExpired):
            fail("SOCKET_SANDBOX_INDISPONIVEL_"+name)
        if p.returncode==1:
            fail("SOCKET_RESIDUAL_REQUER_REVISAO_"+name)
        if p.returncode!=0:
            # Nao expor stderr de Docker (pode conter metadados de runtime).
            fail("SOCKET_SANDBOX_FALHOU_"+name)
    print("SOCKETS_HOST_PREPARADOS=PASS")

def verify_unix_sockets() -> None:
    for service,path in (
        ("php","/run/conectaeduca-fpm/php-fpm.sock"),
        ("nginx","/run/conectaeduca-http/nginx.sock"),
    ):
        ids=run(["docker","ps","-q",
            "--filter","label=com.docker.compose.project="+PROJECT,
            "--filter","label=com.docker.compose.service="+service]).splitlines()
        if len(ids)!=1:
            fail("CONTAINER_SOCKET_NAO_UNICO_"+service)
        run(["docker","exec",ids[0],"test","-S",path])
    print("SOCKETS_UNIX_PRESENTES=PASS")

def check_containers(snapshot: dict, now: dict) -> None:
    for name in SERVICE:
        if now[name]["Id"] != snapshot[name]["container_id"] or now[name]["Image"] != snapshot[name]["image_id"]:
            fail("BASELINE_DRIFT_" + name)

def baseline_dict(now: dict) -> dict:
    return {name:{"container_id":now[name]["Id"],"image_id":now[name]["Image"],
                  "image_ref":now[name]["Config"]["Image"]} for name in SERVICE}

def wait_health(service: str, image_id: str, seconds: int = 65) -> dict:
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        try:
            ids = run(["docker","ps","-q",
                "--filter","label=com.docker.compose.project="+PROJECT,
                "--filter","label=com.docker.compose.service="+service]).splitlines()
            if len(ids)==1:
                obj=inspect(ids[0])
                if (obj.get("Image")==image_id and obj.get("State",{}).get("Running") is True
                        and (obj.get("State",{}).get("Health") or {}).get("Status")=="healthy"):
                    return obj
        except GateError:
            pass
        time.sleep(2)
    fail("NAO_HEALTHY_" + service)
    return {}

def up(files: list[str], service: str, env: dict[str,str]) -> None:
    run(compose(files)+["up","-d","--no-deps","--no-build","--pull","never",
                        "--force-recreate",service],env=env,timeout=180)

def network_ip(container: dict, desired: str) -> str:
    networks = container.get("NetworkSettings", {}).get("Networks", {})
    ip = [v.get("IPAddress") for k,v in networks.items()
          if k.endswith("_"+desired) and v.get("IPAddress")]
    if len(ip) != 1:
        fail("IP_BRIDGE_NAO_UNICO_" + desired)
    return ip[0]

def tcp_listeners(container_id: str) -> set[int]:
    """Le LISTEN TCP v4/v6 da namespace do container, sem testes de rota.

    Qualquer impossibilidade de leitura/parse gera erro e nunca PASS.
    """
    ports: set[int] = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        data=run(["docker","exec",container_id,"cat",table],timeout=20)
        lines=data.splitlines()
        if not lines or "local_address" not in lines[0] or "st" not in lines[0]:
            fail("TCP_PROC_INVALIDO_"+table.rsplit("/",1)[-1])
        for line in lines[1:]:
            cols=line.split()
            if len(cols)<4 or ":" not in cols[1]:
                fail("TCP_PROC_LINHA_INVALIDA")
            if cols[3].upper()=="0A":
                hexport=cols[1].rsplit(":",1)[1]
                if not re.fullmatch(r"[0-9A-Fa-f]{4}",hexport):
                    fail("TCP_PROC_PORTA_INVALIDA")
                ports.add(int(hexport,16))
    return ports


def assert_runtime_tcp_isolation(containers: dict[str,dict]) -> None:
    """Prova ausencia de TCP LISTEN, sem transformar timeout em evidencia.

    Testa controle positivo 8080 da borda WAF; sem leitura confiavel
    de /proc/net/tcp{,6}, aborta e nao declara isolamento.
    """
    for service, network, bypass_port in (
        ("nginx","waf_backend",8080),("php","php_egress",9000)
    ):
        row=containers[service]
        configured=row.get("NetworkSettings",{}).get("Networks",{})
        if (not isinstance(configured,dict) or len(configured)!=1 or
            not next(iter(configured)).endswith("_"+network)):
            fail("BYPASS_REDE_RUNTIME_DIVERGENTE_"+service)
        binds=row.get("HostConfig",{}).get("PortBindings") or {}
        if not isinstance(binds,dict) or any(bool(v) for v in binds.values()):
            fail("BYPASS_PORTA_PUBLICADA_"+service)
        if bypass_port in tcp_listeners(row["Id"]):
            fail("BYPASS_TCP_"+("NGINX" if service=="nginx" else "FPM")+"_AINDA_ACESSIVEL")
        print("BYPASS_TCP_"+("NGINX_8080" if service=="nginx" else "PHP_9000")+"=NEGADO_SEM_LISTENER")

    waf=containers["waf"]
    if 8080 not in tcp_listeners(waf["Id"]):
        fail("BYPASS_CONTROLE_POSITIVO_WAF_8080_NAO_LISTEN")
    print("BYPASS_CONTROLE_POSITIVO_WAF_8080=PASS")
    print("BYPASS_ISOLAMENTO_REDE_E_TCP_V4V6=PASS")

def https_smoke(waf: dict) -> bool:
    ports = waf["HostConfig"].get("PortBindings", {}).get("8443/tcp") or []
    if len(ports)!=1:
        return False
    addr=ports[0].get("HostIp") or ""
    port=ports[0].get("HostPort") or ""
    if addr in ("0.0.0.0", "::"):
        addr = "127.0.0.1"
    if not port.isdigit():
        return False
    # Smoke somente HTTP pela borda WAF; NAO prova validacao estrita CA.
    # Public key endpoint exige encaminhamento WAF -> Nginx -> PHP, nao
    # apenas health da propria borda. Corpo da resposta nao e exposto.
    url = "https://" + ("["+addr+"]" if ":" in addr else addr) + ":" + port + "/api/public_key.php"
    try:
        import urllib.error
        opener=urllib.request.build_opener(
            urllib.request.ProxyHandler({}),
            urllib.request.HTTPSHandler(context=ssl._create_unverified_context()),
        )
        with opener.open(url,timeout=8) as resp:
            return resp.status == 200
    except (OSError, ValueError, urllib.error.URLError):
        return False

def sha256_file(path: Path) -> str:
    h=hashlib.sha256()
    with path.open("rb") as fd:
        for piece in iter(lambda: fd.read(1024*1024), b""):
            h.update(piece)
    return h.hexdigest()

def verify_local_backup(directory_value: str, state: dict) -> None:
    # Um backup local de IMAGENS/COMPOSE nao cobre volumes ou perda da VM.
    if not isinstance(directory_value,str) or not directory_value:
        fail("G0_BACKUP_LOCAL_AUSENTE")
    directory=Path(directory_value)
    if (not directory.is_absolute() or directory.is_symlink()
        or directory.parent!=LOCAL_RECOVERY_DIR
        or not directory.name.startswith("CE-PA02-RC01-")
        or not directory.is_dir()
        or stat.S_IMODE(directory.stat().st_mode)!=0o700
        or directory.stat().st_uid!=os.geteuid()):
        fail("G0_BACKUP_LOCAL_CAMINHO_INVALIDO")
    manifest=load_json(directory/"manifest.json")
    if manifest.get("type")!="CE-PA02-RC01_LOCAL_DOCKER_RECOVERY":
        fail("G0_BACKUP_LOCAL_MANIFESTO_INVALIDO")
    if manifest.get("git_head")!=HEAD or manifest.get("project")!=PROJECT:
        fail("G0_BACKUP_LOCAL_BASE_DIVERGENTE")
    if manifest.get("compose_order")!=BASE:
        fail("G0_BACKUP_LOCAL_COMPOSE_INCOMPLETO")
    try:
        creation=dt.datetime.fromisoformat(manifest["created_at"])
    except (TypeError,ValueError,KeyError):
        fail("G0_BACKUP_LOCAL_DATA_INVALIDA")
    if (creation.tzinfo is None
        or creation.astimezone(dt.timezone.utc)<=MIN_SNAPSHOT.astimezone(dt.timezone.utc)):
        fail("G0_BACKUP_LOCAL_ANTERIOR_PA05")
    saved=manifest.get("services")
    if not isinstance(saved,dict) or set(saved)!=set(SERVICE):
        fail("G0_BACKUP_LOCAL_SERVICOS_INCOMPLETOS")
    for name in SERVICE:
        expected=state["baseline"][name]
        observed=saved[name]
        if (observed.get("image_ref")!=expected["image_ref"]
            or observed.get("image_id")!=expected["image_id"]
            or observed.get("container_id")!=expected["container_id"]):
            fail("G0_BACKUP_LOCAL_IMAGEM_DIVERGENTE_"+name)
    saved_config=directory/"compose"
    if (not saved_config.is_dir() or saved_config.is_symlink()
        or saved_config.stat().st_uid!=os.geteuid()
        or stat.S_IMODE(saved_config.stat().st_mode)!=0o700):
        fail("G0_BACKUP_LOCAL_COMPOSE_PASTA_INVALIDA")
    hashes=manifest.get("compose_sha256")
    if not isinstance(hashes,dict) or set(hashes)!=set(BASE):
        fail("G0_BACKUP_LOCAL_COMPOSE_HASHES_INCOMPLETOS")
    for i,path in enumerate(BASE,1):
        copy=saved_config/(f"{i:02d}-"+Path(path).name)
        perms(copy,0o600)
        expected=hashes[path]
        if (not isinstance(expected,str)
            or not re.fullmatch(r"[a-f0-9]{64}",expected)
            or sha256_file(copy)!=expected or sha256_file(Path(path))!=expected):
            fail("G0_BACKUP_LOCAL_COMPOSE_DIVERGENTE")
    archive=directory/"docker-images.tar.gz"
    perms(archive,0o600)
    actual_size=archive.stat().st_size
    if actual_size<=0 or actual_size!=manifest.get("images_archive_size_bytes"):
        fail("G0_BACKUP_LOCAL_TAMANHO_DIVERGENTE")
    archive_hash=manifest.get("images_archive_sha256")
    if (not isinstance(archive_hash,str) or not re.fullmatch(r"[0-9a-f]{64}",archive_hash)
        or sha256_file(archive)!=archive_hash):
        fail("G0_BACKUP_LOCAL_ARQUIVO_INTEGRO_NAO_VERIFICADO")
    print("G0_PACOTE_LOCAL_3_IMAGENS_11_COMPOSE=VERIFICADO")

def gates(context: Path, change_id: str, state: dict) -> dict:
    approval=load_json(context/"approval.json")
    if approval.get("change_id")!=change_id or approval.get("operator")!="andrea.kiew":
        fail("G0_OPERADOR_OU_CHANGE_ID_DIVERGENTE")
    for key in ("operator_approved","rollback_approved","outage_window_approved"):
        if approval.get(key) is not True:
            fail("G0_NAO_APROVADO_"+key)
    mode=approval.get("recovery_mode")
    if mode=="hypervisor-snapshot":
        for key in ("snapshot_restorable","snapshot_includes_pa05","secrets_recoverable"):
            if approval.get(key) is not True:
                fail("G0_SNAPSHOT_NAO_APROVADO_"+key)
        if not approval.get("snapshot_ref") or approval["snapshot_ref"]=="ubuntu.33":
            fail("G0_SNAPSHOT_REF_AUSENTE_OU_LEGADA")
        try:
            when=dt.datetime.fromisoformat(approval["snapshot_created_at"])
        except (TypeError,ValueError,KeyError):
            fail("G0_SNAPSHOT_DATA_INVALIDA")
        if (when.tzinfo is None
            or when.astimezone(dt.timezone.utc)<=MIN_SNAPSHOT.astimezone(dt.timezone.utc)):
            fail("G0_SNAPSHOT_ANTERIOR_PA05")
        if len(str(approval.get("restore_evidence","")))<12:
            fail("G0_SNAPSHOT_RETORNO_SEM_EVIDENCIA")
        print("G0_MODALIDADE=SNAPSHOT_HIPERVISOR_ATESTADO_NAO_VERIFICADO_API")
    elif mode=="local-service":
        if approval.get("snapshot_restorable") is True or approval.get("snapshot_includes_pa05") is True:
            fail("G0_BACKUP_LOCAL_NAO_E_SNAPSHOT")
        for key in ("same_host_loss_risk_accepted",
                    "volumes_database_secrets_excluded_accepted",
                    "restore_not_tested_risk_accepted",
                    "secrets_current_mounts_present_accepted"):
            if approval.get(key) is not True:
                fail("G0_RISCO_LOCAL_NAO_ACEITO_"+key)
        verify_local_backup(approval.get("local_backup_dir",""),state)
        print("G0_MODALIDADE=RECUPERACAO_LOCAL_APENAS_SERVICOS")
        print("G0_SNAPSHOT_HIPERVISOR=NAO")
        print("G0_VOLUME_BANCO_SEGREDOS_BACKUP=NAO")
        print("G0_RESTAURACAO_NAO_ENSAIADA=SIM")
    else:
        fail("G0_MODALIDADE_RECUPERACAO_NAO_SELECIONADA")
    return approval

def context_path(change_id: str) -> Path:
    if not re.fullmatch(r"PA02-20[0-9]{6}-[A-Z0-9-]{5,45}", change_id):
        fail("CHANGE_ID_INVALIDO")
    return ROOT_CONTEXT / change_id

def prepare(context: Path, change_id: str) -> None:
    socket_roots()
    # O preflight anterior pode ter baixado os assets antes de abortar
    # por validação incorreta de secrets. Reusar SOMENTE contexto parcial
    # privado, com assets aprovados e sem state/approval: sem rm/restore.
    if context.exists():
        if (context.is_symlink() or not context.is_dir()
            or context.stat().st_uid!=os.geteuid()
            or stat.S_IMODE(context.stat().st_mode)!=0o700):
            fail("CONTEXTO_EXISTENTE_INSEGURO")
        children={x.name for x in context.iterdir()}
        if not children.issubset({"assets"}):
            fail("CONTEXTO_EXISTENTE_NAO_PARCIAL")
        assets_dir=context/"assets"
        if assets_dir.exists() and (assets_dir.is_symlink() or not assets_dir.is_dir()
                                   or assets_dir.stat().st_uid!=os.geteuid()):
            fail("ASSETS_PARCIAIS_INVALIDOS")
        print("CONTEXTO_PARCIAL=REUTILIZAVEL")
    for path in BASE:
        if not Path(path).is_file() or Path(path).is_symlink():
            fail("COMPOSE_BASE_AUSENTE")
    now=current()
    labels=now["php"]["Config"]["Labels"]
    if labels.get("com.docker.compose.project.config_files", "").split(",") != BASE:
        fail("BASELINE_PHP_NAO_USA_11_ARQUIVOS")
    if now["php"]["Config"].get("Image") != PA05_IMAGE:
        fail("PHP_PA05_NAO_ESTA_ATIVO")
    for name in SERVICE:
        # Verifica ID de tag contra runtime sem mudar imagem.
        if run(["docker","image","inspect",now[name]["Config"]["Image"],
                "--format","{{.Id}}"]) != now[name]["Image"]:
            fail("IMAGEM_TAG_DRIFT_"+name)
    if not context.exists():
        context.mkdir(parents=True,mode=0o700)
        context.chmod(0o700)
    try:
        fetch_assets(context)
        env=new_environment(now,context/"assets")
        base_cfg=model([],env)
        candidate_cfg=model([str(context/"assets"/x) for x in CANDIDATES],env)
        assert_config(base_cfg,candidate_cfg)
    except BaseException:
        # Nao apagar contexto sem investigar downloads parciais.
        raise
    # Nenhum conteudo secreto persistido: so caminhos e parametros referenciais.
    state={
        "change_id":change_id,"prepared_at":dt.datetime.now().astimezone().isoformat(),
        "baseline":baseline_dict(now),
        "env_values": {k:env[k] for k in (
            *SECRET_MOUNTS.keys(),"CONECTAEDUCA_DB_HOST","CONECTAEDUCA_DB_PORT",
            "CONECTAEDUCA_APP_URL","CONECTAEDUCA_STACK_SECRET_GID",
            "CONECTAEDUCA_WAF_BIND_ADDRESS","CONECTAEDUCA_HTTP_PORT",
            "CONECTAEDUCA_HTTPS_PORT","CONECTAEDUCA_SOURCE_COMMIT",
            "CONECTAEDUCA_GA08_SOCKET_DIR","CONECTAEDUCA_GA08_HTTP_SOCKET_DIR",
            "CONECTAEDUCA_GA08_FPM_CONF","CONECTAEDUCA_GA08_NGINX_CONF",
            "CONECTAEDUCA_GA08_NGINX_HTTP_UNIX_CONF")},
        "status":"PREPARED",
    }
    write_json(context/"state.json",state)
    write_json(context/"approval.json",{
        "change_id":change_id,"operator":"andrea.kiew",
        "recovery_mode":"unselected",
        "snapshot_ref":"","snapshot_created_at":"",
        "restore_evidence":"",
        "local_backup_dir":"",
        "operator_approved":False,"snapshot_restorable":False,
        "snapshot_includes_pa05":False,"secrets_recoverable":False,
        "rollback_approved":False,"outage_window_approved":False,
        "same_host_loss_risk_accepted":False,
        "volumes_database_secrets_excluded_accepted":False,
        "restore_not_tested_risk_accepted":False,
        "secrets_current_mounts_present_accepted":False,
    })
    print("CONTEXTO_PRIVADO=CRIADO")
    print("PREFLIGHT_11MAIS3=PASS")
    print("PA05_PRESERVADO=SIM")
    print("APROVACAO_G0=MODELO_NAO_APROVADO")
    print("CUTOVER_EXECUTADO=NAO")
    print("CE-PA02-CUT01_PREPARACAO_CONCLUIDA")

def load_state(context:Path,change_id:str)->tuple[dict,dict[str,str]]:
    state=load_json(context/"state.json")
    if state.get("change_id") != change_id or not isinstance(state.get("baseline"),dict):
        fail("CONTEXTO_INVALIDO")
    env=os.environ.copy()
    env.update(state["env_values"])
    for key in ("COMPOSE_FILE","COMPOSE_PROJECT_NAME","COMPOSE_PROFILES"):
        env.pop(key,None)
    for name,expected in ASSETS.items():
        target=context/"assets"/name
        if not target.is_file() or target.is_symlink() or git_blob(target.read_bytes()) != expected:
            fail("ASSET_INTEGRIDADE_INVALIDA")
    return state,env

def do_rollback(context:Path,state:dict,env:dict[str,str]) -> bool:
    print("PA02_ROLLBACK=INICIADO",flush=True)
    errors=[]
    # Restaura todos os tres, sempre com os 11 overlays que preservam PA05.
    for service in ("php","nginx","waf"):
        try:
            up([],service,env)
            wait_health(service,state["baseline"][service]["image_id"])
            print("ROLLBACK_"+service.upper()+"=HEALTHY",flush=True)
        except (GateError,ValueError,OSError):
            errors.append(service)
            print("ROLLBACK_"+service.upper()+"=FALHA",flush=True)
    if errors:
        print("ROLLBACK_HTTPS_APP_ENDPOINT=NAO_TESTADO",flush=True)
    else:
        try:
            restored=current()
            if https_smoke(restored["waf"]):
                print("ROLLBACK_HTTPS_APP_ENDPOINT=200",flush=True)
            else:
                errors.append("https")
                print("ROLLBACK_HTTPS_APP_ENDPOINT=FALHA",flush=True)
        except (GateError,ValueError,OSError):
            errors.append("https")
            print("ROLLBACK_HTTPS_APP_ENDPOINT=FALHA",flush=True)
    state["status"]="ROLLBACK_HEALTHY" if not errors else "ROLLBACK_INCOMPLETO"
    write_json(context/"state.json",state)
    print("PA02_ROLLBACK="+state["status"],flush=True)
    return not errors

def deploy(context:Path,state:dict,env:dict[str,str]) -> None:
    socket_roots()
    now=current()
    check_containers(state["baseline"],now)
    files=[str(context/"assets"/x) for x in CANDIDATES]
    basecfg=model([],env)
    cfg=model(files,env)
    assert_config(basecfg,cfg)
    state["status"]="CUTOVER_INICIADO"
    write_json(context/"state.json",state)
    try:
        for service in SERVICE:
            up(files,service,env)
            wait_health(service,state["baseline"][service]["image_id"])
            print("CUTOVER_"+service.upper()+"=HEALTHY",flush=True)
        verify_unix_sockets()
        after=current()
        for service in SERVICE:
            if after[service]["Image"] != state["baseline"][service]["image_id"]:
                fail("IMAGEM_ALTERADA_"+service)
        assert_runtime_tcp_isolation(after)
        if not https_smoke(after["waf"]):
            fail("WAF_HTTPS_HEALTH_FALHOU")
        print("WAF_HTTPS_APP_ENDPOINT=200")
        print("BYPASS_NGINX_8080=NEGADO")
        print("BYPASS_PHP_9000=NEGADO")
        print("PHP_PA05_PRESERVADO=SIM")
        print("SOCKETS_UNIX=IMPLANTADOS")
        print("PA02_REMEDIACAO_RUNTIME=IMPLEMENTADA")
        print("TLS_CA_E_AUTH_APLICACAO=NAO_HOMOLOGADOS_NESTE_CORTE")
        state["status"]="CUTOVER_HEALTHY"
        write_json(context/"state.json",state)
        print("CE-PA02-CUT01_CONCLUIDO")
    except BaseException:
        # Reparacao automatica best-effort para baseline pos PA05.
        do_rollback(context,state,env)
        raise

def dry_run(context: Path, state: dict, env: dict[str,str], backup_dir: str) -> None:
    """Plano reproduzivel de corte/retorno: somente leituras e SHA-256.

    Nunca chama up, deploy, rollback, Docker image load, Docker run ou
    write_json. Docker compose config apenas renderiza o modelo local.
    """
    print("=== CE-PA02-DRY01 — SIMULACAO SEM MUTACAO ===")
    if state.get("status")!="PREPARED":
        fail("DRY_RUN_CONTEXTO_NAO_PREPARADO")
    if not backup_dir:
        fail("DRY_RUN_BACKUP_DIR_OBRIGATORIO")
    actual=current()
    check_containers(state["baseline"],actual)
    php=actual["php"]
    if (php["Config"].get("Image")!=PA05_IMAGE or
        php["Config"]["Labels"].get("com.docker.compose.project.config_files","").split(",")!=BASE):
        fail("DRY_RUN_PHP_PA05_OU_11_COMPOSE_DIVERGENTE")
    for service in SERVICE:
        ref=state["baseline"][service]["image_ref"]
        image_id=state["baseline"][service]["image_id"]
        if run(["docker","image","inspect",ref,"--format","{{.Id}}"])!=image_id:
            fail("DRY_RUN_TAG_IMAGEM_DIVERGENTE_"+service)
    print("DRY_RUN_BASELINE_3_SERVICOS=HEALTHY")
    print("DRY_RUN_IMAGENS_BASELINE=INTEGRIDADE_PASS")
    # Os parametros efetivos sao comparados em memoria; nenhum valor de
    # secret, env, .env, Compose config ou manifest vai para o stdout.
    fresh=new_environment(actual,context/"assets")
    stored=state.get("env_values")
    if not isinstance(stored,dict):
        fail("DRY_RUN_ENV_ESTADO_INVALIDO")
    for key, value in stored.items():
        if key not in fresh or fresh[key]!=value:
            fail("DRY_RUN_ENV_RUNTIME_DIVERGENTE")
    verify_local_backup(backup_dir,state)
    rollback_cfg=model([],env)
    candidate_files=[str(context/"assets"/name) for name in CANDIDATES]
    candidate_cfg=model(candidate_files,env)
    assert_config(rollback_cfg,candidate_cfg)
    for service in SERVICE:
        expected=state["baseline"][service]["image_ref"]
        if (rollback_cfg["services"][service].get("image")!=expected
            or candidate_cfg["services"][service].get("image")!=expected):
            fail("DRY_RUN_IMAGEM_NO_COMPOSE_DIVERGENTE_"+service)
    if rollback_cfg["services"]["php"].get("image")!=PA05_IMAGE:
        fail("DRY_RUN_PA05_NAO_PRESERVADO_NO_RETORNO")
    print("DRY_RUN_ROLLBACK_11_COMPOSE=PASS")
    print("DRY_RUN_CANDIDATO_14_COMPOSE=PASS")
    print("DRY_RUN_PHP_PA05_NO_RETORNO=PASS")
    print("PLANO_CORTE=PHP_NGINX_WAF")
    print("PLANO_RETORNO=PHP_NGINX_WAF")
    print("APROVACAO_G0=NAO_AVALIADA_NESTE_MODO")
    print("DOCKER_COMPOSE_UP_EXECUTADO=NAO")
    print("DOCKER_IMAGE_LOAD_EXECUTADO=NAO")
    print("CONTEINERES_RECRIADOS=NAO")
    print("ROLLBACK_REAL_ENSAIADO=NAO")
    print("SNAPSHOT_HIPERVISOR=NAO")
    print("CE-PA02-DRY01_CONCLUIDO")


def main()->None:
    parser=argparse.ArgumentParser()
    parser.add_argument("--mode",choices=("prepare","dry-run","apply","rollback"),required=True)
    parser.add_argument("--change-id",required=True)
    parser.add_argument("--ack",default="")
    parser.add_argument("--backup-dir",default="")
    args=parser.parse_args()
    os.umask(0o077)
    print("=== CE-PA02-CUT01 — GA08 CORTE PA05-SAFE ===")
    print("DATA="+dt.datetime.now().astimezone().isoformat(timespec="seconds"))
    if os.geteuid()==0 or run(["whoami"])!="andrea.kiew":
        fail("USUARIO_INCORRETO_OU_ROOT")
    if socket.gethostname().split(".")[0] not in ("ep125-pucpr","ep125-pucpr-br"):
        fail("HOST_INCORRETO")
    if run(["git","-C",str(ROOT),"rev-parse","HEAD"])!=HEAD:
        fail("GIT_HEAD_DIVERGENTE")
    context=context_path(args.change_id)
    if args.mode=="prepare":
        if args.ack:
            fail("ACK_INDEVIDO_EM_PREPARE")
        prepare(context,args.change_id)
        return
    if not context.is_dir() or context.is_symlink() or stat.S_IMODE(context.stat().st_mode)!=0o700:
        fail("CONTEXTO_PRIVADO_INVALIDO")
    state,env=load_state(context,args.change_id)
    if args.mode=="dry-run":
        if args.ack:
            fail("DRY_RUN_NAO_ACEITA_ACK")
        dry_run(context,state,env,args.backup_dir)
        return
    if args.backup_dir:
        fail("BACKUP_DIR_APENAS_PARA_DRY_RUN")
    if args.mode=="apply":
        if args.ack!="APLICAR_PA02_EP125":
            fail("ACK_CUTOVER_AUSENTE")
        gates(context,args.change_id,state)
        if state.get("status")!="PREPARED":
            fail("STATUS_NAO_E_PREPARED")
        print("G0_DOCUMENTAL=PASS")
        print("G0_APROVACAO_ATESTADA_PELA_OPERADORA=SIM")
        deploy(context,state,env)
    elif args.mode=="rollback":
        if args.ack!="ROLLBACK_PA02_EP125":
            fail("ACK_ROLLBACK_AUSENTE")
        if state.get("status") not in ("CUTOVER_INICIADO","ROLLBACK_INCOMPLETO","CUTOVER_HEALTHY"):
            fail("SEM_CUTOVER_A_REVERTER")
        if not do_rollback(context,state,env):
            fail("ROLLBACK_PARCIAL_EXIGE_SUPORTE")
        print("CE-PA02-CUT01_ROLLBACK_CONCLUIDO")

if __name__=="__main__":
    try:
        main()
    except GateError as exc:
        print("CE-PA02-CUT01_ABORTADO="+str(exc),file=sys.stderr)
        sys.exit(1)
    except (OSError,ValueError,KeyError,TypeError) as exc:
        print("CE-PA02-CUT01_ABORTADO="+type(exc).__name__,file=sys.stderr)
        sys.exit(1)
