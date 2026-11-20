#!/usr/bin/env bash
# GA-08 / PA-02 — gate operacional para EP125.
# Sem --execute: somente preflight; nenhum Docker Compose up.
# Com --execute: exige aprovacao privada do operador, snapshot e interlock.
set -Eeuo pipefail
umask 077
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 "$SCRIPT_DIR/ga08-change-control.py" --action cutover "$@"
