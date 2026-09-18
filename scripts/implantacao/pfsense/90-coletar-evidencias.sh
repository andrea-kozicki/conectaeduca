#!/bin/sh
# ConectaEduca — pacote de evidências pfSense v3 (somente leitura)
set -u

SCRIPT_DIR="$(CDPATH= cd -P "$(dirname "$0")" 2>/dev/null && pwd -P)" || {
    echo "ERRO: não foi possível determinar o diretório dos scripts." >&2
    exit 1
}

CONFIG="${CONECTAEDUCA_PFSENSE_ENV:-/tmp/conectaeduca-pfsense.env}"
OUTDIR="${CONECTAEDUCA_EVIDENCE_DIR:-/tmp}"
SELF_TEST=0

usage() {
    cat <<'EOF'
Uso:
  sh 90-coletar-evidencias.sh [--config ARQUIVO] [--outdir DIRETORIO] [--self-test]

Gera um .tar.gz com relatórios de leitura.
NÃO inclui /conf/config.xml, tokens, senhas ou secrets das aplicações.
Retorna código diferente de zero quando algum checkpoint obrigatório falha.

Alvo Wazuh do checkpoint de logging:
  host: CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS, se definido;
        caso contrário VM_INTERNA_IP do --config.
  porta: CONECTAEDUCA_WAZUH_SYSLOG_PORT, se definida;
         caso contrário WAZUH_SYSLOG_PORT do --config;
         caso contrário 5514 somente quando a chave não estiver presente.
Uma chave WAZUH_SYSLOG_PORT explicitamente presente mas inválida/vazia falha fechado.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --config)
            [ "$#" -ge 2 ] || { echo "ERRO: --config exige caminho." >&2; exit 2; }
            CONFIG="$2"; shift 2 ;;
        --outdir)
            [ "$#" -ge 2 ] || { echo "ERRO: --outdir exige caminho." >&2; exit 2; }
            OUTDIR="$2"; shift 2 ;;
        --self-test)
            SELF_TEST=1; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "ERRO: argumento desconhecido: $1" >&2
            usage >&2
            exit 2 ;;
    esac
done

if [ "$SELF_TEST" -eq 1 ]; then
    for f in 00-preflight-pfsense.sh 10-checkpoint-interfaces.sh 20-checkpoint-firewall.sh 30-checkpoint-suricata.sh 40-checkpoint-logging.sh; do
        [ -r "$SCRIPT_DIR/$f" ] || {
            echo "SELF_TEST_COLETOR=FALHA arquivo=$f" >&2
            exit 1
        }
        sh "$SCRIPT_DIR/$f" --self-test >/dev/null 2>&1 || {
            echo "SELF_TEST_COLETOR=FALHA self_test=$f" >&2
            exit 1
        }
    done
    command -v tar >/dev/null 2>&1 || {
        echo "SELF_TEST_COLETOR=FALHA comando=tar" >&2
        exit 1
    }
    if ! command -v sha256 >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1; then
        echo "SELF_TEST_COLETOR=FALHA comando_hash_ausente" >&2
        exit 1
    fi
    echo "SELF_TEST_COLETOR=APROVADO"
    exit 0
fi

for cmd in awk date dirname grep hostname mkdir sed tail tar; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "ERRO: comando obrigatório ausente no host alvo: $cmd" >&2
        exit 1
    }
done

if ! command -v sha256 >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1; then
    echo "ERRO: nenhum comando SHA-256 disponível no host alvo." >&2
    exit 1
fi

read_cfg() {
    key="$1"
    [ -r "$CONFIG" ] || { printf '%s' ""; return 0; }
    line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$CONFIG" 2>/dev/null | tail -n 1)"
    [ -n "$line" ] || { printf '%s' ""; return 0; }
    value="${line#*=}"
    value="$(printf '%s' "$value" | sed \
        -e 's/^[[:space:]]*//' \
        -e 's/[[:space:]]*$//' \
        -e "s/^'//" -e "s/'$//" \
        -e 's/^"//' -e 's/"$//')"
    case "$value" in
        *[!A-Za-z0-9._:/-]*)
            echo "ERRO: valor inválido para $key no arquivo de configuração." >&2
            return 1 ;;
    esac
    printf '%s' "$value"
}

cfg_has_key() {
    key="$1"
    [ -r "$CONFIG" ] || return 1
    grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$CONFIG" 2>/dev/null
}

valid_host() {
    case "$1" in
        ""|*[!A-Za-z0-9._:-]*) return 1 ;;
        *) return 0 ;;
    esac
}

valid_port() {
    case "$1" in
        ""|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null
}

STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="$OUTDIR/conectaeduca-pfsense-evidencias-$STAMP"
PACKAGE="$OUTDIR/conectaeduca-pfsense-evidencias-$STAMP.tar.gz"
mkdir -p "$WORK" || exit 1

sh "$SCRIPT_DIR/00-preflight-pfsense.sh" \
    --out "$WORK/00-preflight.txt"
PRE_RC=$?

if [ -r "$CONFIG" ]; then
    sh "$SCRIPT_DIR/10-checkpoint-interfaces.sh" \
        --config "$CONFIG" \
        --out "$WORK/10-interfaces.txt"
    IF_RC=$?
else
    IF_RC=2
    {
        echo "CHECKPOINT_PFSENSE_INTERFACES=NAO_EXECUTADO"
        echo "MOTIVO=configuração não encontrada em $CONFIG"
    } > "$WORK/10-interfaces.txt"
fi

sh "$SCRIPT_DIR/20-checkpoint-firewall.sh" \
    --out "$WORK/20-firewall.txt"
FW_RC=$?

sh "$SCRIPT_DIR/30-checkpoint-suricata.sh" \
    --out "$WORK/30-suricata.txt"
SURICATA_RC=$?

WAZUH_HOST="${CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS:-}"
WAZUH_PORT="${CONECTAEDUCA_WAZUH_SYSLOG_PORT:-}"
WAZUH_TARGET_SOURCE=""

if [ -n "$WAZUH_HOST" ]; then
    WAZUH_TARGET_SOURCE="env"
elif [ -r "$CONFIG" ]; then
    WAZUH_HOST="$(read_cfg VM_INTERNA_IP)" || WAZUH_HOST=""
    WAZUH_TARGET_SOURCE="config:VM_INTERNA_IP"
fi

if [ -n "$WAZUH_PORT" ]; then
    case "$WAZUH_TARGET_SOURCE" in
        "") WAZUH_TARGET_SOURCE="env" ;;
        *) WAZUH_TARGET_SOURCE="${WAZUH_TARGET_SOURCE}+env-port" ;;
    esac
elif [ -r "$CONFIG" ]; then
    if cfg_has_key WAZUH_SYSLOG_PORT; then
        if WAZUH_PORT="$(read_cfg WAZUH_SYSLOG_PORT)" && [ -n "$WAZUH_PORT" ]; then
            WAZUH_TARGET_SOURCE="${WAZUH_TARGET_SOURCE}+config:WAZUH_SYSLOG_PORT"
        else
            WAZUH_PORT="INVALID_CONFIG"
            WAZUH_TARGET_SOURCE="${WAZUH_TARGET_SOURCE}+config:WAZUH_SYSLOG_PORT_INVALID"
        fi
    else
        WAZUH_PORT="5514"
        WAZUH_TARGET_SOURCE="${WAZUH_TARGET_SOURCE}+default-port"
    fi
else
    WAZUH_PORT="5514"
    WAZUH_TARGET_SOURCE="${WAZUH_TARGET_SOURCE}+default-port"
fi

if ! valid_host "$WAZUH_HOST"; then
    LOGGING_RC=2
    {
        echo "CHECKPOINT_PFSENSE_LOGGING=NAO_EXECUTADO"
        echo "MOTIVO=alvo Wazuh ausente/inválido"
        echo "FONTE_ESPERADA=CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS ou VM_INTERNA_IP do --config"
        echo "WAZUH_SYSLOG_PORT=${WAZUH_PORT:-INDETERMINADA}"
    } > "$WORK/40-logging.txt"
elif ! valid_port "$WAZUH_PORT"; then
    LOGGING_RC=2
    {
        echo "CHECKPOINT_PFSENSE_LOGGING=NAO_EXECUTADO"
        echo "MOTIVO=porta Wazuh ausente/inválida; valor configurado não será substituído silenciosamente pelo default"
        echo "WAZUH_HOST=$WAZUH_HOST"
        echo "WAZUH_SYSLOG_PORT=$WAZUH_PORT"
        echo "WAZUH_FORWARDING_TARGET_SOURCE=${WAZUH_TARGET_SOURCE:-INDETERMINADA}"
    } > "$WORK/40-logging.txt"
else
    sh "$SCRIPT_DIR/40-checkpoint-logging.sh" \
        --wazuh-host "$WAZUH_HOST" \
        --wazuh-port "$WAZUH_PORT" \
        --out "$WORK/40-logging.txt"
    LOGGING_RC=$?
fi

{
    echo "=== ConectaEduca / resumo evidências pfSense v3 ==="
    echo "data=$(date 2>/dev/null || true)"
    echo "host=$(hostname 2>/dev/null || echo desconhecido)"
    echo "preflight_rc=$PRE_RC"
    echo "interfaces_rc=$IF_RC"
    echo "firewall_rc=$FW_RC"
    echo "suricata_rc=$SURICATA_RC"
    echo "logging_rc=$LOGGING_RC"
    echo "WAZUH_FORWARDING_TARGET=${WAZUH_HOST:-INDETERMINADO}:${WAZUH_PORT:-INDETERMINADA}"
    echo "WAZUH_FORWARDING_TARGET_SOURCE=${WAZUH_TARGET_SOURCE:-INDETERMINADA}"
    echo "CONFIG_XML_INCLUIDO=NAO"
    echo "SEGREDOS_APLICACAO_INCLUIDOS=NAO"
    echo "LOGS_BRUTOS_INCLUIDOS=NAO"
    echo "VALIDACAO_SEGMENTACAO_ENDPOINT_A_ENDPOINT=PENDENTE"
} > "$WORK/RESUMO.txt"

tar -czf "$PACKAGE" -C "$WORK" . || exit 1

if command -v sha256 >/dev/null 2>&1; then
    SHA="$(sha256 -q "$PACKAGE")"
elif command -v sha256sum >/dev/null 2>&1; then
    SHA="$(sha256sum "$PACKAGE" | awk '{print $1}')"
else
    SHA="NAO_CALCULADO"
fi

echo "PACOTE_EVIDENCIAS=$PACKAGE"
echo "SHA256=$SHA"
echo "WAZUH_FORWARDING_TARGET=${WAZUH_HOST:-INDETERMINADO}:${WAZUH_PORT:-INDETERMINADA}"
echo "CONFIG_XML_INCLUIDO=NAO"
echo "SEGREDOS_INCLUIDOS=NAO"

if [ "$PRE_RC" -eq 0 ] && [ "$IF_RC" -eq 0 ] && [ "$FW_RC" -eq 0 ] && [ "$SURICATA_RC" -eq 0 ] && [ "$LOGGING_RC" -eq 0 ]; then
    echo "COLETA_PFSENSE=CONCLUIDA"
    exit 0
fi

echo "COLETA_PFSENSE=CONCLUIDA_COM_FALHAS"
exit 1
