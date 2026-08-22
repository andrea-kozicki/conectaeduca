#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/srv/www/htdocs/conectaeduca"
OUT="$HOME/Downloads/conectaeduca-checkpoint-pre-handoff-2.1-$(date +%Y%m%d-%H%M%S).txt"
cd "$ROOT"
exec > >(tee "$OUT") 2>&1

declare -a scripts=(
    scripts/evidencias/checkpoint_openbao_bacula_readiness.sh
    scripts/evidencias/checkpoint_yara_antiapt_readiness.sh
    scripts/evidencias/checkpoint_bacula_fd_vm_readiness.sh
)

declare -a markers=(
    OPENBAO_BACULA_READINESS
    YARA_ANTIAPT_READINESS
    BACULA_FD_VM_READINESS
)

blockers=()
failures=()

for i in "${!scripts[@]}"; do
    script="${scripts[$i]}"
    marker="${markers[$i]}"

    echo
    echo "======================================================================"
    echo " EXECUTANDO $marker"
    echo "======================================================================"

    before="$(date +%s)"
    set +e
    bash "$script"
    rc=$?
    set -e

    echo "SUBCHECK=$marker|rc=$rc"

    report="$(
        find "$HOME/Downloads" -maxdepth 1 -type f \
            -newermt "@$before" \
            -name 'conectaeduca-checkpoint-*.txt' \
            -printf '%T@ %p\n' 2>/dev/null \
            | sort -nr \
            | awk 'NR==1 {print $2}'
    )"

    value=""
    if [[ -n "$report" ]]; then
        value="$(
            grep -E "^${marker}=" "$report" \
                | tail -n 1 \
                | cut -d= -f2 \
                || true
        )"
        echo "RELATORIO=$report"
    fi

    if [[ "$rc" -ne 0 ]]; then
        failures+=("$marker")
    else
        case "$value" in
            APROVADO)
                echo "SUBCHECK_RESULT=$marker|APROVADO"
                ;;
            PENDENTE)
                echo "SUBCHECK_RESULT=$marker|PENDENTE"
                blockers+=("$marker")
                ;;
            *)
                echo "SUBCHECK_RESULT=$marker|FALHA_DE_LEITURA"
                failures+=("$marker")
                ;;
        esac
    fi
done

echo
echo "======================================================================"
echo " RESULTADO PRE-HANDOFF 2.1"
echo "======================================================================"

if (( ${#failures[@]} > 0 )); then
    echo "READY_TO_FREEZE=NAO"
    echo "MOTIVO=FALHA_DE_CHECKPOINT"
    printf 'FALHA=%s\n' "${failures[@]}"
elif (( ${#blockers[@]} > 0 )); then
    echo "READY_TO_FREEZE=NAO"
    echo "MOTIVO=PENDENCIAS_TECNICAS"
    printf 'PENDENCIA=%s\n' "${blockers[@]}"
else
    echo "READY_TO_FREEZE=SIM"
    echo "MOTIVO=CHECKPOINTS_PRE_HANDOFF_APROVADOS"
fi

echo "RESERVADO_PARA_AULA=WAZUH_AGENT_ENROLLMENT_FIM_YARA_DEMO"
echo "Twingate=DEPOIS_DO_PENTEST_A"
echo "ARQUIVO_SAIDA=$OUT"
exit 0
