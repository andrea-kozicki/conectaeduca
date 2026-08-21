#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FAILURES: list[str] = []


def fail(path: Path, line: int, rule: str) -> None:
    try:
        shown = path.relative_to(ROOT)
    except ValueError:
        shown = path
    FAILURES.append(f"{shown}:{line}: {rule}")


def scan_lines(path: Path, checks: list[tuple[re.Pattern[str], str]]) -> None:
    if not path.is_file():
        FAILURES.append(f"{path.relative_to(ROOT)}: arquivo ausente")
        return
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        for pattern, rule in checks:
            if pattern.search(line):
                fail(path, number, rule)


# Fixtures: valores sensíveis de teste devem nascer em runtime, nunca ser literais.
for rel in [
    "scripts/evidencias/checkpoint_password_reset_http.php",
    "scripts/evidencias/checkpoint_password_reset_e2e.php",
    "scripts/evidencias/checkpoint_password_reset_mariadb.php",
]:
    scan_lines(
        ROOT / rel,
        [
            (
                re.compile(
                    r"\$(?:old|new|initial|replay)?Password\s*=\s*['\"]"
                ),
                "password de fixture atribuído como literal",
            ),
            (
                re.compile(r"password_hash\(\s*['\"]"),
                "password_hash recebeu literal diretamente",
            ),
        ],
    )

scan_lines(
    ROOT / "tests/Unit/Service/MailServiceTest.php",
    [
        (
            re.compile(
                r"\$_ENV\[['\"]MAIL_PASSWORD['\"]\]\s*=\s*['\"][^'\"]+"
            ),
            "credencial SMTP de teste hardcoded",
        ),
    ],
)

# Exemplo de ambiente: senha direta deve permanecer vazia; secrets reais são por arquivo.
env_example = ROOT / ".env.example"
if env_example.is_file():
    for number, raw in enumerate(env_example.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip().upper()
        value = value.strip()
        if key in {"DB_PASS", "MAIL_PASSWORD"} and value:
            fail(env_example, number, f"{key} deve ficar vazio no template")

# Snyk: checkpoint CLI não deve devolver texto cru de exceção/driver.
scan_lines(
    ROOT / "scripts/evidencias/checkpoint_password_reset_mariadb.php",
    [(re.compile(r"getMessage\s*\("), "mensagem interna de exceção exposta no checkpoint")],
)

# Checkpoints não devem imprimir mensagens cruas de exceção.
for rel in [
    "scripts/evidencias/checkpoint_password_reset_http.php",
    "scripts/evidencias/checkpoint_crypto_hybrid_v2.php",
]:
    scan_lines(
        ROOT / rel,
        [
            (
                re.compile(r"(?:printf|echo|info|failure).*getMessage\s*\("),
                "mensagem crua de exceção enviada à saída",
            ),
        ],
    )

# Semgrep: transporte OpenBao não deve aceitar urllib dinâmico.
scan_lines(
    ROOT / "scripts/bootstrap/provisionar_openbao_smtp.py",
    [(re.compile(r"urllib\.request\.urlopen\s*\("), "urlopen dinâmico ainda presente")],
)

# Semgrep: proc_open é permitido somente no checkpoint cripto com comando em array,
# script canônico local e supressão específica/documentada.
crypto = ROOT / "scripts/evidencias/checkpoint_crypto_hybrid_v2.php"
if crypto.is_file():
    text = crypto.read_text(encoding="utf-8")
    required = [
        "realpath($script)",
        "['node', $script]",
        "nosemgrep: php.lang.security.exec-use.exec-use",
    ]
    for marker in required:
        if marker not in text:
            FAILURES.append(f"{crypto.relative_to(ROOT)}: hardening esperado ausente: {marker}")

# Nenhum runtime/segredo materializado deve estar rastreado.
tracked = subprocess.run(
    ["git", "ls-files"], cwd=ROOT, text=True, capture_output=True, check=True
).stdout.splitlines()
for item in tracked:
    if re.search(r"(^|/)\.runtime(/|$)|(^|/)\.env$", item):
        FAILURES.append(f"{item}: runtime/.env real rastreado pelo Git")
        continue
    if re.search(r"\.(?:pem|key|p12|pfx)$", item) and not (
        item.startswith("tests/") or item.startswith("scripts/evidencias/")
    ):
        FAILURES.append(f"{item}: chave/keystore rastreado fora das fixtures permitidas")

if FAILURES:
    print("FALHA       higiene estática pré-DLP encontrou problemas:")
    for item in FAILURES:
        print(f"            {item}")
    raise SystemExit(1)

print("OK          nenhuma credencial sintética fixa nos checkpoints auditados")
print("OK          .env.example não contém senha direta preenchida")
print("OK          checkpoint MariaDB não expõe mensagens cruas de exceção")
print("OK          cliente OpenBao não usa urllib.urlopen dinâmico")
print("OK          proc_open do checkpoint cripto está restrito e documentado")
print("OK          nenhum runtime/.env real/chave privada está rastreado")
