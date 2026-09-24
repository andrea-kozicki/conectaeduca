# Backlog técnico consolidado — ConectaEduca

Atualizado em 24/09/2026.

Reconciliado com os gates live de 18/09/2026. Itens marcados como **DONE** abaixo
possuem evidência operacional posterior ao snapshot que originou esta Fase 4 e
não devem ser reabertos sem regressão nova.

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

**Estado:** DONE  
**Prioridade:** P0

**Fechado em 21/09/2026.**

A reconciliação deixou de ser gate aberto:

- #89 foi integrado em `main`;
- #91 foi reconciliado e integrado;
- Fase 2 entrou pela reconciliação #97;
- Fase 3 entrou pela reconciliação #100;
- Fase 4 entrou pela reconciliação #101;
- PRs intermediários/superseded permaneceram fechados sem merge indevido;
- #96 Dependabot foi revisado e integrado posteriormente;
- a `main` continuou avançando normalmente até o GUI-01B final (#105).

Reabrir REPO-01 somente se surgir regressão concreta de integração.

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

**Estado:** DONE  
**Prioridade:** P1


**Fechado em 18/09/2026:** proveniência package-based comprovada na EP125 via `bacula-client 15.0.3-1~noble`, binário/configuração em `/opt/bacula`, bootstrap v3 fail-closed alinhado no #91 e CI verde. Não reinstalar o FD live apenas para repetir evidência.
O handoff contém template e instalador package-based, mas a EP125 observada usa
`/opt/bacula/bin/bacula-fd` e `/opt/bacula/etc/bacula-fd.conf`.

**Decisão necessária:** provar o fluxo package-based em VM limpa **ou**
versionar/formalizar o procedimento institucional real de `/opt/bacula`.

**Fechamento:** instalação fail-closed, materialização de segredo/TLS,
`bacula-fd -t -c`, enable/restart e checkpoint funcional reproduzíveis.

---

### BAC-02 — Promover/reconciliar o volume live do Bacula Director

**Estado:** DONE  
**Prioridade:** P1


**Fechado em 18/09/2026:** Director/Storage/Catalog/PgBouncer e volume live foram validados funcionalmente; `bacula-dir -t` passou sob o usuário do serviço e o fluxo backup/restore permaneceu íntegro.
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

**Estado:** DONE  
**Prioridade:** P1


**Fechado em 18/09/2026:** Console dedicado `teste` com ACL mínima, TLS-PSK e configuração protegida; consulta read-only passou e comando `run` foi negado; TCP/9101 permanece somente em loopback.
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

**Estado:** DONE  
**Prioridade:** P1


**Fechado em 18/09/2026:** LAN33/EP125 e LAN49/EP126 receberam egress mínimo: DNS institucional, TCP/80 e TCP/443 necessários preservados, demais destinos públicos bloqueados/logados; regressão cross-zone pós-change passou nas duas direções.
O inventário de 12/09 registrou egress amplo como pendência de segmentação.

**Fechamento:** dependências reais inventariadas e regras de saída reduzidas em
etapas, preservando DNS, HTTP/HTTPS, APT, GitHub/Docker, Wazuh e Bacula
necessários.

---

### WAZ-01 — Fechar pfSense/Suricata → Wazuh ponta a ponta

**Estado:** DONE  
**Prioridade:** P1


**Fechado em 18/09/2026:** receiver pfSense, decoder/regra e persistência/consulta no Wazuh foram validados; Suricata real da EP125 também foi correlacionado no Indexer. O gate visual WAF `rule.id:110300` no Threat Hunting foi fechado em 18/09.
O receptor está declarado no perfil de VM, mas a promoção do listener e o E2E
do sensor pfSense ainda permanecem pendentes.

**Fechamento:** evento gerado no pfSense/Suricata aparece no Wazuh com origem do
sensor e correlação temporal rastreáveis.

---

### WAZ-02 — Canonicalizar policies efetivas dos agentes Wazuh

**Estado:** DONE  
**Prioridade:** P1


**Fechado em 18/09/2026:** policies efetivas foram comparadas/validadas sem regressão e o baseline operacional foi aceito. Reabrir somente diante de drift novo.
Painel de hardening atual:

- `conectaeduca-interna`: recuperar `agent.conf` efetivo e confirmar o SHA-256
  conhecido antes de versionar;
- `conectaeduca-dmz`: canonicalizar somente após auditoria/poda para não
  duplicar Suricata/FIM de demonstração nem interferir no Active Response/YARA.

**Fechamento:** policies efetivas comparadas byte a byte, versionadas somente
após reconciliação e validadas sem regressão.

---

### DMZ-01 — Fechar auditoria de serviço PHP/Nginx/WAF

**Estado:** DONE  
**Prioridade:** P1


**Fechado em 18/09/2026:** PHP/Nginx/WAF passaram revisão funcional e negativa; WAF/CRS permanece ativo, TLS/HTTP e hardening foram comprovados, e o pipeline visual WAF → Wazuh → Indexer → Dashboard foi demonstrado.
O hardening de runtime já existe, mas o painel vivo ainda classifica a camada
de serviço DMZ como parcial.

Escopo:

- PHP: `php.ini`, pool FPM, upload/session/error disclosure e funções de risco;
- Nginx: TLS, headers, métodos, timeouts, disclosure e FastCGI/proxy;
- WAF: paranoia level, exclusions, logging sem dados sensíveis.

**Fechamento:** revisão + testes funcionais/negativos antes do Pentest A, sem
tuning cego que destrua a linha de base.

---

### PENTEST-00 — Readiness sem sudo e caminhos de baixo privilégio

**Estado:** HOST_GATE  
**Prioridade:** P1  
**Dependências:** HOST-01 e identidades técnicas aplicáveis

**Restrição confirmada pelo professor em 24/09/2026:** `sudo` será desativado durante o pentest. Antes do corte, provar que o principal `teste` consegue exercer os caminhos previstos sem:

- `sudo`/`su`;
- grupo `docker`;
- `docker exec`;
- Docker socket;
- configuração root-only emprestada;
- credencial administrativa;
- instalação de pacote durante o pentest;
- coleta de evidência dependente de acesso root-only.

A identidade `teste` deve existir no mecanismo nativo de autorização do serviço, não necessariamente no `/etc/passwd` do container.

Executar nas duas VMs:

```bash
python3 scripts/evidencias/pentest_no_sudo_readiness.py
```

Fechar E2E, quando aplicável, para MariaDB, Catalog/PgBouncer, Bacula Console, OpenBao userpass, Wazuh, Bacularis e phpMyAdmin. Depois da retirada de sudo, executar também `scripts/evidencias/pentest_sem_sudo_runtime_check.py` **como `teste`**.

**Fechamento:** `teste` fora de sudo/wheel/docker; ferramentas cliente disponíveis; caminhos loopback/WebGUI/clientes funcionando sem `docker exec`; positivos e negativos de autorização comprovados.

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

### BAC-04 — Fechar política operacional e prova E2E do Bacula

**Estado:** HOST_GATE  
**Prioridade:** P1

O BAC-04 deixou de ser evolução futura. O baseline atual já possui produtores
dedicados para MariaDB e OpenBao e a próxima execução autorizada é o
`BAC-04 v2.4 operational apply` na EP126.

Ordem de fechamento:

1. aplicar e validar o v2.4: staging, materializer, FileSets, Jobs e Pool
   operacional, preservando integralmente os SmokeJobs;
2. executar o v2.5 E2E: materialização real, backup, perda controlada, restore
   isolado e comparação de SHA-256;
3. somente depois definir e versionar o Schedule operacional, sem inventar
   horário antes da escolha da janela de operação.

A restrição acadêmica de não disponibilizar segundo disco/partição deve
permanecer registrada como boundary do domínio físico de falha.

**Fechamento:** backup/restore operacional comprovado para MariaDB, OpenBao
Raft, Catalog e Recovery State, exclusões sensíveis demonstradas e política
de retenção/Schedule documentada.

---

### GUI-01C — phpMyAdmin read-only para demonstração

**Estado:** HOST_GATE  
**Prioridade:** P1  
**Dependência:** BAC-04 v2.4/v2.5

Preparar uma WebGUI gráfica para demonstrar o menor privilégio do MariaDB sem
criar uma superfície administrativa adicional.

O contrato e o precheck ficam versionados em:

- `deploy/interna/mariadb/PHPMYADMIN-READONLY.md`;
- `scripts/evidencias/gui01c_phpmyadmin_precheck.py`.

A implementação final deve usar `teste`, publicar somente em loopback, não
versionar senha, não usar Docker socket/privileged/host network e provar
graficamente leitura permitida + escrita negada pelo banco.

**Fechamento:** container phpMyAdmin hardened e loopback-only, imagem oficial
fixada por digest, login `teste` funcional, SELECT demonstrado, DML negado e
MariaDB preservado sem recreate.

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
REPO-01 = DONE
              ↓
           HOST-01
              ↓
          BAC-04
              ↓
GUI-01C phpMyAdmin
              ↓
PENTEST-00 readiness sem sudo
              ↓
   inventário read-only pré-freeze
              ↓
TIME-01 (BOUNDARY: resolver ou aceitar risco)
              ↓
           FREEZE-01
              ↓
TEST-01 (ZAP/DAST)
              ↓
TEST-02 (Pentest A)
              ↓
ZT-01 (Twingate)
              ↓
TEST-03 (Pentest B)
              ↓
EVID-01
```

Itens FUTURE podem permanecer fora dessa linha sem bloquear o freeze.