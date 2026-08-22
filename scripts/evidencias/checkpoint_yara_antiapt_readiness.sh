#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/srv/www/htdocs/conectaeduca"
OUT="$HOME/Downloads/conectaeduca-checkpoint-yara-antiapt-readiness-$(date +%Y%m%d-%H%M%S).txt"
cd "$ROOT"
exec > >(tee "$OUT") 2>&1

pass=0
pending=0
fail=0
ok(){ echo "OK       $*"; pass=$((pass+1)); }
pend(){ echo "PENDENTE $*"; pending=$((pending+1)); }
bad(){ echo "FALHA    $*"; fail=$((fail+1)); }

[[ "$(git branch --show-current)" == "feature/auth-local" ]] && ok "branch feature/auth-local" || bad "branch inesperada"
git diff --check >/dev/null && ok "git diff --check" || bad "git diff --check"

manager="conectaeduca-wazuh-wazuh.manager-1"
state="$(docker inspect -f '{{.State.Status}}' "$manager" 2>/dev/null || true)"
[[ "$state" == "running" ]] && ok "Wazuh Manager running" || bad "Wazuh Manager não está running"

required=(
    deploy/interna/wazuh/yara/rules/conectaeduca_baseline.yar
    deploy/interna/wazuh/agent/yara.sh.example
    deploy/interna/wazuh/agent/conectaeduca-fim-yara.xml.example
    deploy/interna/wazuh/config/decoders/conectaeduca_yara_decoders.xml
    deploy/interna/wazuh/config/rules/conectaeduca_yara_rules.xml
    deploy/interna/wazuh/config/yara/conectaeduca-yara-manager.xml.example
    deploy/interna/wazuh/INTEGRACAO-YARA-ANTIAPT.md
)

for f in "${required[@]}"; do
    [[ -s "$f" ]] && ok "artefato YARA: $f" || bad "artefato ausente: $f"
done

RULES="deploy/interna/wazuh/yara/rules/conectaeduca_baseline.yar"
if grep -q 'CONECTAEDUCA_YARA_TEST_MARKER_2026' "$RULES" \
   && grep -q 'ConectaEduca_PHP_Encoded_Eval_Heuristic' "$RULES"; then
    ok "ruleset possui marcador sintético + heurística"
else
    bad "ruleset YARA não possui baseline esperada"
fi

if grep -q '<directories realtime="yes"' deploy/interna/wazuh/agent/conectaeduca-fim-yara.xml.example; then
    ok "FIM realtime preparado"
else
    bad "FIM realtime não confirmado"
fi

if grep -q '<location>local</location>' deploy/interna/wazuh/config/yara/conectaeduca-yara-manager.xml.example \
   && grep -q '<rules_id>110200,110201</rules_id>' deploy/interna/wazuh/config/yara/conectaeduca-yara-manager.xml.example; then
    ok "Active Response local preparada"
else
    bad "Active Response YARA não confirmada"
fi

if grep -q 'id="110203"' deploy/interna/wazuh/config/rules/conectaeduca_yara_rules.xml; then
    ok "regra de alerta YARA 110203 preparada"
else
    bad "regra YARA 110203 ausente"
fi

echo "Aprovacoes=$pass"
echo "Pendencias=$pending"
echo "Falhas=$fail"

if (( fail > 0 )); then
    echo "YARA_ANTIAPT_READINESS=FALHA"
elif (( pending > 0 )); then
    echo "YARA_ANTIAPT_READINESS=PENDENTE"
else
    echo "YARA_ANTIAPT_READINESS=APROVADO"
fi

echo "ATIVACAO_REAL=RESERVADA_PARA_AULA"
echo "ARQUIVO_SAIDA=$OUT"
exit 0
