# Índice de documentação — ConectaEduca

Este índice define **o papel de cada classe de documento** no repositório. O
objetivo é evitar que snapshots históricos, evidências e runbooks antigos sejam
interpretados como fonte operacional atual.

## Estados usados

| Estado | Significado |
|---|---|
| **CANÔNICO** | fonte principal para arquitetura, implantação ou release atual |
| **OPERACIONAL** | runbook/README usado para executar ou validar um componente |
| **EVIDÊNCIA** | registro de teste/estado observado; não redefine o baseline |
| **HISTÓRICO** | decisão, hotfix ou snapshot preservado para rastreabilidade |
| **LAB/FUTURO** | material deliberadamente fora do baseline operacional atual |
| **RECONCILIAR** | documento útil, mas com conteúdo potencialmente superado ou duplicado |

## Pontos de entrada canônicos

- `README.md` — visão geral do projeto e arquitetura;
- `deploy/CONTRATO-IMPLANTACAO.md` — contrato de implantação;
- `deploy/ARQUITETURA-VMs.md` — distribuição dos componentes nas VMs;
- `docs/release/HANDOFF-FINAL.md` — contrato do handoff;
- `docs/release/INVENTARIO-COMPONENTES.md` — inventário do release;
- `docs/seguranca/README.md` — índice de segurança/hardening;
- `scripts/evidencias/README.md` — contratos dos checkpoints/evidências.

## Operação por componente

### pfSense

Fonte principal:

- `deploy/pfsense/README.md`;
- `deploy/pfsense/PACOTES.md`;
- `deploy/pfsense/RUNBOOK-FASE1.md`;
- matrizes/checklists específicos da pasta.

`PACOTES-FASE1.md` é **HISTÓRICO / SUPERADO**. Foi mantido no diretório para
preservar a linha do tempo, mas aponta explicitamente para `PACOTES.md` como
fonte vigente.

### VMs Ubuntu

Fonte principal:

- `deploy/vms/README.md`;
- `deploy/vms/RUNBOOK-FASE1.md`;
- `deploy/vms/IDENTIFICACAO-VMs.md`;
- `deploy/vms/FLUXO-CONTAINERS.md`.

O sufixo `FASE1` aqui **não significa legado**: o runbook ainda descreve a
implantação inicial reproduzível.

### Bacula

Fonte principal:

- `deploy/interna/bacula/README.md`;
- `deploy/interna/bacula/HARDENING-RUNTIME-NOTES.md`;
- `deploy/interna/bacula/pgbouncer/RUNTIME-MATERIALIZATION.md`;
- contratos específicos de FD/restore/checkpoint.

`DECISOES-PRE-IMPLEMENTACAO.md` é **HISTÓRICO/ADR-like**: preserva decisões
arquiteturais anteriores à implementação, mas não deve ser usado para reconstruir
o runtime atual.

### Wazuh

Fonte principal:

- `deploy/interna/wazuh/README.md`;
- `docs/seguranca/WAZUH-MANAGER-RUNTIME-HARDENING.md`;
- `docs/seguranca/WAZUH-INDEXER-DASHBOARD-RUNTIME-HARDENING.md`.

`SERVICO-PREFREEZE.md` é **EVIDÊNCIA/HISTÓRICO** de uma auditoria de
12/09/2026 e agora está rotulado como tal no próprio arquivo.

`PREPENTEST-AUDITD-SCA.md` é **PLANO HISTÓRICO PARCIALMENTE INCORPORADO**:
SCA/Syscollector aparecem comprovados posteriormente; regras Auditd customizadas
permanecem versionadas. O arquivo não é prova isolada do estado live atual.

### OpenBao / Ferret / MariaDB / Twingate

As fontes principais são os READMEs e contratos dentro de cada diretório em
`deploy/interna/`.

Material explicitamente marcado como `LAB-ONLY` ou `FUTURE/LAB-ONLY` não
faz parte do baseline final.

## Evidências

Todo `docs/evidencias/**` é classificado como **EVIDÊNCIA**.

Regra:

> evidência registra o que foi observado em um momento específico; ela não deve
> ser usada como fonte de verdade para o estado atual sem reconciliação com o
> baseline versionado.

No inventário atual existem **32 arquivos** nessa classe.

`docs/evidencias/inventario-pendencias-20260912.md` é um snapshot de backlog
datado e não deve ser usado como backlog atual depois da Fase 4C.

## Laboratório

`deploy/lab/**` é **LAB/FUTURO** por definição e não deve ser confundido com
handoff operacional.

No inventário atual há **2 documentos** nessa classe.

## Histórico arquivado

Artefatos históricos que antes ocupavam a raiz foram movidos para
`docs/historico/`:

- `docs/historico/lab-local/OPENBAO-RETOMADA-HOTFIX-V2.2.md`;
- `docs/historico/lab-local/RETOMADA-POS-REBOOT.md`;
- `docs/historico/snapshots/estrutura-arquivos-repositorio-legado.txt`.

Todos carregam aviso explícito de que não são fonte operacional atual.

## Backlog

Até a Fase 4A, pendências estão espalhadas por:

- `README.md`;
- `docs/seguranca/README.md`;
- `docs/evidencias/inventario-pendencias-20260912.md`;
- READMEs de componentes;
- relatórios das Fases 2 e 3.

A **Fase 4C** criará um backlog técnico único e rastreável. Até lá, nenhum
snapshot datado de pendências deve ser promovido implicitamente a backlog atual.

## Regra de precedência

Quando dois documentos divergirem, usar esta ordem:

1. configuração/scripts versionados e gates automáticos;
2. contrato/README canônico do componente;
3. handoff/release atual;
4. evidência datada;
5. decisão histórica ou material de laboratório.

Uma evidência pode provar que o runtime divergiu do Git, mas não redefine o
baseline sem reconciliação explícita.