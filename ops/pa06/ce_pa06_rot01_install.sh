#!/usr/bin/env bash
# CE-PA06-ROT01: instalar politica de rotacao de auditoria PHP na EP125.
# Sem logrotate -f, docker, restart, leitura de conteudo de logs ou git pull.
set -Eeuo pipefail
umask 077
export LC_ALL=C

echo '=== CE-PA06-ROT01 — INSTALACAO DE LOGROTATE EP125 ==='
whoami
date -Is

LOG='/var/log/conectaeduca/php-audit/audit.log'
DIR='/var/log/conectaeduca/php-audit'
DEST='/etc/logrotate.d/conectaeduca-php-audit'
EXPECTED_HEAD='04f88d275064a005d0ffcd4f9372a371c28c32d5'

abort() { printf 'CE-PA06-ROT01_ABORTADO=%s\n' "$1" >&2; exit 1; }
[[ "$(hostname -s)" == "ep125-pucpr" ]] || abort 'HOST_INCORRETO'
[[ "$(id -u)" != 0 ]] || abort 'EXECUTAR_COM_USUARIO_NORMAL'
[[ "$(git -C /opt/conectaeduca rev-parse HEAD 2>/dev/null)" == "$EXPECTED_HEAD" ]] || abort 'HEAD_NAO_RECONCILIADO'
command -v sudo >/dev/null || abort 'SUDO_NAO_DISPONIVEL'
sudo -v || abort 'SUDO_NAO_AUTORIZADO'
sudo test -f "$LOG" && sudo test ! -L "$LOG" || abort 'AUDIT_LOG_AUSENTE_OU_SYMLINK'
sudo test -d "$DIR" && sudo test ! -L "$DIR" || abort 'DIRETORIO_AUDITORIA_INVALIDO'

log_meta="$(sudo stat -c '%u:%g:%a' -- "$LOG")" || abort 'STAT_AUDIT_LOG_FALHOU'
dir_meta="$(sudo stat -c '%u:%g:%a' -- "$DIR")" || abort 'STAT_DIR_AUDITORIA_FALHOU'
[[ "$log_meta" == '82:82:600' ]] || abort 'PROPRIETARIO_OU_MODO_AUDIT_LOG_DIVERGENTE'
[[ "$dir_meta" == '82:82:700' ]] || abort 'PROPRIETARIO_OU_MODO_DIR_DIVERGENTE'
[[ -x /usr/sbin/logrotate ]] || abort 'LOGROTATE_AUSENTE'
echo 'PERMISSOES_AUDITORIA=82:82_0600_DIR_0700'

if systemctl is-enabled --quiet logrotate.timer 2>/dev/null; then
  echo 'AGENDA_LOGROTATE=SYSTEMD_TIMER'
elif [[ -x /etc/cron.daily/logrotate ]]; then
  echo 'AGENDA_LOGROTATE=CRON_DAILY'
else
  abort 'AGENDAMENTO_AUTOMATICO_NAO_ENCONTRADO'
fi

tmp="$(mktemp "$HOME/.ce-pa06-logrotate.XXXXXX")" || abort 'TMP_FALHOU'
trap 'rm -f -- "$tmp"' EXIT

cat >"$tmp" <<'POLICY'
# ConectaEduca / PA-06 / EP125: politica laboratorial de 30 geracoes.
# Revisar retencao e privacidade com responsavel institucional.
# Nao utilizar logrotate -f nem copytruncate; PHP abre arquivo a cada evento.
/var/log/conectaeduca/php-audit/audit.log {
    daily
    maxsize 16M
    rotate 30
    missingok
    notifempty
    compress
    delaycompress
    su :82 :82
    create 0600 :82 :82
}
POLICY

if sudo test -e "$DEST"; then
    if cmp -s -- "$tmp" "$DEST"; then
       [[ "$(stat -c '%u:%g:%a' -- "$DEST")" == "0:0:644" ]] || abort 'POLITICA_EXISTENTE_PERMISSOES_DIVERGENTES'
       echo 'POLITICA_JA_INSTALADA=SIM'
       echo 'CE-PA06-ROT01_CONCLUIDO'
       exit 0
    fi
    abort 'POLITICA_EXISTENTE_DIFERENTE_NAO_SOBRESCRITA'
fi

# Impede ativacao duplicada do mesmo audit.log no logrotate do sistema.
set +e
existing="$(sudo grep -RFl -- "$LOG" /etc/logrotate.conf /etc/logrotate.d 2>/dev/null)"
grep_rc=$?
set -e
[[ "$grep_rc" -eq 0 || "$grep_rc" -eq 1 ]] || abort 'CONSULTA_DUPLICIDADE_FALHOU'
[[ "$grep_rc" -eq 1 ]] || abort 'REGRA_PREEXISTENTE_PARA_AUDIT_LOG'
[[ -z "$existing" ]] || abort 'REGRA_DUPLICADA'
echo 'REGRA_DUPLICADA=NAO'

# -d = verificacao estatica; NAO rotaciona nem altera arquivo de estado.
if ! sudo /usr/sbin/logrotate -d "$tmp" >/dev/null 2>&1; then
    abort 'VALIDACAO_SINTAXE_LOGROTATE_FALHOU'
fi
echo 'CONFIGURACAO_SINTAXE=PASS'

before_inode="$(sudo stat -c '%i' -- "$LOG")" || abort 'STAT_INODE_INICIAL_FALHOU'
sudo install -o root -g root -m 0644 -- "$tmp" "$DEST" || abort 'INSTALACAO_FALHOU'
cmp -s -- "$tmp" "$DEST" || abort 'INSTALACAO_DIVERGENTE'
[[ "$(stat -c '%u:%g:%a' -- "$DEST")" == "0:0:644" ]] || abort 'POLITICA_INSTALADA_PERMISSOES_DIVERGENTES'
after_inode="$(sudo stat -c '%i' -- "$LOG")" || abort 'STAT_INODE_FINAL_FALHOU'
[[ "$before_inode" == "$after_inode" ]] || abort 'INODE_AUDIT_LOG_ALTERADO_INESPERADAMENTE'

echo 'POLITICA_INSTALADA=SIM'
echo 'DIRETIVAS=DAILY_MAXSIZE_16M_ROTATE_30_COMPRESS_DELAYCOMPRESS'
echo 'UID_GID_PRESERVADOS=82:82'
echo 'LOG_ATIVO_ROTACIONADO=NAO'
echo 'LOG_ATIVO_INODE_PRESERVADO=SIM'
echo 'DOCKER_REINICIADO=NAO'
echo 'CE-PA06-ROT01_CONCLUIDO'
