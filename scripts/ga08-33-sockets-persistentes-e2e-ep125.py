#!/usr/bin/env python3
"""GA08.33: multi-check persistent Unix socket E2E test on EP125.

Authorised lab EP125 only. Uses original locally installed Nginx/PHP images,
exact public candidate configurations with ONLY Unix listener path replaced
by a random per-run subdirectory. Two isolated containers run with
--network none, read-only rootfs and matching 101/82 UIDs, binding actual
host FPM/HTTP socket directories with real RW/RO. A third ephemeral PHP CLI
client accesses HTTP over the shared host Unix socket and exercises
/_container_health (static) and /_fpm_ping (Nginx -> FPM).

Each run has unique, unguessable subdirs under the pre-existing designated
host socket mount roots and removes ONLY its own files/dirs with the same
container UID/GID. Never touches nginx.sock/php-fpm.sock at root, host config,
secret paths, baseline Compose or production containers. No broad rm, sudo,
network, TLS trust assumptions, or automatic live cutover. Failure in cleanup
is FAIL and requires operator review; do not rerun blindly.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import secrets
import socket
import stat
import subprocess
import sys
import tempfile
import time

ROOT = Path("/opt/conectaeduca")
N_CONF = ROOT / "deploy/dmz/ga08/app-http.dual-socket.candidate.conf"
P_CONF = ROOT / "deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf"
HOST_HTTP = Path("/var/lib/conectaeduca-ga08/http")
HOST_FPM = Path("/var/lib/conectaeduca-ga08/fpm")
TARGET_HTTP = "/run/conectaeduca-http"
TARGET_FPM = "/run/conectaeduca-fpm"
N_CONTAINER = "conectaeduca-dmz-nginx-1"
P_CONTAINER = "conectaeduca-dmz-php-1"
BLOBS = {
    N_CONF: "d659dcabf1123c1b8b4b38bc4b381bf34a0d34f2",
    P_CONF: "a1f3f8212f754f005473d8ad2d5d49bfcc5514a1",
}
WAF_NAME = "conectaeduca-dmz-waf-1"
OWNER = ((HOST_HTTP, 101, 101, 0o700), (HOST_FPM, 82, 82, 0o770))

def run(args: list[str], timeout: int = 25) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, check=False, timeout=timeout)

def blob(path: Path) -> str:
    data = path.read_bytes()
    import hashlib
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()

def docker_inspect(name: str) -> dict:
    p = run(["docker", "inspect", name])
    if p.returncode:
        raise RuntimeError("DOCKER_INSPECT")
    data = json.loads(p.stdout)
    if not isinstance(data, list) or len(data) != 1:
        raise RuntimeError("DOCKER_FORMATO")
    return data[0]

def baseline() -> tuple[str, str]:
    images = {}
    for role, name in (("nginx", N_CONTAINER), ("php", P_CONTAINER), ("waf", WAF_NAME)):
        data = docker_inspect(name)
        cfg = data.get("Config") or {}
        labels = cfg.get("Labels") or {}
        state = data.get("State") or {}
        if (labels.get("com.docker.compose.project") != "conectaeduca-dmz"
                or labels.get("com.docker.compose.service") != role
                or state.get("Running") is not True
                or (state.get("Health") or {}).get("Status") != "healthy"):
            raise RuntimeError("BASELINE_NAO_SAUDAVEL_" + role.upper())
        image = data.get("Image")
        if not isinstance(image, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", image):
            raise RuntimeError("IMAGE_ID_INVALIDO")
        images[role] = image
    print("BASELINE_3_3_HEALTHY=PASS")
    return images["nginx"], images["php"]

def check_inputs() -> None:
    if os.geteuid() == 0 or socket.gethostname().split(".")[0] not in (
        "ep125-pucpr", "ep125-pucpr-br"
    ):
        raise RuntimeError("HOST_IDENTIDADE")
    if os.environ.get("GA08_ENABLE_LIVE_CHANGE") == "YES":
        raise RuntimeError("INTERLOCK_LIVE_ATIVO")
    for path, expected in BLOBS.items():
        if path.is_symlink() or not path.is_file() or blob(path) != expected:
            raise RuntimeError("CONFIG_CANDIDATA_DIVERGENTE")
        if not stat.S_IMODE(path.stat().st_mode) & stat.S_IROTH:
            raise RuntimeError("CONFIG_MODO_NAO_LEGIVEL")
    for path, uid, gid, mode in OWNER:
        if path.is_symlink() or not path.is_dir():
            raise RuntimeError("BIND_HOST_INVALIDO")
        s = path.stat()
        if (s.st_uid, s.st_gid, stat.S_IMODE(s.st_mode)) != (uid, gid, mode):
            raise RuntimeError("BIND_HOST_PERMISSOES")
    print("CANDIDATOS_BLOB=PASS")
    print("DIRETORIOS_HOST_UID_GID_MODO=PASS")

def temp_config(source: Path, old: str, new: str, expected: int) -> Path:
    text = source.read_text(encoding="utf-8")
    if text.count(old) != expected:
        raise RuntimeError("CONFIG_ALVO_INESPERADO")
    fd, path = tempfile.mkstemp(prefix="ga08-33-", suffix=".conf")
    try:
        os.fchmod(fd, 0o644)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text.replace(old, new))
            f.flush()
            os.fsync(f.fileno())
    except BaseException:
        try:
            os.unlink(path)
        except OSError:
            pass
        raise
    return Path(path)

def mounts(image: str, container: str, config: Path, config_target: str,
           uid: int, group: list[str], write_dir: str, other_dir: str,
           host_write: Path, host_other: Path, listener: str,
           mkdir_mode: str, program: str, health: str) -> list[str]:
    # One RW bind to own designated host socket root; the opposite socket
    # root is always RO. No secrets or other host mounts.
    args = [
        "docker", "run", "-d", "--pull", "never", "--name", container,
        "--network", "none", "--read-only", "--user", f"{uid}:{uid}",
        "--cap-drop", "ALL", "--security-opt", "no-new-privileges:true",
        "--pids-limit", "128", "--memory", "384m", "--restart", "no",
        "--tmpfs", ("/run:rw,nosuid,nodev,noexec,size=4m,uid=101,gid=101,mode=0750"
                    if uid == 101 else
                    "/run:rw,nosuid,nodev,noexec,size=4m,uid=82,gid=82,mode=0770"),
        "--tmpfs", "/tmp:rw,nosuid,nodev,noexec,size=64m,uid=82,gid=82,mode=1770",
        "--mount", f"type=bind,src={config},dst={config_target},readonly",
        "--mount", f"type=bind,src={host_write},dst={write_dir}",
        "--mount", f"type=bind,src={host_other},dst={other_dir},readonly",
        "--health-cmd", health, "--health-interval", "2s",
        "--health-timeout", "2s", "--health-retries", "4",
        "--health-start-period", "3s",
    ]
    if uid == 101:
        args.extend([
            "--tmpfs", "/var/cache/nginx:rw,nosuid,nodev,noexec,size=16m,uid=101,gid=101,mode=0750",
            "--group-add", "82",
        ])
    else:
        args.extend([
            "--tmpfs", "/var/www/conectaeduca/storage/logs:rw,nosuid,nodev,noexec,size=32m,uid=82,gid=82,mode=0770",
            "--tmpfs", "/var/www/conectaeduca/storage/keys:rw,nosuid,nodev,noexec,size=4m,uid=82,gid=82,mode=0770",
        ])
    directory = listener.rsplit("/", 1)[0]
    flag = "N_CRIADO" if uid == 101 else "P_CRIADO"
    shell = (
        "set -eu; "
        + "mkdir -m " + mkdir_mode + " '" + directory + "'; "
        + "echo " + flag + "=SIM; "
        + "exec " + program
    )
    args.extend(["--entrypoint", "/bin/sh", image, "-c", shell])
    return args

def wait(name: str, label: str) -> bool:
    data = None
    for _ in range(12):
        time.sleep(2)
        data = docker_inspect(name)
        state = data.get("State") or {}
        health = (state.get("Health") or {}).get("Status", "none")
        if not state.get("Running") or health in ("healthy", "unhealthy"):
            break
    state = (data or {}).get("State") or {}
    running = state.get("Running") is True
    healthy = (state.get("Health") or {}).get("Status") == "healthy"
    print(label + "_RUNNING=" + ("PASS" if running else "FAIL"))
    print(label + "_HEALTHY=" + ("PASS" if healthy else "FAIL"))
    return running and healthy

def marker_created(container: str, code: str) -> bool:
    p = run(["docker", "logs", "--tail", "50", container], timeout=12)
    return any(line.strip() == code + "=SIM" for line in p.stdout.splitlines())

def socket_present(container: str, path: str, label: str) -> bool:
    p = run(["docker", "exec", container, "test", "-S", path], timeout=12)
    ok = p.returncode == 0
    print(label + "=" + ("PASS" if ok else "FAIL"))
    return ok

def php_client(image: str, http_socket: str) -> bool:
    # Static request and internal FPM ping, over the real HTTP host bind RO;
    # no TCP/DNS/network or application credentials.
    php = r'''
    $sock = $argv[1];
    $tests = ["/_container_health" => "ok", "/_fpm_ping" => "pong"];
    $good = true;
    foreach ($tests as $uri => $expect) {
        $fd = @stream_socket_client("unix://" . $sock, $errnum, $errstr, 4);
        if (!$fd) {
            echo ($uri === "/_fpm_ping" ? "FASTCGI_PING" : "HTTP_STATIC") . "=FAIL\n";
            $good = false; continue;
        }
        stream_set_timeout($fd, 5);
        fwrite($fd, "GET " . $uri . " HTTP/1.1\r\nHost: conectaeduca.local\r\nConnection: close\r\n\r\n");
        $raw = stream_get_contents($fd, 16384);
        fclose($fd);
        $pass = (str_starts_with($raw, 'HTTP/1.1 200') || str_starts_with($raw, 'HTTP/1.0 200')) &&
                strpos($raw, $expect) !== false;
        echo ($uri === "/_fpm_ping" ? "FASTCGI_PING" : "HTTP_STATIC") . "=" . ($pass ? "PASS" : "FAIL") . "\n";
        $good = $good && $pass;
    }
    exit($good ? 0 : 1);
    '''
    args = [
        "docker", "run", "--rm", "--pull", "never",
        "--network", "none", "--read-only", "--user", "101:101",
        "--cap-drop", "ALL", "--security-opt", "no-new-privileges:true",
        "--pids-limit", "64", "--memory", "128m",
        "--mount", f"type=bind,src={HOST_HTTP},dst={TARGET_HTTP},readonly",
        "--entrypoint", "php", image,
        "-r", php, "--", http_socket,
    ]
    p = run(args, timeout=35)
    found = {}
    for line in p.stdout.splitlines():
        m = re.fullmatch(r"(HTTP_STATIC|FASTCGI_PING)=(PASS|FAIL)", line.strip())
        if m:
            found[m.group(1)] = m.group(2)
    for key in ("HTTP_STATIC", "FASTCGI_PING"):
        print(key + "=" + found.get(key, "NAO_OBSERVADO"))
    return p.returncode == 0 and all(found.get(k) == "PASS" for k in (
        "HTTP_STATIC", "FASTCGI_PING"
    ))

def cleanup(name: str, host: Path, target: str, subdir: str,
            filename: str, uid: int, image: str, permitted: bool) -> bool:
    if not permitted:
        print("LIMPEZA_" + ("HTTP" if uid == 101 else "FPM") + "=NAO_NECESSARIA")
        return True
    target_dir = target + "/" + subdir
    # Never remove any unknown file, and never rm -r. Own mkdir generated
    # a cryptographically unique subdir, under a pinned host socket root.
    command = (
        "set -eu; p='" + target_dir + "'; "
        "test -d \"$p\" && test ! -L \"$p\"; "
        "file=\"$p/" + filename + "\"; "
        'if test -e "$file"; then test -S "$file"; rm -f "$file"; fi; '
        'rmdir "$p";'
    )
    p = run([
        "docker", "run", "--rm", "--pull", "never",
        "--network", "none", "--read-only", "--user", f"{uid}:{uid}",
        "--cap-drop", "ALL", "--security-opt", "no-new-privileges:true",
        "--mount", f"type=bind,src={host},dst={target}",
        "--entrypoint", "/bin/sh", image, "-c", command,
    ], timeout=40)
    success = p.returncode == 0
    print("LIMPEZA_" + ("HTTP" if uid == 101 else "FPM") + "=" + ("PASS" if success else "FAIL"))
    return success

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    opts = parser.parse_args()
    print("=== GA08.33 — BATERIA HOST BIND RW + E2E UNIX SEM REDE ===", flush=True)
    if not opts.run:
        print("MODO=PLANO")
        print("DOCKER_EXECUTADO=NAO")
        return 0
    stamp = secrets.token_hex(8)
    subdir = "ga08check-" + stamp
    npath = TARGET_HTTP + "/" + subdir + "/http.sock"
    ppath = TARGET_FPM + "/" + subdir + "/fpm.sock"
    nname, pname = "ga08-33-ng-" + stamp, "ga08-33-php-" + stamp
    nimage = pimage = ""
    nconf = pconf = None
    launched: list[str] = []
    ncreated = pcreated = False
    result_code = 3
    try:
        check_inputs()
        nimage, pimage = baseline()
        nconf = temp_config(
            N_CONF, "listen unix:/run/conectaeduca-http/nginx.sock;",
            "listen unix:" + npath + ";", 1
        )
        nginx_text = nconf.read_text(encoding="utf-8")
        old_fpm = "fastcgi_pass unix:/run/conectaeduca-fpm/php-fpm.sock;"
        if nginx_text.count(old_fpm) != 6:
            raise RuntimeError("NGINX_FPM_OCORRENCIAS_DIVERGENTES")
        nconf.write_text(nginx_text.replace(
            old_fpm, "fastcgi_pass unix:" + ppath + ";"
        ), encoding="utf-8")
        pconf = temp_config(
            P_CONF, "listen = /run/conectaeduca-fpm/php-fpm.sock",
            "listen = " + ppath, 1
        )
        print("CONFIGS_TEMP_DIFERENCA_SOMENTE_SOCKETS=PASS")
        php_args = mounts(
            pimage, pname, pconf,
            "/usr/local/etc/php-fpm.d/zz-conectaeduca.conf",
            82, [], TARGET_FPM, TARGET_HTTP, HOST_FPM, HOST_HTTP,
            ppath, "750", "php-fpm -F",
            "php-fpm -t >/dev/null 2>&1 && test -S " + ppath,
        )
        p = run(php_args, timeout=60)
        if p.returncode:
            raise RuntimeError("PHP_CANARIO_START")
        launched.append(pname)
        pcreated = marker_created(pname, "P_CRIADO")
        print("FPM_SUBDIR_EXCLUSIVO=" + ("PASS" if pcreated else "FAIL"))
        if not pcreated:
            raise RuntimeError("FPM_MKDIR_FALHOU")
        fpm_live = wait(pname, "FPM_REAL_BIND")
        fpm_sock = socket_present(pname, ppath, "FPM_SOCKET_REAL_RW")
        if not fpm_live or not fpm_sock:
            raise RuntimeError("FPM_CANARIO_NAO_SAUDAVEL")
        nginx_args = mounts(
            nimage, nname, nconf, "/etc/nginx/conf.d/default.conf",
            101, ["82"], TARGET_HTTP, TARGET_FPM, HOST_HTTP, HOST_FPM,
            npath, "700", "nginx -g 'daemon off;'",
            "nginx -t >/dev/null 2>&1 && test -S " + npath,
        )
        p = run(nginx_args, timeout=60)
        if p.returncode:
            raise RuntimeError("NGINX_CANARIO_START")
        launched.append(nname)
        ncreated = marker_created(nname, "N_CRIADO")
        print("HTTP_SUBDIR_EXCLUSIVO=" + ("PASS" if ncreated else "FAIL"))
        if not ncreated:
            raise RuntimeError("HTTP_MKDIR_FALHOU")
        n_live = wait(nname, "NGINX_REAL_BIND")
        n_sock = socket_present(nname, npath, "HTTP_SOCKET_REAL_RW")
        fpm_visible = socket_present(nname, ppath, "NGINX_LE_FPM_SOCKET_RO")
        if not n_live or not n_sock or not fpm_visible:
            raise RuntimeError("NGINX_CANARIO_NAO_SAUDAVEL")
        client_ok = php_client(pimage, npath)
        print("UNIX_E2E_ISOLADO=" + ("PASS" if client_ok else "FAIL"))
        result_code = 0 if client_ok else 1
    except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        msg = str(error)
        print("GA08_33=BLOCKED_" +
              (msg if re.fullmatch(r"[A-Z0-9_]{1,95}", msg) else "ERRO_INDETERMINADO"))
        result_code = 3
    finally:
        for name in reversed(launched):
            try:
                p = run(["docker", "rm", "--force", name], timeout=35)
                print("CANARIO_" + ("NGINX" if name == nname else "PHP") +
                      "_REMOVIDO=" + ("PASS" if p.returncode == 0 else "FAIL"))
                if p.returncode:
                    result_code = 1
            except (OSError, subprocess.TimeoutExpired):
                print("CANARIO_REMOCAO=FAIL")
                result_code = 1
        if nimage and pimage:
            for image, host, target, filename, uid, created in (
                (nimage, HOST_HTTP, TARGET_HTTP, "http.sock", 101, ncreated),
                (pimage, HOST_FPM, TARGET_FPM, "fpm.sock", 82, pcreated),
            ):
                try:
                    if not cleanup("", host, target, subdir, filename, uid, image, created):
                        result_code = 1
                except (OSError, subprocess.TimeoutExpired):
                    print("LIMPEZA_PERSISTENTE=FAIL")
                    result_code = 1
        for file in (nconf, pconf):
            if file and file.exists():
                try:
                    file.unlink()
                except OSError:
                    print("CONFIG_TEMP_LIMPEZA=FAIL")
                    result_code = 1
        print("GA08_33=" + ("PASS_E2E_UNIX_ISOLADO" if result_code == 0 else "FAIL_VER_MARCADORES"))
        print("PA02_FECHADO=NAO")
        print("DOCKER_COMPOSE_EXECUTADO=NAO")
        print("REDE_DOCKER_USADA=NAO")
        print("SERVICOS_PRODUCAO_MODIFICADOS=NAO_POR_ESTE_SCRIPT")
        print("CUTOVER_EXECUTADO=NAO")
    return result_code

if __name__ == "__main__":
    sys.exit(main())
