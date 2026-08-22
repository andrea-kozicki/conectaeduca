#!/usr/bin/env python3

from pathlib import Path


root = Path(__file__).resolve().parents[2]

conf = (
    root
    / "deploy/interna/bacula/.runtime/config/bacula-dir.conf"
)

if not conf.is_file():
    raise SystemExit(
        "ERRO: bacula-dir.conf runtime ausente; "
        "materialize o núcleo primeiro."
    )


begin = "# BEGIN CONECTAEDUCA BACULA WORKLOADS LAB"
end = "# END CONECTAEDUCA BACULA WORKLOADS LAB"


block = r'''
# BEGIN CONECTAEDUCA BACULA WORKLOADS LAB
# Bancada sintética.
# Não substitui os File Daemons nativos das VMs finais.

FileSet {
  Name = "ConectaEducaArtifactsSet"

  Include {
    Options {
      Signature = SHA256
    }

    File = /data/workloads
  }

  Exclude {
    File = /data/workloads/.runtime
    File = /data/workloads/secrets
    File = /data/workloads/openbao/custodia
    File = /data/workloads/smtp/private
    File = /data/workloads/ferret/inbox
    File = /data/workloads/ferret/raw
    File = /data/workloads/wazuh/indexer
  }
}

Job {
  Name = "ConectaEducaArtifactsBackup"
  Type = Backup
  Level = Full
  Client = conectaeduca-lab-fd
  FileSet = "ConectaEducaArtifactsSet"
  Pool = LabPool
  Storage = ConectaEducaStorage
  Messages = Standard
}

Job {
  Name = "ConectaEducaArtifactsRestore"
  Type = Restore
  Client = conectaeduca-lab-fd
  FileSet = "ConectaEducaArtifactsSet"
  Pool = LabPool
  Storage = ConectaEducaStorage
  Messages = Standard
  Where = /restore
  Replace = always
}

# END CONECTAEDUCA BACULA WORKLOADS LAB
'''.lstrip()


text = conf.read_text(
    encoding="utf-8",
)

if begin in text:
    start = text.index(begin)

    stop = text.find(
        end,
        start,
    )

    if stop == -1:
        raise SystemExit(
            "ERRO: marcador final do bloco workloads ausente."
        )

    stop += len(end)

    while (
        stop < len(text)
        and text[stop] in "\r\n"
    ):
        stop += 1

    text = (
        text[:start].rstrip()
        + "\n\n"
        + text[stop:].lstrip()
    )


text = (
    text.rstrip()
    + "\n\n"
    + block
)

tmp = conf.with_suffix(
    conf.suffix + ".tmp"
)

tmp.write_text(
    text,
    encoding="utf-8",
)

tmp.chmod(0o600)

tmp.replace(conf)

conf.chmod(0o600)

print(
    "OK: recursos Bacula de workloads sintéticos materializados."
)

print(
    "OK: exclusões sensíveis declaradas no FileSet."
)
