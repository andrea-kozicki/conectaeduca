#!/usr/bin/env fish

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositório ConectaEduca." >&2
    exit 1
end

cd "$ROOT"

set PY scripts/bootstrap/materializar_openbao_smtp_runtime.py
set BRIDGE scripts/bootstrap/preparar_smtp_secret_container.fish

python3 "$PY"
or exit 1

fish "$BRIDGE"
or exit 1

echo "OK          materialização SMTP runtime concluída sem reprovisionar OpenBao"
