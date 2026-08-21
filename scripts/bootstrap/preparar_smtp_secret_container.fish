#!/usr/bin/env fish

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositório ConectaEduca." >&2
    exit 1
end
cd "$ROOT"

set GROUP_NAME conectaeduca-smtp-secret
set ENV_FILE deploy/dmz/.runtime/smtp-google.env
set SECRET_FILE /dev/shm/conectaeduca-smtp-password

echo
echo "======================================================================"
echo " CONECTAEDUCA - PONTE DE ACESSO AO SECRET SMTP"
echo " Grupo dedicado host -> container www-data, sem ampliar para outros"
echo "======================================================================"

if not test -f "$ENV_FILE"
    echo "FALHA       runtime SMTP ausente: $ENV_FILE"
    exit 1
end

if not test -f "$SECRET_FILE"
    echo "FALHA       segredo SMTP materializado ausente: $SECRET_FILE"
    exit 1
end

set owner_uid (stat -c '%u' "$SECRET_FILE")
set current_uid (id -u)

if test "$owner_uid" != "$current_uid"
    echo "FALHA       segredo não pertence ao usuário atual; owner_uid=$owner_uid current_uid=$current_uid"
    exit 1
end

echo "OK          segredo pertence ao usuário que materializou via OpenBao"

if not getent group "$GROUP_NAME" >/dev/null 2>&1
    echo "INFO        criando grupo de sistema dedicado: $GROUP_NAME"
    sudo groupadd --system "$GROUP_NAME"
    or begin
        echo "FALHA       não foi possível criar grupo dedicado"
        exit 1
    end
end

set GROUP_LINE (getent group "$GROUP_NAME")
set GROUP_GID (string split ':' -- "$GROUP_LINE")[3]
set GROUP_MEMBERS (string split ':' -- "$GROUP_LINE")[4]

if test -z "$GROUP_GID"
    echo "FALHA       GID do grupo dedicado não pôde ser determinado"
    exit 1
end

if test -n "$GROUP_MEMBERS"
    echo "FALHA       grupo dedicado possui membros explícitos; esperado nenhum"
    exit 1
end

echo "OK          grupo dedicado existe sem membros explícitos (gid=$GROUP_GID)"

sudo chgrp "$GROUP_GID" "$SECRET_FILE"
or begin
    echo "FALHA       não foi possível atribuir grupo dedicado ao secret"
    exit 1
end

chmod 0640 "$SECRET_FILE"
or begin
    echo "FALHA       não foi possível definir modo 0640"
    exit 1
end

set mode (stat -c '%a' "$SECRET_FILE")
set gid (stat -c '%g' "$SECRET_FILE")

if test "$mode" != "640"
    echo "FALHA       modo inesperado após preparação: $mode"
    exit 1
end

if test "$gid" != "$GROUP_GID"
    echo "FALHA       GID inesperado após preparação: $gid"
    exit 1
end

echo "OK          secret em RAM ficou owner-read/write + grupo dedicado read-only + other deny"

# Atualiza apenas a variável não secreta de GID.
set TMP_ENV (mktemp /tmp/conectaeduca-smtp-env.XXXXXX)
chmod 600 "$TMP_ENV"

grep -Ev '^CONECTAEDUCA_SMTP_SECRET_GID=' "$ENV_FILE" > "$TMP_ENV"
printf 'CONECTAEDUCA_SMTP_SECRET_GID=%s\n' "$GROUP_GID" >> "$TMP_ENV"

cat "$TMP_ENV" > "$ENV_FILE"
rm -f "$TMP_ENV"
chmod 600 "$ENV_FILE"

echo "OK          GID runtime registrado sem expor qualquer credencial"

echo
echo "Verificação:"
stat -c 'secret: mode=%a uid=%u gid=%g bytes=%s' "$SECRET_FILE"
echo "grupo=$GROUP_NAME gid=$GROUP_GID membros_explicitos=nenhum"

echo
echo "PONTE SMTP SECRET: PREPARADA."
