#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

EXPECTED_HOST = "ep126-pucpr"
PROJECT = "conectaeduca-wazuh"
ROOT = Path("/opt/conectaeduca/deploy/interna/wazuh")
CERTDIR = ROOT / ".runtime/certs"
API_CERT = "/var/ossec/api/configuration/ssl/server.crt"
API_KEY = "/var/ossec/api/configuration/ssl/server.key"
API_YAML = "/var/ossec/api/configuration/api.yaml"
CA_CERT = CERTDIR / "root-ca.pem"
CA_SIGNING_KEY = CERTDIR / "root-ca.key"

OUTDIR = Path.home() / "conectaeduca-evidencias"
OUTDIR.mkdir(parents=True, exist_ok=True, mode=0o700)
STAMP = dt.datetime.now().astimezone().strftime("%Y%m%d-%H%M%S")
REPORT = OUTDIR / f"conectaeduca-wazuh-api-pki-reconcile-{STAMP}.txt"
BACKUP = (
    Path.home()
    / ".local/share/conectaeduca/wazuh-api-pki-backup"
    / STAMP
)

parser = argparse.ArgumentParser(
    description="Reconciliador de PKI da API Wazuh Manager do ConectaEduca"
)
parser.add_argument("--apply", action="store_true")
parser.add_argument("--confirm-apply", action="store_true")
args = parser.parse_args()
if args.apply and not args.confirm_apply:
    raise SystemExit("APPLY exige --confirm-apply")
MODE = "APPLY" if args.apply else "CHECK"

counts = {"PASS": 0, "WARN": 0, "FAIL": 0, "INFO": 0}
lines: list[str] = []
changed = False
rollback_used = False
manager = dashboard = indexer = ""
meta: dict[str, tuple[int, int, int]] = {}


def log(msg: str = "") -> None:
    lines.append(str(msg))
    print(msg, flush=True)


def mark(kind: str, msg: str) -> None:
    counts[kind] += 1
    log(f"[{kind}] {msg}")


def run(cmd: list[str], *, input_text: str | None = None, timeout: int = 45):
    try:
        p = subprocess.run(
            cmd,
            input=input_text,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except subprocess.TimeoutExpired as exc:
        return 124, (exc.stdout or "").strip(), f"timeout: {(exc.stderr or '').strip()}"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def services() -> dict[str, str]:
    rc, out, err = run([
        "docker", "ps",
        "--filter", f"label=com.docker.compose.project={PROJECT}",
        "--format", '{{.Names}}\t{{.Label "com.docker.compose.service"}}',
    ])
    if rc:
        raise RuntimeError(err or out)
    found: dict[str, str] = {}
    for line in out.splitlines():
        name, service = line.split("\t", 1)
        found[service] = name
    return found


def inspect_container(name: str) -> dict:
    rc, out, err = run(["docker", "inspect", name])
    if rc:
        raise RuntimeError(err or out)
    d = json.loads(out)[0]
    state = d.get("State") or {}
    return {
        "id": d.get("Id", ""),
        "running": bool(state.get("Running")),
        "health": ((state.get("Health") or {}).get("Status") or "sem-healthcheck"),
        "restart": int(d.get("RestartCount") or 0),
        "image": (d.get("Config") or {}).get("Image") or "",
        "ports": (d.get("NetworkSettings") or {}).get("Ports") or {},
    }


def wait_healthy(name: str, timeout: int = 180) -> dict:
    deadline = time.time() + timeout
    while time.time() < deadline:
        snap = inspect_container(name)
        if snap["running"] and snap["health"] in {"healthy", "sem-healthcheck"}:
            return snap
        time.sleep(4)
    raise RuntimeError("Manager não ficou healthy no prazo")


def stat_in_container(name: str, path: str) -> tuple[int, int, int]:
    rc, out, err = run(["docker", "exec", name, "stat", "-c", "%u:%g:%a", path])
    if rc:
        raise RuntimeError(err or out)
    uid, gid, mode = out.split(":")
    return int(uid), int(gid), int(mode, 8)


def cp_from(name: str, src: str, dst: Path) -> None:
    rc, out, err = run(["docker", "cp", f"{name}:{src}", str(dst)])
    if rc:
        raise RuntimeError(err or out)


def cp_to(name: str, src: Path, dst: str) -> None:
    rc, out, err = run(["docker", "cp", str(src), f"{name}:{dst}"])
    if rc:
        raise RuntimeError(err or out)


def cert_summary(path: Path) -> str:
    rc, out, err = run([
        "openssl", "x509", "-in", str(path), "-noout",
        "-subject", "-issuer", "-dates",
        "-ext", "subjectAltName",
        "-fingerprint", "-sha256",
    ])
    if rc:
        raise RuntimeError(err or out)
    return out


def verify_cert(cert: Path, ca: Path) -> None:
    rc, out, err = run(["openssl", "verify", "-CAfile", str(ca), str(cert)])
    if rc:
        raise RuntimeError(err or out)
    for host in ("wazuh.manager", "localhost"):
        rc, out, err = run([
            "openssl", "x509", "-in", str(cert), "-noout", "-checkhost", host
        ])
        if rc:
            raise RuntimeError(f"certificado não cobre {host}: {err or out}")


def validate_ca_signing_key() -> None:
    if not CA_SIGNING_KEY.is_file():
        raise RuntimeError(
            "chave de assinatura da CA ausente no runtime canônico: "
            f"{CA_SIGNING_KEY}"
        )

    mode = CA_SIGNING_KEY.stat().st_mode & 0o777
    if mode not in {0o400, 0o600}:
        raise RuntimeError(
            "chave de assinatura da CA deve permanecer privada (0400/0600); "
            f"observado={mode:04o}"
        )


def verify_installed_cert_key_match() -> None:
    # Compara somente hashes das chaves públicas derivadas do certificado e da
    # private key dentro do Manager. A chave privada nunca sai do container.
    shell = r"""
set -eu
cert_pub="$(
  openssl x509 -in /var/ossec/api/configuration/ssl/server.crt -pubkey -noout |
  openssl pkey -pubin -outform DER |
  sha256sum | awk '{print $1}'
)"
key_pub="$(
  openssl pkey -in /var/ossec/api/configuration/ssl/server.key -pubout -outform DER |
  sha256sum | awk '{print $1}'
)"
[ -n "$cert_pub" ] && [ -n "$key_pub" ]
[ "$cert_pub" = "$key_pub" ] || {
  echo CERT_KEY_MISMATCH >&2
  exit 42
}
printf 'CERT_KEY_MATCH=1\n'
"""
    rc, out, err = run(["docker", "exec", manager, "sh", "-lc", shell])
    if rc or "CERT_KEY_MATCH=1" not in out:
        raise RuntimeError(
            "certificado instalado não corresponde à chave privada persistente: "
            f"{err or out}"
        )


def generate_signed_pair(workdir: Path, helper_image: str) -> None:
    (workdir / "pki.cnf").write_text(
        "[req]\n"
        "prompt = no\n"
        "distinguished_name = dn\n"
        "req_extensions = ext\n\n"
        "[dn]\n"
        "C = BR\nST = PR\nL = Curitiba\nO = ConectaEduca\n"
        "OU = Wazuh API\nCN = wazuh.manager\n\n"
        "[ext]\n"
        "subjectAltName = @alt\n"
        "extendedKeyUsage = serverAuth\n"
        "keyUsage = critical,digitalSignature,keyEncipherment\n\n"
        "[alt]\nDNS.1 = wazuh.manager\nDNS.2 = localhost\n",
        encoding="utf-8",
    )

    shell = r"""
set -eu
CA_KEY=/certs/root-ca.key
[ -r "$CA_KEY" ] || { echo CA_KEY_NOT_FOUND >&2; exit 44; }

cp /certs/root-ca.pem /work/root-ca.pem
openssl genrsa -out /work/server.key 3072
openssl req -new -key /work/server.key -out /work/server.csr -config /work/pki.cnf
openssl x509 -req \
  -in /work/server.csr \
  -CA /certs/root-ca.pem \
  -CAkey "$CA_KEY" \
  -CAcreateserial \
  -CAserial /work/root-ca.srl \
  -out /work/server.crt \
  -days 825 \
  -sha256 \
  -extfile /work/pki.cnf \
  -extensions ext
chmod 0600 /work/server.key
chmod 0644 /work/server.crt /work/root-ca.pem
"""
    rc, out, err = run([
        "docker", "run", "--rm",
        "--entrypoint", "sh",
        "-v", f"{CERTDIR}:/certs:ro",
        "-v", f"{workdir}:/work",
        helper_image,
        "-lc", shell,
    ], timeout=90)
    if rc:
        raise RuntimeError(err or out)
    verify_cert(workdir / "server.crt", workdir / "root-ca.pem")


def backup_current() -> None:
    BACKUP.mkdir(parents=True, exist_ok=False, mode=0o700)
    for src, name in (
        (API_CERT, "server.crt.before"),
        (API_KEY, "server.key.before"),
        (API_YAML, "api.yaml.before"),
    ):
        dst = BACKUP / name
        cp_from(manager, src, dst)
        os.chmod(dst, 0o600)
    mark("PASS", f"Backup privado criado em {BACKUP}.")


def install_pair(cert: Path, key: Path) -> None:
    cert_uid, cert_gid, cert_mode = meta[API_CERT]
    key_uid, key_gid, key_mode = meta[API_KEY]

    cp_to(manager, cert, "/tmp/conectaeduca-api.crt")
    cp_to(manager, key, "/tmp/conectaeduca-api.key")

    shell = (
        f"set -eu; "
        f"cp /tmp/conectaeduca-api.crt {API_CERT}; "
        f"cp /tmp/conectaeduca-api.key {API_KEY}; "
        f"chown {cert_uid}:{cert_gid} {API_CERT}; "
        f"chown {key_uid}:{key_gid} {API_KEY}; "
        f"chmod {cert_mode:o} {API_CERT}; "
        f"chmod {key_mode:o} {API_KEY}; "
        "rm -f /tmp/conectaeduca-api.crt /tmp/conectaeduca-api.key"
    )
    rc, out, err = run(["docker", "exec", manager, "sh", "-lc", shell])
    if rc:
        raise RuntimeError(err or out)


def dashboard_tls_probe():
    return run([
        "docker", "exec", dashboard,
        "curl", "-sS",
        "--cacert", "/usr/share/wazuh-dashboard/certs/root-ca.pem",
        "--connect-timeout", "4",
        "--max-time", "10",
        "-o", "/dev/null",
        "-w", "%{http_code}",
        "https://wazuh.manager:55000/",
    ])


def dashboard_auth_probe():
    shell = r"""
set -eu
CFG=/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml
CA=/usr/share/wazuh-dashboard/certs/root-ca.pem
umask 077
AUTHCFG=/dev/shm/conectaeduca-wazuh-pki-auth.$$
cleanup() { rm -f "$AUTHCFG"; unset u p token; }
trap cleanup EXIT INT TERM

u="$(awk -F': ' '/^[[:space:]]*username:/ {gsub(/"/,"",$2); print $2; exit}' "$CFG")"
p="$(awk -F': ' '/^[[:space:]]*password:/ {gsub(/"/,"",$2); print $2; exit}' "$CFG")"
printf 'user = "%s:%s"\n' "$u" "$p" > "$AUTHCFG"

token="$(curl -fsS \
  --config "$AUTHCFG" \
  --cacert "$CA" \
  'https://wazuh.manager:55000/security/user/authenticate?raw=true')"

[ -n "$token" ]
printf 'AUTH_OK\n'
"""
    return run(["docker", "exec", "-i", dashboard, "sh", "-lc", shell])


def rollback() -> None:
    global rollback_used
    if not changed:
        return
    rollback_used = True
    install_pair(BACKUP / "server.crt.before", BACKUP / "server.key.before")
    rc, out, err = run(["docker", "restart", manager], timeout=60)
    if rc:
        raise RuntimeError(err or out)
    wait_healthy(manager)
    mark("PASS", "Rollback restaurou o par TLS anterior.")


log("ConectaEduca — reconciliador PKI da API Wazuh Manager")
log(f"Data/hora={dt.datetime.now().astimezone().isoformat(timespec='seconds')}")
log(f"MODO={MODE}")
log("SAN_DNS=wazuh.manager,localhost")
log("USA_INSECURE_K=NAO")
log("USA_SUDO=NAO")
log("ALTERA_GIT=NAO")
log("PUBLICA_PORTAS=NAO")
log("SEGREDOS_EXIBIDOS=NAO")
log("=" * 100)

workdir: Path | None = None

try:
    rc, host, err = run(["hostname"])
    if rc or host.strip() != EXPECTED_HOST:
        raise RuntimeError(f"executar somente em {EXPECTED_HOST}")
    mark("PASS", f"VM confirmada: {host.strip()}")

    rc, _, err = run(["docker", "info"])
    if rc:
        raise RuntimeError(err)
    mark("PASS", "Docker acessível sem sudo.")

    svc = services()
    manager = svc["wazuh.manager"]
    dashboard = svc["wazuh.dashboard"]
    indexer = svc["wazuh.indexer"]

    before = inspect_container(manager)
    if not before["running"] or before["health"] not in {"healthy", "sem-healthcheck"}:
        raise RuntimeError("Manager não está saudável")
    if before["ports"].get("55000/tcp"):
        raise RuntimeError("55000 está publicada no host")
    mark("PASS", "Manager healthy e 55000 sem host binding.")

    meta[API_CERT] = stat_in_container(manager, API_CERT)
    meta[API_KEY] = stat_in_container(manager, API_KEY)

    rc, out, err = run([
        "docker", "exec", manager, "sh", "-lc",
        f"test -r {API_YAML} && test -r {API_CERT} && test -r {API_KEY}",
    ])
    if rc:
        raise RuntimeError("artefatos TLS da API não estão acessíveis")
    mark("PASS", "Artefatos TLS persistentes da API localizados.")

    workdir = Path(tempfile.mkdtemp(prefix="ce-wazuh-pki-", dir="/dev/shm"))
    os.chmod(workdir, 0o700)

    current = workdir / "current-server.crt"
    cp_from(manager, API_CERT, current)
    log("CERTIFICADO_ATUAL:")
    for line in cert_summary(current).splitlines():
        log(f"  {line}")

    if MODE == "CHECK":
        # CHECK valida o estado realmente instalado, não um certificado
        # temporário recém-gerado. A CA pública é obtida do Dashboard, que já
        # a usa para validar o Manager no fluxo operacional.
        runtime_ca = workdir / "root-ca.pem"
        cp_from(
            dashboard,
            "/usr/share/wazuh-dashboard/certs/root-ca.pem",
            runtime_ca,
        )
        verify_cert(current, runtime_ca)
        mark(
            "PASS",
            "Certificado atualmente instalado valida na CA do runtime e cobre "
            "wazuh.manager + localhost.",
        )

        verify_installed_cert_key_match()
        mark(
            "PASS",
            "Certificado persistente corresponde à chave privada persistente.",
        )

        rc, code, err = dashboard_tls_probe()
        if rc or code not in {"200", "301", "302", "401", "403"}:
            raise RuntimeError(
                f"TLS live Dashboard->Manager falhou no CHECK: {err or code}"
            )
        mark(
            "PASS",
            f"CHECK live: Dashboard valida wazuh.manager:55000; HTTP={code}; sem -k.",
        )

        rc, out, err = dashboard_auth_probe()
        if rc or "AUTH_OK" not in out:
            raise RuntimeError(
                f"CHECK live: wazuh-wui não autenticou com TLS verificado: {err or out}"
            )
        mark("PASS", "CHECK live: wazuh-wui autenticou com TLS verificado.")
        mark("PASS", "CHECK concluído sem alteração persistente.")
    else:
        validate_ca_signing_key()
        mark(
            "PASS",
            "Chave de assinatura root-ca.key presente e protegida no host emissor.",
        )
        generate_signed_pair(workdir, before["image"])
        mark("PASS", "Novo certificado validado para wazuh.manager e localhost.")
        log(f"NOVO_CERT_SHA256={sha256(workdir / 'server.crt')}")

        backup_current()

        # A partir deste ponto uma falha parcial em install_pair pode já ter
        # sobrescrito cert ou key. Marcar antes da primeira escrita garante
        # tentativa de rollback usando o backup privado.
        changed = True
        install_pair(workdir / "server.crt", workdir / "server.key")
        mark("PASS", "Novo par TLS instalado no volume persistente da API.")

        rc, out, err = run(["docker", "restart", manager], timeout=60)
        if rc:
            raise RuntimeError(err or out)

        after = wait_healthy(manager)
        if after["id"] != before["id"]:
            raise RuntimeError("Manager foi recriado; esperado apenas restart")
        mark("PASS", "Manager reiniciado e voltou healthy.")

        rc, code, err = dashboard_tls_probe()
        if rc or code not in {"200", "301", "302", "401", "403"}:
            raise RuntimeError(f"TLS Dashboard->Manager falhou: {err or code}")
        mark("PASS", f"Dashboard valida wazuh.manager:55000; HTTP={code}; sem -k.")

        rc, out, err = dashboard_auth_probe()
        if rc or "AUTH_OK" not in out:
            raise RuntimeError(f"wazuh-wui não autenticou: {err or out}")
        mark("PASS", "wazuh-wui autenticou com TLS verificado.")

        installed = workdir / "installed-server.crt"
        cp_from(manager, API_CERT, installed)
        verify_cert(installed, workdir / "root-ca.pem")
        if sha256(installed) != sha256(workdir / "server.crt"):
            raise RuntimeError("certificado instalado difere do gerado")
        verify_installed_cert_key_match()
        mark(
            "PASS",
            "Certificado instalado corresponde ao artefato validado e à chave "
            "privada persistente.",
        )

except Exception as exc:
    mark("FAIL", f"{type(exc).__name__}: {exc}")
    if MODE == "APPLY" and changed:
        try:
            rollback()
        except Exception as rollback_exc:
            mark("FAIL", f"rollback falhou: {rollback_exc}")
finally:
    if workdir is not None:
        shutil.rmtree(workdir, ignore_errors=True)

status = (
    "PKI_WAZUH_API_RECONCILIADA"
    if MODE == "APPLY" and counts["FAIL"] == 0
    else "PKI_WAZUH_API_CHECK_APROVADO"
    if MODE == "CHECK" and counts["FAIL"] == 0
    else "PKI_WAZUH_API_BLOQUEADA"
)

log("=" * 100)
log(
    f"RESUMO_FINAL: PASS={counts['PASS']} WARN={counts['WARN']} "
    f"FAIL={counts['FAIL']} INFO={counts['INFO']}"
)
log(f"STATUS={status}")
log(f"ROLLBACK_USED={1 if rollback_used else 0}")
log("USOU_INSECURE_K=0")
log("ALTERACOES_GIT=0")
log("55000_PUBLICADO=0")
log("SEGREDOS_EXIBIDOS=0")

REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
os.chmod(REPORT, 0o600)
print(f"RELATORIO={REPORT}")
print(f"RELATORIO_SHA256={sha256(REPORT)}")

if counts["FAIL"] > 0:
    sys.exit(1)
