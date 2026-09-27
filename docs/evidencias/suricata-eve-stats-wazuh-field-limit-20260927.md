# Evidência — Suricata EVE `stats` x Wazuh JSON field limit — 27/09/2026

## Objetivo

Registrar o diagnóstico e a correção do erro repetitivo do Wazuh Manager:

```text
wazuh-analysisd: ERROR: Too many fields for JSON decoder.
```

O objetivo foi eliminar a causa no produtor da telemetria, sem elevar
globalmente `analysisd.decoder_order_size` e sem perder os alertas IDS do
Suricata.

## Ambiente

- EP125: Suricata 8.0.7 e Wazuh Agent 4.14.7.
- EP126: Wazuh Manager 4.14.7.
- Coleta centralizada da EP125:
  `/var/log/suricata/eve.json` com `log_format=json`.
- `analysisd.decoder_order_size=256`.
- Sem override em `local_internal_options.conf`.

## Diagnóstico

Uma amostra somente leitura das 4.000 linhas mais recentes do EVE encontrou:

```text
JSON_PARSE_ERRORS=0
EVENT_TYPE=alert|COUNT=14|LEAF_MAX=31
EVENT_TYPE=dns|COUNT=1538|LEAF_MAX=73
EVENT_TYPE=flow|COUNT=899|LEAF_MAX=39
EVENT_TYPE=ldap|COUNT=28|LEAF_MAX=162
EVENT_TYPE=stats|COUNT=1125|LEAF_MIN=509|LEAF_MAX=509|LEAF_MEDIAN=509
STATS_DELTA_MIN=8.001
STATS_DELTA_MAX=8.004
STATS_8SEC_RATIO=1.000
STATS_EVENTS_LEAF_GT_256=1125
STATS_LEAF_GT_256_RATIO=1.000
SURICATA_STATS_HYPOTHESIS=STRONGLY_CONFIRMED
```

Os eventos `stats` eram, portanto, muito maiores que os outros tipos
observados e excediam de forma sistemática o limite de 256 campos.

No Manager, o padrão de erros aparecia em rajadas periódicas compatíveis com o
intervalo de 8 segundos configurado para estatísticas do Suricata.

## WAF não era a causa

Durante a mesma investigação, o evento WAF pós-reboot foi localizado no
Manager:

```text
timestamp=2026-09-26T23:14:42.273+0000
agent_id=001
agent_name=ep125-pucpr
rule_id=110300
decoder=conectaeduca_waf_modsecurity
program_name=conectaeduca-waf
location=journald
```

Assim, o caminho WAF -> journald -> Wazuh Agent -> Manager -> rule 110300
permaneceu funcional. O erro de JSON foi tratado como problema separado.

## Correção aplicada

Foi removido somente o item direto `- stats:` de:

```text
outputs
  -> eve-log
     -> types
```

Foram preservados:

- `alert` e os demais event types do EVE;
- o bloco global `stats.interval=8`;
- o logger separado `outputs -> stats`;
- `/var/log/suricata/stats.log`;
- `analysisd.decoder_order_size=256`;
- Wazuh Agent sem restart.

A configuração candidata:

- foi gerada por parser estrutural baseado em indentação;
- teve diff restrito à remoção do bloco EVE `stats`;
- passou em `suricata -T`;
- teve backup bit-identical;
- foi instalada atomicamente;
- reiniciou somente o Suricata;
- manteve o Wazuh Agent conectado à EP126.

## Validação EP125

Após o processo novo do Suricata estar ativo e um período de grace para excluir
flush do processo anterior:

```text
POST_BOUNDARY_STATS_EVENTS=0
EVE_STATS_AFTER_GRACE=0
EVE_STATS_SUPPRESSION=PASS
GLOBAL_STATS_LOG_RUNTIME=PASS
SURICATA_EVE_STATS_SUPPRESSION=PASS_EP125
ROLLBACK_DONE=0
```

O `stats.log` continuou crescendo, comprovando que a telemetria estatística
global não foi desligada.

Configuração ativa após a alteração:

```text
SHA256=f1da451af33e647e1cb148689e712b867aa657b157c7f17b5891413627c934f7
```

Backup criado antes do apply:

```text
/var/backups/conectaeduca/suricata/suricata.yaml.pre-eve-stats-v3-20260927-000921Z.bak
```

## Validação EP126

A validação posterior no Wazuh Manager comparou uma janela anterior à mudança
com uma janela posterior ampla:

```text
PRE_ERROR_COUNT=5478
TRANSITION_ERROR_COUNT=747
POST_ERROR_COUNT=0
LAST_FIELDLIMIT_ERROR=2026/09/27 00:10:14
POST_OBSERVATION_SECONDS=742
POST_OBSERVATION_SUFFICIENT=YES
FIELDLIMIT_FIX_VALIDATION=PASS
SURICATA_EVE_STATS_ROOT_CAUSE=CONFIRMED_OPERATIONALLY
```

Também foi confirmado:

```text
events_dropped='0'
event_queue_usage='0.00'
rule_matching_queue_usage='0.00'
alerts_queue_usage='0.00'
archives_queue_usage='0.00'
queue_size='0'
discarded_count='0'
```

## Conclusão

A causa operacional dos erros repetitivos `Too many fields for JSON decoder`
foi confirmada como a exportação periódica de `event_type=stats` do Suricata
para o EVE coletado pelo Wazuh.

A correção canônica é filtrar esse tipo no produtor e preservar o logger global
de estatísticas. Não foi necessário aumentar o limite global do decoder JSON do
Wazuh.

## Reprodutibilidade

O estado é reconciliado por:

```text
scripts/implantacao/reconciliar_suricata_eve_wazuh.sh
```

Modos:

```bash
scripts/implantacao/reconciliar_suricata_eve_wazuh.sh check
scripts/implantacao/reconciliar_suricata_eve_wazuh.sh apply
scripts/implantacao/reconciliar_suricata_eve_wazuh.sh --self-test
```

O `apply` é fail-closed, cria backup, valida o candidato, exige confirmação
literal, aplica atomicamente e possui rollback automático.
