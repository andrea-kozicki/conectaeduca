#!/usr/bin/env python3
"""CE-PA02-ISO02-DIAG: diagnostico somente leitura dos digests do Docker save.

Nao executa docker run/load/save, nao le conteudos de secrets e nao altera
backup ou containers. Reporta somente 12 caracteres de digests para comparar.
"""
from __future__ import annotations

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
import tarfile

BACKUP=Path("/home/andrea.kiew/.local/share/conectaeduca/pa02-recovery/CE-PA02-RC01-20261108-183146")
PROJECT="conectaeduca-dmz"
SERVICES=("php","nginx","waf")

def abort(code: str) -> None:
    print("CE-PA02-ISO02_ABORTADO="+code, file=sys.stderr)
    raise SystemExit(1)

def call(args: list[str]) -> str:
    try:
        out=subprocess.run(args,capture_output=True,text=True,timeout=35)
    except (OSError,subprocess.TimeoutExpired):
        abort("DOCKER_INDISPONIVEL")
    if out.returncode:
        abort("COMANDO_FALHOU")
    return out.stdout.strip()

def image_info(service: str) -> tuple[str,str]:
    ids=call(["docker","ps","-q",
        "-f","label=com.docker.compose.project="+PROJECT,
        "-f","label=com.docker.compose.service="+service]).splitlines()
    if len(ids)!=1:
        abort("SERVICO_NAO_UNICO_"+service)
    data=json.loads(call(["docker","inspect",ids[0]]))[0]
    if data["State"].get("Running") is not True or (data["State"].get("Health") or {}).get("Status")!="healthy":
        abort("SERVICO_NAO_HEALTHY_"+service)
    ref=data["Config"]["Image"]
    iid=data["Image"]
    if not re.fullmatch(r"sha256:[a-f0-9]{64}",iid):
        abort("IMAGE_ID_INVALIDO_"+service)
    if call(["docker","image","inspect",ref,"--format","{{.Id}}"])!=iid:
        abort("TAG_DIVERGENTE_"+service)
    return ref,iid

def main() -> None:
    print("=== CE-PA02-ISO02 — DIAGNOSTICO DIGESTS DOCKER ===")
    print("DATA="+dt.datetime.now().astimezone().isoformat(timespec="seconds"))
    if sys.argv[1:]!=["--diagnose"]:
        abort("EXIGE_--diagnose")
    if os.geteuid()==0 or call(["whoami"])!="andrea.kiew":
        abort("IDENTIDADE_INCORRETA")
    if socket.gethostname().split(".")[0] not in ("ep125-pucpr","ep125-pucpr-br"):
        abort("HOST_INCORRETO")
    if BACKUP.is_symlink() or not BACKUP.is_dir() or stat.S_IMODE(BACKUP.stat().st_mode)!=0o700:
        abort("BACKUP_PASTA_INVALIDA")
    archive=BACKUP/"docker-images.tar.gz"
    if archive.is_symlink() or not archive.is_file() or stat.S_IMODE(archive.stat().st_mode)!=0o600:
        abort("BACKUP_ARQUIVO_INVALIDO")
    service_info={name:image_info(name) for name in SERVICES}
    print("PRODUCAO_3_SERVICOS=HEALTHY")
    driver="DESCONHECIDO"
    try:
        status=json.loads(call(["docker","info","--format","{{json .DriverStatus}}"]))
        if "io.containerd.snapshotter.v1" in json.dumps(status):
            driver="CONTAINERD"
        elif status:
            driver="OUTRO"
    except (ValueError,SystemExit):
        driver="INDETERMINADO"
    print("ARMAZENAMENTO_IMAGENS="+driver)

    # Docker save classico: Config SHA de config JSON; o image ID do
    # containerd pode usar identificador diferente (manifest/index).
    hashes: dict[str,str]={}
    manifest=None
    count=0
    try:
        with tarfile.open(archive,mode="r|gz") as tf:
            for item in tf:
                count+=1
                if count>100000:
                    abort("TAR_ENTRADAS_EXCESSIVAS")
                if not item.isfile():
                    continue
                if item.name.startswith("/") or ".." in Path(item.name).parts:
                    abort("TAR_NOME_INVALIDO")
                if item.name!="manifest.json" and not (
                    item.name.endswith(".json") or re.fullmatch(r"blobs/sha256/[a-f0-9]{64}",item.name)):
                    continue
                if item.size>2*1024*1024:
                    continue
                fd=tf.extractfile(item)
                if fd is None:
                    abort("TAR_META_ILEGIVEL")
                data=fd.read(2*1024*1024+1)
                if len(data)!=item.size:
                    abort("TAR_META_TRUNCADO")
                hashes[item.name]=hashlib.sha256(data).hexdigest()
                if item.name=="manifest.json":
                    manifest=json.loads(data)
    except (tarfile.TarError,OSError,EOFError,ValueError):
        abort("TAR_LEITURA_INVALIDA")
    if not isinstance(manifest,list) or len(manifest)!=3:
        abort("TAR_MANIFEST_DIVERGENTE")
    print("TAR_MANIFEST=3_ENTRADAS")

    mapped={}
    for row in manifest:
        if not isinstance(row,dict):
            abort("TAR_LINHA_INVALIDA")
        for ref in row.get("RepoTags",[]):
            if ref in mapped:
                abort("TAR_TAG_DUPLICADA")
            mapped[ref]=row
    if set(mapped)!={value[0] for value in service_info.values()}:
        abort("TAR_TAGS_NAO_CORRESPONDEM")

    for name in SERVICES:
        ref,iid=service_info[name]
        config=mapped[ref].get("Config")
        if not isinstance(config,str) or config not in hashes:
            abort("TAR_CONFIG_NAO_LOCALIZADO_"+name)
        content_digest=hashes[config]
        basename=Path(config).name.removesuffix(".json")
        filename_digest=basename if re.fullmatch(r"[a-f0-9]{64}",basename) else ""
        print("SERVICO="+name.upper())
        print("  IMAGE_ID_RUNTIME_12="+iid[7:19])
        print("  CONFIG_SHA256_ARQUIVO_12="+content_digest[:12])
        print("  CONFIG_NOME_HASH_COINCIDE="+("SIM" if filename_digest==content_digest else "NAO_OU_NAO_APLICAVEL"))
        print("  CONFIG_SHA_VS_IMAGE_ID="+("IGUAL" if "sha256:"+content_digest==iid else "DIFERENTE"))
        print("  CAMADAS_DECLARADAS="+str(len(mapped[ref].get("Layers",[]))))
    print("BACKUP_MODIFICADO=NAO")
    print("CONTEINERES_CRIADOS=NAO")
    print("DOCKER_LOAD_SAVE_EXECUTADO=NAO")
    print("RESTAURACAO_ENSAIADA=NAO")
    print("CE-PA02-ISO02_DIAGNOSTICO_CONCLUIDO")

if __name__=="__main__":
    main()
