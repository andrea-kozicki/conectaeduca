# Backlog técnico consolidado — ConectaEduca

Atualizado em 26/09/2026.

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

**Estado:** HOST_GATE  
**Prioridade:** P1  
**Dependência:** EP126 / Wazuh Manager

O fechamento de 18/09/2026 permanece válido como evidência histórica daquele
baseline. O item foi **reaberto em 26/09/2026 por regressão nova de cobertura**
identificada no pente-fino pós-reboot da EP125.

Estado observado na EP125:

- Wazuh Agent 4.14.7 `active/enabled`;
- `wazuh-syscheckd -t`: PASS;
- `wazuh-logcollector -t`: PASS;
- transporte EP125 -> EP126:1514/TCP: ESTABLISHED;
- `No rootcheck_files file configured`;
- `No rootcheck_trojans file configured`;
- `netstat not available. Skipping port check`;
- `ss` presente, mas `netstat` ausente.

A configuração central versionada do grupo
`deploy/interna/wazuh/groups/conectaeduca-dmz/agent.conf` habilita
`check_files`, `check_trojans` e `check_ports`, porém ainda não referencia
as bases `rootkit_files`/`rootkit_trojans` e o diretório do grupo não
versiona esses arquivos.

A correção deve ser feita **manager-side**, pelo grupo centralizado do Wazuh,
para evitar hotfix local divergente na EP125.

Fechamento mínimo:

- materializar/versionar as bases necessárias do Rootcheck no grupo DMZ e
  referenciá-las pela policy efetiva;
- sincronizar/recarregar a configuração pelo Manager;
- confirmar no agente EP125 que os warnings
  `No rootcheck_files file configured` e
  `No rootcheck_trojans file configured` não reaparecem;
- decidir explicitamente o subcheck de portas:
  - instalar `net-tools` por change control, **ou**
  - desabilitar/documentar `check_ports` como risco residual se o laboratório
    não autorizar essa dependência;
- preservar `wazuh-syscheckd -t`, `wazuh-logcollector -t` e TCP/1514 em PASS;
- registrar evidência sanitizada e atualizar o freeze.

**Fechamento:** cobertura Rootcheck coerente com o baseline centralizado,
sem warning de bases ausentes; decisão de `check_ports` formalizada.

---

### DMZ-01 — Fechar auditoria de serviço PHP/Nginx/WAF

**Estado:** DONE  
**Prioridade:** P1


**Fechado em 18/09/2026:** PHP/Nginx/WAF passaram revisão funcional e negativa; WAF/CRS permanece ativo, TLS/HTTP e hardening foram comprovados, e o pipeline visual WAF → Wazuh → Indexer → Dashboard foi demonstrado. Reabrir somente diante de regressão nova.

---

### APPSEC-02 — Limpar finding Snyk no gate zero-sudo

**Estado:** DONE  
**Prioridade:** P1

**Fechado em 25/09/2026.**

O finding Snyk Code classificado como CWE-798 no gate zero-sudo foi removido
sem Ignore/suppression. O contrato passou a materializar o UID aprovado em
`/etc/conectaeduca/pentest-principal.uid`, root-owned, e os checks vinculam o
runtime ao UID esperado em vez de usar literal interpretável como credencial.

Resultado consolidado:

- PR #118 mergeado;
- E2E de CI com identidades A/B: principal esperado PASS, principal divergente
  BLOCK;
- Snyk, Semgrep, Gitleaks, Static Integrity e PHPUnit verdes;
- nenhuma thread pendente.

A validação AppSec posterior da `main` em 26/09 também confirmou
`snyk code test = 0 issues`.

Documento canônico do estado atual:
`docs/seguranca/APPSEC-BASELINE-PREFREEZE.md`.

**Fechamento:** scan limpo + comportamento zero-sudo preservado.


---

### APPSEC-03 — Resolver recorrência Semgrep Popen1/Popen2

**Estado:** DONE  
**Prioridade:** P1

**Fechado em 26/09/2026.**

A divergência entre o scan antigo e o checkout canônico foi reconciliada. O
sanitizador OpenBao vigente mantém `subprocess.Popen` em modo binário e faz o
decode tolerante fora do construtor do processo. O gate de origem do scan
continua registrando root, branch, HEAD, `origin/main`, ahead/behind e blob
Git para impedir nova evidência ambígua.

Validação final na `main`:

- `semgrep scan --config auto .`: 1.742 regras, 561 targets,
  **0 findings / 0 blocking**;
- o finding Popen1/Popen2 não reapareceu;
- `snyk code test`: **0 issues**;
- nenhum suppression foi necessário.

Documento canônico:
`docs/seguranca/APPSEC-BASELINE-PREFREEZE.md`.

**Fechamento:** fonte do scan reconciliada + finding ausente no scan amplo da
`main`.


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

**Checkpoint repo 25/09/2026 — CRED-01 tooling:** foi versionado
`scripts/evidencias/cred01_consistencia_identidades.py`, com matriz distinta
para EP125/EP126, coleta raw sem senha, estados PASS/N_A/PENDENTE/BLOCK,
finalizador fail-closed e manifests RAW/FINAL. O fechamento operacional continua
dependente das VMs e dos testes reais de PAM/OpenBao/Bacularis/MariaDB-
phpMyAdmin/PostgreSQL-PgBouncer/Bacula/Wazuh.

Runbook:
`docs/seguranca/CRED-01-CONSISTENCIA-IDENTIDADES.md`.

**Fechamento:** inventário completo PASS/N/A por serviço, autenticação positiva com
o método esperado e autorização mínima preservada.

**Checkpoint 25/09/2026 — CRED-01 OpenBao:** material de recuperação administrativa pronto. OpenBao healthy/unsealed, generate-root legado bloqueado (HTTP 405), HCL endurecido, Share 1 local 0600 e pacote criptografado da Share 2/Google Drive validado por manifesto + SHA-256. Nenhuma mutação executada; próximo passo é janela controlada para root temporário em memória, troca exclusiva da senha de `userpass/teste`, reteste de menor privilégio, revogação e restauração do hardening.

---

### TIME-01 — NTP/timezone institucional

**Estado:** DONE  
**Prioridade:** P1

**Fechado em 25/09/2026 por aceitação formal de risco residual.**

Diagnósticos registraram NTP ativo sem sincronização confiável e diferença
temporal entre pfSense e VMs. A conta acadêmica não possui privilégio suficiente
para alterar a configuração temporal do firewall institucional.

Decisão:
- não executar workaround não autorizado;
- não apresentar sincronização como comprovada;
- preservar timestamps originais;
- documentar o impacto na correlação Wazuh/Suricata/WAF/pfSense/aplicação;
- registrar eventual skew no pacote de evidências;
- escopo da aceitação restrito ao laboratório acadêmico.

Documento canônico:
`docs/seguranca/TIME-01-RISCO-TEMPORAL.md`.

`FREEZE-01` deve registrar:
`TIME01_NTP_RISK_ACCEPTED=YES`,
`TIME01_CROSS_SOURCE_TIMESTAMP_EXACTNESS=NOT_GUARANTEED`.

**Fechamento:** `TIME01_STATUS=DONE_WITH_ACCEPTED_RISK`.

---

### AUDIT-01 — Lynis EP125/EP126 pré-freeze

**Estado:** DONE  
**Prioridade:** P1

**Fechado em 26/09/2026.**

O Lynis foi executado nas duas VMs, com saída bruta preservada, SHA-256,
comparação baseline/pós-ajuste e triagem manual fail-closed.

EP126:

- baseline: hardening index 56, 2 warnings, 52 suggestions, 54 findings;
- pós-ajustes: index 63, 1 warning, 45 suggestions, 46 findings;
- triagem final: 54/54 findings classificados;
- manifesto final SHA-256 preservado.

EP125:

- baseline: hardening index 56, 4 warnings, 53 suggestions, 57 findings;
- pós-ajustes: index 64, 3 warnings, 46 suggestions, 49 findings;
- 8 findings removidos, nenhum novo;
- triagem final: 57/57 findings classificados;
- 7 remediados;
- 6 remediados com scanner sem reconhecer integralmente;
- 4 change-controls foram tratados no closeout pós-reboot;
- manifesto final SHA-256 preservado.

O pós-reboot confirmou o kernel alvo nas duas VMs e levou à correção persistente
do logrotate do Suricata na EP125. Os resíduos NTP e Rootcheck foram separados
nos gates TIME-01 e WAZ-02, evitando reabrir AUDIT-01 por issues de domínio
distinto.

**Fechamento:** relatórios EP125/EP126 preservados, findings triados e riscos
residuais encaminhados aos gates canônicos correspondentes.


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

**Estado:** DONE  
**Prioridade:** P1  
**Dependência:** BAC-04 = DONE

**Fechado em 25/09/2026 por aceitação formal de risco residual.**

O laboratório permanecerá com execução **manual** dos backups operacionais.
Nenhum Schedule será criado apenas para produzir evidência, porque não existe
janela operacional real definida para as VMs acadêmicas.

Consequências documentadas:

- `BAC05_SCHEDULE_ACTIVE=NO`;
- `BAC05_EXECUTION_MODE=MANUAL`;
- o RPO de até 24 horas permanece alvo de arquitetura, mas **não é garantido**
  automaticamente;
- `FREEZE-01` deve registrar a freshness/idade do último backup válido;
- se necessário para a demonstração ou teste, novo backup manual deve ser
  executado antes do freeze;
- a decisão vale somente para o laboratório acadêmico;
- produção futura exige Schedule em janela real, monitoramento e alertas.

A decisão completa está em
`deploy/interna/bacula/BAC-05-DECISAO-RECORRENCIA.md`.

Este fechamento não reabre BAC-04 e não altera os recursos live já validados.

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
BAC-05 = DONE (manual; risco aceito)
              ↓
APPSEC-02 = DONE / APPSEC-03 = DONE
              ↓
AUDIT-01 = DONE
              ↓
PENTEST-00 readiness sem sudo / CRED-01
              ↓
WAZ-02 Rootcheck manager-side na EP126
              ↓
   inventário read-only pré-freeze
              ↓
TIME-01 = DONE (risco temporal aceito)
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