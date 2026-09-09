# Estado validado do Wazuh na EP126

## Objetivo

Este documento registra o estado **realmente validado em execução** da integração Wazuh na VM interna EP126 em 08/09/2026. Ele existe para separar configuração apenas prevista/documentada de configuração efetivamente aplicada e testada.

Não são versionados relatórios brutos da VM, `.runtime/`, credenciais, chaves, conteúdo DLP original ou qualquer segredo. A prova versionada registra resultados, identificadores técnicos e hashes dos artefatos não sensíveis relevantes.

## Wazuh Manager — runtime do container

O runtime do `wazuh.manager` 4.14.7 foi promovido anteriormente e está canônico no overlay `compose.host.yml`.

Controles validados no container:

- `no-new-privileges:true`;
- `pids_limit: 1024`;
- healthcheck local para os nove daemons essenciais do Manager;
- presença de Filebeat;
- resposta da API HTTPS local em `localhost:55000`;
- root filesystem permanece gravável por decisão explícita;
- conjunto de Linux capabilities da imagem não foi reduzido nesta fase.

A promoção live do Manager terminou com `PASS=83`, `WARN=0`, `FAIL=0`, sem rollback e sem recriar Indexer/Dashboard.

Referência de Git: merge da PR #45, commit `1219cc7f73a466d9366026d6d141701ee47acb29`.

## Centralização da política do agente EP126

O agente nativo da EP126 é o agente Wazuh `002` (`ep126-pucpr`).

A política centralizada foi validada oficialmente com `verify-agent-conf` e aplicada ao grupo exclusivo:

```text
conectaeduca-interna
```

Estado final validado:

- agente `002` removido do grupo `default`;
- agente `002` exclusivamente em `conectaeduca-interna`;
- agente `002` `Active` no Manager;
- agente `002` `synchronized` após a aplicação;
- agente `001` da EP125 permaneceu byte-a-byte invariável em seu membership e continuou em `default`;
- nenhum restart do Manager foi necessário.

SHA-256 da política central aplicada ao grupo `conectaeduca-interna`:

```text
41f69c91175616230592ecad696a08f1b7f8241f6a8eab242f3d84e532a3971b
```

A política central da EP126 contém os módulos/coletores destinados a esta VM, incluindo:

- FIM/Syscheck para os caminhos padrão aprovados;
- Rootcheck;
- SCA;
- Syscollector;
- `journald`;
- `/var/log/dpkg.log`;
- `/var/ossec/logs/active-responses.log`;
- `localfile` JSON para o evento sanitizado do Ferret em `.runtime/events/dlp.jsonl`.

## Poda transacional do `ossec.conf` local

Antes da associação ao grupo central, foi realizada auditoria de colisões local x central.

Foram identificadas exatamente sete colisões funcionais:

1. `syscheck`;
2. `rootcheck`;
3. `sca`;
4. `wodle:syscollector`;
5. `/var/log/dpkg.log`;
6. `/var/ossec/logs/active-responses.log`;
7. `journald`.

A migração removeu somente esse conjunto duplicado do `ossec.conf` local. Os nove blocos locais que não pertenciam à política central foram preservados semanticamente, incluindo `client` e `wodle:osquery`.

SHA-256 do `ossec.conf` local antes da poda:

```text
8d108c99b3792b48a53f3d75f9f13da067167caf32cc9cc187c507a456cdfbdd
```

SHA-256 do `ossec.conf` local após a poda validada:

```text
a7b82c3e074864d16def5e3fb87ab22d7d3d73e0c984443d1520e68d995dadf3
```

Após a sincronização central, os quatro configtests retornaram sucesso:

- `wazuh-syscheckd -t`;
- `wazuh-logcollector -t`;
- `wazuh-modulesd -t`;
- `wazuh-agentd -t`.

Depois de um único restart local do agente, os cinco daemons esperados foram confirmados em execução: `wazuh-execd`, `wazuh-agentd`, `wazuh-syscheckd`, `wazuh-logcollector` e `wazuh-modulesd`.

Resultado da transação:

```text
PASS=51
WARN=0
FAIL=0
ROLLBACK_USED=0
TRANSACTION_COMMITTED=1
```

## Ferret DLP → Wazuh — prova ponta a ponta

O pipeline de DLP envia ao SIEM somente o JSONL sanitizado produzido pelo contrato de eventos. `inbox/`, `reports/raw/` e conteúdo original não são coletados pelo Wazuh.

O `localfile` centralizado foi confirmado no agente EP126 e o `wazuh-logcollector` permaneceu ativo.

### Regras no Manager

O arquivo ativo do Manager é:

```text
/var/ossec/etc/rules/conectaeduca_dlp_rules.xml
```

O ruleset contém as regras reservadas `110100` a `110113`. O teste final usou a regra:

```text
110113 — finding DLP de alta confiança — level 12
```

### Evento sintético de teste

Foi criado somente em memória um `dlp_finding` sintético e sanitizado, sem PII, senha, token ou segredo real.

Características registradas:

```text
event_type=dlp_finding
confidence_level=high
environment_type=test
secret_type=synthetic
real_sensitive_content=0
```

SHA-256 do evento sintético usado no teste:

```text
304fba146e5a1bb90c13f85dfed5045545bd05470fcdc0fff7dff436bc6d3b06
```

Tamanho do evento com newline: `522` bytes.

Antes de qualquer append, `wazuh-logtest` confirmou:

```text
decoder=json
rule_id=110113
rule_level=12
alert_marker=1
```

Somente após esse gate o evento foi anexado como uma linha JSONL ao arquivo sanitizado, preservando owner/mode do runtime.

### Resultado no Manager

O Manager registrou um novo alerta já na primeira tentativa de observação:

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

Contagem objetiva:

```text
ALERTS_110113_BEFORE=0
ALERTS_110113_AFTER=1
ALERT_110113_DELTA=1
E2E_PROVEN=1
```

O teste não criou dado pessoal nem segredo real e não alterou configuração Wazuh, membership de agentes, Git ou ciclo de vida dos containers.

O `wazuh-logcollector.state` não apresentou incremento no primeiro polling; como o alerta foi encontrado imediatamente, o loop encerrou antes de uma nova atualização estatística. A presença do novo alerta específico para agente `002`, regra `110113` e `dlp_finding` constitui a prova direta de entrega e análise pelo Manager.

## Resultado consolidado

O fluxo abaixo está operacionalmente comprovado na EP126:

```text
Ferret
  -> relatório bruto local protegido
  -> sanitizador allowlist
  -> .runtime/events/dlp.jsonl
  -> Wazuh Agent 002 / EP126
  -> Wazuh Manager
  -> decoder JSON
  -> regra 110113 / level 12
  -> alerta
```

## Pendências que este documento não declara concluídas

- migração da política da EP125/DMZ para o grupo `conectaeduca-dmz`;
- reconciliação do checkout da EP125 com o `main` canônico;
- validação final de FIM/SCA/Syscollector/Suricata da EP125 após a migração;
- fechamento final de overlays e do gate `.runtime/stack.env`.

Esses itens permanecem separados para evitar que uma evidência válida da EP126 seja interpretada como conclusão integral de todo o bloco Wazuh.