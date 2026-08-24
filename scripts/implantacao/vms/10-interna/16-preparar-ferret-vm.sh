#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"; [[ -n "$ROOT" && -d "$ROOT/.git" ]] || exit 1
DIR="$ROOT/deploy/interna/ferret"; RUNTIME="$DIR/.runtime"; COMPOSE="$DIR/compose.yml"; MODE=check
while (($#)); do case "$1" in --apply) MODE=apply; shift;; --check) MODE=check; shift;; --self-test) [[ -f "$COMPOSE" ]] && grep -Fq '127.0.0.1' "$COMPOSE" && echo 'SELF_TEST_FERRET_VM=APROVADO'; exit;; *) exit 64;; esac; done
[[ "$(hostname)" == conectaeduca-interna ]] || { echo "ERRO: execute em CE-UBUNTU-INT" >&2; exit 1; }
for p in "$RUNTIME" "$RUNTIME/state" "$RUNTIME/inbox" "$RUNTIME/reports" "$RUNTIME/reports/raw" "$RUNTIME/events"; do install -d -m 0700 "$p"; done
owner="$(stat -c '%u:%g' "$RUNTIME")"; if [[ "$owner" != 1000:1000 ]]; then if [[ "$MODE" == apply && $(id -u) -eq 0 ]]; then chown -R 1000:1000 "$RUNTIME"; else echo "ERRO: runtime Ferret deve pertencer a 1000:1000; atual=$owner" >&2; exit 1; fi; fi
[[ "$MODE" == check ]] && { echo 'FERRET_VM=RUNTIME_PRONTO'; exit 0; }
command -v docker >/dev/null && docker info >/dev/null 2>&1 || exit 1; docker compose -f "$COMPOSE" config >/dev/null; docker compose -f "$COMPOSE" up -d
cid="$(docker compose -f "$COMPOSE" ps -q ferret)"; [[ -n "$cid" ]] || exit 1; echo 'FERRET_VM=INICIADO'
