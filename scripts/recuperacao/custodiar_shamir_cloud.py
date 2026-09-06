#!/usr/bin/env python3
from __future__ import annotations

import argparse
import getpass
import hashlib
import json
import os
import shutil
import socket
import stat
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path

HOME = Path.home()
CUSTODY = HOME / ".local/share/conectaeduca/openbao-custodia-lab"
SHARE1 = CUSTODY / "unseal-share-1.txt"
SHARE2 = CUSTODY / "unseal-share-2.txt"
SHARE3 = CUSTODY / "unseal-share-3.txt"
STATE = CUSTODY / "custody-state.json"

ITERATIONS = 600_000


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def mode(path: Path) -> int:
    return stat.S_IMODE(path.stat().st_mode)


def emit(report: Path, line: str = "") -> None:
    print(line, flush=True)
    with report.open("a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def section(report: Path, title: str) -> None:
    emit(report)
    emit(report, "=" * 80)
    emit(report, title)
    emit(report, "=" * 80)


def openssl_crypt(data: bytes, passphrase: str, decrypt: bool = False) -> bytes:
    openssl = shutil.which("openssl")
    if not openssl:
        raise RuntimeError("openssl não encontrado")

    read_fd, write_fd = os.pipe()
    try:
        os.write(write_fd, (passphrase + "\n").encode("utf-8"))
    finally:
        os.close(write_fd)

    cmd = [
        openssl,
        "enc",
        "-aes-256-cbc",
        "-pbkdf2",
        "-iter",
        str(ITERATIONS),
        "-salt",
        "-pass",
        f"fd:{read_fd}",
    ]
    if decrypt:
        cmd.insert(2, "-d")

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
        raise RuntimeError(
            "openssl falhou: "
            + stderr.decode("utf-8", errors="replace").strip()
        )
    return stdout


def atomic_write(path: Path, data: bytes, file_mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    tmp = Path(tmp_name)
    try:
        os.fchmod(fd, file_mode)
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
        os.chmod(path, file_mode)
    finally:
        try:
            tmp.unlink()
        except FileNotFoundError:
            pass


def atomic_json(path: Path, payload: dict) -> None:
    atomic_write(
        path,
        (json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode(),
        0o600,
    )


def require_local_baseline() -> None:
    if os.geteuid() == 0:
        raise RuntimeError("execute como usuário normal, não root")
    if "ep126" not in socket.gethostname():
        raise RuntimeError("execute somente na EP126")
    if not CUSTODY.is_dir() or mode(CUSTODY) != 0o700:
        raise RuntimeError("diretório de custódia ausente ou diferente de 0700")
    for share in (SHARE1, SHARE2, SHARE3):
        if not share.is_file():
            raise RuntimeError(f"share local ausente: {share.name}")
        if mode(share) != 0o600:
            raise RuntimeError(f"{share.name} não está 0600")


def read_share(path: Path) -> bytes:
    data = path.read_bytes()
    if not data.strip():
        raise RuntimeError(f"share vazia: {path.name}")
    return data


def prompt_new_passphrase(label: str) -> str:
    first = getpass.getpass(
        f"Frase secreta para {label} (mín. 20 caracteres; não guardar na nuvem): "
    )
    second = getpass.getpass(f"Repita a frase secreta para {label}: ")
    if first != second:
        raise RuntimeError(f"frases secretas de {label} não coincidem")
    if len(first) < 20:
        raise RuntimeError(f"frase secreta de {label} é curta demais")
    return first


def manifest_for(label: str, enc_path: Path) -> dict:
    return {
        "schema": "conectaeduca-openbao-shamir-cloud-v1",
        "share_label": label,
        "created_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "cipher": "AES-256-CBC",
        "kdf": "PBKDF2",
        "pbkdf2_iterations": ITERATIONS,
        "ciphertext_sha256": sha256_file(enc_path),
        "contains_plaintext_share": False,
        "contains_passphrase": False,
    }


def verify_download(
    encrypted: Path,
    manifest: Path,
    expected_share: bytes,
    passphrase: str,
    expected_label: str,
) -> None:
    if not encrypted.is_file():
        raise RuntimeError(f"arquivo criptografado ausente: {encrypted}")
    if not manifest.is_file():
        raise RuntimeError(f"manifest ausente: {manifest}")

    meta = json.loads(manifest.read_text(encoding="utf-8"))
    if meta.get("share_label") != expected_label:
        raise RuntimeError(
            f"manifest não corresponde a {expected_label}"
        )

    current_sha = sha256_file(encrypted)
    if current_sha != meta.get("ciphertext_sha256"):
        raise RuntimeError(
            f"SHA-256 do ciphertext não confere para {expected_label}"
        )

    plaintext = openssl_crypt(
        encrypted.read_bytes(),
        passphrase,
        decrypt=True,
    )
    if plaintext != expected_share:
        plaintext = b""
        raise RuntimeError(
            f"pacote baixado não corresponde à {expected_label} original"
        )
    plaintext = b""


def report_path(kind: str) -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    path = (
        HOME
        / "Downloads"
        / f"conectaeduca-ep126-custodia-shamir-cloud-{kind}-{stamp}.txt"
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("", encoding="utf-8")
    return path


def prepare() -> int:
    require_local_baseline()
    report = report_path("prepare")

    section(report, "1. BASELINE E GUARDA-CORPOS")
    emit(report, f"Data={datetime.now().astimezone().isoformat(timespec='seconds')}")
    emit(report, f"Host={socket.gethostname()}")
    emit(report, "MODO=PREPARAR_CUSTODIA_CLOUD_GOOGLE_DRIVE_ONEDRIVE")
    emit(report, "SUDO_UTILIZADO=NAO")
    emit(report, "OPENBAO_MODIFICADO=NAO")
    emit(report, "REDE_MODIFICADA=NAO")
    emit(report, "SHARES_EXIBIDAS=NAO")
    emit(report, "PASSPHRASES_EXIBIDAS=NAO")
    emit(report, "PASSPHRASES_PERSISTIDAS=NAO")
    emit(report, "LOCAL_SHARES_REMOVIDAS=NAO")
    emit(report, "CUSTODY_DIR_MODE_0700=APROVADO")
    emit(report, "SHARE1_MODE_0600=APROVADO")
    emit(report, "SHARE2_MODE_0600=APROVADO")
    emit(report, "SHARE3_MODE_0600=APROVADO")

    share2 = read_share(SHARE2)
    share3 = read_share(SHARE3)

    pass2 = prompt_new_passphrase("Share 2 / Google Drive")
    pass3 = prompt_new_passphrase("Share 3 / OneDrive")

    if pass2 == pass3:
        raise RuntimeError(
            "Google Drive e OneDrive devem usar frases secretas diferentes"
        )

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    stage = HOME / "Downloads" / f"conectaeduca-shamir-cloud-stage-{stamp}"
    google = stage / "GOOGLE-DRIVE"
    onedrive = stage / "ONEDRIVE"

    enc2 = google / "unseal-share-2.enc"
    man2 = google / "unseal-share-2.manifest.json"
    enc3 = onedrive / "unseal-share-3.enc"
    man3 = onedrive / "unseal-share-3.manifest.json"

    section(report, "2. CRIPTOGRAFAR E VERIFICAR SHARE 2 — GOOGLE DRIVE")

    encrypted2 = openssl_crypt(share2, pass2, decrypt=False)
    atomic_write(enc2, encrypted2)
    atomic_json(man2, manifest_for("share-2", enc2))
    verify_download(enc2, man2, share2, pass2, "share-2")

    emit(report, "GOOGLE_DRIVE_SHARE2_PACKAGE=CRIADO")
    emit(report, "GOOGLE_DRIVE_SHARE2_DECRYPT_VERIFY=APROVADO")
    emit(report, f"GOOGLE_DRIVE_SHARE2_CIPHERTEXT_SHA256={sha256_file(enc2)}")

    section(report, "3. CRIPTOGRAFAR E VERIFICAR SHARE 3 — ONEDRIVE")

    encrypted3 = openssl_crypt(share3, pass3, decrypt=False)
    atomic_write(enc3, encrypted3)
    atomic_json(man3, manifest_for("share-3", enc3))
    verify_download(enc3, man3, share3, pass3, "share-3")

    emit(report, "ONEDRIVE_SHARE3_PACKAGE=CRIADO")
    emit(report, "ONEDRIVE_SHARE3_DECRYPT_VERIFY=APROVADO")
    emit(report, f"ONEDRIVE_SHARE3_CIPHERTEXT_SHA256={sha256_file(enc3)}")

    pass2 = ""
    pass3 = ""
    share2 = b""
    share3 = b""

    section(report, "4. PRÓXIMO PASSO MANUAL")

    emit(report, f"STAGING_DIR={stage}")
    emit(report, f"UPLOAD_GOOGLE_DRIVE_DIR={google}")
    emit(report, f"UPLOAD_ONEDRIVE_DIR={onedrive}")
    emit(report, "UPLOAD_AUTOMATICO_EXECUTADO=NAO")
    emit(report, "INSTRUCAO_1=ENVIAR_CONTEUDO_DE_GOOGLE-DRIVE_PARA_GOOGLE_DRIVE")
    emit(report, "INSTRUCAO_2=ENVIAR_CONTEUDO_DE_ONEDRIVE_PARA_ONEDRIVE")
    emit(report, "INSTRUCAO_3=GUARDAR_CADA_PASSPHRASE_FORA_DAS_NUVENS")
    emit(report, "INSTRUCAO_4=BAIXAR_DE_VOLTA_AMBOS_OS_PACOTES_ANTES_DO_FINALIZE")
    emit(report, "CUSTODIA_CLOUD_PREPARE=APROVADO")
    emit(report, "LOCAL_SHARES_REMOVIDAS=NAO")
    emit(report, f"RELATORIO={report}")
    return 0


def finalize(
    google_enc: Path,
    google_manifest: Path,
    onedrive_enc: Path,
    onedrive_manifest: Path,
) -> int:
    require_local_baseline()
    report = report_path("finalize")

    section(report, "1. REVALIDAR CÓPIAS BAIXADAS DAS NUVENS")
    emit(report, "MODO=FINALIZAR_CUSTODIA_CLOUD_APOS_DOWNLOAD_DE_VERIFICACAO")
    emit(report, "SUDO_UTILIZADO=NAO")
    emit(report, "OPENBAO_MODIFICADO=NAO")
    emit(report, "SHARES_EXIBIDAS=NAO")
    emit(report, "PASSPHRASES_EXIBIDAS=NAO")

    share2 = read_share(SHARE2)
    share3 = read_share(SHARE3)

    pass2 = getpass.getpass(
        "Frase secreta da Share 2 / Google Drive para verificação: "
    )
    pass3 = getpass.getpass(
        "Frase secreta da Share 3 / OneDrive para verificação: "
    )

    verify_download(
        google_enc.expanduser().resolve(),
        google_manifest.expanduser().resolve(),
        share2,
        pass2,
        "share-2",
    )
    emit(report, "GOOGLE_DRIVE_DOWNLOADED_COPY=APROVADA")

    verify_download(
        onedrive_enc.expanduser().resolve(),
        onedrive_manifest.expanduser().resolve(),
        share3,
        pass3,
        "share-3",
    )
    emit(report, "ONEDRIVE_DOWNLOADED_COPY=APROVADA")

    if pass2 == pass3:
        raise RuntimeError(
            "as duas custódias não devem usar a mesma frase secreta"
        )

    pass2 = ""
    pass3 = ""

    google_enc_sha = sha256_file(google_enc.expanduser().resolve())
    onedrive_enc_sha = sha256_file(onedrive_enc.expanduser().resolve())

    section(report, "2. CONFIRMAÇÃO HUMANA")

    emit(
        report,
        "AVISO=ESTA_ETAPA_REMOVE_SHARE2_E_SHARE3_DO_ESTADO_LIVE_DA_EP126"
    )
    emit(
        report,
        "AVISO=EXCLUSAO_NORMAL_NAO_APAGA_COPIAS_HISTORICAS_EM_SNAPSHOTS_OU_BACKUPS"
    )

    answer = input(
        'Digite exatamente "FINALIZAR CUSTODIA CLOUD" para continuar: '
    ).strip()

    if answer != "FINALIZAR CUSTODIA CLOUD":
        emit(report, "FINALIZE_CANCELADO=SIM")
        emit(report, "LOCAL_SHARES_REMOVIDAS=NAO")
        emit(report, f"RELATORIO={report}")
        return 2

    SHARE2.unlink()
    SHARE3.unlink()

    # Remove somente staging criptografado local, se existir. Downloads manuais
    # de verificação não são removidos automaticamente porque o caminho foi
    # escolhido pelo operador; o relatório manda apagá-los após a validação.
    for candidate in (HOME / "Downloads").glob(
        "conectaeduca-shamir-cloud-stage-*"
    ):
        if candidate.is_dir():
            shutil.rmtree(candidate)

    remaining = sorted(
        p.name
        for p in CUSTODY.glob("unseal-share-*.txt")
        if p.is_file()
    )

    if remaining != ["unseal-share-1.txt"]:
        raise RuntimeError(
            f"estado local inesperado após finalização: {remaining!r}"
        )

    state = {
        "schema": "conectaeduca-openbao-shamir-custody-state-v1",
        "threshold": 2,
        "shares": 3,
        "local_share": "share-1",
        "google_drive_share": "share-2",
        "onedrive_share": "share-3",
        "google_drive_ciphertext_sha256": google_enc_sha,
        "onedrive_ciphertext_sha256": onedrive_enc_sha,
        "completed_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "contains_secret_values": False,
        "contains_passphrases": False,
        "historical_snapshot_copy_risk": True,
    }
    atomic_json(STATE, state)

    section(report, "3. RESULTADO FINAL")
    emit(report, "LOCAL_SHARE1_RETAINED=APROVADO")
    emit(report, "LOCAL_SHARE2_REMOVED=APROVADO")
    emit(report, "LOCAL_SHARE3_REMOVED=APROVADO")
    emit(report, "GOOGLE_DRIVE_SHARE2_VERIFIED=APROVADO")
    emit(report, "ONEDRIVE_SHARE3_VERIFIED=APROVADO")
    emit(report, "CUSTODY_STATE_FILE=CRIADO_SEM_SEGREDOS")
    emit(report, "LIVE_SINGLE_FAILURE_DOMAIN_MITIGATION=APROVADA")
    emit(report, "HISTORICAL_SNAPSHOT_COPY_RISK=RESIDUAL_DOCUMENTADO")
    emit(report, "REKEY_EXECUTADO=NAO")
    emit(
        report,
        "INSTRUCAO_POS_FINALIZE=APAGAR_AS_COPIAS_BAIXADAS_USADAS_NA_VERIFICACAO"
    )
    emit(
        report,
        "PROXIMO_PASSO=TESTAR_RECOVERY_CONTROLADO_EM_JANELA_APROPRIADA_SEM_REINICIAR_AGORA"
    )
    emit(report, f"RELATORIO={report}")

    share2 = b""
    share3 = b""
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Custódia Shamir cloud: Share 2 no Google Drive e Share 3 no OneDrive."
    )
    subs = parser.add_subparsers(dest="mode", required=True)

    subs.add_parser("prepare")

    fin = subs.add_parser("finalize")
    fin.add_argument("google_enc", type=Path)
    fin.add_argument("google_manifest", type=Path)
    fin.add_argument("onedrive_enc", type=Path)
    fin.add_argument("onedrive_manifest", type=Path)

    args = parser.parse_args()

    if args.mode == "prepare":
        return prepare()

    return finalize(
        args.google_enc,
        args.google_manifest,
        args.onedrive_enc,
        args.onedrive_manifest,
    )


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"FALHA: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
