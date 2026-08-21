# Contrato de implantação — Wazuh central

## Escopo

Este diretório prepara a stack Wazuh central para a VM interna sem configurar
a infraestrutura real da equipe. pfSense, regras de firewall, endereçamento,
DNS e certificados finais continuam sendo responsabilidades da implantação.

## Componentes

A stack single-node mantém exatamente a mesma versão de patch nos três
componentes centrais:

- Wazuh Manager 4.14.7
- Wazuh Indexer 4.14.7
- Wazuh Dashboard 4.14.7

O gerador oficial de certificados também é fixado por digest.

## Contrato do host

O host que executar esta stack precisa atender, no mínimo:

- Linux `amd64` no cenário atual do ConectaEduca;
- Docker Engine e plugin `docker compose`;
- Docker Compose >= 2.24.4, pois os overlays do projeto usam `!override`;
- `vm.max_map_count >= 262144`;
- recursos compatíveis com a stack Wazuh single-node.

A VM interna planejada possui 16 GiB de RAM, mas esse host também receberá
outros serviços. A suficiência final de recursos deve ser confirmada novamente
quando Bacula e Twingate estiverem adicionados.

## Superfície de rede preparada

O overlay `compose.host.yml` publica somente:

- TCP/1514 — tráfego de agentes Wazuh;
- TCP/1515 — enrollment de agentes;
- HTTPS do Dashboard em endereço/porta explicitamente configurados.

O Wazuh Indexer API (9200), Wazuh Server API (55000) e syslog UDP/514 não são
publicados pelo perfil de handoff atual.

Essa decisão reduz a superfície exposta. Se o projeto passar a exigir syslog
direto ou API externa, isso deverá ser adicionado conscientemente em um overlay
separado e validado.

## Variáveis não secretas de implantação

- `CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS`
- `CONECTAEDUCA_WAZUH_AGENT_PORT` (padrão 1514)
- `CONECTAEDUCA_WAZUH_ENROLLMENT_PORT` (padrão 1515)
- `CONECTAEDUCA_WAZUH_DASHBOARD_BIND_ADDRESS`
- `CONECTAEDUCA_WAZUH_DASHBOARD_PORT` (padrão 443)

Nenhum IP real de VM é versionado.

## Segredos e certificados

Credenciais, certificados e chaves de runtime permanecem em `.runtime/`, fora
do Git. O handoff não deve reutilizar certificados privados de laboratório como
certificados definitivos da infraestrutura.

## Agentes

O desenho do projeto prevê agentes Wazuh instalados nos hosts que precisam ser
monitorados. O Manager central recebe esses agentes pelas portas 1514/1515.

## Integração DLP preparada

O Manager carrega a regra customizada versionada
`config/rules/conectaeduca_dlp_rules.xml`. Ela classifica somente o contrato
JSONL sanitizado do Ferret e usa IDs customizados na faixa 110100–110113.

O transporte final do evento será feito pelo Wazuh Agent nativo da VM interna.
O Manager não recebe `reports/raw/`, `inbox/` nem credenciais do Ferret. O
modelo do bloco `<localfile>` do agente está em
`agent/conectaeduca-dlp-localfile.xml.example`.

O checkpoint do Wazuh valida as regras com `wazuh-logtest`; o teste de coleta
real pelo agente fica para a etapa de implantação do agente na VM.
