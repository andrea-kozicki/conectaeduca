#!/usr/bin/env bash
# GA-08 / PA-02 — restauracao seletiva do baseline da EP125.
# Sem --execute: verifica manifesto e configuracao; nao recria containers.
# Com --execute: exige aprovacao independente e confirmacao explicita.
set -Eeuo pipefail
umask 077
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 "$SCRIPT_DIR/ga08-change-control.py" --action rollback "$@"
