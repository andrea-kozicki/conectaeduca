# Backlog técnico consolidado — ConectaEduca

Atualizado em 18/09/2026.

Este documento é a **fonte canônica de pendências técnicas abertas** do projeto.
Snapshots anteriores, como
`docs/evidencias/inventario-pendencias-20260912.md`, permanecem como evidência
histórica e não devem ser usados como backlog corrente.

## Estados

| Estado | Significado |
|---|---|
| **REPO_GATE** | depende de reconciliação/merge/CI do repositório |
| **HOST_GATE** | exige execução e evidência em EP125/EP126/pfSense |
| **BOUNDARY** | depende de privilégio, suporte ou decisão institucional |
| **SEQUENCED** | etapa planejada que só deve ocorrer após pré-requisitos |
| **FUTURE** | evolução útil, mas não bloqueia o baseline acadêmico atual |
| **DONE** | item removido do backlog aberto por evidência posterior |

## Prioridades

- **P0** — bloqueia freeze canônico ou coerência do baseline;
- **P1** — deve fechar antes do Pentest A, salvo risco residual formalmente aceito;
- **P2** — importante para fechamento acadêmico, mas pode ocorrer após freeze inicial;
- **P3** — evolução futura não bloqueante.

---

## P0 — coerência do baseline e freeze

### REPO-01 — Reconciliar PR #89 e a stack do pente fino

**Estado:** REPO_GATE  
**Prioridade:** P0

Topologia real dos PRs:

```text
#89 (base: main) ── integração prévia/compatibilidade
#91 (base: main) ── Fase 1
  ↓
#92 ── Fase 2
  ↓
#93 ── Fase 3
  ↓
#94 ── Fase 4
```

O #89 **não é pai Git do #91**; ele é uma dependência de integração porque
também parte de `main` e deve ser reconciliado antes de promover a stack
#91→#94.

Critério:

1. resolver/reconciliar o #89 em `main`;
2. atualizar/reconciliar #91 contra o novo `main`;
3. propagar a nova base para #92, #93 e #94;
4. executar novamente todos os gates em cada HEAD final;
5. fazer merge da stack #91→#94 de baixo para cima, sem merge isolado de PR
   empilhado.

**Fechamento:** `main` contendo #89 e as Fases 1–4 sem conflito/regressão e CI verde.

---

### HOST-01 — Reconciliar EP125/EP126 com o `main` canônico

**Estado:** HOST_GATE  
**Prioridade:** P0  
**Dependência:** REPO-01

O snapshot de 12/09 já registrava que as VMs haviam sido validadas em commits
anteriores ao avanço da `main`. O pente fino acrescentou novos contratos,
handoffs e gates sem alterar automaticamente o runtime live.

**Fechamento:** checkouts operacionais reconciliados com o `main` vigente ou
divergências explicitamente aceitas/documentadas, sem mutação acidental do
runtime validado.

---

### FREEZE-01 — Criar freeze pré-Pentest A

**Estado:** SEQUENCED  
**Prioridade:** P0  
**Dependências:** REPO-01, HOST-01 e todos os P1 aplicáveis

**Fechamento:** snapshot/freeze identificado, hashes/evidências consolidados e
riscos residuais P1 aceitos ou encerrados.

---

## P1 — gates de host antes do Pentest A

### BAC-01 — Fechar reprodutibilidade do Bacula File Daemon nativo

**Estado:** HOST_GATE  
**Prioridade:** P1

O handoff contém template e instalador package-based, mas a EP125 observada usa
`/opt/bacula/bin/bacula-fd` e `/opt/bacula/etc/bacula-fd.conf`.

**Decisão necessária:** provar o fluxo package-based em VM limpa **ou**
versionar/formalizar o procedimento institucional real de `/opt/bacula`.

**Fechamento:** instalação fail-closed, materialização de segredo/TLS,
`bacula-fd -t -c`, enable/restart e checkpoint funcional reproduzíveis.

---

### BAC-02 — Promover/reconciliar o volume live do Bacula Director

**Estado:** HOST_GATE  
**Prioridade:** P1

O handoff declara:

- fonte live: `conectaeduca-bacula-director-config`;
- baseline host: rollback-only;
- acesso ao Catalog: `/run/pgbouncer:6432`;
- `bacula_final_runtime_materialization=host_gate`.

**Fechamento:** volume live reconciliado/promovido na EP126 com backup,
validação sintática/funcional e rollback disponível, sem regressão para
`catalog:5432`.

---

### BAC-03 — Console Bacula de privilégio mínimo para `teste`

**Estado:** HOST_GATE  
**Prioridade:** P1

Este gate operacional ativo ainda não possuía item canônico no backlog.

Objetivo: disponibilizar acesso de consulta limitado ao Bacula sem conceder
Docker group, shell root persistente ou comandos administrativos destrutivos.

**Fechamento mínimo:**

- identidade Console dedicada;
- ACLs explícitas e verificadas;
- teste positivo de consulta/status;
- teste negativo de comando mutante;
- segredo protegido e fora do Git;
- evidência sanitizada com PASS/WARN/FAIL e SHA-256;
- Director continua operacional após a mudança.

---

### NET-01 — Reduzir egress amplo do pfSense por zona

**Estado:** HOST_GATE  
**Prioridade:** P1

O inventário de 12/09 registrou egress amplo como pendência de segmentação.

**Fechamento:** dependências reais inventariadas e regras de saída reduzidas em
etapas, preservando DNS, HTTP/HTTPS, APT, GitHub/Docker, Wazuh e Bacula
necessários.

---

### WAZ-01 — Fechar pfSense/Suricata → Wazuh ponta a ponta

**Estado:** HOST_GATE  
**Prioridade:** P1

O receptor está declarado no perfil de VM, mas a promoção do listener e o E2E
do sensor pfSense ainda permanecem pendentes.

**Fechamento:** evento gerado no pfSense/Suricata aparece no Wazuh com origem do
sensor e correlação temporal rastreáveis.

---

### WAZ-02 — Canonicalizar policies efetivas dos agentes Wazuh

**Estado:** HOST_GATE  
**Prioridade:** P1

Painel de hardening atual:

- `conectaeduca-interna`: recuperar `agent.conf` efetivo e confirmar o SHA-256
  conhecido antes de versionar;
- `conectaeduca-dmz`: canonicalizar somente após auditoria/poda para não
  duplicar Suricata/FIM de demonstração nem interferir no Active Response/YARA.

**Fechamento:** policies efetivas comparadas byte a byte, versionadas somente
após reconciliação e validadas sem regressão.

---

### DMZ-01 — Fechar auditoria de serviço PHP/Nginx/WAF

**Estado:** HOST_GATE  
**Prioridade:** P1

O hardening de runtime já existe, mas o painel vivo ainda classifica a camada
de serviço DMZ como parcial.

Escopo:

- PHP: `php.ini`, pool FPM, upload/session/error disclosure e funções de risco;
- Nginx: TLS, headers, métodos, timeouts, disclosure e FastCGI/proxy;
- WAF: paranoia level, exclusions, logging sem dados sensíveis.

**Fechamento:** revisão + testes funcionais/negativos antes do Pentest A, sem
tuning cego que destrua a linha de base.

---

### TIME-01 — NTP/timezone institucional

**Estado:** BOUNDARY  
**Prioridade:** P1

Diagnósticos registraram NTP ativo sem sincronização e diferença temporal entre
pfSense e VMs. A conta acadêmica não possui acesso suficiente às páginas de
configuração do pfSense.

**Fechamento:** suporte institucional corrige a sincronização **ou** o risco é
formalmente aceito no freeze com impacto sobre correlação temporal documentado.

---

## Sequência de testes acadêmicos

### TEST-01 — DAST dedicado nas VMs

**Estado:** SEQUENCED  
**Prioridade:** P1  
**Dependência:** FREEZE-01

Executar OWASP ZAP/DAST sobre o baseline congelado e registrar findings,
correções e regressões.

---

### TEST-02 — Pentest A sem Zero Trust

**Estado:** SEQUENCED  
**Prioridade:** P1  
**Dependências:** FREEZE-01 e TEST-01 quando aplicável

Objetivo: medir o baseline perimetral/segmentado **antes** do Twingate.

---

### ZT-01 — Ativar Twingate

**Estado:** SEQUENCED  
**Prioridade:** P2  
**Dependência:** TEST-02

Artefatos declarativos e checkpoints já entram no handoff; tokens permanecem
fora do Git e `twingate_active=no` até esta etapa.

**Fechamento:** Connector ativo com tokens efêmeros, checkpoint operacional e
superfície administrativa validada.

---

### TEST-03 — Pentest B com Zero Trust

**Estado:** SEQUENCED  
**Prioridade:** P2  
**Dependência:** ZT-01

Comparar os mesmos vetores relevantes do Pentest A após a camada Zero Trust.

---

### EVID-01 — Consolidar relatório/evidências finais

**Estado:** SEQUENCED  
**Prioridade:** P2  
**Dependência:** TEST-03

Consolidar arquitetura final, TTPs/MITRE ATT&CK, resultados dos testes,
limitações institucionais, riscos residuais e comparação Pentest A/B.

---

## P2/P3 — evolução não bloqueante ou pós-baseline

### REL-01 — Pipeline de release com SBOM e promoção automatizada

**Estado:** FUTURE  
**Prioridade:** P2

As Fases 2 e 3 já entregaram:

- handoffs reproduzíveis e smoke offline;
- provenance de imagens locais;
- build real Nginx e Bacula→PgBouncer no CI.

Ainda falta uma pipeline de release completa com SBOM, scan das imagens
efetivamente promovidas e publicação automatizada/assinada dos handoffs.

---

### BAC-04 — Políticas operacionais avançadas do Bacula

**Estado:** FUTURE  
**Prioridade:** P3

Revisar Jobs, FileSets, RunScripts, retenção/mídia e Directors autorizados se o
ambiente deixar de ser mono-operador ou a topologia mudar.

---

### RES-01 — Domínio de falha independente para backup

**Estado:** FUTURE  
**Prioridade:** P3

O Storage ainda compartilha o domínio físico da VM interna. Um segundo
disco/storage em domínio de falha distinto depende de infraestrutura/autorização
externa.

---

### FER-01 — Quarentena DLP

**Estado:** FUTURE  
**Prioridade:** P3

Ferret permanece detect-only. Quarentena automática é evolução futura e não
bloqueia o baseline pré-pentest.

---

## Itens removidos do backlog aberto

Os itens abaixo apareciam em documentos antigos, mas têm evidência posterior de
fechamento e **não devem voltar como pendência sem nova regressão**:

| Item antigo | Estado atual |
|---|---|
| reconciliar Ferret 2.4.3 com baseline Git 2.2.1 | **DONE** — baseline atual fixa 2.4.3 |
| DLP Ferret → Wazuh Agent | **DONE** — E2E comprovado com regra 110113 |
| Suricata nativo EP125 → Wazuh | **DONE** — telemetria/alerta comprovados |
| MariaDB service hardening | **DONE** — painel vivo classifica serviço como validado |
| PostgreSQL/Bacula Catalog TLS/service | **DONE** — SCRAM + PgBouncer + TLS verify-full validados |
| Wazuh Manager/Indexer/Dashboard service-layer | **DONE** — baseline pré-freeze concluído |
| Wazuh API PKI + identidade técnica `teste` | **DONE NO REPO/HOST VALIDADO** — reconciliadores e E2E documentados |
| handoff reproduzível | **DONE NO REPO** — Fase 2 |
| provenance/build gate de imagens locais | **DONE NO REPO** — Fase 3 |

## Ordem operacional sugerida

```text
#89 → REPO-01 (#91 → #92 → #93 → #94)
              ↓
           HOST-01
  ↓
BAC-01 / BAC-02 / BAC-03
NET-01 / WAZ-01 / WAZ-02
DMZ-01 / TIME-01
  ↓
FREEZE-01
  ↓
TEST-01
  ↓
TEST-02  (Pentest A)
  ↓
ZT-01
  ↓
TEST-03  (Pentest B)
  ↓
EVID-01
```

Itens FUTURE podem permanecer fora dessa linha sem bloquear o freeze.