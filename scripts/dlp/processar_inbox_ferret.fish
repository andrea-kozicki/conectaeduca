#!/usr/bin/env fish

# Processa arquivos da inbox do Ferret em modo detect-only.
# O relatório bruto permanece restrito em .runtime/reports/raw/.
# Somente eventos allowlist/minimizados são gravados em .runtime/events/.

set ROOT (git rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositório ConectaEduca." >&2
    exit 1
end

cd "$ROOT"

set COMPOSE deploy/interna/ferret/compose.yml
set RUNTIME deploy/interna/ferret/.runtime
set INBOX "$RUNTIME/inbox"
set RAW_DIR "$RUNTIME/reports/raw"
set EVENTS_DIR "$RUNTIME/events"
set DEFAULT_EVENTS "$EVENTS_DIR/dlp.jsonl"
set DEFAULT_LEDGER "$RUNTIME/state/processed.sha256"
set SANITIZER scripts/dlp/sanitizar_ferret.py

if set -q FERRET_EVENTS_FILE
    set EVENTS_FILE "$FERRET_EVENTS_FILE"
else
    set EVENTS_FILE "$DEFAULT_EVENTS"
end

if set -q FERRET_LEDGER_FILE
    set LEDGER_FILE "$FERRET_LEDGER_FILE"
else
    set LEDGER_FILE "$DEFAULT_LEDGER"
end

set FORCE 0
set ONLY_FILE ""
set MODE all
set i 1
while test $i -le (count $argv)
    switch $argv[$i]
        case --force
            set FORCE 1
        case --arquivo
            set i (math "$i + 1")
            if test $i -gt (count $argv)
                echo "ERRO: --arquivo exige um nome de arquivo da inbox." >&2
                exit 2
            end
            set ONLY_FILE $argv[$i]
            set MODE one
        case --todos
            set MODE all
        case -h --help
            echo "Uso: processar_inbox_ferret.fish [--todos | --arquivo NOME] [--force]"
            echo "Padrão: --todos. O modo é detect-only; arquivos da inbox não são removidos."
            exit 0
        case '*'
            echo "ERRO: argumento desconhecido: $argv[$i]" >&2
            exit 2
    end
    set i (math "$i + 1")
end

for required in "$COMPOSE" "$SANITIZER" scripts/bootstrap/preparar_ferret.fish
    if not test -f "$required"
        echo "ERRO: arquivo obrigatório ausente: $required" >&2
        exit 1
    end
end

fish scripts/bootstrap/preparar_ferret.fish >/dev/null
or exit 1

mkdir -p "$RAW_DIR" "$EVENTS_DIR" (dirname "$LEDGER_FILE")
or exit 1
chmod 0700 "$RAW_DIR" "$EVENTS_DIR" (dirname "$LEDGER_FILE") 2>/dev/null

function process_one --argument-names file_path
    if not test -f "$file_path"
        echo "AVISO: não é arquivo regular: $file_path" >&2
        return 0
    end

    set basename_file (basename "$file_path")
    set file_hash (sha256sum "$file_path" | awk '{print $1}')
    if test $status -ne 0 -o -z "$file_hash"
        echo "ERRO: não foi possível calcular SHA-256 de $basename_file" >&2
        return 1
    end

    if test "$FORCE" -ne 1 -a -f "$LEDGER_FILE"
        if grep -Fxq "$file_hash" "$LEDGER_FILE" 2>/dev/null
            echo "INFO: artefato já processado; ignorado (file_id="(string sub -l 12 "$file_hash")"...)."
            return 0
        end
    end

    set stamp (date '+%Y%m%d-%H%M%S')
    set short_hash (string sub -l 16 "$file_hash")
    set raw_basename "$stamp-$short_hash.json"
    set raw_path "$RAW_DIR/$raw_basename"

    echo "INFO: processando artefato file_id=$short_hash..."

    docker compose -f "$COMPOSE" run --rm --no-deps ferret \
        --file "/data/inbox/$basename_file" \
        --config /etc/ferret/ferret.yaml \
        --profile conectaeduca-deep \
        --format json \
        --no-color \
        --output "/data/reports/raw/$raw_basename" \
        --suppression-file /var/lib/ferret/suppressions.yaml
    set scan_rc $status

    if test $scan_rc -ne 0
        echo "ERRO: Ferret falhou para file_id=$short_hash... (rc=$scan_rc)." >&2
        return 1
    end

    if not test -s "$raw_path"
        echo "ERRO: relatório bruto não foi produzido para file_id=$short_hash..." >&2
        return 1
    end

    chmod 0600 "$raw_path"

    python3 "$SANITIZER" \
        --input "$raw_path" \
        --output "$EVENTS_FILE" \
        --file-id "$file_hash"
    or return 1

    chmod 0600 "$EVENTS_FILE" 2>/dev/null

    if not test -f "$LEDGER_FILE"
        touch "$LEDGER_FILE"
        chmod 0600 "$LEDGER_FILE"
    end

    if not grep -Fxq "$file_hash" "$LEDGER_FILE" 2>/dev/null
        printf '%s\n' "$file_hash" >> "$LEDGER_FILE"
    end

    echo "OK: file_id=$short_hash... processado; evento sanitizado disponível em $EVENTS_FILE"
    return 0
end

set failures 0
set processed_candidates 0

if test "$MODE" = one
    set requested_base (basename -- "$ONLY_FILE")
    if test "$requested_base" != "$ONLY_FILE" -o "$ONLY_FILE" = "." -o "$ONLY_FILE" = ".."
        echo "ERRO: --arquivo aceita somente o nome de um arquivo diretamente dentro da inbox." >&2
        exit 2
    end

    set candidate "$INBOX/$ONLY_FILE"
    if not test -f "$candidate"
        echo "ERRO: arquivo não localizado na inbox: $ONLY_FILE" >&2
        exit 1
    end

    set processed_candidates 1
    process_one "$candidate"
    or set failures (math "$failures + 1")
else
    for candidate in (find "$INBOX" -maxdepth 1 -type f -print0 2>/dev/null | string split0)
        if test -f "$candidate"
            set processed_candidates (math "$processed_candidates + 1")
            process_one "$candidate"
            or set failures (math "$failures + 1")
        end
    end
end

if test $processed_candidates -eq 0
    echo "INFO: inbox sem arquivos regulares para processar."
end

if test $failures -gt 0
    echo "ERRO: $failures artefato(s) falharam no pipeline DLP." >&2
    exit 1
end

exit 0
