# Recursos e retenção do Wazuh — ConectaEduca

## Decisão do laboratório

A política versionada nesta pasta mantém os índices `wazuh-alerts-*` por **30 dias**
antes da ação de exclusão do ISM.

Esse prazo é uma **decisão de dimensionamento do laboratório ConectaEduca**, não um
prazo obrigatório definido pelo Wazuh nem uma afirmação de prazo legal geral.

Motivos do laboratório:

- o Wazuh central compartilhará a VM interna com MariaDB, Bacula e Twingate;
- a VM interna prevista possui 16 GB de RAM e pelo menos 100 GB de disco;
- a implantação acadêmica terá poucos endpoints, mas poderá receber eventos do ambiente
  de segurança e, futuramente, integração de logs de rede;
- a retenção pode ser revisada após medição real de ingestão na VM.

## Arquivamento completo de eventos

O projeto mantém o `wazuh-archives-*` **desabilitado** nesta etapa. O arquivamento de
todos os eventos consome muito mais armazenamento do que indexar apenas alertas.

## Aplicação da política

A política usa um `ism_template` para `wazuh-alerts-*`, portanto é aplicada
automaticamente a **índices futuros** que correspondam ao padrão.

A Fase 4G-E não anexa automaticamente a política aos índices históricos existentes.
Na implantação definitiva, a política deve ser criada antes de começar a ingestão
normal de agentes/logs.

## Limites de recursos

A Fase 4G-E mede o consumo real da stack estabilizada, mas não impõe limites rígidos
de memória/CPU aos containers. O orçamento final da VM será decidido depois que
MariaDB, Bacula e Twingate também tiverem sido medidos.

O heap atual do Indexer permanece no valor definido pela configuração Docker do
projeto (`-Xms1g -Xmx1g`) até termos evidência suficiente para alterar.
