#!/usr/bin/env python3
"""GA08.30: inspect Unix HTTP socket parent from inside isolated Nginx canary.

A single ephemeral Docker container uses pinned GA08.28 image/config/args,
replacing the entrypoint only with /bin/sh to measure mount namespace before
exec nginx. No network, secrets, host socket bind or production changes.
Do not report raw Docker logs. Diagnostics are sanitized status booleans and
a restricted nginx fatal error category/target.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import runpy
import secrets
import socket
import subprocess
import sys
import time

ROOT=Path("/opt/conectaeduca")
CANARY=ROOT/"scripts/ga08-nginx-canario-ep125.py"
DIFF=ROOT/"scripts/ga08-nginx-entrypoint-isolation-ep125.py"
CANARY_BLOB="c460306bab91c300d0878bc7c1c8a1cf5676a2a7"
DIFF_BLOB="502c475c479aa35d6b4f983bcf4a183bb39b1176"
LABELS={
    "GA08_RUN_DIR":"-d /run",
    "GA08_RUN_WRITABLE":"-w /run",
    "GA08_VAR_RUN_DIR":"-d /var/run",
    "GA08_VAR_RUN_SYMLINK":"-L /var/run",
    "GA08_HTTP_DIR":"-d /run/conectaeduca-http",
    "GA08_HTTP_DIR_WRITABLE":"-w /run/conectaeduca-http",
    "GA08_HTTP_DIR_EXECUTABLE":"-x /run/conectaeduca-http",
    "GA08_FPM_DIR":"-d /run/conectaeduca-fpm",
    "GA08_PID_DIR_WRITABLE":"-w /var/run",
    "GA08_CACHE_DIR_WRITABLE":"-w /var/cache/nginx",
}
# The shell is used only in this disposable network=none container. No files
# or permissions are modified. Error output is intentionally not printed.
SHELL_PROBE = """\
for item in \
  GA08_RUN_DIR:-d:/run \
  GA08_RUN_WRITABLE:-w:/run \
  GA08_VAR_RUN_DIR:-d:/var/run \
  GA08_VAR_RUN_SYMLINK:-L:/var/run \
  GA08_HTTP_DIR:-d:/run/conectaeduca-http \
  GA08_HTTP_DIR_WRITABLE:-w:/run/conectaeduca-http \
  GA08_HTTP_DIR_EXECUTABLE:-x:/run/conectaeduca-http \
  GA08_FPM_DIR:-d:/run/conectaeduca-fpm \
  GA08_PID_DIR_WRITABLE:-w:/var/run \
  GA08_CACHE_DIR_WRITABLE:-w:/var/cache/nginx
do
  key=${item%%:*}
  args=${item#*:}
  test_mode=${args%%:*}
  path=${args#*:}
  if test "$test_mode" "$path"; then echo "$key=SIM"; else echo "$key=NAO"; fi
done
if grep -Eq ' /run/conectaeduca-http ' /proc/self/mountinfo; then
  echo 'GA08_HTTP_MOUNT_PRESENTE=SIM'
else
  echo 'GA08_HTTP_MOUNT_PRESENTE=NAO'
fi
if nginx -t >/dev/null 2>&1; then
  echo 'GA08_NGINX_CONF_TEST=PASS'
else
  echo 'GA08_NGINX_CONF_TEST=FAIL'
fi
exec nginx -g 'daemon off;'
"""

def main() -> int:
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run", action="store_true")
    opts=ap.parse_args()
    print("=== GA08.30 — DIRETORIOS HTTP DO NGINX CANDIDATO ===",flush=True)
    if not opts.run:
        print("MODO=PLANO")
        print("SERVICOS_MODIFICADOS=NAO")
        return 0
    if os.geteuid()==0 or socket.gethostname().split(".")[0] not in ("ep125-pucpr","ep125-pucpr-br"):
        print("GA08_30=BLOCKED_IDENTIDADE")
        return 3
    name="ga08-nginx-paths-"+secrets.token_hex(6)
    created=False
    module=None
    try:
        if any(not p.is_file() or p.is_symlink() for p in (CANARY,DIFF)):
            raise RuntimeError("FONTE_DIAGNOSTICO_INVALIDA")
        module=runpy.run_path(str(CANARY))
        if module["git_blob"](CANARY)!=CANARY_BLOB or module["git_blob"](DIFF)!=DIFF_BLOB:
            raise RuntimeError("FONTE_DIAGNOSTICO_DIVERGENTE")
        direct=runpy.run_path(str(DIFF))
        image=module["preconditions"]()
        argv=module["args"](name,image)
        idx=argv.index(image)
        argv[idx:idx]=["--entrypoint","/bin/sh"]
        argv.extend(["-c",SHELL_PROBE])
        result=module["call"](argv,timeout=60)
        if result.returncode:
            raise RuntimeError("DOCKER_RUN_FALHOU")
        created=True
        print("CANDIDATO_BLOB=PASS")
        print("IMAGE_ATIVA_REUTILIZADA=SIM")
        info={}
        for _ in range(12):
            time.sleep(2)
            info=module["inspect"](name)
            state=info.get("State") or {}
            health=(state.get("Health") or {}).get("Status","none")
            if not state.get("Running") or health in ("healthy","unhealthy"):
                break
        state=info.get("State") or {}
        print("NGINX_RUNNING="+("SIM" if state.get("Running") else "NAO"))
        health=(state.get("Health") or {}).get("Status","none")
        print("NGINX_HEALTH="+(health.upper() if re.fullmatch(r"[a-z]+",health) else "INDETERMINADO"))
        code=state.get("ExitCode")
        print("NGINX_EXIT_CODE="+(str(code) if isinstance(code,int) else "INDETERMINADO"))
        p=module["call"](["docker","logs","--tail","90",name],timeout=12)
        logs=p.stdout+"\n"+p.stderr
        valid=set(LABELS)|{"GA08_HTTP_MOUNT_PRESENTE","GA08_NGINX_CONF_TEST"}
        found={}
        for line in logs.splitlines():
            match=re.fullmatch(r"(GA08_[A-Z0-9_]+)=(SIM|NAO|PASS|FAIL)",line.strip())
            if match and match.group(1) in valid:
                found[match.group(1)]=match.group(2)
        for key in sorted(valid):
            print(key+"="+found.get(key,"NAO_OBSERVADO"))
        category,target=direct["category_and_target"](logs)
        print("ERRO_FATAL_CATEGORIA="+category)
        print("ERRO_FATAL_ALVO="+target)
        path_ready=all(found.get(key)=="SIM" for key in (
            "GA08_HTTP_DIR","GA08_HTTP_DIR_WRITABLE","GA08_HTTP_DIR_EXECUTABLE",
            "GA08_HTTP_MOUNT_PRESENTE"
        ))
        print("HTTP_DIR_PRONTO="+("SIM" if path_ready else "NAO"))
        print("GA08_30="+("PASS_SANDBOX" if state.get("Running") and health=="healthy" and path_ready else "DIAGNOSTICO_CONCLUIDO_COM_FALHA"))
        return 0 if path_ready else 1
    except (OSError,RuntimeError,subprocess.TimeoutExpired) as error:
        reason=str(error)
        if not re.fullmatch(r"[A-Z0-9_]{1,100}",reason):
            reason="ERRO_AMBIENTE"
        print("GA08_30=BLOCKED_"+reason)
        return 3
    finally:
        if created and module is not None:
            p=module["call"](["docker","rm","--force",name],timeout=30)
            print("CANARIO_REMOVIDO="+("SIM" if p.returncode==0 else "NAO"))
        else:
            print("CANARIO_CRIADO=NAO")
        print("MONTAGENS_HOST_TESTADAS=NAO")
        print("DOCKER_COMPOSE_EXECUTADO=NAO")
        print("SERVICOS_PRODUCAO_MODIFICADOS=NAO_POR_ESTE_SCRIPT")
        print("CUTOVER_EXECUTADO=NAO")

if __name__=="__main__":
    sys.exit(main())
