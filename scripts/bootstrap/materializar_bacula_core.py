#!/usr/bin/env python3

from pathlib import Path
import os
import re
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "deploy/interna/bacula/.runtime"
CONFIG = RUNTIME / "config"


def fail(message: str) -> None:
    raise SystemExit(f"ERRO       {message}")


def read_env(path: Path) -> dict[str, str]:
    if not path.is_file():
        fail(f"arquivo runtime ausente: {path.name}")

    values: dict[str, str] = {}

    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()

        if not line or line.startswith("#"):
            continue

        if "=" not in line:
            fail(f"linha inválida em {path.name}")

        key, value = line.split("=", 1)
        values[key] = value

    return values


def require(values: dict[str, str], key: str) -> str:
    value = values.get(key, "")

    if not value:
        fail(f"variável obrigatória ausente: {key}")

    # As credenciais deste bootstrap são token_hex e os demais
    # parâmetros são identificadores simples.
    if not re.fullmatch(r"[A-Za-z0-9_.:-]+", value):
        fail(f"valor inesperado em {key}")

    return value


def atomic_secret(path: Path, content: str) -> None:
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        dir=path.parent,
        text=True,
    )

    try:
        os.fchmod(fd, 0o600)

        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)

        os.replace(tmp_name, path)
        path.chmod(0o600)

    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


db = read_env(RUNTIME / "director-db.env")
core = read_env(RUNTIME / "core.env")

db_host = require(db, "BACULA_DB_HOST")
db_port = require(db, "BACULA_DB_PORT")
db_name = require(db, "BACULA_DB_NAME")
db_user = require(db, "BACULA_DB_USER")
db_password = require(db, "BACULA_DB_PASSWORD")

console_password = require(core, "BACULA_CONSOLE_PASSWORD")
sd_password = require(core, "BACULA_SD_PASSWORD")
bootstrap_fd_password = require(
    core,
    "BACULA_BOOTSTRAP_FD_PASSWORD",
)

CONFIG.mkdir(parents=True, exist_ok=True)
CONFIG.chmod(0o700)

director_conf = f'''Director {{
  Name = conectaeduca-dir
  DIRport = 9101
  QueryFile = "/etc/bacula/scripts/query.sql"
  WorkingDirectory = "/var/lib/bacula"
  PidDirectory = "/run/bacula"
  Maximum Concurrent Jobs = 5
  Password = "{console_password}"
  Messages = Standard
}}

Catalog {{
  Name = ConectaEducaCatalog
  dbname = "{db_name}"
  DB Address = "{db_host}"
  DB Port = {db_port}
  dbuser = "{db_user}"
  dbpassword = "{db_password}"
}}

Storage {{
  Name = ConectaEducaStorage
  Address = storage
  SDPort = 9103
  Password = "{sd_password}"
  Device = FileStorage
  Media Type = File
  Maximum Concurrent Jobs = 5
}}

Client {{
  Name = conectaeduca-lab-fd
  Address = filedaemon-lab
  FDPort = 9102
  Catalog = ConectaEducaCatalog
  Password = "{bootstrap_fd_password}"
  File Retention = 7 days
  Job Retention = 7 days
  AutoPrune = yes
}}

FileSet {{
  Name = "LabSyntheticSet"

  Include {{
    Options {{
      Signature = SHA256
    }}

    File = /data/synthetic.bin
  }}
}}

Pool {{
  Name = LabPool
  Pool Type = Backup
  Storage = ConectaEducaStorage
  Recycle = yes
  AutoPrune = yes
  Volume Retention = 1 day
  Maximum Volumes = 2
}}

Job {{
  Name = "LabSyntheticBackup"
  Type = Backup
  Level = Full
  Client = conectaeduca-lab-fd
  FileSet = "LabSyntheticSet"
  Pool = LabPool
  Storage = ConectaEducaStorage
  Messages = Standard
}}

Job {{
  Name = "LabSyntheticRestore"
  Type = Restore
  Client = conectaeduca-lab-fd
  FileSet = "LabSyntheticSet"
  Pool = LabPool
  Storage = ConectaEducaStorage
  Messages = Standard
  Where = /restore
  Replace = always
}}

Messages {{
  Name = Standard
  stdout = all, !skipped, !saved
}}
'''

storage_conf = f'''Storage {{
  Name = conectaeduca-sd
  SDPort = 9103
  WorkingDirectory = "/var/lib/bacula"
  PidDirectory = "/run/bacula"
  PluginDirectory = "/usr/lib/bacula"
  Maximum Concurrent Jobs = 5
  SDAddress = 0.0.0.0
}}

Director {{
  Name = conectaeduca-dir
  Password = "{sd_password}"
}}

Device {{
  Name = FileStorage
  Media Type = File
  Device Type = File
  Archive Device = /backup
  LabelMedia = yes
  Random Access = yes
  AutomaticMount = yes
  RemovableMedia = no
  AlwaysOpen = no
}}

Messages {{
  Name = Standard
  stdout = all, !skipped, !saved
}}
'''

bconsole_conf = f'''Director {{
  Name = conectaeduca-dir
  DIRport = 9101
  Address = director
  Password = "{console_password}"
}}
'''

fd_conf = f"""FileDaemon {{
  Name = conectaeduca-lab-fd
  FDport = 9102
  WorkingDirectory = "/var/lib/bacula"
  Pid Directory = "/run/bacula"
  Maximum Concurrent Jobs = 5
  FDAddress = 0.0.0.0
}}

Director {{
  Name = conectaeduca-dir
  Password = "{bootstrap_fd_password}"
}}

Messages {{
  Name = Standard
  stdout = all, !skipped, !saved
}}
"""

atomic_secret(CONFIG / "bacula-fd.conf", fd_conf)

atomic_secret(CONFIG / "bacula-dir.conf", director_conf)
atomic_secret(CONFIG / "bacula-sd.conf", storage_conf)
atomic_secret(CONFIG / "bconsole.conf", bconsole_conf)

print("OK         configuração runtime do Director materializada")
print("OK         configuração runtime do Storage materializada")
print("OK         configuração runtime do bconsole materializada")
print("OK         nenhum segredo exibido")
