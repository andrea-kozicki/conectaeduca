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

**Estado:** DONE  
**Prioridade:** P0  
**Dependência:** REPO-01

**Fechado novamente em 24/09/2026 após delta pré-freeze.**

O fechamento anterior de 21/09/2026 foi válido para a `main`
`3d7abdb4e21d76f504c75ab04faca09e3faa16e5`. Como a `main` avançou depois
disso, foi executado novo inventário read-only nas duas VMs antes do freeze.

Resultado final:

- EP126 já estava em
  `0b1201cfec99282573959973cb493992a6332443`, com worktree limpa e
  `HEAD == main == origin/main`;
- EP125 estava em `3d7abdb...`, worktree limpa;
- após `git fetch --prune origin main`, a EP125 confirmou
  `origin/main=0b1201cf...`;
- relação de fast-forward comprovada, com `HEAD_VS_ORIGIN_MAIN_COUNTS=0 75`;
- `FF_BIND_HAZARDS=0`;
- nenhum path em `deploy/dmz` mudou;
- atualização aplicada somente por `git merge --ff-only origin/main`;
- HEAD final EP125 =
  `0b1201cfec99282573959973cb493992a6332443`;
- worktree permaneceu limpa;
- os três containers DMZ mantiveram IDs, imagens, `StartedAt`, portas e
  `restart_count=0`;
- Bacula FD, Wazuh Agent, Suricata, xrdp e Docker permaneceram invariáveis;
- nenhuma mutação de Docker Compose/systemd, nenhum restart de container e
  nenhum root shell foram usados.

**Fechamento:** EP125 e EP126 reconciliadas com a mesma `main` canônica vigente,
sem regressão ou mutação acidental do runtime.

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


**Fechado em 18/09/2026:** proveniência package-based comprovada na EP125 via `bacula-client 15.0.3-1~noble`, binário/configuração em `/opt/bacula`, bootstrap v3 fail-closed alinhado no #91 e CI verde. O procedimento institucional de `/opt/bacula` foi formalizado no handoff. Não reinstalar o FD live apenas para repetir evidência.

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


**Fechado em 18/09/2026:** receiver pfSense, decoder/regra e persistência/consulta no Wazuh foram validados; Suricata real da EP125 também foi correlacionado no Indexer. O gate visual WAF `rule.id:110300` no Threat Hunting foi fechado em 18/09. Reabrir somente diante de regressão nova.

---

### WAZ-02 — Canonicalizar policies efetivas dos agentes Wazuh

**Estado:** DONE  
**Prioridade:** P1


**Fechado em 18/09/2026:** policies efetivas foram comparadas/validadas sem regressão e o baseline operacional foi aceito. Reabrir somente diante de drift novo.

---

### DMZ-01 — Fechar auditoria de serviço PHP/Nginx/WAF

**Estado:** DONE  
**Prioridade:** P1


**Fechado em 18/09/2026:** PHP/Nginx/WAF passaram revisão funcional e negativa; WAF/CRS permanece ativo, TLS/HTTP e hardening foram comprovados, e o pipeline visual WAF → Wazuh → Indexer → Dashboard foi demonstrado. Reabrir somente diante de regressão nova.

---

### APPSEC-02 — Limpar finding Snyk no gate zero-sudo

**Estado:** REPO_GATE  
**Prioridade:** P1  
**Dependência:** PENTEST-00 tooling

Novo finding Snyk Code identificado em 24/09/2026 em
`scripts/evidencias/pentest_sem_sudo_runtime_check.py`:

- regra: **Use of Hardcoded Credentials / CWE-798**;
- ponto: comparação `if USER == "teste"`;
- o literal é o nome da identidade técnica esperada, não senha/token;
- classificação preliminar: provável falso positivo semântico, mas o repositório
  deve voltar a scan limpo antes do freeze.

Não usar Ignore/suppression como primeira opção. Refatorar o gate para receber ou
derivar a identidade esperada sem literal classificado como credencial, preservar
a exigência de execução como `teste`, rerodar Snyk/Semgrep/Gitleaks e validar o
script funcionalmente.

**Fechamento:** scan limpo + comportamento zero-sudo preservado.

---

### APPSEC-03 — Verificar fechamento do achado Semgrep Popen

**Estado:** REPO_GATE  
**Prioridade:** P2

Achado histórico reapresentado em 24/09/2026 no sanitizador OpenBao:

- `python36-compatibility-Popen1` por `errors=` em `subprocess.Popen`;
- `python36-compatibility-Popen2` por `encoding=` em `subprocess.Popen`.

A implementação canônica atual já usa `Popen` em modo binário, sem
`text=`, `encoding=` ou `errors=`; a decodificação UTF-8 tolerante ocorre
em `process_stream()`. A correção entrou no commit
`788d2fa6415b052ec8144a433bd2f5d7a23924a8` e o baseline Python suportado
permanece >=3.10.

A pendência é somente confirmar que o scan que gerou o print antigo não estava
sobre checkout desatualizado e preservar evidência de rerun limpo. Não criar
nova suppression.

**Fechamento:** Semgrep no checkout canônico sem Popen1/Popen2 e CI verde.

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

O mapa operacional dos cenários oficiais está em `docs/seguranca/PENTEST-S01-S13-ZERO-SUDO.md`. Antes do corte, fechar em especial os GAPs de S10 (FIM user-writable), S11/S13 (DLP user-writable), S07/S08 (evidência independente de Docker), S06 (grants) e S12 (restore separado da fase atacante).

**Fechamento:** `teste` fora de sudo/wheel/docker; ferramentas cliente disponíveis; caminhos loopback/WebGUI/clientes funcionando sem `docker exec`; positivos e negativos de autorização comprovados.

#### CRED-01 — consistência da autenticação padronizada de `teste`

Antes do freeze, inventariar cada mecanismo em que a identidade técnica `teste`
realmente existe e confirmar que a credencial acadêmica padronizada está coerente
onde o método é password-based. Não forçar senha compartilhada em mecanismos que
usem PKI, certificado, PSK ou outra forma de autenticação: nesses casos registrar
`N/A` e validar o método nativo.

Cobertura mínima:

- Linux/PAM na EP125 e EP126;
- OpenBao `userpass`;
- Bacularis WebGUI;
- MariaDB/phpMyAdmin;
- PostgreSQL/PgBouncer;
- Bacula Console;
- Wazuh, conforme o mecanismo efetivamente configurado.

Onde tecnicamente seguro, provar também que a credencial incorreta/anterior deixa
de autenticar após a correção. Toda evidência deve ser sanitizada, sem registrar
senha, token, hash, PSK ou chave privada.

**Fechamento:** inventário completo PASS/N/A por serviço, autenticação positiva com
o método esperado e autorização mínima preservada.

**Checkpoint 25/09/2026 — CRED-01 OpenBao:** material de recuperação administrativa pronto. OpenBao healthy/unsealed, generate-root legado bloqueado (HTTP 405), HCL endurecido, Share 1 local 0600 e pacote criptografado da Share 2/Google Drive validado por manifesto + SHA-256. Nenhuma mutação executada; próximo passo é janela controlada para root temporário em memória, troca exclusiva da senha de `userpass/teste`, reteste de menor privilégio, revogação e restauração do hardening.

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

### AUDIT-01 — Lynis EP125/EP126 pré-freeze

**Estado:** HOST_GATE  
**Prioridade:** P1  
**Dependências:** PENTEST-00 e ajustes pré-freeze aplicáveis

Item recuperado do plano de 21/09/2026 e do Trello, ausente da consolidação
canônica anterior.

Executar Lynis nas duas VMs, preservar saída bruta + SHA-256 e classificar cada
warning/suggestion como aplicável, não aplicável ao laboratório, já mitigado ou
risco aceito. Não aplicar remediação automática nem reabrir arquitetura apenas
por recomendação genérica.

**Fechamento:** relatórios EP125/EP126 preservados, findings triados e resumo de
risco residual incorporado ao freeze/relatório.

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

### DEMO-01 — Consolidar evidências visuais reais

**Estado:** SEQUENCED  
**Prioridade:** P2  
**Dependência:** AUDIT-01 / FREEZE-01 quando aplicável

O material de apresentação já existe, mas ainda precisa substituir placeholders
por evidências reais e atualizar a narrativa final. OpenBao, Bacularis e
phpMyAdmin já possuem provas visuais; ainda deve ser consolidada a evidência
visual do Ferret e o resultado do Lynis, sem transformar UI opcional em blocker
de runtime.

**Fechamento:** PPTX/relatório com prints reais, legendas e matriz final coerente.

---

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

**Estado:** DONE  
**Prioridade:** P1

**Fechado em 24/09/2026.**

A política operacional e a prova E2E foram concluídas na EP126:

- BAC-04B v2.4.4: staging, materializer, FileSets, Jobs e
  `ConectaEducaOperationalPool` promovidos com `bacula-dir -t` válido;
- SmokeJobs preservados integralmente e Console `teste` mantido com ACL
  de recurso mínima, sem ampliar `CommandACL`;
- somente o Director foi reiniciado durante o APPLY; demais serviços ficaram
  sem restart;
- Pool operacional: 5 volumes x 5 GiB, retenção de 14 dias e
  `Volume Use Duration` de 7 dias;
- materialização real validada para MariaDB lógico, OpenBao Raft snapshot,
  Bacula Catalog e Recovery State por allowlist;
- backups E2E: JobIds 10–13, todos `JobStatus=T` e `JobErrors=0`;
- restores isolados: JobIds 14–17, todos `Type=R`, `JobStatus=T` e
  `JobErrors=0`;
- SHA-256 dos quatro restores idêntico aos artefatos de origem;
- formatos revalidados: dump MariaDB, snapshot OpenBao, Catalog por
  `pg_restore --list` e Recovery State por allowlist exata;
- staging e diretórios de restore limpos somente após 4/4 restores
  comprovados;
- `BAC04B_OPERATIONAL_BACKUP_RESTORE_PROVEN=YES`;
- Schedule não foi ativado: a janela operacional continua deliberadamente
  sem horário inventado.

A restrição acadêmica de não disponibilizar segundo disco/partição permanece
como risco residual explícito: `PHYSICAL_ISOLATION=0`, pois o Storage ainda
compartilha o domínio físico da EP126.

O escopo BAC-04 encerra a política, os recursos operacionais e a prova E2E.
A recorrência automática foi separada em BAC-05 para que a ausência de um
horário real não seja mascarada pelo fechamento da prova de backup/restore.

---

### BAC-05 — Definir janela e ativar Schedule operacional

**Estado:** HOST_GATE  
**Prioridade:** P1  
**Dependência:** BAC-04 = DONE

O laboratório já comprovou backup e restore operacional, mas o Schedule não deve
receber um horário arbitrário apenas para fechar o gate. Antes do freeze, deve
ocorrer uma das duas opções, de forma explícita:

1. escolher uma janela operacional real, versionar o Schedule e validar ao menos
   uma execução agendada; ou
2. registrar formalmente no freeze que o laboratório permanecerá com execução
   manual por decisão acadêmica, incluindo o impacto sobre RPO/recorrência.

Este item não reabre BAC-04: ele rastreia apenas a recorrência automática que foi
deliberadamente mantida fora da prova E2E.

**Fechamento:** Schedule operacional validado em janela justificada **ou** risco
residual de execução manual explicitamente aceito/documentado antes do freeze.

---

### GUI-01C — phpMyAdmin read-only para demonstração

**Estado:** DONE  
**Prioridade:** P1  
**Dependência:** BAC-04 = DONE

**Fechado em 24/09/2026.**

Estado final comprovado:

- imagem oficial fixada por digest;
- publicação somente em loopback via `https://localhost:9443`;
- fallback HTTP `127.0.0.1:9098` removido;
- `cap_drop: ALL` com somente `CHOWN,DAC_OVERRIDE,SETGID,SETUID`;
- `no-new-privileges:true`, sem privileged, Docker socket ou host network;
- entrypoint nativo preservado;
- TLS navegador → phpMyAdmin: TLSv1.3, `Verification: OK`,
  `Verified peername: localhost`;
- TLS phpMyAdmin → MariaDB explícito com `SSL=1`, `SSL_VERIFY=1` e CA correta;
- principal `teste@172.18.255.254` limitado a SELECT na view de pentest;
- login e SELECT: PASS;
- DELETE seguro: DENY PASS (#1142);
- smoke manual HTTPS-only final: PASS;
- logs sem marcadores fatais/insecure transport;
- MariaDB preservado sem mutation/restart/recreate;
- Compose final sanitizado versionado em
  `deploy/interna/mariadb/compose.phpmyadmin.yml`;
- SHA-256 do runtime/candidato final:
  `6affbf67959ed4c4b670d29d1a6b9834e748f86eb667a7a60350649ecf845900`.

**Fechamento:** GUI-01C DONE; reabrir somente diante de regressão nova.

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
        HOST-01 = DONE
              ↓
     BAC-04 = DONE
              ↓
GUI-01C = DONE
              ↓
BAC-05 Schedule (resolver ou aceitar risco)
              ↓
APPSEC-02 Snyk zero-sudo
              ↓
PENTEST-00 readiness sem sudo / CRED-01
              ↓
AUDIT-01 Lynis EP125/EP126
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