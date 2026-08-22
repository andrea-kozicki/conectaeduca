#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import stat
import subprocess
import sys
import time
import http.client
from pathlib import Path


# O retomador opera somente sobre o repositorio que contem este proprio script.
# Nao aceitamos override por variavel de ambiente para evitar que um processo
# privilegiado seja redirecionado para uma arvore arbitraria.
ROOT = Path(__file__).resolve().parents[2]

OPENBAO_CONTAINER = "conectaeduca-openbao"
OPENBAO_HOST = "127.0.0.1"
OPENBAO_PORT = 18200

# A custodia do LAB tambem possui local fixo no HOME do operador.
# Unseal shares nunca sao buscadas em caminho fornecido externamente.
CUSTODIA_DIR = (
    Path.home()
    / ".local/share/conectaeduca/openbao-custodia-lab"
)

SHARES = (
    CUSTODIA_DIR / "unseal-share-1.txt",
    CUSTODIA_DIR / "unseal-share-2.txt",
)

EXPECTED_CONTAINERS = (
    "conectaeduca-openbao",
    "conectaeduca-mariadb-local-mariadb-1",
    "conectaeduca-dmz-local-php-1",
    "conectaeduca-dmz-local-nginx-1",
    "conectaeduca-dmz-local-waf-1",
    "conectaeduca-ferret-ferret-1",
    "conectaeduca-mailpit-lab",
)

USE_COLOR = sys.stdout.isatty()


def cor(code: str, text: str) -> str:
    if not USE_COLOR:
        return text
    return f"\033[{code}m{text}\033[0m"


def info(msg: str) -> None:
    print(cor("36", f"INFO     {msg}"))


def ok(msg: str) -> None:
    print(cor("32", f"OK       {msg}"))


def aviso(msg: str) -> None:
    print(cor("33", f"AVISO    {msg}"))


def falha(msg: str) -> "NoReturn":
    print(cor("31", f"FALHA    {msg}"), file=sys.stderr)
    raise SystemExit(1)


def run(
    argv: list[str],
    *,
    check: bool = True,
    capture: bool = False,
) -> subprocess.CompletedProcess[str]:
    kwargs = {
        "cwd": ROOT,
        "text": True,
        "check": False,
    }

    if capture:
        kwargs["stdout"] = subprocess.PIPE
        kwargs["stderr"] = subprocess.PIPE

    proc = subprocess.run(argv, **kwargs)

    if check and proc.returncode != 0:
        falha(
            "comando retornou código "
            f"{proc.returncode}: {' '.join(argv)}"
        )

    return proc


def command_ok(argv: list[str]) -> bool:
    return (
        subprocess.run(
            argv,
            cwd=ROOT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode
        == 0
    )


def container_exists(name: str) -> bool:
    return command_ok(["docker", "inspect", name])


def container_running(name: str) -> bool:
    proc = run(
        [
            "docker",
            "inspect",
            "--format",
            "{{.State.Running}}",
            name,
        ],
        check=False,
        capture=True,
    )

    return (
        proc.returncode == 0
        and proc.stdout.strip() == "true"
    )


def http_json(
    method: str,
    path: str,
    payload: dict | None = None,
    accepted: set[int] | None = None,
) -> dict:
    if accepted is None:
        accepted = {200}

    if (
        not path.startswith("/v1/")
        or "://" in path
        or ".." in path.split("/")
    ):
        raise RuntimeError(f"path OpenBao inválido: {path!r}")

    data = None
    headers = {}

    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"

    # HTTP é deliberadamente restrito ao loopback do LAB.
    # Ao atravessar VMs, este cliente deve migrar para TLS.
    conn = http.client.HTTPConnection(
        OPENBAO_HOST,
        OPENBAO_PORT,
        timeout=5,
    )

    try:
        conn.request(
            method,
            path,
            body=data,
            headers=headers,
        )
        resp = conn.getresponse()
        raw = resp.read()
        status = resp.status
    except Exception as exc:
        raise RuntimeError(
            f"OpenBao indisponível: {type(exc).__name__}"
        ) from exc
    finally:
        conn.close()

    if status not in accepted:
        raise RuntimeError(
            f"OpenBao respondeu HTTP {status} em {path}"
        )

    if not raw:
        return {}

    return json.loads(raw.decode("utf-8"))


def wait_docker() -> None:
    info("1/8 - verificando Docker")

    if command_ok(["docker", "info"]):
        ok("Docker disponível")
        return

    aviso("Docker ainda não responde; iniciando serviço")
    run(["sudo", "systemctl", "start", "docker"])

    for _ in range(30):
        if command_ok(["docker", "info"]):
            ok("Docker iniciado")
            return
        time.sleep(1)

    falha("Docker não ficou disponível")


def wait_openbao_http() -> dict:
    for _ in range(45):
        try:
            return http_json(
                "GET",
                "/v1/sys/health",
                accepted={200, 429, 472, 473, 501, 503},
            )
        except Exception:
            time.sleep(1)

    falha("endpoint HTTP do OpenBao não ficou disponível")


def prepare_openbao_container() -> dict:
    info("2/8 - retomando OpenBao")

    if container_exists(OPENBAO_CONTAINER):
        if not container_running(OPENBAO_CONTAINER):
            run(["docker", "start", OPENBAO_CONTAINER])
            ok("container OpenBao iniciado")
        else:
            ok("container OpenBao já estava em execução")
    else:
        compose = ROOT / "deploy/interna/openbao/compose.yml"

        if not compose.is_file():
            falha("compose do OpenBao não encontrado")

        run(
            [
                "docker",
                "compose",
                "-f",
                str(compose),
                "up",
                "-d",
            ]
        )
        ok("OpenBao criado a partir do Compose versionado")

    status = wait_openbao_http()

    if status.get("initialized") is not True:
        falha(
            "OpenBao não está inicializado; "
            "o retomador se recusa a inicializá-lo automaticamente"
        )

    return status


def preparar_custodia() -> None:
    if not CUSTODIA_DIR.is_dir():
        falha(
            "diretório de custódia não encontrado: "
            f"{CUSTODIA_DIR}"
        )

    # Laboratório local: 0700 é intencional; 0644 seria menos seguro
    # e inadequado para diretório de custódia.
    os.chmod(CUSTODIA_DIR, 0o700)  # nosemgrep: python.lang.security.audit.insecure-file-permissions.insecure-file-permissions

    for arquivo in SHARES:
        if not arquivo.is_file():
            falha(
                "share de custódia ausente: "
                f"{arquivo.name}"
            )

        os.chmod(arquivo, 0o600)

        if not arquivo.read_text(
            encoding="utf-8"
        ).strip():
            falha(
                f"share vazia: {arquivo.name}"
            )


def unseal_openbao(status: dict) -> None:
    if status.get("sealed") is False:
        ok("OpenBao já estava desbloqueado")
        return

    aviso(
        "OpenBao está selado; usando a custódia LOCAL "
        "do laboratório sem imprimir as shares"
    )

    preparar_custodia()

    # Torna a operação idempotente caso uma tentativa anterior
    # tenha deixado progresso parcial de unseal.
    try:
        http_json(
            "POST",
            "/v1/sys/unseal",
            {"reset": True},
            accepted={200},
        )
        ok("progresso de unseal normalizado")
    except Exception as exc:
        falha(
            "não foi possível zerar com segurança "
            f"o progresso de unseal: {exc}"
        )

    ultimo = None

    for numero, arquivo in enumerate(SHARES, 1):
        chave = arquivo.read_text(
            encoding="utf-8"
        ).strip()

        try:
            ultimo = http_json(
                "POST",
                "/v1/sys/unseal",
                {"key": chave},
                accepted={200},
            )
        finally:
            chave = ""

        sealed = ultimo.get("sealed")
        progress = ultimo.get("progress")

        ok(
            f"share {numero}/2 processada; "
            f"sealed={sealed} progress={progress}"
        )

    if not ultimo or ultimo.get("sealed") is not False:
        falha(
            "OpenBao continua selado após o quorum esperado"
        )

    ok("OpenBao desbloqueado com quorum local")


def sudo_cache() -> None:
    info("3/8 - preparando privilégios locais mínimos")
    run(["sudo", "-v"])
    ok("credencial sudo temporariamente validada")


def materializar_smtp() -> None:
    info("4/8 - rematerializando SMTP via AppRole")

    script = (
        ROOT
        / "scripts/bootstrap/"
        "materializar_openbao_smtp_runtime.fish"
    )

    if not script.is_file():
        falha(
            "materializador runtime SMTP não encontrado"
        )

    run(["fish", str(script)])
    ok("SMTP rematerializado sem root token")


def subir_stack() -> None:
    info("5/8 - subindo stack local")

    script = (
        ROOT
        / "scripts/bootstrap/subir_stack_local.fish"
    )

    if not script.is_file():
        falha("launcher da stack local não encontrado")

    run(["fish", str(script)])
    ok("stack local operacional")


def subir_ferret() -> None:
    info("6/8 - retomando Ferret")

    name = "conectaeduca-ferret-ferret-1"

    raw_port = os.environ.get("FERRET_WEB_PORT", "18082")
    try:
        web_port = int(raw_port, 10)
    except ValueError:
        falha("FERRET_WEB_PORT deve ser um inteiro TCP valido")

    if not 1 <= web_port <= 65535:
        falha("FERRET_WEB_PORT fora do intervalo 1..65535")

    if container_exists(name):
        if not container_running(name):
            run(["docker", "start", name])
            ok("container Ferret iniciado sem pull")
        else:
            ok("container Ferret já estava em execução")
    else:
        script = (
            ROOT
            / "scripts/bootstrap/subir_ferret.fish"
        )

        if not script.is_file():
            falha("launcher do Ferret não encontrado")

        aviso(
            "container Ferret ausente; usando bootstrap versionado"
        )
        run(["fish", str(script)])

    for _ in range(30):
        conn = http.client.HTTPConnection(
            "127.0.0.1",
            web_port,
            timeout=2,
        )

        try:
            conn.request("GET", "/")
            resp = conn.getresponse()
            resp.read()

            # Qualquer resposta HTTP prova que o listener local esta vivo.
            if 100 <= resp.status <= 599:
                ok("Ferret operacional")
                return
        except OSError:
            pass
        finally:
            conn.close()

        time.sleep(1)

    falha("Ferret não respondeu na interface Web local")


def subir_mailpit() -> None:
    info("7/8 - retomando Mailpit")

    compose = ROOT / "deploy/lab/mailpit/compose.yml"

    if not compose.is_file():
        falha("Compose versionado do Mailpit não encontrado")

    run(
        [
            "docker",
            "compose",
            "-f",
            str(compose),
            "config",
        ],
        capture=True,
    )

    run(
        [
            "docker",
            "compose",
            "-f",
            str(compose),
            "up",
            "-d",
            "mailpit",
        ]
    )

    ok("Mailpit garantido pelo Compose versionado")


def state_container(name: str) -> dict:
    proc = run(
        [
            "docker",
            "inspect",
            "--format",
            "{{json .State}}",
            name,
        ],
        capture=True,
    )

    return json.loads(proc.stdout)


def verificar_baseline() -> None:
    info("8/8 - verificando baseline operacional")

    for nome in EXPECTED_CONTAINERS:
        if not container_exists(nome):
            falha(f"container obrigatório ausente: {nome}")

        aprovado = False

        for _ in range(60):
            state = state_container(nome)

            if not state.get("Running"):
                time.sleep(1)
                continue

            health = state.get("Health")

            if health:
                hstatus = health.get("Status")

                if hstatus == "healthy":
                    aprovado = True
                    break

                if hstatus == "unhealthy":
                    falha(f"{nome} ficou unhealthy")
            else:
                aprovado = True
                break

            time.sleep(1)

        if not aprovado:
            falha(
                f"{nome} não atingiu estado operacional"
            )

        health = state_container(nome).get("Health")
        detalhe = (
            health.get("Status")
            if health
            else "running"
        )

        ok(f"{nome}: {detalhe}")

    status = wait_openbao_http()

    if status.get("sealed") is not False:
        falha("OpenBao voltou a ficar selado")

    if not command_ok(
        [
            "curl",
            "-ksSf",
            "-o",
            "/dev/null",
            "https://conectaeduca.local:18444/login.php",
        ]
    ):
        falha("login HTTPS não responde via WAF")

    ok("aplicação HTTPS responde via WAF")

    secret = Path("/dev/shm/conectaeduca-smtp-password")

    if not secret.is_file():
        falha("secret SMTP materializado não foi encontrado em RAM")

    secret_stat = secret.stat()
    secret_mode = stat.S_IMODE(secret_stat.st_mode)

    if secret_stat.st_size <= 0:
        falha("secret SMTP materializado está vazio")

    if secret_mode != 0o640:
        falha(
            "secret SMTP materializado está com modo inesperado: "
            f"{oct(secret_mode)}"
        )

    ok(
        "secret SMTP validado em RAM: "
        "arquivo não vazio, mode=0640, conteúdo não exibido"
    )

    print()
    print("=" * 70)
    print(" CONECTAEDUCA - BASELINE PÓS-REBOOT: ONLINE")
    print("=" * 70)

    run(
        [
            "docker",
            "ps",
            "--format",
            "table {{.Names}}\t{{.Status}}\t{{.Image}}",
        ],
        check=False,
    )


def descobrir_checkpoint_bacula() -> Path:
    base = ROOT / "scripts/evidencias"
    candidatos: list[Path] = []

    if not base.is_dir():
        falha("diretório scripts/evidencias não encontrado")

    for path in base.iterdir():
        if not path.is_file():
            continue

        if path.suffix not in {".fish", ".sh", ".py"}:
            continue

        try:
            texto = path.read_text(
                encoding="utf-8",
                errors="ignore",
            )
        except Exception:
            continue

        if (
            "pre-bacula-arch-1.0" in texto
            or "CHECKPOINT ARQUITETURA PRÉ-BACULA" in texto
        ):
            candidatos.append(path)

    if len(candidatos) != 1:
        nomes = ", ".join(
            p.name for p in candidatos
        ) or "nenhum"

        falha(
            "não encontrei exatamente um checkpoint "
            f"arquitetural pré-Bacula; encontrados: {nomes}"
        )

    return candidatos[0]


def executar_script(path: Path) -> None:
    if path.suffix == ".fish":
        run(["fish", str(path)])
    elif path.suffix == ".sh":
        run(["bash", str(path)])
    elif path.suffix == ".py":
        run(["python3", str(path)])
    else:
        falha(f"tipo de script não suportado: {path}")


def gate_pre_bacula() -> None:
    print()
    print("=" * 70)
    print(" CONECTAEDUCA - GATE FINAL PRÉ-BACULA")
    print("=" * 70)

    status = run(
        ["git", "status", "--porcelain"],
        capture=True,
    ).stdout

    if status.strip():
        print(status.rstrip())
        falha(
            "working tree não está limpa. "
            "Consolide/commite a argamassa antes de iniciar Bacula."
        )

    ok("working tree limpa")

    run(["git", "diff", "--check"])
    ok("git diff --check")

    geral = (
        ROOT
        / "scripts/evidencias/"
        "checkpoint_containerizacao_geral.fish"
    )

    if not geral.is_file():
        falha("checkpoint geral não encontrado")

    info("executando checkpoint geral COMPLETO")
    run(["fish", str(geral), "--completo"])
    ok("checkpoint geral completo aprovado")

    arch = descobrir_checkpoint_bacula()

    info(
        "executando checkpoint arquitetural pré-Bacula: "
        f"{arch.name}"
    )
    executar_script(arch)

    ok("checkpoint arquitetural pré-Bacula aprovado")

    print()
    print("=" * 70)
    print(" BACULA: PORTÃO DE ENTRADA APROVADO")
    print("=" * 70)
    print(
        "Wazuh Agent nativo/FIM/YARA e Twingate "
        "continuam fora deste gate."
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Retomada idempotente do laboratório ConectaEduca "
            "após reboot."
        )
    )

    parser.add_argument(
        "--pre-bacula",
        action="store_true",
        help=(
            "após retomar o ambiente, exige árvore Git limpa "
            "e executa os checkpoints completos pré-Bacula"
        ),
    )

    args = parser.parse_args()

    if not ROOT.is_dir():
        falha(f"repositório não encontrado: {ROOT}")

    os.chdir(ROOT)

    print("=" * 70)
    print(" CONECTAEDUCA - ARGAMASSA DE RETOMADA PÓS-REBOOT")
    print("=" * 70)

    wait_docker()

    status = prepare_openbao_container()
    unseal_openbao(status)

    sudo_cache()
    materializar_smtp()
    subir_stack()
    subir_ferret()
    subir_mailpit()
    verificar_baseline()

    if args.pre_bacula:
        gate_pre_bacula()


if __name__ == "__main__":
    main()
