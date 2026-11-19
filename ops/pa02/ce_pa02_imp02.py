#!/usr/bin/env python3
"""CE-PA02-IMP02: materializa OCI layout com stdlib, sem daemon/instalacoes.

Importa dados do arquivo RC01 em OCI layout PRIVADO, verifica digest de blobs
e rootfs.diff_ids. NAO importa no Docker, NAO restaura stack, banco ou volumes.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import socket
import stat
import subprocess
import sys
import tarfile
import zlib

ROOT = Path("/opt/conectaeduca")
HEAD = "04f88d275064a005d0ffcd4f9372a371c28c32d5"
BACKUP = Path("/home/andrea.kiew/.local/share/conectaeduca/pa02-recovery/CE-PA02-RC01-20261108-183146")
PROJECT = "conectaeduca-dmz"
SERVICES = ("php", "nginx", "waf")
PA05 = "conectaeduca/php-fpm:pa05-10328ab6"
LIMIT = 16 * 1024**3
RESERVE = 1024**3

class Abort(Exception):
    pass

def fail(code: str) -> None:
    raise Abort(code)

def capture(cmd: list[str], timeout: int = 50) -> str:
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True,
                              check=False, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        fail("COMANDO_NAO_DISPONIVEL")
    if proc.returncode:
        fail("COMANDO_FALHOU")
    return proc.stdout.strip()

def check_private(path: Path, directory: bool = False) -> None:
    if (path.is_symlink() or
        not (path.is_dir() if directory else path.is_file()) or
        path.stat().st_uid != os.geteuid() or
        stat.S_IMODE(path.stat().st_mode) != (0o700 if directory else 0o600)):
        fail("CAMINHO_PRIVADO_INVALIDO")

def file_sha(path: Path) -> str:
    h=hashlib.sha256()
    with path.open("rb") as fd:
        for chunk in iter(lambda:fd.read(1024*1024),b""):
            h.update(chunk)
    return h.hexdigest()

def write_json(path: Path, value: dict) -> None:
    fd=os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as out:
        json.dump(value, out, separators=(",",":"), sort_keys=True)
        out.flush()
        os.fsync(out.fileno())

def runtime(service: str) -> dict:
    ids=capture(["docker","ps","-q",
        "--filter","label=com.docker.compose.project="+PROJECT,
        "--filter","label=com.docker.compose.service="+service]).splitlines()
    if len(ids)!=1:
        fail("SERVICO_NAO_UNICO_"+service)
    obj=json.loads(capture(["docker","inspect",ids[0]]))[0]
    if obj.get("State",{}).get("Running") is not True or (obj["State"].get("Health") or {}).get("Status")!="healthy":
        fail("RUNTIME_NAO_HEALTHY_"+service)
    ref=obj["Config"]["Image"]
    iid=obj["Image"]
    img=json.loads(capture(["docker","image","inspect",ref]))[0]
    if (not re.fullmatch(r"sha256:[a-f0-9]{64}",iid) or img.get("Id")!=iid):
        fail("IMAGE_ID_DIVERGENTE_"+service)
    layers=(img.get("RootFS") or {}).get("Layers")
    if not isinstance(layers,list) or not layers:
        fail("ROOTFS_AUSENTE_"+service)
    return {"ref":ref,"id":iid,"cid":obj["Id"],"layers":layers,
            "size":int(img.get("Size") or 0)}

def read_archive_manifest(archive: Path, refs: set[str]) -> dict:
    try:
        with tarfile.open(archive,"r|gz") as tf:
            for item in tf:
                if item.name != "manifest.json":
                    continue
                if not item.isfile() or item.size > 2*1024*1024:
                    fail("DOCKER_ARCHIVE_MANIFEST_INVALIDO")
                data=tf.extractfile(item)
                if data is None:
                    fail("DOCKER_ARCHIVE_MANIFEST_ILEGIVEL")
                rows=json.load(data)
                break
            else:
                fail("DOCKER_ARCHIVE_MANIFEST_AUSENTE")
    except (tarfile.TarError,OSError,EOFError,ValueError):
        fail("DOCKER_ARCHIVE_LEITURA_FALHOU")
    if not isinstance(rows,list) or len(rows)!=len(refs):
        fail("DOCKER_ARCHIVE_3_IMAGENS_DIVERGENTES")
    mapped={}
    required=set()
    for row in rows:
        if not isinstance(row,dict):
            fail("DOCKER_ARCHIVE_ROW_INVALIDA")
        tags=row.get("RepoTags",[])
        cfg=row.get("Config")
        layers=row.get("Layers")
        if (not isinstance(tags,list) or len(tags)!=1
            or not isinstance(cfg,str) or not isinstance(layers,list)
            or not layers or not all(isinstance(x,str) for x in layers)):
            fail("DOCKER_ARCHIVE_CONTEUDO_INVALIDO")
        name=tags[0]
        if name in mapped:
            fail("DOCKER_ARCHIVE_TAG_DUPLICADA")
        mapped[name]=row
        required.add(cfg)
        required.update(layers)
    if set(mapped)!=refs:
        fail("DOCKER_ARCHIVE_TAG_NAO_CORRESPONDE")
    return {"mapped":mapped,"required":required}

def safe_tar_name(name: str) -> None:
    parts=PurePosixPath(name).parts
    if not name or name.startswith("/") or ".." in parts or "\\" in name:
        fail("TAR_NOME_INSEGURO")

def stream_blob(member: tarfile.TarInfo, src, blobs: Path, tmp: Path,
                layer: bool) -> dict:
    """Copia bytes sem extração de paths, computa sha raw e diffid gzip."""
    if member.size < 1 or member.size > LIMIT:
        fail("TAR_TAMANHO_INVALIDO")
    tmp_file=tmp / ("partial-"+str(os.getpid()))
    if tmp_file.exists():
        fail("TMP_REUTILIZADO")
    fd=os.open(tmp_file, os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600)
    compressed_hash=hashlib.sha256()
    diff_hash=hashlib.sha256()
    decoder=None
    seen=0
    out_len=0
    first=True
    try:
        with os.fdopen(fd,"wb") as dest:
            while True:
                chunk=src.read(1024*1024)
                if not chunk:
                    break
                seen+=len(chunk)
                if seen>member.size:
                    fail("TAR_ENTRADA_LONGA")
                compressed_hash.update(chunk)
                dest.write(chunk)
                if layer:
                    if first and chunk.startswith(b"\x1f\x8b"):
                        decoder=zlib.decompressobj(16+zlib.MAX_WBITS)
                    first=False
                    if decoder is None:
                        diff_hash.update(chunk)
                        out_len+=len(chunk)
                    else:
                        pending=chunk
                        while pending:
                            output=decoder.decompress(pending, 1024*1024)
                            diff_hash.update(output)
                            out_len+=len(output)
                            if out_len>LIMIT:
                                fail("TAR_LAYER_DESCOMPACTADA_EXCESSIVA")
                            pending=decoder.unconsumed_tail
                        while True:
                            output=decoder.decompress(b"",1024*1024)
                            if not output:
                                break
                            diff_hash.update(output)
                            out_len+=len(output)
                            if out_len>LIMIT:
                                fail("TAR_LAYER_DESCOMPACTADA_EXCESSIVA")
            if seen!=member.size:
                fail("TAR_ENTRADA_TRUNCADA")
            if decoder is not None:
                if not decoder.eof or decoder.unused_data:
                    fail("TAR_GZIP_LAYER_INVALIDO")
                tail=decoder.flush()
                diff_hash.update(tail)
                out_len+=len(tail)
            dest.flush()
            os.fsync(dest.fileno())
        digest=compressed_hash.hexdigest()
        original=PurePosixPath(member.name).name
        if (member.name.startswith("blobs/sha256/") and
            (not re.fullmatch(r"[a-f0-9]{64}",original) or original!=digest)):
            fail("TAR_OCI_BLOB_DIGEST_INVALIDO")
        target=blobs/digest
        if target.exists() or target.is_symlink():
            if target.is_symlink() or file_sha(target)!=digest:
                fail("BLOB_DUPLICADO_DIVERGENTE")
            tmp_file.unlink()
        else:
            os.replace(tmp_file,target)
        return {"mediaType":("application/vnd.oci.image.layer.v1.tar+gzip"
                             if decoder is not None else "application/vnd.oci.image.layer.v1.tar")
                if layer else "application/vnd.oci.image.config.v1+json",
                "digest":"sha256:"+digest,"size":member.size,
                "_diffid":"sha256:"+diff_hash.hexdigest() if layer else None}
    finally:
        if tmp_file.exists():
            tmp_file.unlink()

def read_json_limited(path: Path, size: int = 4*1024*1024) -> dict:
    if not path.is_file() or path.is_symlink() or path.stat().st_size>size:
        fail("OCI_JSON_INVALIDO")
    try:
        obj=json.loads(path.read_text(encoding="utf-8"))
    except (ValueError,UnicodeError,OSError):
        fail("OCI_JSON_ILEGIVEL")
    if not isinstance(obj,dict):
        fail("OCI_JSON_OBJETO_INVALIDO")
    return obj

def create_layout(archive: Path, folder: Path, rows: dict, current: dict) -> None:
    blobs=folder/"blobs"/"sha256"
    blobs.mkdir(parents=True,mode=0o700)
    temp=folder/"tmp"
    temp.mkdir(mode=0o700)
    output={}
    try:
        with tarfile.open(archive,"r|gz") as tf:
            count=0
            for member in tf:
                count+=1
                if count>100000:
                    fail("TAR_ENTRADAS_EXCESSIVAS")
                safe_tar_name(member.name)
                if member.name not in rows["required"]:
                    continue
                if not member.isfile() or member.name in output:
                    fail("TAR_ENTRADA_AUSENTE_OU_DUPLICADA")
                src=tf.extractfile(member)
                if src is None:
                    fail("TAR_ENTRADA_NAO_LIDA")
                kind=any(member.name in entry["Layers"] for entry in rows["mapped"].values())
                output[member.name]=stream_blob(member,src,blobs,temp,kind)
    except (tarfile.TarError,OSError,EOFError,zlib.error):
        fail("TAR_CONVERSAO_FALHOU")
    if set(output)!=rows["required"]:
        fail("TAR_BLOBS_INCOMPLETOS")
    manifests=[]
    for service in SERVICES:
        ref=current[service]["ref"]
        entry=rows["mapped"][ref]
        cdesc=output[entry["Config"]].copy()
        cdesc.pop("_diffid",None)
        cfg=read_json_limited(blobs/cdesc["digest"][7:])
        diffids=(cfg.get("rootfs") or {}).get("diff_ids")
        from_archive=[output[k]["_diffid"] for k in entry["Layers"]]
        if not isinstance(diffids,list) or diffids!=from_archive:
            fail("ROOTFS_DIFFID_EXPORT_DIVERGENTE_"+service)
        if diffids!=current[service]["layers"]:
            fail("ROOTFS_RUNTIME_DIVERGENTE_"+service)
        layer_desc=[]
        for filename in entry["Layers"]:
            d=output[filename].copy()
            d.pop("_diffid",None)
            layer_desc.append(d)
        body={"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json",
              "config":cdesc,"layers":layer_desc}
        raw=json.dumps(body,sort_keys=True,separators=(",",":")).encode()
        digest=hashlib.sha256(raw).hexdigest()
        out=blobs/digest
        fd=os.open(out,os.O_WRONLY|os.O_EXCL|os.O_CREAT,0o600)
        with os.fdopen(fd,"wb") as f:
            f.write(raw)
            f.flush()
            os.fsync(f.fileno())
        manifests.append({"mediaType":"application/vnd.oci.image.manifest.v1+json",
                          "digest":"sha256:"+digest,"size":len(raw),
                          "annotations":{"org.opencontainers.image.ref.name":service}})
        print("IMP02_"+service.upper()+"_MATERIALIZADO=PASS",flush=True)
    write_json(folder/"oci-layout",{"imageLayoutVersion":"1.0.0"})
    write_json(folder/"index.json",{"schemaVersion":2,"manifests":manifests})
    # Releitura independente de todos os descritores efetivamente gravados.
    index=read_json_limited(folder/"index.json")
    for descriptor in index["manifests"]:
        path=blobs/descriptor["digest"][7:]
        if file_sha(path)!=descriptor["digest"][7:]:
            fail("OCI_MANIFEST_SHA_INVALIDO")
        manifest=read_json_limited(path)
        for d in [manifest["config"],*manifest["layers"]]:
            path=blobs/d["digest"][7:]
            if path.stat().st_size!=d["size"] or file_sha(path)!=d["digest"][7:]:
                fail("OCI_BLOB_SHA_INVALIDO")
    print("IMP02_LAYOUT_OCI_3_IMAGENS=PASS")
    print("IMP02_INDEX_MANIFESTS_BLOBS_SHA256=PASS")

def main() -> None:
    os.umask(0o077)
    print("=== CE-PA02-IMP02 — OCI SEM SKOPEO/DAEMON ===",flush=True)
    print("DATA="+dt.datetime.now().astimezone().isoformat(timespec="seconds"))
    if sys.argv[1:]!=["--materialize"]:
        fail("EXIGE_--materialize")
    if os.geteuid()==0 or capture(["whoami"])!="andrea.kiew":
        fail("USUARIO_NAO_PERMITIDO")
    if socket.gethostname().split(".")[0] not in ("ep125-pucpr","ep125-pucpr-br"):
        fail("HOST_INCORRETO")
    if capture(["git","-C",str(ROOT),"rev-parse","HEAD"])!=HEAD:
        fail("GIT_HEAD_ALTERADO")
    check_private(BACKUP,True)
    check_private(BACKUP.parent,True)
    archive=BACKUP/"docker-images.tar.gz"
    meta=BACKUP/"manifest.json"
    check_private(archive)
    check_private(meta)
    manifest=read_json_limited(meta)
    if (manifest.get("type")!="CE-PA02-RC01_LOCAL_DOCKER_RECOVERY" or
        manifest.get("git_head")!=HEAD or manifest.get("project")!=PROJECT):
        fail("PACOTE_RC01_MANIFEST_DIVERGENTE")
    expected_hash=manifest.get("images_archive_sha256")
    if not isinstance(expected_hash,str) or file_sha(archive)!=expected_hash:
        fail("PACOTE_RC01_SHA256_DIVERGENTE")
    print("PACOTE_RC01_SHA256=PASS")
    current={}
    if not isinstance(manifest.get("services"),dict) or set(manifest["services"])!=set(SERVICES):
        fail("PACOTE_RC01_SERVICOS_INCOMPLETOS")
    for name in SERVICES:
        state=runtime(name)
        old=manifest["services"][name]
        if (old.get("image_ref")!=state["ref"] or old.get("image_id")!=state["id"]
            or old.get("container_id")!=state["cid"]):
            fail("BASELINE_RUNTIME_DIVERGENTE_"+name)
        current[name]=state
    if current["php"]["ref"]!=PA05:
        fail("PHP_PA05_AUSENTE")
    print("RUNTIME_3_IMAGENS=HEALTHY")
    rows=read_archive_manifest(archive,{current[n]["ref"] for n in SERVICES})
    print("ARQUIVO_DOCKER_SAVE_3_REFS=PASS")
    # Reserva de disco: estimativa conservadora, sem quota FS.
    estimate=max(2*RESERVE, int(sum(max(x["size"],0) for x in current.values())*1.5)+RESERVE)
    free=shutil.disk_usage(BACKUP.parent).free
    if free<estimate:
        print("ESPACO_LIVRE_GIB="+str(round(free/RESERVE,2)))
        print("ESPACO_REQUERIDO_GIB="+str(round(estimate/RESERVE,2)))
        fail("ESPACO_INSUFICIENTE_SEM_GRAVACAO")
    print("ESPACO_PRECHECK=PASS")
    dest=BACKUP.parent/("CE-PA02-IMP02-"+dt.datetime.now().strftime("%Y%m%d-%H%M%S"))
    if dest.exists() or dest.is_symlink():
        fail("DESTINO_JA_EXISTE")
    dest.mkdir(mode=0o700)
    print("PASTA_PRIVADA_CRIADA=SIM")
    create_layout(archive,dest,rows,current)
    print("DESTINO_OCI_PRIVADO="+str(dest))
    print("CONVERSAO_SEM_SKOPEO=SIM")
    print("DOCKER_IMAGE_LOAD_EXECUTADO=NAO")
    print("DOCKER_COMPOSE_EXECUTADO=NAO")
    print("CONTEINERES_PRODUCAO_RECRIADOS=NAO")
    print("ROLLBACK_REAL_ENSAIADO=NAO")
    print("SNAPSHOT_VM=NAO")
    print("G0_APROVADO=NAO")
    print("CE-PA02-IMP02_CONCLUIDO")

if __name__=="__main__":
    try:
        main()
    except Abort as exc:
        print("CE-PA02-IMP02_ABORTADO="+str(exc),file=sys.stderr)
        sys.exit(1)
    except (OSError,ValueError,KeyError,TypeError) as exc:
        print("CE-PA02-IMP02_ABORTADO="+type(exc).__name__,file=sys.stderr)
        sys.exit(1)
