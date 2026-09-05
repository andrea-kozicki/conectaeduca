# Contrato de implantação — Wazuh central

## Escopo

Este documento define a superfície de host da stack Wazuh na VM interna e registra a evolução entre bootstrap, enrollment e operação normal.

pfSense, roteamento e regras entre zonas continuam sendo controles independentes da configuração Docker.

## Componentes

Versão comum:

- Wazuh Manager 4.14.7;
- Wazuh Indexer 4.14.7;
- Wazuh Dashboard 4.14.7.

O gerador de certificados é artefato de preparação, não workload persistente.

## Requisitos do host

- Linux `amd64`;
- Docker Engine;
- plugin `docker compose`;
- Docker Compose >= 2.24.4;
- `vm.max_map_count >= 262144`;
- recursos compatíveis com a stack single-node.

A VM interna possui classe de 16 GiB RAM / 180 GiB e compartilha recursos com MariaDB, OpenBao, Ferret e Bacula; retenção e memória devem ser acompanhadas por medição.

## Evolução da superfície de rede

### Estado de preparação

O desenho inicial admitia:

- 1514/tcp — tráfego de agentes;
- 1515/tcp — enrollment;
- Dashboard em binding administrativo configurável.

### Estado operacional pós-enrollment

Depois que EP125 e EP126 foram registradas e confirmadas como **Active**, a publicação host de TCP/1515 foi removida.

A superfície atual do overlay é deliberadamente menor:

- **1514/tcp:** tráfego dos agentes;
- **1515/tcp:** não permanece publicado;
- **9200/tcp:** Indexer API não publicada;
- **55000/tcp:** Manager API não publicada;
- Dashboard: somente binding administrativo explicitamente definido.

Esse fechamento de 1515 é parte do hardening: uma superfície necessária para bootstrap não precisa permanecer disponível durante operação normal.

## Testes/resultados associados

| Verificação | Resultado |
|---|---|
| agentes EP125/EP126 | Active via 1514 |
| configuração central | configtests aprovados |
| YARA/FIM | fluxo sintético validado |
| regra final de match YARA | `110211`, nível 12 |
| publicação 1515 | removida após enrollment |
| API Manager 55000 | não exposta entre zonas |
| Indexer 9200 | não exposto entre zonas |

## Variáveis não secretas

- `CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS`;
- `CONECTAEDUCA_WAZUH_AGENT_PORT`;
- `CONECTAEDUCA_WAZUH_DASHBOARD_BIND_ADDRESS`;
- `CONECTAEDUCA_WAZUH_DASHBOARD_PORT`.

A variável histórica de enrollment pode continuar em templates/runbooks para operação controlada, mas não implica publicação permanente.

## Segredos e certificados

Credenciais, certificados e chaves de runtime permanecem em `.runtime/`, fora do Git. O handoff não reutiliza material privado do laboratório como certificado definitivo por simples cópia.

## Agentes

Os agentes são nativos nos endpoints monitorados.

O estado operacional comprovado nas VMs é superior ao antigo estado de "readiness": EP125 e EP126 foram registradas e permaneceram Active após o fechamento da porta de enrollment.

## DLP

O Manager carrega a regra customizada de eventos Ferret/DLP. O transporte correto é feito pelo Wazuh Agent da VM interna a partir do JSONL sanitizado.

Nunca conceder ao Manager acesso direto a:

- `reports/raw/`;
- `inbox/`;
- conteúdo original analisado pelo Ferret;
- credenciais do DLP.

## YARA

O Manager carrega:

- `config/rules/conectaeduca_yara_rules.xml`;
- `config/decoders/conectaeduca_yara_decoders.xml`.

O fluxo FIM → Active Response → YARA → alerta foi validado com artefato sintético, evitando malware funcional como prova de controle.
