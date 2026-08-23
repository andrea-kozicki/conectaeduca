#!/bin/sh
# ConectaEduca — pacote de evidências pfSense (somente leitura)
set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)"
CONFIG="${CONECTAEDUCA_PFSENSE_ENV:-/tmp/conectaeduca-pfsense.env}"
OUTDIR="${CONECTAEDUCA_EVIDENCE_DIR:-/tmp}"
SELF_TEST=0

usage() {
    cat <<'EOF'
Uso:
  sh 90-coletar-evidencias.sh [--config ARQUIVO] [--outdir DIRETORIO] [--self-test]

Gera um .tar.gz com relatórios de leitura.
NÃO inclui /conf/config.xml, tokens, senhas ou secrets das aplicações.
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
    for f in 00-preflight-pfsense.sh 10-checkpoint-interfaces.sh 20-checkpoint-firewall.sh; do
        [ -r "$SCRIPT_DIR/$f" ] || {
            echo "SELF_TEST_COLETOR=FALHA arquivo=$f" >&2
            exit 1
        }
    done
    echo "SELF_TEST_COLETOR=APROVADO"
    exit 0
fi

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

{
    echo "=== ConectaEduca / resumo evidências pfSense ==="
    echo "data=$(date 2>/dev/null || true)"
    echo "host=$(hostname 2>/dev/null || echo desconhecido)"
    echo "preflight_rc=$PRE_RC"
    echo "interfaces_rc=$IF_RC"
    echo "firewall_rc=$FW_RC"
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
echo "CONFIG_XML_INCLUIDO=NAO"
echo "SEGREDOS_INCLUIDOS=NAO"

if [ "$PRE_RC" -eq 0 ] && [ "$IF_RC" -eq 0 ] && [ "$FW_RC" -eq 0 ]; then
    echo "COLETA_PFSENSE=CONCLUIDA"
    exit 0
fi

echo "COLETA_PFSENSE=CONCLUIDA_COM_PENDENCIAS"
exit 0
