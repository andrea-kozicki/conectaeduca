#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/srv/www/htdocs/conectaeduca"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HOME/Downloads/conectaeduca-checkpoint-snyk-code-hardening-$STAMP.txt"

mkdir -p "$HOME/Downloads"
exec > >(tee "$OUT") 2>&1

section() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

fail() {
    echo "FALHA: $*" >&2
    exit 1
}

cd "$ROOT"

section "1. INFORMACOES"
echo "data=$(date --iso-8601=seconds)"
echo "branch=$(git branch --show-current)"
echo "head=$(git rev-parse HEAD)"
echo "saida=$OUT"

section "2. QUARENTENA DE ARQUIVO ACIDENTAL"
ACCIDENTAL=$'h \\'
if [[ -e "$ACCIDENTAL" ]]; then
    Q="/var/tmp/conectaeduca-acidentais-$STAMP"
    mkdir -p "$Q"
    stat -c 'bytes=%s modo=%a owner=%U:%G arquivo=%n' -- "$ACCIDENTAL"
    sha256sum -- "$ACCIDENTAL"
    mv -- "$ACCIDENTAL" "$Q/"
    echo "OK: arquivo acidental movido para $Q"
else
    echo "OK: nenhum arquivo acidental h\\ encontrado."
fi

section "3. SINTAXE SEM GERAR PYCACHE"
python3 - <<'PY'
import ast
from pathlib import Path
files = [
    Path('scripts/bootstrap/retomar_lab_pos_reboot.py'),
    Path('scripts/dlp/sanitizar_ferret.py'),
    Path('scripts/dlp/validar_eventos_ferret.py'),
]
for path in files:
    ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
    print(f'OK python_ast={path}')
PY
fish -n scripts/dlp/processar_inbox_ferret.fish
echo "OK: Python e Fish validos."

section "4. FONTES DE TAINT REMOVIDAS"
if grep -q 'CONECTAEDUCA_ROOT' scripts/bootstrap/retomar_lab_pos_reboot.py; then
    fail "override CONECTAEDUCA_ROOT ainda existe"
fi
if grep -q 'CONECTAEDUCA_CUSTODIA_DIR' scripts/bootstrap/retomar_lab_pos_reboot.py; then
    fail "override CONECTAEDUCA_CUSTODIA_DIR ainda existe"
fi
grep -Fq 'ROOT = Path(__file__).resolve().parents[2]' scripts/bootstrap/retomar_lab_pos_reboot.py \
    || fail "ROOT nao esta ancorado no proprio script"
grep -Fq 'web_port = int(raw_port, 10)' scripts/bootstrap/retomar_lab_pos_reboot.py \
    || fail "porta Ferret nao esta validada como inteiro"
if grep -nE 'curl.*web_url|web_url.*curl' scripts/bootstrap/retomar_lab_pos_reboot.py; then
    fail "healthcheck Ferret ainda envia URL dinamica a subprocess"
fi
echo "OK: ROOT/custodia fixos e healthcheck Ferret sem command injection."

section "5. CONTENCAO DE PATHS FERRET"
grep -Fq 'RAW_REPORTS_DIR' scripts/dlp/sanitizar_ferret.py \
    || fail "sanitizador sem base fixa de raw reports"
grep -Fq 'EVENTS_DIR' scripts/dlp/sanitizar_ferret.py \
    || fail "sanitizador sem base fixa de eventos"
grep -Fq 'O_NOFOLLOW' scripts/dlp/sanitizar_ferret.py \
    || fail "sanitizador sem protecao nofollow de output"
grep -Fq 'EVENTS_DIR' scripts/dlp/validar_eventos_ferret.py \
    || fail "validador sem base fixa de eventos"
echo "OK: paths do pipeline presos ao runtime esperado."

section "6. TESTES NEGATIVOS DE ESCAPE"
set +e
python3 scripts/dlp/sanitizar_ferret.py \
    --input /etc/passwd \
    --output /tmp/nao-deve-ser-criado.jsonl \
    --file-id "$(printf '0%.0s' {1..64})" \
    >/tmp/conectaeduca-snyk-sanitizer-negative.out 2>&1
SAN_NEG_RC=$?
python3 scripts/dlp/validar_eventos_ferret.py \
    --input /etc/passwd \
    >/tmp/conectaeduca-snyk-validator-negative.out 2>&1
VAL_NEG_RC=$?
set -e
rm -f /tmp/nao-deve-ser-criado.jsonl
[[ "$SAN_NEG_RC" -ne 0 ]] || fail "sanitizador aceitou input fora do runtime"
[[ "$VAL_NEG_RC" -ne 0 ]] || fail "validador aceitou input fora do runtime"
echo "sanitizer_escape_rc=$SAN_NEG_RC"
echo "validator_escape_rc=$VAL_NEG_RC"
echo "OK: tentativas de leitura/escrita fora do runtime foram rejeitadas."

section "7. CHECKPOINT FUNCIONAL FERRET"
fish scripts/evidencias/checkpoint_ferret_pipeline.fish

echo "OK: pipeline Ferret continua funcional."

section "8. SEMGREP DIRECIONADO"
set +e
semgrep scan --config auto \
    scripts/bootstrap/retomar_lab_pos_reboot.py \
    scripts/dlp/sanitizar_ferret.py \
    scripts/dlp/validar_eventos_ferret.py
SEMGREP_RC=$?
set -e
echo "semgrep_rc=$SEMGREP_RC"
[[ "$SEMGREP_RC" -eq 0 ]] || fail "Semgrep retornou finding/erro"

section "9. SNYK CODE"
set +e
snyk code test .
SNYK_CODE_RC=$?
set -e
echo "snyk_code_rc=$SNYK_CODE_RC"
if [[ "$SNYK_CODE_RC" -eq 0 ]]; then
    echo "OK: Snyk Code sem findings."
elif [[ "$SNYK_CODE_RC" -eq 1 ]]; then
    fail "Snyk Code ainda encontrou findings; revisar este relatorio"
else
    fail "Snyk Code falhou operacionalmente rc=$SNYK_CODE_RC"
fi

section "10. GIT"
git diff --check
git status --short
if find scripts -type d -name __pycache__ -print -quit | grep -q .; then
    echo "AVISO: existe __pycache__ local; nao versionar."
fi

section "RESULTADO"
echo "SNYK_CODE_PATH_TRAVERSAL_HARDENING=SIM"
echo "SNYK_CODE_COMMAND_INJECTION_HARDENING=SIM"
echo "FERRET_PIPELINE_POS_HARDENING=APROVADO"
echo "SEMGREP_POS_HARDENING=APROVADO"
echo "SNYK_CODE_FINDINGS=0"
echo "CHECKPOINT_RESULTADO=SUCESSO"
echo "ARQUIVO_SAIDA=$OUT"
