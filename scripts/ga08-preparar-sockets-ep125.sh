#!/usr/bin/env bash
# GA-08 / PA-02 — preparar SOMENTE diretórios persistentes para sockets Unix.
# Não executa Docker Compose, não reinicia serviços, não modifica segredos,
# não troca imagens, não altera /etc/hosts nem o checkout Git.
# Uso autorizado na EP125: sudo ./scripts/ga08-preparar-sockets-ep125.sh --prepare
set -Eeuo pipefail
umask 077

die() { printf 'GA08_PREPARACAO=BLOCKED_%s\n' "$1" >&2; exit 2; }
[[ "${1:-}" == "--prepare" && "$#" == "1" ]] || die USO_ESPERADO_PREPARE
[[ "$(id -u)" == "0" ]] || die PRIVILEGIOS
case "$(hostname -s)" in ep125-pucpr|ep125-pucpr-br) ;; *) die HOST ;; esac

ROOT="/opt/conectaeduca"
DMZ="$ROOT/deploy/dmz"
BASE="/var/lib/conectaeduca-ga08"
FPM="$BASE/fpm"
HTTP="$BASE/http"

[[ -d "$ROOT/.git" || -f "$ROOT/.git" ]] || die CHECKOUT_INSTITUCIONAL
for rel in \
  compose.ga08-socket.candidate.yml \
  compose.ga08-dual-socket.candidate.yml \
  ga08/app-http.socket.candidate.conf \
  ga08/app-http.dual-socket.candidate.conf \
  ga08/zz-conectaeduca.socket.candidate.conf
do
  [[ -f "$DMZ/$rel" && ! -L "$DMZ/$rel" ]] || die CANDIDATO_NAO_INSTALADO
done

for p in "$BASE" "$FPM" "$HTTP"; do
  [[ ! -L "$p" ]] || die CAMINHO_SYMLINK
  [[ ! -e "$p" || -d "$p" ]] || die CAMINHO_NAO_DIRETORIO
done

# Se já existem, aceitamos SOMENTE diretórios vazios, com dono/modo corretos.
check_existing() {
  local d="$1" expected="$2" policy="${3:-empty}"
  [[ -d "$d" ]] || return 0
  [[ "$(stat -c '%u:%g:%a' "$d")" == "$expected" ]] || die DIRETORIO_EXISTENTE_DIVERGENTE
  if [[ "$policy" == "empty" ]]; then
    [[ -z "$(find "$d" -mindepth 1 -maxdepth 1 -print -quit)" ]] || die DIRETORIO_NAO_VAZIO
  fi
}
check_existing "$BASE" "0:0:711" "allow_contents"
check_existing "$FPM" "82:82:770"
check_existing "$HTTP" "101:101:700"

# Pai 0711 permite travessia (não listagem); subdiretórios são isolados por UID/GID.
[[ -d "$BASE" ]] || install -d -o 0 -g 0 -m 0711 "$BASE"
[[ -d "$FPM" ]] || install -d -o 82 -g 82 -m 0770 "$FPM"
[[ -d "$HTTP" ]] || install -d -o 101 -g 101 -m 0700 "$HTTP"

check_existing "$BASE" "0:0:711" "allow_contents"
check_existing "$FPM" "82:82:770"
check_existing "$HTTP" "101:101:700"

printf '%s\n' "=== GA08 — SOCKETS PREPARADOS (EP125) ==="
printf '%s\n' "GA08_PREPARACAO=PASS" "FPM_SOCKET_OWNER_MODE=82:82:770" \
  "HTTP_SOCKET_OWNER_MODE=101:101:700" "DIRETORIO_PAI=ROOT_711" \
  "DOCKER_COMPOSE_EXECUTADO=NAO" "CONTEINERES_MODIFICADOS=NAO" \
  "SEGREDOS_LIDOS=NAO" "CUTOVER_EXECUTADO=NAO"

# Os paths públicos abaixo não contêm valores secretos; exportar no shell
# do operador normal antes de executar preflight/cutover controlado.
printf '%s\n' "ENV_GA08_SOCKET_DIR=$FPM" "ENV_GA08_HTTP_SOCKET_DIR=$HTTP" \
 "ENV_GA08_NGINX_CONF=$DMZ/ga08/app-http.socket.candidate.conf" \
 "ENV_GA08_NGINX_HTTP_UNIX_CONF=$DMZ/ga08/app-http.dual-socket.candidate.conf" \
 "ENV_GA08_FPM_CONF=$DMZ/ga08/zz-conectaeduca.socket.candidate.conf"
