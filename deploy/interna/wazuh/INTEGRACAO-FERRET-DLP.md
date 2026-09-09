# Integração Ferret DLP → Wazuh

## Escopo desta fase

Esta integração prepara, aplica e valida a **coleta e análise no Wazuh** dos eventos JSONL sanitizados produzidos pelo pipeline DLP do ConectaEduca.

O transporte definitivo é feito pelo **Wazuh Agent nativo da VM interna EP126**. O Manager não recebe bind mount de `reports/raw/`, `inbox/` ou do conteúdo original analisado.

Fluxo validado em 08/09/2026:

```text
Ferret -> reports/raw/ -> sanitizador -> events/dlp.jsonl
                                      -> Wazuh Agent 002 / EP126
                                      -> Wazuh Manager
                                      -> decoder JSON
                                      -> regra DLP
                                      -> alerta
```

## Decoder

Não há decoder customizado para os eventos DLP. O evento é JSON simples e o Wazuh usa o decoder JSON nativo, que transforma os campos em dynamic fields para as regras.

## Regras customizadas

Arquivo versionado:

```text
deploy/interna/wazuh/config/rules/conectaeduca_dlp_rules.xml
```

IDs reservados pelo ConectaEduca:

| Regra | Nível | Uso |
|---|---:|---|
| 110100 | 0 | regra-base para eventos `source=ferret-scan`, schema 1 |
| 110101 | 0 | scan limpo, sem findings; não gera alerta |
| 110102 | 3 | summary com um ou mais findings |
| 110110 | 6 | fallback para finding com confiança não classificada |
| 110111 | 5 | finding `low` |
| 110112 | 8 | finding `medium` |
| 110113 | 12 | finding `high` |

As regras usam `no_full_log`. O evento já é minimizado pelo sanitizador e o Wazuh não precisa guardar uma cópia textual integral para cumprir a função de alerta.

## Coleta pelo agente EP126

A coleta está centralizada no grupo Wazuh:

```text
conectaeduca-interna
```

O agente `002` (`ep126-pucpr`) foi removido do grupo `default`, associado exclusivamente a `conectaeduca-interna`, sincronizado e permaneceu `Active` no Manager.

A política central contém um único `localfile` JSON para:

```text
/opt/conectaeduca/deploy/interna/ferret/.runtime/events/dlp.jsonl
```

O Wazuh Agent recebe apenas o JSONL sanitizado. Não possui coleta configurada para:

- `.runtime/inbox/`;
- `.runtime/reports/raw/`;
- `.runtime/state/`;
- conteúdo original submetido ao DLP.

A política de permissões preserva o runtime protegido. O arquivo JSONL foi validado com owner/mode restritivos e não foi necessário abrir acesso amplo, adicionar ACL ou conceder ao Ferret credenciais do Wazuh.

## Validação da configuração central

A política `conectaeduca-interna` foi aprovada por `verify-agent-conf` imediatamente antes da aplicação.

SHA-256 da política aplicada ao grupo:

```text
41f69c91175616230592ecad696a08f1b7f8241f6a8eab242f3d84e532a3971b
```

Após a sincronização central, os seguintes configtests retornaram sucesso:

```text
wazuh-syscheckd -t
wazuh-logcollector -t
wazuh-modulesd -t
wazuh-agentd -t
```

## Teste da classificação

Antes do teste live, `wazuh-logtest` confirmou que um finding sintético e sanitizado de confiança `high` seria classificado como:

```text
decoder=json
rule_id=110113
rule_level=12
Alert to be generated
```

Esse gate foi executado antes do append ao JSONL.

## Prova ponta a ponta

Foi usado um único evento sintético de teste, sem PII, senha, token ou segredo real.

Campos de controle:

```text
event_type=dlp_finding
confidence_level=high
environment_type=test
secret_type=synthetic
```

Após a escrita controlada no `dlp.jsonl`, o Manager registrou um novo alerta:

```text
agent_id=002
agent_name=ep126-pucpr
rule_id=110113
rule_level=12
event_type=dlp_finding
confidence_level=high
validator=SECRETS
environment_type=test
source=ferret-scan
schema_version=1
```

Resultado objetivo:

```text
ALERTS_110113_BEFORE=0
ALERTS_110113_AFTER=1
ALERT_110113_DELTA=1
E2E_PROVEN=1
```

Portanto, o teste de transporte pelo Wazuh Agent **não é mais apenas planejado**: ele foi executado e aprovado na EP126.

## Segurança da evidência

A evidência versionada não contém conteúdo original submetido ao Ferret nem payload sensível. O evento de validação foi sintético, sanitizado e construído com a mesma allowlist do contrato DLP.

Durante o teste E2E final não houve:

```text
NEW_PERSONAL_DATA_CREATED=0
NEW_REAL_SECRET_CREATED=0
WAZUH_CONFIG_MUTATION_PERFORMED=0
AGENT_GROUPS_CHANGED=0
AGENTS_REASSIGNED=0
SERVICES_RESTARTED_BY_SCRIPT=0
DOCKER_CONTAINER_LIFECYCLE_MUTATION=0
GIT_MUTATION_PERFORMED=0
```

## Evidência operacional detalhada

Consulte também:

```text
deploy/interna/wazuh/ESTADO-VALIDADO-EP126.md
```

Esse documento registra hashes, resultado da migração transacional, estado do container `wazuh.manager` e a prova E2E do alerta.
