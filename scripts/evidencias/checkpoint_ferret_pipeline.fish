#!/usr/bin/env fish

# ==========================================================================
# CONECTAEDUCA - CHECKPOINT DO PIPELINE DLP FERRET -> EVENTO SANITIZADO
# ==========================================================================

set -g PASS_COUNT 0
set -g WARN_COUNT 0
set -g FAIL_COUNT 0

function ok
    set -g PASS_COUNT (math "$PASS_COUNT + 1")
    set -l msg (string join ' ' -- $argv)
    printf 'OK       %s\n' "$msg" | tee -a "$REPORT"
end

function warn
    set -g WARN_COUNT (math "$WARN_COUNT + 1")
    set -l msg (string join ' ' -- $argv)
    printf 'AVISO    %s\n' "$msg" | tee -a "$REPORT"
end

function fail
    set -g FAIL_COUNT (math "$FAIL_COUNT + 1")
    set -l msg (string join ' ' -- $argv)
    printf 'FALHA    %s\n' "$msg" | tee -a "$REPORT"
end

function line
    set -l msg (string join ' ' -- $argv)
    printf '%s\n' "$msg" | tee -a "$REPORT"
end

set -g ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositório ConectaEduca." >&2
    exit 1
end

cd "$ROOT"

set -g TIMESTAMP (date '+%Y%m%d-%H%M%S')
set -g REPORT "/tmp/conectaeduca-checkpoint-ferret-pipeline-$TIMESTAMP.txt"
set -g COMPOSE deploy/interna/ferret/compose.yml
set -g RUNTIME deploy/interna/ferret/.runtime
set -g RAW_DIR "$RUNTIME/reports/raw"
set -g EVENTS_DIR "$RUNTIME/events"
set -g PROCESSOR scripts/dlp/processar_inbox_ferret.fish
set -g SANITIZER scripts/dlp/sanitizar_ferret.py
set -g VALIDATOR scripts/dlp/validar_eventos_ferret.py

set -g POS_NAME "checkpoint-dlp-positive-$TIMESTAMP.txt"
set -g NEG_NAME "checkpoint-dlp-negative-$TIMESTAMP.txt"
set -g POS_FILE "$RUNTIME/inbox/$POS_NAME"
set -g NEG_FILE "$RUNTIME/inbox/$NEG_NAME"
set -g POS_EVENTS "$EVENTS_DIR/checkpoint-positive-$TIMESTAMP.jsonl"
set -g NEG_EVENTS "$EVENTS_DIR/checkpoint-negative-$TIMESTAMP.jsonl"
set -g POS_LEDGER "$RUNTIME/state/checkpoint-positive-$TIMESTAMP.sha256"
set -g NEG_LEDGER "$RUNTIME/state/checkpoint-negative-$TIMESTAMP.sha256"
set -g MALFORMED "$RAW_DIR/checkpoint-malformed-$TIMESTAMP.json"
set -g MALFORMED_OUT "$EVENTS_DIR/checkpoint-malformed-$TIMESTAMP.jsonl"
set -g NONEMPTY_ARRAY "$RAW_DIR/checkpoint-nonempty-array-$TIMESTAMP.json"
set -g NONEMPTY_ARRAY_OUT "$EVENTS_DIR/checkpoint-nonempty-array-$TIMESTAMP.jsonl"
set -g POS_RAW ""
set -g NEG_RAW ""
set -g POS_TOKEN ""

function cleanup --on-event fish_exit
    rm -f \
        "$POS_FILE" \
        "$NEG_FILE" \
        "$POS_EVENTS" \
        "$NEG_EVENTS" \
        "$POS_LEDGER" \
        "$NEG_LEDGER" \
        "$MALFORMED" \
        "$MALFORMED_OUT" \
        "$NONEMPTY_ARRAY" \
        "$NONEMPTY_ARRAY_OUT" \
        "$POS_RAW" \
        "$NEG_RAW" 2>/dev/null
    set -e POS_TOKEN
end

touch "$REPORT"

line "======================================================================"
line " CONECTAEDUCA - CHECKPOINT PIPELINE DLP FERRET -> EVENTO SANITIZADO"
line " Data: "(date --iso-8601=seconds)
line "======================================================================"
line ""

line "=== 1. CONTRATO / ARQUIVOS ==="
for required in \
    deploy/interna/ferret/CONTRATO-EVENTOS-DLP.md \
    deploy/interna/ferret/RETENCAO.md \
    "$PROCESSOR" \
    "$SANITIZER" \
    "$VALIDATOR"
    if test -f "$required"
        ok "$required"
    else
        fail "arquivo ausente: $required"
    end
end

if python3 -m py_compile "$SANITIZER" "$VALIDATOR" >/dev/null 2>&1
    ok "scripts Python do pipeline compilam"
else
    fail "py_compile dos scripts do pipeline"
end

if fish scripts/bootstrap/preparar_ferret.fish >>"$REPORT" 2>&1
    ok "runtime do pipeline preparado"
else
    fail "preparação do runtime"
end

for dir in "$RAW_DIR" "$EVENTS_DIR"
    set mode (stat -c '%a' "$dir" 2>/dev/null)
    if test "$mode" = 700
        ok "$dir protegido com modo 0700"
    else
        fail "$dir possui modo inesperado: $mode"
    end
end

line ""
line "=== 2. FRONTEIRA COM O CONTAINER ==="
set CID (docker compose -f "$COMPOSE" ps -q ferret 2>/dev/null)
if test -z "$CID"
    docker compose -f "$COMPOSE" up -d ferret >>"$REPORT" 2>&1
    set CID (docker compose -f "$COMPOSE" ps -q ferret 2>/dev/null)
end

if test -n "$CID"
    ok "container Ferret disponível"
    set MOUNTS (docker inspect "$CID" --format '{{range .Mounts}}{{println .Destination}}{{end}}' 2>/dev/null)
    if string match -q '*/data/events*' "$MOUNTS"
        fail "área de eventos SIEM está montada no container Ferret"
    else
        ok "Ferret não possui escrita direta na área de eventos SIEM"
    end
else
    fail "container Ferret não disponível"
end

line ""
line "=== 3. CASO POSITIVO / SEGREDO SINTÉTICO ==="
set -g POS_TOKEN (python3 -c 'import secrets,string; a=string.ascii_letters+string.digits; print("ghp_"+"".join(secrets.choice(a) for _ in range(36)))')
printf 'synthetic_credential=%s\n' "$POS_TOKEN" > "$POS_FILE"
chmod 0600 "$POS_FILE"
set POS_HASH (sha256sum "$POS_FILE" | awk '{print $1}')
set POS_SHORT (string sub -l 16 "$POS_HASH")

if env FERRET_EVENTS_FILE="$POS_EVENTS" FERRET_LEDGER_FILE="$POS_LEDGER" \
    fish "$PROCESSOR" --arquivo "$POS_NAME" >>"$REPORT" 2>&1
    ok "pipeline processou caso positivo"
else
    fail "pipeline falhou no caso positivo"
end

set -g POS_RAW (find "$RAW_DIR" -maxdepth 1 -type f -name "*-$POS_SHORT.json" 2>/dev/null | tail -n 1)
if test -n "$POS_RAW" -a -s "$POS_RAW"
    ok "relatório bruto positivo produzido"
    if grep -Fq "$POS_TOKEN" "$POS_RAW"
        fail "relatório bruto expôs o match sintético"
    else
        ok "relatório bruto mantém show_match=false"
    end
else
    fail "relatório bruto positivo não localizado"
end

if test -s "$POS_EVENTS"
    ok "JSONL sanitizado positivo produzido"
    set mode (stat -c '%a' "$POS_EVENTS" 2>/dev/null)
    if test "$mode" = 600
        ok "JSONL positivo protegido com modo 0600"
    else
        fail "JSONL positivo possui modo inesperado: $mode"
    end

    if python3 "$VALIDATOR" --input "$POS_EVENTS" --min-findings 1 --forbid-substring "$POS_TOKEN" >>"$REPORT" 2>&1
        ok "evento positivo obedece allowlist e não expõe o match"
    else
        fail "evento positivo viola contrato de sanitização"
    end
else
    fail "JSONL sanitizado positivo não produzido"
end

line ""
line "=== 4. DEDUPLICAÇÃO ==="
set BEFORE_LINES (wc -l < "$POS_EVENTS" 2>/dev/null | string trim)
if env FERRET_EVENTS_FILE="$POS_EVENTS" FERRET_LEDGER_FILE="$POS_LEDGER" \
    fish "$PROCESSOR" --arquivo "$POS_NAME" >>"$REPORT" 2>&1
    set AFTER_LINES (wc -l < "$POS_EVENTS" 2>/dev/null | string trim)
    if test "$BEFORE_LINES" = "$AFTER_LINES"
        ok "mesmo artefato não gera evento duplicado por padrão"
    else
        fail "deduplicação alterou o JSONL: antes=$BEFORE_LINES depois=$AFTER_LINES"
    end
else
    fail "segunda execução do pipeline retornou erro"
end

line ""
line "=== 5. CASO NEGATIVO ==="
printf 'alpha beta gamma delta epsilon\n' > "$NEG_FILE"
chmod 0600 "$NEG_FILE"
set NEG_HASH (sha256sum "$NEG_FILE" | awk '{print $1}')
set NEG_SHORT (string sub -l 16 "$NEG_HASH")

if env FERRET_EVENTS_FILE="$NEG_EVENTS" FERRET_LEDGER_FILE="$NEG_LEDGER" \
    fish "$PROCESSOR" --arquivo "$NEG_NAME" >>"$REPORT" 2>&1
    ok "pipeline processou caso negativo"
else
    fail "pipeline falhou no caso negativo"
end

set -g NEG_RAW (find "$RAW_DIR" -maxdepth 1 -type f -name "*-$NEG_SHORT.json" 2>/dev/null | tail -n 1)
if test -n "$NEG_RAW" -a -s "$NEG_RAW"
    ok "relatório bruto negativo produzido"
    if python3 -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); sys.exit(0 if ((isinstance(d,list) and len(d)==0) or (isinstance(d,dict) and isinstance(d.get("results"),list) and isinstance(d.get("stats"),dict))) else 1)' "$NEG_RAW"
        ok "shape do relatório negativo é compatível com Ferret 2.2.1 ou formatter novo"
    else
        fail "shape inesperado no relatório bruto negativo"
    end
else
    fail "relatório bruto negativo não localizado"
end

if test -s "$NEG_EVENTS"
    if python3 "$VALIDATOR" --input "$NEG_EVENTS" --max-findings 0 >>"$REPORT" 2>&1
        ok "caso negativo gera apenas summary sem finding"
    else
        warn "caso negativo recebeu finding; revisar tuning/supressões antes de enforcement"
    end
else
    fail "JSONL sanitizado negativo não produzido"
end

line ""
line "=== 6. FAIL-CLOSED DO SANITIZADOR ==="
printf '%s\n' '{"results":{},"stats":{}}' > "$MALFORMED"
chmod 0600 "$MALFORMED"

python3 "$SANITIZER" \
    --input "$MALFORMED" \
    --output "$MALFORMED_OUT" \
    --file-id 0000000000000000000000000000000000000000000000000000000000000000 \
    >>"$REPORT" 2>&1
set MALFORMED_RC $status

if test $MALFORMED_RC -ne 0
    ok "sanitizador rejeita schema bruto inválido"
else
    fail "sanitizador aceitou schema bruto inválido"
end

if not test -e "$MALFORMED_OUT"
    ok "falha de schema não produz evento parcial"
else
    fail "falha de schema produziu saída parcial"
end

printf '%s\n' '[{"unexpected":"shape"}]' > "$NONEMPTY_ARRAY"
chmod 0600 "$NONEMPTY_ARRAY"

python3 "$SANITIZER" \
    --input "$NONEMPTY_ARRAY" \
    --output "$NONEMPTY_ARRAY_OUT" \
    --file-id 0000000000000000000000000000000000000000000000000000000000000000 \
    >>"$REPORT" 2>&1
set NONEMPTY_ARRAY_RC $status

if test $NONEMPTY_ARRAY_RC -ne 0
    ok "sanitizador rejeita array não vazio no nível raiz"
else
    fail "sanitizador aceitou array não vazio inesperado"
end

if not test -e "$NONEMPTY_ARRAY_OUT"
    ok "array não vazio rejeitado não produz evento parcial"
else
    fail "array não vazio rejeitado produziu saída parcial"
end

line ""
line "======================================================================"
line " RESULTADO"
line "======================================================================"
line "Aprovações:   $PASS_COUNT"
line "Advertências: $WARN_COUNT"
line "Falhas:       $FAIL_COUNT"

if test $FAIL_COUNT -eq 0
    if test $WARN_COUNT -eq 0
        line "CHECKPOINT PIPELINE DLP: APROVADO."
    else
        line "CHECKPOINT PIPELINE DLP: APROVADO COM ADVERTÊNCIAS."
    end
else
    line "CHECKPOINT PIPELINE DLP: REPROVADO."
end
line "Relatório: $REPORT"

if test $FAIL_COUNT -gt 0
    exit 1
end
exit 0
