# Pente fino — Fase 4: documentação, legado e backlog — 18/09/2026

## Objetivo

Reduzir ambiguidade documental sem perder rastreabilidade histórica.

A Fase 4 não deve apagar evidências úteis nem transformar documentos antigos em
"erro". O objetivo é separar claramente:

- fonte canônica;
- runbook operacional;
- evidência;
- histórico;
- laboratório/futuro;
- material a reconciliar.

## Mini-fases

- **4A — inventário e classificação documental**;
- **4B — limpeza/movimentação de referências obsoletas ou duplicadas**;
- **4C — backlog técnico consolidado**;
- **4D — fechamento e revisão final**.

## 4A — inventário e classificação — CONCLUÍDA NO REPO

Inventário no branch da Fase 4:

- documentos textuais totais: **124**;
- raiz: **4**;
- `docs/evidencias/`: **32**;
- `docs/release/`: **2**;
- `docs/seguranca/`: **15**;
- `deploy/pfsense/`: **10**;
- `deploy/interna/bacula/`: **16**;
- `deploy/interna/wazuh/`: **12**;
- `deploy/lab/`: **2**.

Foi criado `docs/INDEX-DOCUMENTACAO.md` com a taxonomia e a precedência entre
fontes.

### Achados objetivos

1. **`estrutura_arquivos_repositorio.txt` está desatualizado**

   O snapshot mostra uma árvore anterior à infraestrutura atual e não contém os
   workflows, deploys e documentação existentes hoje.

   Classificação: **SNAPSHOT HISTÓRICO DESATUALIZADO**.

2. **Documentos raiz de retomada/hotfix são locais/históricos**

   - `README-HOTFIX-V2.2.md`;
   - `README-RETOMADA.md`.

   Ambos registram fluxos do laboratório local/OpenBao/SMTP e não devem
   disputar precedência com os contratos das VMs.

3. **`PACOTES-FASE1.md` e `PACOTES.md` do pfSense se sobrepõem**

   `PACOTES.md` é mais novo e explica explicitamente a reconciliação entre
   "nenhum pacote na subida inicial" e "Suricata após aprovação da rede".

   `PACOTES-FASE1.md` fica candidato a histórico/reconciliação na 4B.

4. **Sufixo `FASE1` não é critério suficiente de legado**

   `deploy/vms/RUNBOOK-FASE1.md` continua sendo o runbook reproduzível da
   implantação inicial e é referenciado pelo README atual.

5. **Bacula possui documentação de decisão pré-implementação ainda útil**

   `DECISOES-PRE-IMPLEMENTACAO.md` é um registro de decisão arquitetural
   histórico, não uma fonte de runtime atual. Deve ser preservado com essa
   classificação.

6. **Wazuh mistura runbook atual e evidência pré-freeze**

   `SERVICO-PREFREEZE.md` registra prova de 12/09/2026 e deve ser tratado como
   evidência/histórico.

   `PREPENTEST-AUDITD-SCA.md` contém linguagem de aplicação futura e fica como
   **RECONCILIAR** até ser confrontado com o estado posterior.

7. **Backlog está fragmentado**

   Pendências aparecem no README, índice de segurança, snapshot de evidências e
   documentos de componentes. A 4C criará uma única fonte de backlog técnico.

## Critério da 4A

A 4A **não move nem remove documentos**. Ela fecha somente:

- inventário;
- taxonomia;
- precedência;
- candidatos objetivos para 4B/4C.

Nenhum documento histórico foi apagado.

## 4B — limpeza/reconciliação de legado — CONCLUÍDA NO REPO

A mini-fase reduziu fontes concorrentes sem apagar a linha do tempo do projeto.

### Artefatos movidos para histórico

Foram retirados da raiz e preservados em `docs/historico/`:

- `README-HOTFIX-V2.2.md` →
  `docs/historico/lab-local/OPENBAO-RETOMADA-HOTFIX-V2.2.md`;
- `README-RETOMADA.md` →
  `docs/historico/lab-local/RETOMADA-POS-REBOOT.md`;
- `estrutura_arquivos_repositorio.txt` →
  `docs/historico/snapshots/estrutura-arquivos-repositorio-legado.txt`.

Os arquivos arquivados receberam cabeçalho explícito de contexto e não devem
ser tratados como fonte operacional das EP125/EP126.

### pfSense

`deploy/pfsense/PACOTES-FASE1.md` foi preservado como registro histórico, mas
agora declara `deploy/pfsense/PACOTES.md` como fonte vigente.

O arquivo não foi removido porque ainda é útil para explicar a sequência
original baseline → IDS.

### Wazuh

`SERVICO-PREFREEZE.md` foi rotulado como **EVIDÊNCIA HISTÓRICA — 12/09/2026**.

`PREPENTEST-AUDITD-SCA.md` foi reconciliado como **PLANO HISTÓRICO
PARCIALMENTE INCORPORADO**:

- SCA e Syscollector aparecem comprovados posteriormente;
- regras Auditd customizadas permanecem versionadas;
- o documento não é usado como prova isolada do estado live atual do Auditd.

### Bacula — decisão pré-implementação

`deploy/interna/bacula/DECISOES-PRE-IMPLEMENTACAO.md` foi preservado no local
por valor arquitetural, mas recebeu banner **REGISTRO HISTÓRICO DE DECISÃO
(ADR-like)** e aponta para os documentos de runtime atuais.

### Resultado

A raiz do repositório deixa de misturar README atual com três artefatos
históricos, e documentos antigos que permanecem próximos dos componentes passam
a declarar explicitamente a precedência documental.

Nenhuma evidência foi apagada e nenhum estado live foi inferido a partir da
limpeza documental.

## 4C — backlog técnico consolidado — CONCLUÍDA NO REPO

Foi criado `docs/BACKLOG-TECNICO.md` como única fonte corrente de pendências.

### Estrutura

Cada item possui:

- ID estável;
- estado (`REPO_GATE`, `HOST_GATE`, `BOUNDARY`, `SEQUENCED`, `FUTURE`);
- prioridade P0–P3;
- dependências;
- critério de fechamento.

### Pendências abertas consolidadas

**P0 / freeze**

- REPO-01 — reconciliar a stack #89 → #91 → #92 → #93 → #94;
- HOST-01 — reconciliar EP125/EP126 com o `main` canônico;
- FREEZE-01 — criar freeze pré-Pentest A.

**P1 / host gates**

- BAC-01 — fechar reprodutibilidade do Bacula FD nativo;
- BAC-02 — promover/reconciliar o volume live do Director;
- BAC-03 — Console Bacula de privilégio mínimo para `teste`;
- NET-01 — reduzir egress amplo do pfSense;
- WAZ-01 — pfSense/Suricata → Wazuh E2E;
- WAZ-02 — canonicalizar policies efetivas dos agentes;
- DMZ-01 — auditoria de serviço PHP/Nginx/WAF;
- TIME-01 — NTP/timezone institucional.

**Sequência acadêmica**

- TEST-01 — DAST;
- TEST-02 — Pentest A;
- ZT-01 — ativar Twingate;
- TEST-03 — Pentest B;
- EVID-01 — consolidar relatório/evidências finais.

**Evoluções não bloqueantes**

- REL-01 — pipeline de release com SBOM/promoção;
- BAC-04 — políticas operacionais avançadas;
- RES-01 — domínio de falha independente para backup;
- FER-01 — quarentena DLP.

### Pendências fantasmas removidas

O backlog não mantém como aberto:

- Ferret 2.4.3;
- DLP Ferret → Wazuh;
- Suricata nativo EP125 → Wazuh;
- hardening de serviço MariaDB;
- PostgreSQL/Bacula TLS;
- service-layer Wazuh central;
- PKI/RBAC técnico Wazuh;
- handoff reproduzível;
- provenance/build gate das imagens locais.

### Fontes concorrentes reconciliadas

- a lista antiga de testes no `README.md` foi substituída por ponte para o
  backlog canônico;
- `docs/evidencias/inventario-pendencias-20260912.md` foi preservado e
  marcado como snapshot histórico;
- `docs/seguranca/README.md` diferencia backlog atual de snapshot histórico;
- `docs/INDEX-DOCUMENTACAO.md` registra a precedência do backlog.
