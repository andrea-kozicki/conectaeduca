#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT=/opt/conectaeduca
BRANCH=origin/docs/fase3-arquitetura-zero-trust-20261021
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"
OUT="$BASE/GA08"; DIARIO="$BASE/diario.md"
mkdir -p "$OUT"
LOG="$OUT/GA08_COMPOSE_ESTATICO_$(date +%Y%m%dT%H%M%S).txt"
TMP=$(mktemp -d)
STATUS=BLOQUEADO
finish() {
 rc=$?; trap - EXIT
 rm -rf "$TMP"
 [[ $rc -eq 0 ]] && STATUS=VALIDADO_ESTATICAMENTE
 printf '\n## GA-08 — Validação estática Compose — %s\nStatus: %s\nEvidência: %s\nProdução: não alterada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true
 echo "STATUS=$STATUS"; exit "$rc"
}
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 COMPOSE ESTATICO — SEM APLICACAO ==="
echo "DATA=$(date -Is)"
test -d "$ROOT/.git"
test -w "$DIARIO"
docker compose version
FILES=(compose.yml compose.database.yml compose.app-secrets.yml compose.waf.yml compose.waf-tls.yml compose.waf-policy.yml compose.host.yml compose.vm.yml compose.database-tls.yml compose.audit-persistent.yml)
args=()
for f in "${FILES[@]}"; do
 test -r "$ROOT/deploy/dmz/$f" || { echo "BLOQUEIO=COMPOSE_BASE_AUSENTE:$f"; exit 2; }
 args+=(-f "$ROOT/deploy/dmz/$f")
done
for p in deploy/dmz/compose.ga08-socket.candidate.yml deploy/dmz/ga08/app-http.socket.candidate.conf deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf; do
 git -C "$ROOT" show "$BRANCH:$p" > "$TMP/$(basename "$p")" || { echo "BLOQUEIO=CANDIDATO_AUSENTE:$p"; exit 2; }
done
if grep -Eq '^[[:space:]]*listen\.(owner|group)[[:space:]]*=' "$TMP/zz-conectaeduca.socket.candidate.conf"; then
 echo "BLOQUEIO=FPM_CHOWN_NAO_ROOT"; exit 2
fi
grep -q 'fastcgi_pass unix:/run/conectaeduca-fpm/php-fpm.sock;' "$TMP/app-http.socket.candidate.conf" || { echo "BLOQUEIO=NGINX_SEM_SOCKET"; exit 2; }
grep -q 'listen = /run/conectaeduca-fpm/php-fpm.sock' "$TMP/zz-conectaeduca.socket.candidate.conf" || { echo "BLOQUEIO=FPM_SEM_SOCKET"; exit 2; }
# Use diretório fictício: 'config' apenas, sem montagem real ou criação de contêiner.
export CONECTAEDUCA_GA08_SOCKET_DIR="$TMP/socket"
export CONECTAEDUCA_GA08_NGINX_CONF="$TMP/app-http.socket.candidate.conf"
export CONECTAEDUCA_GA08_FPM_CONF="$TMP/zz-conectaeduca.socket.candidate.conf"
args+=(-f "$TMP/compose.ga08-socket.candidate.yml")
# Não imprimir config interpolada, pois pode conter credenciais.
if ! docker compose --project-directory "$ROOT/deploy/dmz" "${args[@]}" config --quiet >"$TMP/compose.out" 2>"$TMP/compose.err"; then
 echo "BLOQUEIO=COMPOSE_CONFIG_INVALIDO"
 # Saída de erro potencialmente sensível: não exibir automaticamente.
 echo "ERRO_COMPOSE_OCULTADO=SIM"
 exit 2
fi
echo "COMPOSE_CONFIG=PASS"
# Saída sem interpolação de segredos: somente inspeção textual do overlay versionado.
grep -q 'networks: !override' "$TMP/compose.ga08-socket.candidate.yml" || { echo "BLOQUEIO=SEM_OVERRIDE_REDES"; exit 2; }
grep -q 'group_add:' "$TMP/compose.ga08-socket.candidate.yml" || { echo "BLOQUEIO=SEM_GRUPO_SOCKET"; exit 2; }
grep -q 'read_only: true' "$TMP/compose.ga08-socket.candidate.yml" || { echo "BLOQUEIO=SEM_MOUNT_READ_ONLY"; exit 2; }
echo "OVERLAY_SOCKET=PASS"
echo "REDES_CANDIDATAS=waf_backend,php_egress"
echo "PHP_EP126=NAO_VALIDADO"
echo "ISOLAMENTO_RUNTIME=NAO_VALIDADO"
echo "ROLLBACK_TESTADO=NAO"
echo "PRODUCAO=NAO_ALTERADA"
