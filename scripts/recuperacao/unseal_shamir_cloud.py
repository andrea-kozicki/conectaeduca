#!/usr/bin/env python3
from __future__ import annotations

import argparse
import getpass
import hashlib
import http.client
import json
import os
import shutil
import socket
import stat
import subprocess
import time
from pathlib import Path

HOME = Path.home()
CUSTODY = HOME / ".local/share/conectaeduca/openbao-custodia-lab"
LOCAL_SHARE = CUSTODY / "unseal-share-1.txt"

BAO_HOST = "127.0.0.1"
BAO_PORT = 18200
ITERATIONS = 600_000


def openssl_decrypt(data: bytes, passphrase: str) -> bytes:
    openssl = shutil.which("openssl")
    if not openssl:
        raise RuntimeError("openssl não encontrado")

    read_fd, write_fd = os.pipe()
    try:
        os.write(write_fd, (passphrase + "\n").encode())
    finally:
        os.close(write_fd)

    cmd = [
        openssl,
        "enc",
        "-d",
        "-aes-256-cbc",
        "-pbkdf2",
        "-iter",
        str(ITERATIONS),
        "-salt",
        "-pass",
        f"fd:{read_fd}",
    ]

    try:
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            pass_fds=(read_fd,),
        )
        stdout, stderr = proc.communicate(input=data)
    finally:
        os.close(read_fd)

    if proc.returncode != 0:
        raise RuntimeError("falha ao descriptografar pacote externo")
    return stdout


def api(method: str, path: str, payload=None, expected=(200,)) -> dict:
    body = None if payload is None else json.dumps(payload).encode()
    headers = {"Content-Type": "application/json"}

    conn = http.client.HTTPConnection(BAO_HOST, BAO_PORT, timeout=8)
    try:
        conn.request(method, f"/v1/{path}", body=body, headers=headers)
        resp = conn.getresponse()
        raw = resp.read()
        code = resp.status
    finally:
        conn.close()

    if code not in expected:
        raise RuntimeError(f"OpenBao retornou HTTP {code} em {path}")
    if not raw:
        return {}
    return json.loads(raw)


def health() -> dict:
    return api(
        "GET",
        "sys/health",
        expected=(200, 429, 472, 473, 501, 503),
    )


def load_external(enc: Path, manifest: Path, label: str) -> str:
    enc = enc.expanduser().resolve()
    manifest = manifest.expanduser().resolve()

    if not enc.is_file() or not manifest.is_file():
        raise RuntimeError(f"pacote/manifest ausente para {label}")

    meta = json.loads(manifest.read_text(encoding="utf-8"))
    if meta.get("share_label") != label:
        raise RuntimeError(f"manifest incorreto para {label}")

    if hashlib.sha256(enc.read_bytes()).hexdigest() != meta.get(
        "ciphertext_sha256"
    ):
        raise RuntimeError(f"ciphertext SHA-256 inválido para {label}")

    pw = getpass.getpass(f"Frase secreta de {label}: ")
    plain = openssl_decrypt(enc.read_bytes(), pw)
    pw = ""

    value = plain.decode("utf-8").strip()
    plain = b""

    if not value:
        raise RuntimeError(f"share externa vazia: {label}")
    return value


def submit_share(value: str) -> dict:
    return api(
        "POST",
        "sys/unseal",
        {"key": value},
        expected=(200,),
    )


def wait_active() -> None:
    deadline = time.monotonic() + 45
    last = {}
    while time.monotonic() < deadline:
        last = health()
        if (
            last.get("sealed") is False
            and last.get("standby") is False
        ):
            return
        time.sleep(1)
    raise RuntimeError(f"OpenBao não assumiu estado ativo: {last!r}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Recovery Shamir usando Share 1 local + nuvem, ou Google Drive + OneDrive."
    )
    mode = parser.add_mutually_exclusive_group(required=True)

    mode.add_argument(
        "--normal",
        action="store_true",
        help="usa Share 1 local + UMA share externa",
    )
    mode.add_argument(
        "--disaster",
        action="store_true",
        help="usa duas shares externas quando Share 1 local não está disponível",
    )

    parser.add_argument("--external-enc", type=Path)
    parser.add_argument("--external-manifest", type=Path)
    parser.add_argument("--external-label", choices=["share-2", "share-3"])

    parser.add_argument("--google-enc", type=Path)
    parser.add_argument("--google-manifest", type=Path)
    parser.add_argument("--onedrive-enc", type=Path)
    parser.add_argument("--onedrive-manifest", type=Path)

    args = parser.parse_args()

    if os.geteuid() == 0:
        raise RuntimeError("execute como usuário normal")
    if "ep126" not in socket.gethostname():
        raise RuntimeError("execute somente na EP126")

    current = health()
    if current.get("initialized") is not True:
        raise RuntimeError("OpenBao não inicializado")

    if current.get("sealed") is False:
        print("OK          OpenBao já está unsealed; nenhuma share foi lida.")
        return 0

    if args.normal:
        if not LOCAL_SHARE.is_file():
            raise RuntimeError("Share 1 local ausente; use modo --disaster")
        if stat.S_IMODE(LOCAL_SHARE.stat().st_mode) != 0o600:
            raise RuntimeError("Share 1 local não está 0600")
        if not (
            args.external_enc
            and args.external_manifest
            and args.external_label
        ):
            raise RuntimeError(
                "--normal exige --external-enc, --external-manifest e --external-label"
            )

        local = LOCAL_SHARE.read_text(encoding="utf-8").strip()
        external = load_external(
            args.external_enc,
            args.external_manifest,
            args.external_label,
        )

        first = submit_share(local)
        local = ""
        if first.get("sealed") is False:
            external = ""
            raise RuntimeError(
                "OpenBao ficou unsealed com uma share; threshold esperado é 2"
            )

        second = submit_share(external)
        external = ""

        if second.get("sealed") is not False:
            raise RuntimeError("OpenBao continuou sealed após quorum 2-de-3")

        wait_active()
        print("OK          Recovery normal: Share 1 local + share externa.")
        print("OK          Share externa foi descriptografada somente em memória.")
        print("SHAMIR_RECOVERY_NORMAL_2_DE_3=APROVADO")
        return 0

    if not (
        args.google_enc
        and args.google_manifest
        and args.onedrive_enc
        and args.onedrive_manifest
    ):
        raise RuntimeError(
            "--disaster exige pacotes/manifestos do Google Drive e OneDrive"
        )

    google = load_external(
        args.google_enc,
        args.google_manifest,
        "share-2",
    )
    onedrive = load_external(
        args.onedrive_enc,
        args.onedrive_manifest,
        "share-3",
    )

    first = submit_share(google)
    google = ""
    if first.get("sealed") is False:
        onedrive = ""
        raise RuntimeError(
            "OpenBao ficou unsealed com uma share; threshold esperado é 2"
        )

    second = submit_share(onedrive)
    onedrive = ""

    if second.get("sealed") is not False:
        raise RuntimeError("OpenBao continuou sealed após duas shares externas")

    wait_active()
    print("OK          Disaster recovery: Google Drive + OneDrive.")
    print("OK          Nenhuma share externa foi persistida em plaintext.")
    print("SHAMIR_RECOVERY_DISASTER_2_DE_3=APROVADO")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"FALHA: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
