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
