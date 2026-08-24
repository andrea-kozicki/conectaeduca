#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"; [[ -n "$ROOT" && -d "$ROOT/.git" ]] || exit 1
ROLE=""; MODE=check; INSTALL_FD=0
while (($#)); do case "$1" in --role) ROLE="${2:-}"; shift 2;; --check) MODE=check; shift;; --apply-readiness) MODE=apply; shift;; --install-fd) INSTALL_FD=1; shift;; --self-test) [[ -f "$ROOT/deploy/interna/bacula/CONTRATO-FD-VM.md" ]] && echo 'SELF_TEST_BACULA_VM=APROVADO'; exit;; *) exit 64;; esac; done
[[ "$ROLE" == dmz || "$ROLE" == interna ]] || exit 64; expected=conectaeduca-$ROLE; [[ "$ROLE" == interna ]] && expected=conectaeduca-interna; [[ "$(hostname)" == "$expected" ]] || { echo "ERRO: hostname incompatível" >&2; exit 1; }
TEMPLATE="$ROOT/deploy/$ROLE/bacula-fd/bacula-fd.conf.example"; [[ "$ROLE" == interna ]] && TEMPLATE="$ROOT/deploy/interna/bacula/fd/bacula-fd.conf.example"; [[ -f "$TEMPLATE" ]] || exit 1; grep -q '__RUNTIME_SECRET_' "$TEMPLATE" || exit 1
echo 'BACULA_FD_TLS=OBRIGATORIO'; echo 'BACULA_FD_SECRET=DEVE_SER_MATERIALIZADO_NA_VM'
if [[ "$ROLE" == interna ]]; then [[ -f "$ROOT/deploy/interna/bacula/compose.vm.yml" ]] || exit 1; if command -v docker >/dev/null && docker info >/dev/null 2>&1; then docker compose -f "$ROOT/deploy/interna/bacula/compose.vm.yml" config >/dev/null || exit 1; echo 'BACULA_CORE_COMPOSE=VALIDO'; else echo 'BACULA_CORE_COMPOSE=NAO_VALIDADO_SEM_DOCKER'; fi; fi
if (( INSTALL_FD )); then [[ "$MODE" == apply ]] || exit 64; [[ $(id -u) -eq 0 ]] || exit 1; bash "$ROOT/scripts/implantacao/preparar_bacula_fd_ubuntu.sh" "$ROLE" "$ROOT"; fi
echo 'BACULA_VM=READINESS_CONCLUIDO'; echo 'BACULA_FD_ATIVACAO=PENDENTE_TLS_E_SECRET_FINAL'
