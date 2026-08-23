#!/usr/bin/env fish
set -l OUT /dev/shm/conectaeduca-twingate.env

if not test -d /dev/shm
    echo "ERRO: /dev/shm indisponível." >&2
    exit 1
end

echo "Preparação efêmera do Twingate Connector."
echo "Nenhum token será exibido."

read -P "Twingate Network (ex.: conectaeducalab): " TWINGATE_NETWORK
if test -z "$TWINGATE_NETWORK"
    echo "ERRO: TWINGATE_NETWORK vazio." >&2
    exit 1
end

read -s -P "Access Token: " TWINGATE_ACCESS_TOKEN
echo
if test -z "$TWINGATE_ACCESS_TOKEN"
    echo "ERRO: Access Token vazio." >&2
    exit 1
end

read -s -P "Refresh Token: " TWINGATE_REFRESH_TOKEN
echo
if test -z "$TWINGATE_REFRESH_TOKEN"
    echo "ERRO: Refresh Token vazio." >&2
    exit 1
end

set -l OLD_UMASK (umask)
umask 077

printf 'TWINGATE_NETWORK=%s\n' "$TWINGATE_NETWORK" > "$OUT"
printf 'TWINGATE_ACCESS_TOKEN=%s\n' "$TWINGATE_ACCESS_TOKEN" >> "$OUT"
printf 'TWINGATE_REFRESH_TOKEN=%s\n' "$TWINGATE_REFRESH_TOKEN" >> "$OUT"

chmod 600 "$OUT"
umask "$OLD_UMASK"

set -e TWINGATE_ACCESS_TOKEN
set -e TWINGATE_REFRESH_TOKEN

echo "OK: runtime criado em $OUT"
echo "OK: modo "(stat -c '%a' "$OUT")
echo "AVISO: arquivo efêmero; será perdido no reboot."
