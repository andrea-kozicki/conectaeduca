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
    # Vinculo dos logs de auditoria e secretos PA05 nao pode desaparecer.
    for path in ("/var/www/conectaeduca/storage/logs",
                 "/run/secrets/conectaeduca_db_password",
                 "/run/secrets/conectaeduca_db_tls_ca"):
        if not any(v.get("target") == path for v in php.get("volumes", []) if isinstance(v,dict)):
            fail("MOUNT_PHP_NAO_PRESERVADO")
    for name in ("php", "nginx", "waf"):
        if base["services"][name].get("read_only") != candidate["services"][name].get("read_only"):
            fail("READONLY_DIVERGENTE_" + name)

def socket_roots() -> None:
    for name, uid, gid, mode, sock in (
        ("http", 101, 101, 0o700, "nginx.sock"),
        ("fpm", 82, 82, 0o770, "php-fpm.sock"),
    ):
        directory=Path("/var/lib/conectaeduca-ga08")/name
        if not directory.is_dir() or directory.is_symlink():
            fail("SOCKET_DIR_INVALIDO_"+name)
        st=directory.stat()
        if (st.st_uid,st.st_gid,stat.S_IMODE(st.st_mode))!=(uid,gid,mode):
            fail("SOCKET_DIR_IDENTIDADE_DIVERGENTE_"+name)
        if (directory/sock).exists() or (directory/sock).is_symlink():
            fail("SOCKET_RESIDUAL_REQUER_REVISAO_"+name)
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

def blocked(ip: str, port: int) -> bool:
    try:
        with socket.create_connection((ip, port), timeout=2.0):
            return False
    except (OSError, TimeoutError):
        return True

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

def gates(context: Path, change_id: str) -> dict:
    approval=load_json(context/"approval.json")
    if approval.get("change_id") != change_id:
        fail("APROVACAO_ID_DIVERGENTE")
    for key in ("operator_approved","snapshot_restorable","snapshot_includes_pa05",
                "secrets_recoverable","rollback_approved","outage_window_approved"):
        if approval.get(key) is not True:
            fail("G0_NAO_APROVADO_" + key)
    if approval.get("operator") != "andrea.kiew" or not approval.get("snapshot_ref"):
        fail("G0_OPERADOR_OU_SNAPSHOT_AUSENTE")
    if approval["snapshot_ref"] == "ubuntu.33":
        fail("G0_SNAPSHOT_LEGADO_03_11")
    try:
        when=dt.datetime.fromisoformat(approval["snapshot_created_at"])
    except (TypeError,ValueError,KeyError):
        fail("G0_SNAPSHOT_DATA_INVALIDA")
    if when.tzinfo is None or when.astimezone(dt.timezone.utc) <= MIN_SNAPSHOT.astimezone(dt.timezone.utc):
        fail("G0_SNAPSHOT_ANTERIOR_PA05")
    if len(str(approval.get("restore_evidence", ""))) < 12:
        fail("G0_RETORNO_SEM_EVIDENCIA")
    return approval

def context_path(change_id: str) -> Path:
    if not re.fullmatch(r"PA02-20[0-9]{6}-[A-Z0-9-]{5,45}", change_id):
        fail("CHANGE_ID_INVALIDO")
    return ROOT_CONTEXT / change_id

def prepare(context: Path, change_id: str) -> None:
    socket_roots()
    if context.exists():
        fail("CONTEXTO_CHANGE_ID_JA_EXISTE")
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
        "snapshot_ref":"","snapshot_created_at":"",
        "restore_evidence":"",
        "operator_approved":False,"snapshot_restorable":False,
        "snapshot_includes_pa05":False,"secrets_recoverable":False,
        "rollback_approved":False,"outage_window_approved":False,
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
        if not blocked(network_ip(after["nginx"],"waf_backend"),8080):
            fail("BYPASS_TCP_NGINX_AINDA_ACESSIVEL")
        if not blocked(network_ip(after["php"],"php_egress"),9000):
            fail("BYPASS_TCP_FPM_AINDA_ACESSIVEL")
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

def main()->None:
    parser=argparse.ArgumentParser()
    parser.add_argument("--mode",choices=("prepare","apply","rollback"),required=True)
    parser.add_argument("--change-id",required=True)
    parser.add_argument("--ack",default="")
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
    if args.mode=="apply":
        if args.ack!="APLICAR_PA02_EP125":
            fail("ACK_CUTOVER_AUSENTE")
        gates(context,args.change_id)
        if state.get("status")!="PREPARED":
            fail("STATUS_NAO_E_PREPARED")
        print("G0_DOCUMENTAL=PASS")
        print("OBS_SNAPSHOT_ATTESTADO_POR_OPERADOR_NAO_VERIFICADO_API")
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
