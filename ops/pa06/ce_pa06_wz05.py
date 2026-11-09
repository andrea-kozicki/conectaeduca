#!/usr/bin/env python3
"""CE-PA06-WZ05: corrige 80710 preservando alertas de ativacao real.

--preflight: somente leitura.
--apply: nova regra em volume /var/ossec/etc, logtest antes de reiniciar,
         reinicia SOMENTE manager Wazuh, health e rollback best-effort.
Nao usa sudo, nao edita ruleset de fabrica, nao imprime logs/segredos.
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
import stat
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

MANAGER="conectaeduca-wazuh-wazuh.manager-1"
VERSION="wazuh/wazuh-manager:4.14.7"
RULE_ORIG="/var/ossec/ruleset/rules/0365-auditd_rules.xml"
RULE_DIR="/var/ossec/etc/rules"
RULE_NEW=RULE_DIR+"/ce_pa06_80710_promisc.xml"
BASE=Path("/home/andrea.kiew/.local/share/conectaeduca/pa06")
SERVICES={"manager":MANAGER,
          "dashboard":"conectaeduca-wazuh-wazuh.dashboard-1",
          "indexer":"conectaeduca-wazuh-wazuh.indexer-1"}
EVENTS={
 "ATIVACAO":("0","256"),
 "DESATIVACAO":("256","0"),
 "SEM_TRANSICAO":("256","256"),
}
RULE_PATTERN=re.compile(r"(?m)^\s*id:\s*['\"]?(\d+)")
FIELD_PATTERN=r"(?m)^\s*{key}:\s*['\"]?([^'\"\r\n]+)"
class Abort(Exception):
    pass

def abort(marker: str) -> None:
    raise Abort(marker)

def cmd(args:list[str], *, input_text:str|None=None, timeout:int=45,
        quiet:bool=False) -> str:
    try:
        p=subprocess.run(args,input=input_text,text=True,capture_output=True,
                         timeout=timeout,check=False)
    except (OSError,subprocess.TimeoutExpired):
        abort("COMANDO_INDISPONIVEL")
    if p.returncode:
        abort("COMANDO_FALHOU_"+args[0])
    return p.stdout if not quiet else ""

def docker(*args:str,timeout:int=45) -> str:
    return cmd(["docker",*args],timeout=timeout)

def manager_health() -> dict:
    for name,container in SERVICES.items():
        data=json.loads(docker("inspect",container))[0]
        state=data.get("State") or {}
        if (state.get("Running") is not True or
            (state.get("Health") or {}).get("Status")!="healthy"):
            abort("WAZUH_"+name.upper()+"_NAO_HEALTHY")
        if name=="manager":
            if data.get("Config",{}).get("Image")!=VERSION:
                abort("IMAGEM_MANAGER_DIVERGENTE")
            mounts=data.get("Mounts") or []
            if not any(m.get("Destination")=="/var/ossec/etc"
                       and m.get("Type")=="volume" and m.get("RW") is True
                       for m in mounts):
                abort("ETC_VOLUME_PERSISTENTE_AUSENTE")
    return data

def rule_source() -> ET.Element:
    raw=docker("exec",MANAGER,"cat",RULE_ORIG)
    try:
        root=ET.fromstring(raw)
    except ET.ParseError:
        abort("RULESET_XML_INVALIDO")
    found=root.findall(".//rule[@id='80710']")
    if len(found)!=1:
        abort("REGRA80710_NAO_UNICA")
    rule=found[0]
    if (rule.get("level")!="10" or
        rule.findtext("if_sid")!="80700" or
        rule.findtext("match")!="prom=256" or
        not any(x.get("name")=="audit.type" and
                (x.text or "").strip()=="ANOM_PROMISCUOUS"
                for x in rule.findall("field"))):
        abort("REGRA80710_BASELINE_DIVERGENTE")
    return rule

def no_previous_override()->None:
    paths=docker("exec",MANAGER,"find",RULE_DIR,
                 "-maxdepth","1","-type","f","-name","*.xml").splitlines()
    if not paths:
        abort("REGRAS_LOCAIS_AUSENTES")
    for path in paths:
        if not path.startswith(RULE_DIR+"/") or "\n" in path:
            abort("CAMINHO_REGRA_LOCAL_INVALIDO")
        txt=docker("exec",MANAGER,"cat",path)
        try:
            xml=ET.fromstring(txt)
        except ET.ParseError:
            abort("REGRA_LOCAL_XML_INVALIDO")
        if xml.findall(".//rule[@id='80710']"):
            abort("OVERRIDE_80710_JA_EXISTE")
    proc=subprocess.run(["docker","exec",MANAGER,"test","!","-e",RULE_NEW],
                        capture_output=True,timeout=20,check=False)
    if proc.returncode:
        abort("DESTINO_OVERRIDE_JA_EXISTE")
    print("REGRA80710_OVERRIDE_EXISTENTE=NAO",flush=True)

def field(text:str,key:str)->str|None:
    m=re.search(FIELD_PATTERN.format(key=re.escape(key)),text)
    return m.group(1).strip() if m else None

def probe(name:str, old:str, new:str) -> str:
    event=("type=ANOM_PROMISCUOUS msg=audit(1390181243.575:738): "
           f"dev=vethCEtest prom={new} old_prom={old} "
           "auid=4294967295 uid=0 gid=0 ses=4294967295")
    p=subprocess.run(["docker","exec","-i",MANAGER,
                      "/var/ossec/bin/wazuh-logtest","-v"],
                     input=event+"\n\n",text=True,capture_output=True,
                     timeout=55,check=False)
    if p.returncode:
        abort("LOGTEST_EXECUCAO_FALHOU_"+name)
    out=p.stdout+"\n"+p.stderr
    if ("Phase 2:" not in out or
        field(out,"audit.prom")!=new or
        field(out,"audit.old_prom")!=old):
        abort("LOGTEST_DECODER_INCONCLUSIVO_"+name)
    ids=RULE_PATTERN.findall(out)
    result=ids[-1] if ids else "NENHUMA"
    print("LOGTEST_"+name+"_RULE_ID="+result,flush=True)
    return result

def baseline()->None:
    manager_health()
    print("WAZUH_3_SERVICOS=HEALTHY",flush=True)
    rule_source()
    print("REGRA80710_ORIGINAL=CONFIRMADA",flush=True)
    no_previous_override()
    act=probe("ATIVACAO",*EVENTS["ATIVACAO"])
    deact=probe("DESATIVACAO",*EVENTS["DESATIVACAO"])
    stay=probe("SEM_TRANSICAO",*EVENTS["SEM_TRANSICAO"])
    if act!="80710":
        abort("BASELINE_ATIVACAO_NAO_DETECTADA")
    if deact!="80710":
        abort("BASELINE_FALSO_POSITIVO_NAO_REPRODUZIDO")
    if stay!="80710":
        print("BASELINE_SEM_TRANSICAO_NAO_GERA_80710=SIM")
    print("BASELINE_FALSO_POSITIVO=REPRODUZIDO",flush=True)

def make_xml(rule:ET.Element)->bytes:
    import copy
    patch=copy.deepcopy(rule)
    patch.set("overwrite","yes")
    for match in list(patch.findall("match")):
        patch.remove(match)
    for key,pattern in (("audit.prom","^256$"),
                        ("audit.old_prom","^0$")):
        e=ET.SubElement(patch,"field",{"name":key,"type":"pcre2"})
        e.text=pattern
    group=ET.Element("group",{"name":"audit,"})
    group.append(patch)
    raw=ET.tostring(group,encoding="utf-8",xml_declaration=True)
    test=ET.fromstring(raw)
    assert len(test.findall(".//rule[@id='80710']"))==1
    return raw

def health_wait(seconds:int=130)->bool:
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        try:
            d=json.loads(docker("inspect",MANAGER,timeout=12))[0]
            st=d.get("State",{})
            if (st.get("Running") is True and
                (st.get("Health") or {}).get("Status")=="healthy"):
                return True
        except (Abort,ValueError,KeyError):
            pass
        time.sleep(4)
    return False

def remove_own_file()->bool:
    # Testa sempre que o arquivo exato existe antes de remover.
    p=subprocess.run(["docker","exec","-u","0",MANAGER,
                      "rm","-f",RULE_NEW],capture_output=True,
                     text=True,timeout=35,check=False)
    return p.returncode==0

def restore_after_failure()->None:
    print("ROLLBACK_CONFIGURACAO=INICIADO",flush=True)
    try:
        removed=remove_own_file()
        print("ROLLBACK_REGRA_REMOVIDA="+("SIM" if removed else "NAO"))
        if removed:
            try:
                docker("restart","--time","20",MANAGER,timeout=100)
                print("ROLLBACK_RESTART_MANAGER=EXECUTADO")
                if health_wait():
                    print("ROLLBACK_MANAGER_HEALTHY=SIM")
                    print("ROLLBACK_ESTADO=RECUPERADO")
                else:
                    print("ROLLBACK_ESTADO=INCOMPLETO")
            except (Abort,OSError):
                print("ROLLBACK_ESTADO=INCOMPLETO")
        else:
            print("ROLLBACK_ESTADO=INCOMPLETO")
    except (OSError,subprocess.TimeoutExpired):
        print("ROLLBACK_ESTADO=INCOMPLETO")

def apply()->None:
    # Preflight estrito que confirma evento nao-ativacao falsamente alertado.
    baseline()
    raw=make_xml(rule_source())
    BASE.mkdir(parents=True,exist_ok=True,mode=0o700)
    if BASE.is_symlink() or BASE.stat().st_uid!=os.geteuid() or stat.S_IMODE(BASE.stat().st_mode)!=0o700:
        abort("PASTA_EVIDENCIAS_INSEGURA")
    dest=BASE/("WZ05-"+dt.datetime.now().strftime("%Y%m%d-%H%M%S"))
    dest.mkdir(mode=0o700)
    path=dest/"ce_pa06_80710_promisc.xml"
    fd=os.open(path,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
    with os.fdopen(fd,"wb") as output:
        output.write(raw)
    print("OVERRIDE_SHA256="+hashlib.sha256(raw).hexdigest())
    print("BACKUP_REGRAS_PADRAO=RULESET_ORIGINAL_INTACTO")
    installed=False
    restarted=False
    try:
        # A copia pode falhar APOS criar um arquivo parcial no destino.
        # Marcamos a tentativa antes do comando para sempre tentar limpeza.
        installed=True
        docker("cp",str(path),MANAGER+":"+RULE_NEW,timeout=60)
        docker("exec","-u","0",MANAGER,"chmod","0644",RULE_NEW)
        sha=docker("exec",MANAGER,"sha256sum",RULE_NEW).strip().split()[0]
        if sha!=hashlib.sha256(raw).hexdigest():
            abort("OVERRIDE_INTEGRIDADE_FALHOU")
        print("OVERRIDE_PERSISTENTE_INSTALADO=SIM")
        print("OVERRIDE_SHA256_CONTAINER=PASS")
        a=probe("ATIVACAO",*EVENTS["ATIVACAO"])
        d=probe("DESATIVACAO",*EVENTS["DESATIVACAO"])
        s=probe("SEM_TRANSICAO",*EVENTS["SEM_TRANSICAO"])
        if a!="80710" or d=="80710" or s=="80710":
            abort("REGRESSAO_PERSISTENTE_LOGTEST_REPROVADA")
        print("REGRESSAO_LOGTEST_3_CASOS=PASS")
        docker("restart","--time","20",MANAGER,timeout=100)
        restarted=True
        print("RESTART_SOMENTE_MANAGER=EXECUTADO")
        if not health_wait():
            abort("MANAGER_NAO_HEALTHY_APOS_RESTART")
        # Reconfirmar que os indices e dashboard continuam saudaveis.
        manager_health()
        print("WAZUH_3_SERVICOS_POS_RESTART=HEALTHY")
        a=probe("ATIVACAO",*EVENTS["ATIVACAO"])
        d=probe("DESATIVACAO",*EVENTS["DESATIVACAO"])
        s=probe("SEM_TRANSICAO",*EVENTS["SEM_TRANSICAO"])
        if a!="80710" or d=="80710" or s=="80710":
            abort("REGRESSAO_POS_RESTART_REPROVADA")
        print("REGRESSAO_POS_RESTART=PASS")
        print("SNAPSHOT_VM_REALIZADO=NAO")
        print("ALERTAS_REAIS_POS_RESTART=AINDA_NAO_MEDIDOS")
        print("CE-PA06-WZ05_IMPLANTADO")
    except BaseException:
        if installed:
            restore_after_failure()
        raise

def main()->None:
    os.umask(0o077)
    print("=== CE-PA06-WZ05 — REGRA 80710 FAIL-CLOSED ===")
    print("DATA="+dt.datetime.now().astimezone().isoformat(timespec="seconds"))
    p=argparse.ArgumentParser()
    group=p.add_mutually_exclusive_group(required=True)
    group.add_argument("--preflight",action="store_true")
    group.add_argument("--apply",action="store_true")
    args=p.parse_args()
    if os.geteuid()==0 or cmd(["whoami"]).strip()!="andrea.kiew" or socket.gethostname().split(".")[0]!="ep126-pucpr-br":
        abort("IDENTIDADE_OU_HOST_INCORRETO")
    if args.preflight:
        baseline()
        print("SERVICOS_MODIFICADOS=NAO")
        print("CE-PA06-WZ05_PREFLIGHT_PASS")
    else:
        apply()

if __name__=="__main__":
    try:
        main()
    except Abort as e:
        print("CE-PA06-WZ05_ABORTADO="+str(e),file=sys.stderr)
        sys.exit(1)
    except (OSError,ValueError,KeyError,ET.ParseError,subprocess.TimeoutExpired) as e:
        print("CE-PA06-WZ05_ABORTADO="+type(e).__name__,file=sys.stderr)
        sys.exit(1)
