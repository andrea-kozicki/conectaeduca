#!/usr/bin/env fish

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositório ConectaEduca." >&2
    exit 1
end

cd "$ROOT"

set COMPOSE deploy/interna/openbao/compose.yml
set PROVISIONER scripts/bootstrap/provisionar_openbao_smtp.py

echo
echo "======================================================================"
echo " CONECTAEDUCA - OPENBAO OPERACIONAL / PREPARAÇÃO SMTP"
echo "======================================================================"

for cmd in docker python3 git
    if not type -q $cmd
        echo "FALHA       comando ausente: $cmd"
        exit 1
    end
end

if not test -f "$PROVISIONER"
    echo "FALHA       provisionador ausente: $PROVISIONER"
    exit 1
end

docker compose -f "$COMPOSE" config >/dev/null
or begin
    echo "FALHA       Docker Compose do OpenBao é inválido"
    exit 1
end

echo "OK          compose OpenBao válido"

# Recria para garantir que a configuração declarativa de auditoria está carregada.
docker compose -f "$COMPOSE" up -d --force-recreate
or begin
    echo "FALHA       OpenBao não iniciou"
    exit 1
end

echo "OK          OpenBao iniciado/recriado com configuração atual"

set RELATORIO /tmp/conectaeduca-openbao-smtp-operacional-(date +%Y%m%d-%H%M%S).txt

python3 "$PROVISIONER" | tee "$RELATORIO"
set RC $pipestatus[1]

echo
echo "Relatório:"
echo "$RELATORIO"

if test $RC -ne 0
    echo "FALHA       operacionalização OpenBao/SMTP reprovada"
    exit $RC
end

echo "OK          OpenBao operacionalizado para SMTP"
