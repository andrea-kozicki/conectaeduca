#!/usr/bin/env python3
from __future__ import annotations
import argparse, datetime as dt, getpass, hashlib, http.client, json, os, re, socket
from pathlib import Path
from urllib.parse import urlsplit

VERSION="1.0.2"
DEFAULT_ADDR="http://127.0.0.1:18200"
DEFAULT_USER="teste"
POLICY_NAME="conectaeduca-human-view"
DEFAULT_POLICY_FILE=(
    Path(__file__).resolve().parents[2]
    / "deploy/interna/openbao/policies/conectaeduca-human-view.hcl"
)
P=W=F=0
LOG=[]

class BaoError(RuntimeError): pass
def emit(s=""): print(s,flush=True); LOG.append(s)
def ok(s):
    global P; P+=1; emit(f"[PASS] {s}")
def warn(s):
    global W; W+=1; emit(f"[WARN] {s}")
def bad(s):
    global F; F+=1; emit(f"[FAIL] {s}")

def ep(addr):
    u=urlsplit(addr.rstrip("/"))
    if u.scheme not in {"http","https"} or not u.hostname or u.username or u.password or u.query or u.fragment or u.path not in {"","/"}:
        raise BaoError("endereço OpenBao inválido")
    return u.scheme,u.hostname,u.port or (443 if u.scheme=="https" else 80)

def api(addr,method,path,payload=None,token=None,expected=(200,204)):
    scheme,host,port=ep(addr); method=method.upper(); safe=path.lstrip("/")
    if method not in {"GET","POST","PUT","DELETE","LIST"} or not safe or ".." in safe.split("/") or not re.fullmatch(r"[A-Za-z0-9._/@-]+",safe):
        raise BaoError("requisição API inválida")
    body=None if payload is None else json.dumps(payload).encode()
    headers={"Accept":"application/json"}
    if payload is not None: headers["Content-Type"]="application/json"
    if token: headers["X-Vault-Token"]=token
    cls=http.client.HTTPSConnection if scheme=="https" else http.client.HTTPConnection
    c=cls(host,port,timeout=10)
    try:
        c.request(method,f"/v1/{safe}",body=body,headers=headers)
        r=c.getresponse(); raw=r.read(); code=r.status
    finally: c.close()
    if code not in expected:
        raise BaoError(f"{method} {path}: HTTP {code}")
    if not raw: return code,{}
    try: return code,json.loads(raw.decode())
    except json.JSONDecodeError: return code,{}

def health(addr):
    code,h=api(addr,"GET","sys/health",expected=(200,429,472,473,501,503))
    emit(f"HEALTH_HTTP={code}")
    emit(f"OPENBAO_STATE=initialized={h.get('initialized')}|sealed={h.get('sealed')}|standby={h.get('standby')}|version={h.get('version')}")
    if h.get("initialized") is True and h.get("sealed") is False: ok("OpenBao initialized e unsealed.")
    else: bad("OpenBao não está initialized+unsealed.")
    return h

def validate_policy(txt):
    active="\n".join(line.split("#",1)[0] for line in txt.splitlines())
    if 'secret/data/' in active: raise BaoError("policy humana não pode conter secret/data/")
    for needle in ('path "sys/health"','path "sys/seal-status"','path "sys/mounts"','path "sys/auth"','path "secret/metadata/conectaeduca"','path "secret/metadata/conectaeduca/*"'):
        if needle not in active: raise BaoError(f"policy incompleta: {needle}")

def finish(mode,edir):
    final="FAIL" if F else ("WARN" if W else "PASS")
    emit(""); emit("=== SUMMARY ==="); emit(f"PASS={P}"); emit(f"WARN={W}"); emit(f"FAIL={F}"); emit(f"FINAL={final}")
    emit("SECRET_VALUES_LOGGED=0"); emit("TOKEN_VALUES_LOGGED=0")
    edir=Path(edir).expanduser(); edir.mkdir(parents=True,exist_ok=True)
    host=socket.gethostname().split(".")[0]; stamp=dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%SZ")
    out=edir/f"conectaeduca-gui01-openbao-{mode}-{host}-{stamp}-pid{os.getpid()}.txt"
    out.write_text("\n".join(LOG)+"\n",encoding="utf-8"); os.chmod(out,0o644)
    d=hashlib.sha256(out.read_bytes()).hexdigest(); sc=Path(str(out)+".sha256")
    sc.write_text(f"{d}  {out.name}\n",encoding="utf-8"); os.chmod(sc,0o644)
    print(f"EVIDENCE_FILE={out}"); print(f"SHA256={d}"); print(f"SHA256_FILE={sc}")
    return 1 if F else 0

def prompt_admin():
    t=getpass.getpass("Token administrativo TEMPORÁRIO OpenBao: ").strip()
    if not t: raise BaoError("token vazio")
    return t
def prompt_pw(confirm=True):
    p=getpass.getpass("Senha userpass (oculta): ")
    if len(p)!=5: raise BaoError("senha acadêmica deve ter exatamente 5 caracteres")
    if confirm and p!=getpass.getpass("Repita a senha: "): raise BaoError("senhas não coincidem")
    return p

def verify_user(addr,user,pw):
    _,x=api(addr,"POST",f"auth/userpass/login/{user}",{"password":pw},expected=(200,))
    a=x.get("auth") or {}; tok=str(a.get("client_token") or ""); policies=list(a.get("policies") or [])
    if not tok: raise BaoError("login não retornou token")
    emit("USER_TOKEN=OCULTO"); emit("USER_POLICIES="+",".join(sorted(policies)))
    if POLICY_NAME not in policies or "root" in policies: raise BaoError("policies inesperadas")
    ok("Login userpass não-root validado.")
    try:
        api(addr,"LIST","secret/metadata/conectaeduca",token=tok,expected=(200,404)); ok("Metadata/list permitida.")
        api(addr,"GET","secret/data/conectaeduca/smtp",token=tok,expected=(403,)); ok("Valor SMTP negado.")
    finally:
        try: api(addr,"POST","auth/token/revoke-self",{},token=tok,expected=(200,204)); ok("Token de teste revogado.")
        except Exception: warn("Não foi possível confirmar revoke-self.")

def mode_check(a):
    emit("=== GUI-01A OPENBAO CHECK ==="); emit(f"VERSION={VERSION}"); emit(f"ADDR={a.addr}"); emit("MODE=READ_ONLY")
    try:
        health(a.addr); api(a.addr,"GET","sys/internal/ui/mounts",expected=(200,)); ok("Endpoint interno da UI respondeu.")
    except Exception as e: bad(f"{type(e).__name__}: {e}")
    return finish("check",a.evidence_dir)

def mode_apply(a):
    emit("=== GUI-01A OPENBAO APPLY ==="); emit(f"VERSION={VERSION}"); emit(f"USERNAME={a.username}"); emit(f"POLICY_FILE={a.policy_file}"); emit("PASSWORD=OCULTA"); emit("ADMIN_TOKEN=OCULTO")
    admin=pw=""
    try:
        health(a.addr); txt=a.policy_file.read_text(encoding="utf-8"); validate_policy(txt); ok("Policy local validada.")
        admin=prompt_admin()
        _,lk=api(a.addr,"GET","auth/token/lookup-self",token=admin,expected=(200,))
        aps=list((lk.get("data") or {}).get("policies") or []); emit("ADMIN_POLICIES="+",".join(sorted(aps)))
        if "root" not in aps: warn("Token não é root; precisa ter permissões administrativas equivalentes.")
        _,auths=api(a.addr,"GET","sys/auth",token=admin,expected=(200,))
        auth_data=auths.get("data") or auths
        userpass=auth_data.get("userpass/")
        if userpass is None:
            api(a.addr,"POST","sys/auth/userpass",{"type":"userpass","description":"Acesso humano WebUI ConectaEduca"},token=admin)
            ok("userpass/ habilitado.")
        elif userpass.get("type") == "userpass":
            ok("userpass/ já existia.")
        else:
            raise BaoError("auth/userpass existe com tipo inesperado")
        api(a.addr,"POST","sys/auth/userpass/tune",{
            "default_lease_ttl":"30m","max_lease_ttl":"2h",
            "user_lockout_config":{"lockout_threshold":"5","lockout_duration":"15m","lockout_counter_reset":"15m","lockout_disable":False}
        },token=admin); ok("TTL e lockout aplicados.")
        api(a.addr,"PUT",f"sys/policies/acl/{POLICY_NAME}",{"policy":txt},token=admin); ok("Policy humana aplicada.")
        pw=prompt_pw()
        api(a.addr,"POST",f"auth/userpass/users/{a.username}",{
            "password":pw,"token_policies":["default",POLICY_NAME],"token_ttl":"30m","token_max_ttl":"2h"
        },token=admin); ok("Usuário criado/atualizado sem registrar senha.")
        verify_user(a.addr,a.username,pw); ok("GUI-01A APPLY concluído.")
    except Exception as e: bad(f"{type(e).__name__}: {e}")
    finally: admin=pw=""
    return finish("apply",a.evidence_dir)

def mode_verify(a):
    emit("=== GUI-01A OPENBAO VERIFY ==="); emit(f"USERNAME={a.username}")
    pw=""
    try: health(a.addr); pw=prompt_pw(False); verify_user(a.addr,a.username,pw)
    except Exception as e: bad(f"{type(e).__name__}: {e}")
    finally: pw=""
    return finish("verify",a.evidence_dir)

def mode_rollback(a):
    emit("=== GUI-01A OPENBAO ROLLBACK ==="); emit(f"USERNAME={a.username}"); emit("ADMIN_TOKEN=OCULTO")
    admin=""
    try:
        health(a.addr); admin=prompt_admin()
        api(a.addr,"DELETE",f"auth/userpass/users/{a.username}",token=admin); ok("Usuário removido.")
        api(a.addr,"DELETE",f"sys/policies/acl/{POLICY_NAME}",token=admin); ok("Policy removida.")
        warn("userpass/ preservado deliberadamente; não desabilitado automaticamente.")
    except Exception as e: bad(f"{type(e).__name__}: {e}")
    finally: admin=""
    return finish("rollback",a.evidence_dir)

def main():
    p=argparse.ArgumentParser(); p.add_argument("mode",choices=("check","apply","verify","rollback"))
    p.add_argument("--addr",default=DEFAULT_ADDR); p.add_argument("--username",default=DEFAULT_USER); p.add_argument("--evidence-dir",default=str(Path.home()))
    p.add_argument("--policy-file",type=Path,default=DEFAULT_POLICY_FILE)
    a=p.parse_args()
    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{2,63}",a.username): raise SystemExit("username inválido")
    a.policy_file=a.policy_file.expanduser().resolve()
    if a.mode == "apply" and not a.policy_file.is_file(): raise SystemExit(f"policy ausente: {a.policy_file}")
    return {"check":mode_check,"apply":mode_apply,"verify":mode_verify,"rollback":mode_rollback}[a.mode](a)
if __name__=="__main__": raise SystemExit(main())
