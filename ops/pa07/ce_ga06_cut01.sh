#!/usr/bin/env bash
# CE-GA06-CUT01: Ferret PA-07, troca reversivel v2.4.3 -> v5 na EP126.
# Invocar como sudo ./ce_ga06_cut01.sh --apply, sem sudo -s.
set -Eeuo pipefail
umask 077
export LC_ALL=C
ROOT=/opt/conectaeduca
BASE="$ROOT/deploy/interna/ferret/compose.yml"
OVERRIDE="$ROOT/deploy/interna/ferret/pa07-v5/compose.pa07-v5.override.yml"
SOURCE="$ROOT/deploy/interna/ferret/pa07-v5/90-ga06-ferret-v5-healthcheck.conf"
MANIFEST="$ROOT/deploy/interna/ferret/pa07-v5/GA06_CANDIDATE_PROVENANCE.json"
PREFLIGHT="$ROOT/scripts/evidencias/ga06_preflight_tar_local.sh"
ARCHIVE=/home/andrea.kiew/Downloads/ferret-pa07-v5-candidate-docker-archive.tar
MONITOR=conectaeduca-ferret-healthcheck.service
TIMER=conectaeduca-ferret-healthcheck.timer
DROP_DIR=/etc/systemd/system/conectaeduca-ferret-healthcheck.service.d
DROP="$DROP_DIR/90-ga06-ferret-v5.conf"
HEAD=04f88d275064a005d0ffcd4f9372a371c28c32d5
NEW=localhost/conectaeduca/ferret-scan:2.4.3-pa07-v5-candidate
NEW_ID=sha256:535ec9efb590dbaaeca41123321d773ba6d26d338686d89605492380ae9e187d
OLD=public.ecr.aws/awslabs/ferret-scan:2.4.3@sha256:7a1b36050ae20a74632ac05b5c34e4aeb26b69836ca6703e10c1392b724b270f
TMP=''
TIMER_STOPPED=0
TOUCHED=0
DROP_CREATED=0
SUCCESS=0
abort() { echo "CE-GA06-CUT01_ABORTADO=$1" >&2; exit 1; }
check_blob() {
  [[ -f "$1" && ! -L "$1" ]] || abort "ARQUIVO_AUSENTE_$(basename "$1")"
  [[ "$(git hash-object -- "$1")" == "$2" ]] || abort "HASH_INVALIDO_$(basename "$1")"
}
health() {
  local response="$2" i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if curl --max-time 5 -fsS 'http://127.0.0.1:18082/health' -o "$response" 2>/dev/null &&
       python3 - "$response" "$1" <<'PY' >/dev/null 2>&1
import json,sys
data=json.load(open(sys.argv[1],encoding="utf-8"))
assert data.get("status")=="healthy"
assert data.get("service")=="ferret-scan-web"
assert str(data.get("version"))==sys.argv[2]
PY
    then return 0; fi
    sleep 2
  done
  return 1
}
rollback() {
  set +e
  echo 'CE-GA06-ROLLBACK=INICIANDO'
  if [[ "$DROP_CREATED" == 1 ]]; then
    rm -f -- "$DROP"
    systemctl daemon-reload >/dev/null 2>&1
  fi
  if [[ "$TOUCHED" == 1 ]]; then
    if docker compose -f "$BASE" up -d --no-deps --pull never ferret >"$TMP/rollback.log" 2>&1 &&
       health 2.4.3 "$TMP/rollback-health.json"; then
      echo 'ROLLBACK_FERRET_2_4_3=PASS'
    else
      echo 'ROLLBACK_FERRET_2_4_3=FALHA_ESCALAR_OPERADOR'
    fi
  fi
  if [[ "$TIMER_STOPPED" == 1 ]]; then
    systemctl start "$TIMER" >/dev/null 2>&1 ||
      echo 'ROLLBACK_TIMER=FALHA_ESCALAR_OPERADOR'
  fi
  echo 'CE-GA06-ROLLBACK=FINALIZADO'
}
cleanup() {
  local rc="$?"
  trap - EXIT
  if [[ "$SUCCESS" == 0 && ( "$TIMER_STOPPED" == 1 || "$TOUCHED" == 1 || "$DROP_CREATED" == 1 ) ]]; then
    rollback
  fi
  if [[ -n "$TMP" && -d "$TMP" ]]; then rm -rf -- "$TMP"; fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo '=== CE-GA06-CUT01 — FERRET V5 / PA-07 ==='
whoami
date -Is
[[ "$#" == 1 && "$1" == '--apply' ]] || abort 'EXIGE_--apply'
[[ "$(id -u)" == 0 ]] || abort 'EXECUTAR_COM_sudo_PONTO_BARRA'
[[ "$(printenv SUDO_USER)" == 'andrea.kiew' ]] || abort 'OPERADOR_NAO_AUTORIZADO'
[[ "$(hostname -s)" == 'ep126-pucpr-br' ]] || abort 'HOST_INCORRETO'
[[ "$(git -C "$ROOT" rev-parse HEAD)" == "$HEAD" ]] || abort 'GIT_HEAD_DIVERGENTE'
unset COMPOSE_FILE COMPOSE_PROFILES FERRET_COMPOSE_OVERRIDE
export FERRET_BIND_ADDRESS=127.0.0.1 FERRET_WEB_PORT=18082

check_blob "$BASE" 9f4e17461d2179607343780fed922153050f1e86
check_blob "$OVERRIDE" decf0a8b5d5b18b6122b4afcc12a17e5ee5627f2
check_blob "$SOURCE" 82114898db5b576dcfd84d85b91be88debee9261
check_blob "$MANIFEST" e63ee4b1a9a862e74bfacc4d01b26bd68ec7bfcf
check_blob "$PREFLIGHT" 50a594948bf47e5a168c8d1b84470b1eee7f4001
[[ ! -e "$DROP" && ! -L "$DROP" ]] || abort 'DROPIN_PREEXISTENTE'
systemctl is-active --quiet "$TIMER" || abort 'TIMER_NAO_ATIVO'

CID="$(docker compose -f "$BASE" ps -q ferret)"
[[ -n "$CID" ]] || abort 'CONTAINER_BASELINE_AUSENTE'
[[ "$(docker inspect --format '{{.Image}}' "$CID")" ==
   "$(docker image inspect --format '{{.Id}}' "$OLD")" ]] || abort 'RUNTIME_NAO_EH_BASELINE'
[[ "$(docker image inspect --format '{{.Id}}' "$NEW")" == "$NEW_ID" ]] ||
  abort 'IMAGE_ID_CANDIDATA_DIVERGENTE'
TMP="$(mktemp -d)"
chmod 0700 "$TMP"
if ! bash "$PREFLIGHT" --archive "$ARCHIVE" >"$TMP/preflight.log" 2>&1; then
  abort 'PREFLIGHT_PROVENIENCIA_OU_COMPOSE_FALHOU'
fi
grep -q '^GA06_PREFLIGHT=PASS$' "$TMP/preflight.log" || abort 'PREFLIGHT_SEM_PASS'
health 2.4.3 "$TMP/health-before.json" || abort 'HEALTH_BASELINE_FALHOU'
echo 'PREFLIGHT=PASS'

DATA="$ROOT/deploy/interna/ferret"
for p in config/ferret.yaml .runtime/state .runtime/inbox .runtime/reports .runtime/events; do
  [[ -e "$DATA/$p" && ! -L "$DATA/$p" ]] ||
    abort "BACKUP_ORIGEM_AUSENTE_$(basename "$p")"
done
BK="$(mktemp -d /var/backups/GA06-CUT01-EP126-XXXXXXXX)"
chmod 0700 "$BK"
tar -C "$DATA" --acls --xattrs --numeric-owner \
  -czf "$BK/ferret-precutover.tar.gz" \
  config/ferret.yaml .runtime/state .runtime/inbox .runtime/reports .runtime/events \
  >"$TMP/tar.stdout" 2>"$TMP/tar.stderr" || abort 'BACKUP_TAR_FALHOU'
chmod 0600 "$BK/ferret-precutover.tar.gz"
gzip -t "$BK/ferret-precutover.tar.gz" || abort 'BACKUP_GZIP_FALHOU'
tar -tzf "$BK/ferret-precutover.tar.gz" >"$TMP/tar-list" || abort 'BACKUP_INDICE_FALHOU'
sha256sum "$BK/ferret-precutover.tar.gz" >"$BK/manifest.sha256"
chmod 0600 "$BK/manifest.sha256"
echo 'BACKUP_NOVO_VERIFICADO=SIM'
echo "BACKUP_DIRETORIO=$BK"

systemctl stop "$TIMER" || abort 'NAO_PAUSOU_TIMER'
TIMER_STOPPED=1
TOUCHED=1  # Mesmo se compose falhar, tenta restaurar o baseline.
docker compose -f "$BASE" -f "$OVERRIDE" \
  up -d --no-deps --pull never ferret >"$TMP/cutover.log" 2>&1 ||
  abort 'COMPOSE_CUTOVER_FALHOU'
health '2.4.3+ce.pa07.v5' "$TMP/health-after.json" || abort 'HEALTH_V5_FALHOU'
NEW_CID="$(docker compose -f "$BASE" -f "$OVERRIDE" ps -q ferret)"
[[ -n "$NEW_CID" && "$(docker inspect --format '{{.Image}}' "$NEW_CID")" == "$NEW_ID" ]] ||
  abort 'IMAGEM_V5_RUNTIME_DIVERGENTE'
echo 'FERRET_V5_HEALTH=PASS'

install -d -m 0755 -o root -g root "$DROP_DIR"
DROP_CREATED=1
install -m 0644 -o root -g root "$SOURCE" "$DROP" || abort 'DROPIN_INSTALL_FALHOU'
systemctl daemon-reload || abort 'DAEMON_RELOAD_FALHOU'
systemctl start "$TIMER" || abort 'TIMER_REATIVACAO_FALHOU'
systemctl start "$MONITOR" >"$TMP/monitor.stdout" 2>"$TMP/monitor.stderr" ||
  abort 'MONITOR_V5_FALHOU'
systemctl is-active --quiet "$TIMER" || abort 'TIMER_INATIVO'
echo 'MONITOR_V5=PASS'
echo 'TIMER_ATIVO=SIM'
echo 'PA07_FERRET_V5_IMPLANTADO=SIM'
echo 'CLI_DLP=NAO_MODIFICADA_NESTE_CORTE'
echo 'ROLLBACK_BASELINE=DISPONIVEL'
echo 'CE-GA06-CUT01_CONCLUIDO'
SUCCESS=1
