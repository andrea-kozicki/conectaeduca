# Evidência — centralização Wazuh EP125/EP126 e telemetria pós-migração (09/09/2026)

## Objetivo

Registrar, de forma sanitizada, a canonicalização das policies centralizadas dos agentes Wazuh do ConectaEduca e a validação operacional da EP125 após migração para o grupo `conectaeduca-dmz`.

A evidência não contém credenciais, chaves privadas, tokens, payloads brutos de alertas, PII ou segredos reais.

## Estado final dos agentes

- Agent `001` / `ep125-pucpr`: grupo exclusivo `conectaeduca-dmz`, `Active` e `synchronized`.
- Agent `002` / `ep126-pucpr`: grupo exclusivo `conectaeduca-interna`, `Active` e `synchronized`.
- O sync do Agent `001` foi validado de forma estrita em três leituras consecutivas após o restart controlado da EP125.

## Policies centralizadas canonicalizadas

Os `agent.conf` efetivos foram extraídos diretamente do Wazuh Manager após a validação operacional e conferidos byte a byte antes de entrar no Git.

| Grupo | Arquivo canonicalizado | SHA-256 validado | Tamanho |
|---|---|---|---:|
| `conectaeduca-dmz` | `deploy/interna/wazuh/groups/conectaeduca-dmz/agent.conf` | `a4df1ce1b8e2affa766fa1164c157d25aea150e07fa43d90b3a4e3d43610b57b` | 3003 bytes |
| `conectaeduca-interna` | `deploy/interna/wazuh/groups/conectaeduca-interna/agent.conf` | `41f69c91175616230592ecad696a08f1b7f8241f6a8eab242f3d84e532a3971b` | 2473 bytes |

Ambos passaram novamente por `verify-agent-conf` antes da extração.

A triagem automática encontrou `0` padrões explícitos de segredo em cada policy, e a revisão de conteúdo confirmou que os arquivos contêm apenas configuração declarativa do agente.

## Conteúdo funcional das policies

As duas policies usam `<agent_config os="^Linux">` e centralizam o baseline comum de:

- FIM / `syscheck`;
- Rootcheck;
- SCA;
- Syscollector;
- `journald`;
- `/var/ossec/logs/active-responses.log`;
- `/var/log/dpkg.log`.

A policy `conectaeduca-dmz` acrescenta:

- FIM dos alvos reais do checkout `/opt/conectaeduca`;
- quatro alvos em `realtime` (`deploy/dmz`, `src`, `public` e `bootstrap`);
- `composer.json` e `composer.lock` com `check_all`;
- exclusão de `deploy/dmz/.runtime` do FIM;
- coleta JSON de `/var/log/suricata/eve.json`.

A policy `conectaeduca-interna` acrescenta a coleta JSON do contrato sanitizado do Ferret em:

`/opt/conectaeduca/deploy/interna/ferret/.runtime/events/dlp.jsonl`

Nenhuma das duas policies habilita `report_changes` para os alvos do ConectaEduca.

## Migração da EP125

Antes da associação ao grupo central, a configuração local da EP125 foi podada de forma transacional para remover oito colisões com a policy central:

1. `syscheck`;
2. `rootcheck`;
3. `sca`;
4. `syscollector`;
5. `journald`;
6. `/var/ossec/logs/active-responses.log`;
7. `/var/log/dpkg.log`;
8. `/var/log/suricata/eve.json`.

O `ossec.conf` local final preservou os nove blocos que deveriam permanecer locais. O Agent `001` foi então associado exclusivamente a `conectaeduca-dmz`, sincronizou e passou por um único restart controlado. Os configtests pré e pós-restart foram aprovados e os artefatos YARA permaneceram invariáveis.

## Telemetria pós-centralização

A validação no Manager foi passiva e somente leitura. O banco SQLite do Agent `001` foi aberto com `mode=ro`, sem dump de registros.

Resultado observado:

```text
AGENT001_SYNC_STABLE=1
FIM_TABLES=1
FIM_ROWS=4883
FIM_TARGET_ROWS=150
SCA_TABLES=7
SCA_ROWS=3954
SYSCOLLECTOR_TABLES=13
SYSCOLLECTOR_ROWS=2417
AGENT001_ALERTS_FRESH=41
SURICATA_AGENT001_TOTAL_WINDOW=155
SURICATA_AGENT001_FRESH=1
```

Isso comprova que, após a centralização:

- o Manager possui estado FIM do Agent `001`;
- existem 150 entradas FIM sob `/opt/conectaeduca` sem exposição dos caminhos individuais na evidência;
- SCA possui estado no banco do agente;
- Syscollector possui inventário no banco do agente;
- houve 41 alertas do Agent `001` posteriores ao restart;
- pelo menos um alerta Suricata foi recebido após a centralização.

Não foi necessário gerar evento sintético adicional para fechar essa validação.

## Integridade das evidências operacionais

Relatório de telemetria pós-centralização:

`conectaeduca-telemetria-wazuh-agent001-pos-centralizacao-v1-20260909-155744.txt`

SHA-256:

`ef713545ad0a54f17759004d539aacab075090022152c83b5b964f88d75939a2`

Resultado: `PASS=24 WARN=0 FAIL=0 GAP=0`.

Relatório de extração byte-exata dos `agent.conf`:

`conectaeduca-evidencia-extracao-agentconf-wazuh-20260909-160437.txt`

SHA-256:

`937c59f662ebe97340b5fbb87bbb2f2b339eec964a3c76a387a2d75a4b4824fa`

Resultado: `PASS=19 WARN=0 FAIL=0 GAP=0`.

Bundle local usado para revisão antes da canonicalização:

`conectaeduca-wazuh-group-configs-exatos-20260909-160437.tar.gz`

SHA-256:

`b031cb8a9b066e3bb8dadbd1ab61c9375d2901dad2e1549ffd9a3d098b0f3aef`

O bundle não é necessário no repositório; os dois `agent.conf` canonicalizados são os artefatos declarativos relevantes.

## Riscos residuais / próximos passos

- reconciliar os checkouts operacionais das VMs com o `main` canônico antes do freeze, sem alterar o runtime já validado durante a reconciliação;
- revisar API/RBAC e módulos Wazuh restantes antes de declarar todo o bloco de serviço integralmente encerrado;
- manter TCP/1515 fechada no estado pós-enrollment e tratá-la apenas como exceção temporária e explícita;
- concluir o gate de overlays/`.runtime` no pré-freeze.
