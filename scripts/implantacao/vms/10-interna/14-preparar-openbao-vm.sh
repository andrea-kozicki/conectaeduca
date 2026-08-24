#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"; [[ -n "$ROOT" && -d "$ROOT/.git" ]] || exit 1
IMAGE='openbao/openbao:2.6.1@sha256:5b2486ab0fb90bbc788cc345b0a08616dfb375873ee8be5df3a2fd4d378a67e0'; COMPOSE="$ROOT/deploy/interna/openbao/compose.yml"; RUNTIME="$ROOT/deploy/interna/openbao/.runtime"; VOLUME=conectaeduca-openbao-data; MODE=check
while (($#)); do case "$1" in --apply) MODE=apply; shift;; --check) MODE=check; shift;; --self-test) [[ -f "$COMPOSE" ]] && grep -Eq 'tls_disable[[:space:]]*=[[:space:]]*true' "$ROOT/deploy/interna/openbao/config/openbao.hcl" && echo 'SELF_TEST_OPENBAO_VM=APROVADO'; exit;; *) exit 64;; esac; done
[[ "$(hostname)" == conectaeduca-interna ]] || { echo "ERRO: execute em CE-UBUNTU-INT" >&2; exit 1; }; command -v docker >/dev/null && docker info >/dev/null 2>&1 || { echo "ERRO: Docker indisponível" >&2; exit 1; }
install -d -m 0700 "$RUNTIME"; docker compose -f "$COMPOSE" config >/dev/null
[[ "$MODE" == check ]] && { echo 'OPENBAO_VM=PRONTO_PARA_PREPARAR'; echo 'OPENBAO_CROSS_VM=NAO_HABILITADO'; exit 0; }
docker pull --platform linux/amd64 "$IMAGE" >/dev/null; docker volume inspect "$VOLUME" >/dev/null 2>&1 || docker volume create "$VOLUME" >/dev/null
docker run --rm --user 0:0 --entrypoint /bin/sh -v "$VOLUME:/openbao/data" "$IMAGE" -ec 'chown -R openbao:openbao /openbao/data; chmod 700 /openbao/data'
docker compose -f "$COMPOSE" up -d
echo 'OPENBAO_VM=INICIADO_NAO_INICIALIZADO'; echo 'PENDENTE=INIT_UNSEAL_CUSTODIA'; echo 'CROSS_VM_TLS=NAO_IMPLEMENTADO_NESTA_FASE'
