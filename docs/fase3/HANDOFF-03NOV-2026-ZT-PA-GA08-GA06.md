# Fase 3 — handoff único para 03/11/2026: Zero Trust, PA-02 e Ferret v5

**Elaborado em 02/11/2026 (America/Sao_Paulo)** · **Natureza:** DOCUMENTAÇÃO PRONTA PARA EXECUÇÃO FUTURA, não autorização nem afirmação de implementação.  
**Regra:** esta branch contém **somente Markdown**, não muda runtime, regras, Compose, pipelines, scripts, tokens ou `main`.
**Prazo:** preservar o trabalho já validado. Usar uma janela por VM, gates objetivos e um pacote de provas; evitar inventários, reruns e PRs duplicadas.

## Atualização de 03/11 — resposta docente, snapshots e AD

[Registro da orientação docente, snapshots e tabela AD/pfSense](DECISAO-DOCENTE-SNAPSHOTS-AD-PFSENSE-20261103.md).

- O professor confirmou **portal de usuários finais via internet/HTTPS/WAF**. **Twingate** fica para administração e infraestrutura interna, mantendo MFA/RBAC da aplicação e a segregação do Wazuh.
- O suporte informou **snapshots realizados**, mas não apresentou ID/cobertura/restore; portanto **G0 permanece fechado**. **Correção posterior da responsável:** o acesso à EP126 voltou a funcionar porque o suporte **desativou todas as regras pfSense que ela havia criado**; **não há evidência de restauração de snapshot**. As regras personalizadas de segregação estão inativas, e a causa exata da interferência no acesso/AD permanece a esclarecer. Não reativar tudo de uma vez. Registro detalhado no [adendo pfSense](DECISAO-DOCENTE-SNAPSHOTS-AD-PFSENSE-20261103.md).
- A tabela sugerida de DNS/Kerberos/LDAP/GC/NTP para o AD é **hipótese inicial, não abertura efetiva**. Confirmar o cliente, os DCs, origem/destino, modalidade de ingresso e necessidade de SMB/RPC/LDAPS antes de qualquer mudança pfSense.

## 1. Pacotes preparados para a janela
| Entrega | Local | Situação |
| --- | --- | --- |
| Decisão professor, snapshots e tabela AD/pfSense | [ATUALIZAÇÃO 03/11](DECISAO-DOCENTE-SNAPSHOTS-AD-PFSENSE-20261103.md) | **REGISTRADO**, G0 e firewall pendentes de validação |
| Roteiro de execução Python, gates e aceite por PA | [ROTEIRO PENTEST B](EXECUCAO-E-ACEITE-PENTEST-B-EP125-EP126-CLIENT-20261103.md) | **PREPARADO** na documentação, não executado; alinhado à PR #219 e seus 64 testes offline |
| Matriz Pentest A×B para PA-01…07 | [MATRIZ PA01–07](PA01-PA07-MATRIZ-PENTEST-A-B-20261102.md) | **PRONTA PARA USO**, resultados B não executados |
| Checklist PA-02/EP125 e GA08.18 | [ROTEIRO GA08](../release/GA08-18-EP125-ROTEIRO-CORTE-RETESTE-20261103.md) | **PRONTO, G0 FECHADO** até snapshot e revisão |
| Checklist Ferret v5/EP126 e GA06 | [ROTEIRO GA06](../release/GA06-FERRET-V5-EP126-ROTEIRO-CORTE-RETESTE-20261103.md) | **PRONTO, G0 FECHADO** até snapshot/autorização |
| Rastreabilidade de PRs, Zero Trust e ordem de trabalho | Este documento | **PRONTO**; não alterar PRs de código para simular aceite |

## 2. Linha de base do Zero Trust — fatos observados e limites
- **EP125 DMZ 192.168.6.34** e **EP126 interna 192.168.6.50**; roteamento, NAT e regras interzonas pertencem ao pfSense; bridge Docker local é caminho independente, não automaticamente submetido ao Twingate.
- Connectors institucionais `conectaeduca-dmz-01` EP125 e `conectaeduca-interna-ep126` EP126 foram reportados **Running/healthy/Connected** em 31/10–02/11; conectores antigos/cadastrados não conectados NÃO são motivo para reinstalar os saudáveis.
- Resource `ConectaEducaAPP` para EP125 HTTPS/443: openSUSE com FortiClient desconectado e Twingate online acessou portal com cadeia CA confiável, `curl` HTTP200/TLS verificado e Firefox no perfil isolado. **Prova de acesso pelo cliente, não de backend isolado.**
- Resource `ConectaEduca — Wazuh Dashboard`: no Connector EP126 destino `127.0.0.1:443`, alias `wazuh.dashboard`, grupo `CE-SOC-OPERACAO` com política MFA. `twingate auth` mostrou sucesso; login de aplicação Wazuh com conta de teste e negações de leitura em Users/Roles/Policies/Roles mapping versus admin permitido foram documentados em 01/11.
- **Teste de segregação ZT-07.26B/C (02/11):** identidade limitada no Android em 5G com Twingate conectado alcançou ConectaEducaAPP, mas Wazuh não apareceu e o alias não resolveu DNS nessa sessão. **PASS_WITH_SCOPE**: duas identidades em **dispositivos distintos**, sem packet capture universal ou logs completos de auditoria de negação; não transformar em prova de impossibilidade de qualquer rota lateral.
- **PA-02 permanece aberto:** acesso direto host→bridge Nginx EP125 reproduzido antes do cutover; o Twingate não inspeciona sozinho o upstream HTTP. A proposta dual socket exige G0 e GA08.18.
- **Arquitetura de exposição:** página pública HTML/HTTPS e endpoints administrativos privados são papéis distintos. Um Resource `IP:443` Twingate não protege apenas caminho `/admin`; exigir listener/hostname/endpoint próprio ou negação explícita no WAF para isolamento administrativo futuro.
- Nunca repetir prints de QR MFA, URL efêmera, token, cookie ou exportar secret dos Configs; evidência acadêmica usa screenshots **sanitizados** e hashes de cópias privadas.

**Referências ZT atuais:** [PR #214](https://github.com/andrea-kozicki/conectaeduca/pull/214), `docs/evidencias/CONSOLIDADO-ZT08-TWINGATE-PORTAL-WAZUH-20261102.md` e `docs/runbooks/TWINGATE-WAZUH-GATE-NEGATIVO-20261102.md` **na branch do PR #214**. Alguns parágrafos mais antigos do corpo da PR #214 ainda refletem 31/10 (CA ou login pendentes) e não devem prevalecer sobre os adendos datados 01–02/11.

## 3. PRs abertas — coordenação sem merges inesperados
| PR / escopo | Situação no GitHub em 02/11 | Encaminhamento correto |
| --- | --- | --- |
| [#219](https://github.com/andrea-kozicki/conectaeduca/pull/219) Kit Python Pentest B | OPEN/DRAFT; 64 testes offline PASS (03/11); fases 1–5 e gerador Markdown Daily 9; **nenhum ataque real executado** | usar [ROTEIRO PENTEST B](EXECUCAO-E-ACEITE-PENTEST-B-EP125-EP126-CLIENT-20261103.md), observar gates EP125/EP126, nunca converter fixture ou CI em PASS |
| [#217](https://github.com/andrea-kozicki/conectaeduca/pull/217) GA08/PA02 dual socket | OPEN/DRAFT; 6 CI workflows PASS HEAD `67ab035b`; mudança runtime ainda não aplicada | usar [GA08.18](../release/GA08-18-EP125-ROTEIRO-CORTE-RETESTE-20261103.md), snapshot **EP125**, validar 9/10 Compose e mounts, revisar rollback, só depois cutover |
| [#207](https://github.com/andrea-kozicki/conectaeduca/pull/207) Ferret v5 | OPEN/DRAFT; 6 CI workflows PASS HEAD `1c7b8e1`; imagem 2.4.3 em produção | usar [GA06](../release/GA06-FERRET-V5-EP126-ROTEIRO-CORTE-RETESTE-20261103.md), snapshot **EP126**, custódia TAR/monitor/CLI/rollback, reteste pós-cutover |
| [#206](https://github.com/andrea-kozicki/conectaeduca/pull/206) Wazuh DLP rules | OPEN/DRAFT; ruleset operacional corrigido EP126 | evidências GA07.3–4 e GA07.8R PASS **não são merge**, preservar diferença Git/runtime |
| [#214](https://github.com/andrea-kozicki/conectaeduca/pull/214) ZT docs | OPEN/DRAFT; Connectors e Recursos parcialmente operacionais | corrigir interpretação histórica com observações de 02/11; evitar reinstalação e coleta repetitiva |
| [#200](https://github.com/andrea-kozicki/conectaeduca/pull/200) desenho ZT amplo | OPEN/DRAFT, `mergeable=false` em 02/11 | **não** fazer merge do lote heterogêneo; a correção PA02 isolada está na #217 |
| [#205](https://github.com/andrea-kozicki/conectaeduca/pull/205) MFA/login PHP | OPEN/DRAFT; testes offline de contrato | não misturar com PA02/GA06; exige decisão de compatibilidade WebCrypto/UX e testes app |
| [#203](https://github.com/andrea-kozicki/conectaeduca/pull/203) audit.log | OPEN/DRAFT em histórico (não revalidado neste pacote) | política retenção/rotação exige validação separada |

**Fonte de verdade Git:** `main@b74ea581a0814d86a99b6b455d5569f12fa967e5` em 02/11. Branch desta documentação foi criada **a partir desse commit**. Não supor atualização automática nas VMs após merge. A EP126 tem **dois arquivos locais modificados deliberadamente** pela GA07.7B (`scripts/dlp/sanitizar_ferret.py` e `validar_eventos_ferret.py`), ambos correspondentes aos blobs da #207, com backups privados `GA07_7B_cxonskrl`; não sobrescrever com reset/reconciliação cega. Na EP125, `deploy/dmz/compose.audit-persistent.yml` não versionado deve ser preservado. Não comitar segredos ou estado Docker.

## 4. Solicitação objetiva ao suporte para amanhã (DUAS VMs)
**EP125 — PA02:** confirmar ID/timestamp do snapshot, discos/binds/volumes/CA e restaurabilidade; dar visibilidade sobre seis origens protegidas que o usuário comum não consegue inspecionar, sem compartilhar conteúdo. Manter o pacote GA08/17B e rollback revisado antes de qualquer recriação.
**EP126 — Ferret:** confirmar identificação do **snapshot reportado como realizado**, com cobertura `.runtime`, `state`, `inbox`, `reports/raw`, configuração e possibilidade de retorno. Confirmar custódia/aceite de uso do TAR offline e do procedimento de monitor v5; não presumir que o TAR local feito 01/11 é snapshot restaurável.
**pfSense:** as regras criadas pela responsável estão **desativadas pelo suporte para restabelecer acesso à EP126**; recuperar backup/diff e tracker IDs antes de alterar qualquer regra. Aplicar apenas mudança institucional autorizada, uma por etapa, testando login e negação lateral com rollback. Não inferir que o firewall inteiro está desligado, nem abrir regra genérica para fazer o ZT passar.
**Se o suporte fornecer apenas o snapshot de uma VM, somente a respectiva frente pode avançar**, condicionada aos demais gates.

## 5. Sequência de execução de 03/11 — sem retrabalho
1. **Receber confirmação documental dos snapshots reportados e seus planos de recuperação**. Registrar separadamente EP125 vs EP126, operador, cobertura, retenção, hora e autorização.
2. **Escolher a janela de uma VM de cada vez**, impedir concorrência entre GA08 e GA06. Prioridade sugerida: **PA02/EP125** (bypass WAF P0 e dependência de Pentest B). Se EP125 não tiver snapshot válido mas EP126 tiver, considerar apenas Ferret, sem cruzar change control.
3. **GA08.18 (somente com G0 completo)**: executar o procedimento gated da #217, retestes positivos/negativos e registrar estado final. Um 403 WAF sem negativa de backend não encerra PA02.
4. **GA06/v5 (somente com G0 próprio)**: executar procedimento da #207 para imagem/monitor/CLI e seis testes dirigidos; um UI health sem falha 403/inconclusão não encerra PA07.
5. **Pentest B por prioridade de lacunas**: usar [roteiro de execução e aceite](EXECUCAO-E-ACEITE-PENTEST-B-EP125-EP126-CLIENT-20261103.md) e [matriz PA01–07](PA01-PA07-MATRIZ-PENTEST-A-B-20261102.md); executar scripts da PR #219 somente nas identidades, janelas e alvos autorizados. A saída do comparador e os 64 testes CI **não** encerram automaticamente um PA; atrelar resultados às duas campanhas sem reescrever histórico do Pentest A.
6. **Fechamento:** evidências locais com SHA256, relatório Daily 9, links PR/Trello, conclusão/limites, retorno de eventual rollback; só então avaliar review/merge de PRs, uma a uma.

## 6. Checklist único de recebimento do suporte (não contém secrets)
```text
DATA=2026-11-03
EP125_SNAPSHOT_ID=
EP125_TIMESTAMP=
EP125_DISCOS_VOLUMES_COBERTURA=
EP125_RESTAURABILIDADE_CONFIRMACAO=
EP125_OPERADOR_SUPORTE=
EP125_JANELA_E_APROVACAO=
EP125_GA08_G0=ABERTO|FECHADO

EP126_SNAPSHOT_ID=
EP126_TIMESTAMP=
EP126_RUNTIME_STATE_COBERTURA=
EP126_RESTAURABILIDADE_CONFIRMACAO=
EP126_OPERADOR_SUPORTE=
EP126_TAR_V5_EXCECAO_APROVADA=
EP126_JANELA_E_APROVACAO=
EP126_GA06_G0=ABERTO|FECHADO

PA02_CUTOVER=NÃO_EXECUTADO
FERRET_V5_CUTOVER=NÃO_EXECUTADO
PENTEST_B=NÃO_EXECUTADO
```

## 7. Critério de conclusão desta preparação documental
- [x] Matriz de sete PAs produzida, com origem e resultado A, controles B e limitações.
- [x] Roteiro operacional Pentest B com cinco fases, três posições, condições de bloqueio e evidência mínima por PA vinculado à PR #219 (03/11).
- [x] GA08.18 definido com G0, positivos/negativos, drift 9/10 Compose e retorno.
- [x] GA06 v5 definido com TAR/proveniência, monitor, CLI, seis retestes dirigidos e retorno.
- [x] PRs relevantes e estados históricos reconciliados **documentalmente**, sem alterar conteúdo de produção.
- [ ] Snapshots EP125 e EP126 **informados pelo suporte como realizados**; comprovar IDs, cobertura e restaurabilidade para liberar G0.
- [ ] Operação autorizada e executada; retestes pós-cutover e aceite.
- [ ] Pentest B comparativo e revisão/merge posterior das PRs.

**Esta entrega de 02/11 encerra a preparação do dia, NÃO declara encerrados PA-02, PA-07, Zero Trust integral ou Pentest B.**

## Atualização de campo 03/11 — GA-08 EP125 bloqueada no Compose baseline

A responsável integrou os **nove arquivos essenciais da PR #217** em `/opt/conectaeduca` na EP125 a partir do commit imutável `67ab035b6cbd18aac7ed5584af59e6820a9b9813`, mantendo `HEAD=b74ea58`, o overlay local `deploy/dmz/compose.audit-persistent.yml` e hashes Git de todos os nove arquivos (9/9 PASS). A primeira tentativa em shell interativo encerrou o terminal por causa de `set -e/exit`; refizeram-se verificações em subshell sem queda de Guacamole. **Nenhum Compose up/deploy/merge foi realizado.**

Preflight GA08 da PR #217: `GA08_GATE=FAIL_CLOSED`, `GA08_MOTIVO=compose_config_exit_1`. Diagnóstico subsequente isolou **`BASELINE_10_EXIT_CODE=1`, categoria `VARIAVEL_OBRIGATORIA_AUSENTE`**, portanto a falha precede os overlays GA-08. Nem `/opt/conectaeduca/.env` nem `deploy/dmz/.env` existem, `COMPOSE_ENV_FILES` não está configurado, e dez variáveis requeridas (`CONECTAEDUCA_APP_URL`, `DB_HOST`, `DB_PASSWORD_FILE`, `DB_TLS_CA_FILE`, `PRIVATE_KEY_FILE`, `PUBLIC_KEY_FILE`, `STACK_SECRET_GID`, `WAF_BIND_ADDRESS`, `WAF_TLS_CERT_FILE`, `WAF_TLS_KEY_FILE`) não estão exportadas na sessão. Erro de Compose menciona primeiro `DB_HOST` e `DB_PASSWORD_FILE`. **Não significa que os serviços em execução perderam os valores**; provável diferença de ambiente de inicialização original. Não criar arquivos de ambiente artificiais, não enviar segredos nem executar up até recuperar fonte legítima e Gate G0.

**Decisão da responsável:** suspender investigação prolongada da GA-08 enquanto a fonte de ambiente original não for localizada e avançar para preparação da **GA-06 Ferret v5 na EP126**. Snapshot integral reportado pelo suporte, mas ID, cobertura real de binds/externalidades e restauração confirmada ainda pendentes; não inferir gate aprovado. GA-06 deve permanecer sem cutover até comprovar proveniência do TAR/candidato, persistência recuperável, atualização/reversão do monitor, janela/aceite e rollback. Não repetir os inventários GA06.1–5 já aprovados; usar preflight dirigido.

## GA-06.6 — preflight completo EP126 PASS em 03/11/2026 (sem cutover)

Relato de execução na EP126 `ep126-pucpr-br` pela responsável: commit candidato PR #207 `1c7b8e12524f07cea400e83a35775dc49755807b` validado; cinco arquivos de GA06 integrados sem conflitos e sem merge. O preflight inicial parou com `GA06_OFFLINE_TAR_POLICY=FAIL` por ausência de `deploy/interna/ferret/pa07-v5/GA06_CANDIDATE_PROVENANCE.json`. O sexto arquivo foi recuperado **diretamente do mesmo commit**, hash de blob local idêntico ao Git (PASS). Repetido o preflight sobre `~/Downloads/ferret-pa07-v5-candidate-docker-archive.tar`, com resultados:

```text
GA06_OFFLINE_TAR_POLICY=PASS scope=opt-in-path-only
GA06_TAR_E_CONFIG=PASS
GA06_DOCKER_DESCRIPTOR_E_ROOTFS=PASS
GA06_PROVENIENCIA=PASS
GA06_PREFLIGHT=PASS
GA06_TAR_INTEGRITY=PASS
GA06_IMAGE_ID_AND_ROOTFS=PASS
GA06_COMPOSE_ONLY_IMAGE_AND_PULL_POLICY_CHANGED=PASS
GA06_INSTITUTIONAL_DEPLOY_APPROVAL=PENDENTE
GA06_SERVICE_CHANGED=NAO
GA06_PREFLIGHT_FINAL=PASS
PREFLIGHT_EXIT_CODE=0
CUTOVER=NAO_EXECUTADO
```

**Interpretação:** proveniência local do TAR, imagem Docker e único delta de `image` + `pull_policy` confirmados. Não houve `docker compose up`, `docker load`, mudança em systemd ou merge. Os dados persistentes Ferret, drop-in do monitor 2.4.3→2.4.3+ce.pa07.v5, acesso `sudo -n` e rollback não foram ainda confirmados para a janela de mudança. Snapshot **integral** informado pelo suporte, mas ID, horário, exclusões de armazenamento externo e procedimento operacional de recuperação não documentados. Antes do cutover, obter estes dados e confirmar autorização da exceção TAR, adequação do backup dos estados `.runtime/state`, `.runtime/inbox`, `.runtime/reports` e `.runtime/events`, preparar monitor e rollback; então operar mudança isolada do Ferret com reteste UI/CLI/Wazuh. Nenhum teste antigo precisa ser refeito só por rotina.

## GA-06.7 — verificação pontual de baseline e diretórios na EP126 (03/11)

Resultado comunicado da EP126: Compose baseline `config --quiet` PASS; Ferret em execução com imagem original `public.ecr.aws/awslabs/ferret-scan:2.4.3@sha256:7a1b36050ae20a74632ac05b5c34e4aeb26b69836ca6703e10c1392b724b270f`, cujo Image ID foi confirmado presente; timer `conectaeduca-ferret-healthcheck.timer` `active`; drop-in GA-06 v5 `AUSENTE` (esperado). `GA06_CUTOVER=NAO_EXECUTADO`.

**Pendência de dados persistentes:** o script GA06.7 conferiu `-d` nos caminhos `/opt/conectaeduca/deploy/interna/ferret/.runtime/{state,inbox,reports,events}` e obteve `NAO_LOCALIZADO` nos quatro. Esse teste não diferencia diretório ausente de erro de permissão/travessia, nem verifica o `Source` real dos bind mounts do contêiner em execução; **não concluir perda dos dados**. Bloquear cutover até verificar por `docker inspect .Mounts` (somente metadados, sem conteúdo), comparar sources de `/var/lib/ferret`, `/data/inbox`, `/data/reports` e `/etc/ferret/ferret.yaml` com os paths esperados no Compose e examinar `os.lstat` com classificação de `ENOENT/EACCES`. O diretório `.runtime/events` é externo ao Compose do Ferret, mas pertence à trilha DLP/Wazuh e deve ser analisado separadamente. Não criar diretórios, alterar ACL, copiar dados, fazer `compose up` ou reinstalar imagens enquanto origem e persistência não estiverem confirmadas.

## GA-06.8 — binds confirmados; autoridade de operação esclarecida (03/11/2026)

A responsável esclareceu que **é ela quem administra e implanta alterações nas VMs**, inclusive Docker/serviços EP126; o suporte **não executa essas mudanças**, atua no snapshot/restauração institucional e em componentes sob sua gestão. Portanto, **não exigir anuência operacional rotineira do suporte para o cutover Docker**, exceto regras institucionais explícitas eventualmente aplicáveis a artefatos TAR; a responsável aprova janela, executa e verifica rollback dentro de sua delegação.

Evidência GA06.8: `docker inspect .Mounts` do Ferret confirma 4 bind mounts com origem exatamente conforme Compose (config, state, inbox, reports). `config` é arquivo; `state`, `inbox`, `reports` retornam `PERMISSAO_NEGADA` ao usuário por proteção de diretório, **não `NAO_EXISTE`**. A raiz `.runtime` é diretório; `.runtime/events` igualmente nega leitura direta. `GA06_CUTOVER=NAO_EXECUTADO`. Não mexer em ACLs para "corrigir" a proteção. Prosseguir com conferência mínima de leitura administrativa dos 4 diretórios e proteção de rollback, não novo inventário geral. As verificações GA06.6 de TAR/Compose/imagem seguem PASS.

## GA-06.9A e GA-06.10 — sudo interativo recuperado; backup bloqueado por ACL do destino (03/11)

GA-06.9A EP126: `sudo -v` retornou `SUDO_INTERATIVO=PASS`, seguido de `sudo -n true` `PASS`; o bloqueio anterior `SUDO_N=INDISPONIVEL` era compatível com ausência de credenciais em cache. Aviso repetido `sudo: unable to resolve host ep126-pucpr-br: Temporary failure in name resolution`; investigar separadamente correspondência hostname/hosts/DNS, **sem alterar o resolver nem pfSense como efeito colateral da GA06**.

GA-06.10: os diretórios protegidos `state`, `inbox`, `reports`, `events` foram confirmados sob privilégio, entrada de configuração presente; `du` estimou **72 KiB** e `df` relatou **125759648 KiB livres** em `/var/backups`. O procedimento recusou prosseguir em `DESTINO_ACL_NAO_APROVADA` porque o caminho **já existente** `/var/backups/conectaeduca` não correspondia ao predicado estrito `0700 root:root`. Esse resultado **não demonstra ACL insegura**; pode ser política legítima de outros backups. O script interrompeu-se antes de criar TAR novo e antes de alterar containers. **Não executar `chown/chmod` no diretório existente.** Próximo passo: preparar pasta nova privada exclusiva da GA06 sob `/var/backups` (0700 root), arquivar dados com ACLs/xattrs (0600 root), testar gzip/tar integral e registrar SHA, sem publicar o conteúdo. Backup vivo não é snapshot de aplicação consistente; confirmar snapshot institucional e retorno antes de cutover.

## GA-06.10B — backup EP126 concluído, custódia SHA (03/11)

Backup privado isolado em `/var/backups/GA06-EP126-.../ferret-precutover.tar.gz`, criado com `sudo ./GA06_10B_backup_ferret.sh` após alerta da política institucional contra `sudo bash`. Resultado `BACKUP_INTEGRIDADE=PASS`, `GA06_BACKUP=PASS`, `BACKUP_PERMISSOES=600`, `DIRETORIO_PERMISSOES=700`; SHA-256 `6b91681ccd83c7f5b99c06d606d8c8783ada125d40639d634ce464233134e5c3`. `DADOS_ORIGINAIS_MODIFICADOS=NAO`, `CONTEINERES_MODIFICADOS=NAO`, `CUTOVER=NAO_EXECUTADO`. Foram incluídos config e runtime state/inbox/reports/events; cópia realizada com serviço ativo, sem prova de restauração funcional. O aviso `sudo: unable to resolve host ep126-pucpr-br` permanece pendente separado do Ferret e não bloqueou o backup. Ver documentação operacional da PR #207 para sequência de monitor/rollback e reteste.

## Redirecionamento após GA06.10B — frente GA-09 Bacula (03/11)

**Informação adicional da responsável:** suporte confirmou que o snapshot integral **pode ser restaurado**, mas ainda não forneceu o ID. A operadora prefere **avançar para outra frente** em vez de aguardar em GA06. Cutover Ferret v5 segue NÃO EXECUTADO e 2.4.3 preservada.

**Priorização fundamentada no Trello e issue #196:** GA07 auditoria PHP→Wazuh e PR #206 regras DLP já têm partes comprovadas em runtime, portanto não reaplicar. GA07 logrotate ainda depende de política de retenção, validação de UID82/Wazuh e risco de perdas de eventos. A GA09 Bacula permite avanço restrito: **revalidação de frescor dos quatro conjuntos de staging e posterior backup MANUAL controlado**, não ativar schedules (BAC-05 decisão vigente de 25/09: sem agendamento automático, risco RPO aceito). Últimos Jobs informados via Bacularis: MariaDB JobId22 em 06/10; OpenBao JobId19, Catalog JobId20 e RecoveryState JobId21 em 05/10. Essa prova histórica não garante atualidade; tentativas GA09.3/3B no PostgreSQL já foram inconclusivas e NÃO repetir. Staging `/var/lib/conectaeduca/bacula-staging` pertence a `bacula:bacula` com modo 0700; usuário não tem travessia, **não alterar ACLs/UID/GID**. A responsável possui sudo interativo confirmado e política institucional indica execução de scripts completos por `sudo ./script.sh`, não `sudo bash` ou shell privilegiado interativo. Qualquer verificação de metadados deve respeitar essa política e evitar conteúdo de dumps/segredos.

**Próximo passo pontual GA09:** script local para inspecionar só estatísticas agregadas e datas/idades de arquivos regulares nos quatro diretórios `mariadb`, `openbao`, `catalog`, `recovery-state` (sem nomes ou conteúdo) antes de permitir backup manual. Não produzir novo Job Bacula se fontes estiverem vazias/desatualizadas ou se faltarem condições de armazenamento/retenção e recuperação. Não mudar schedules, Director, Catalog, PgBouncer ou FD nessa coleta. Reconciliar a evidência com a issue #196 sem afirmar correção do histórico de reinícios.

## GA-09.11 — staging Bacula 29 dias sem renovação comprovada (03/11)

Execução de script de metadados em EP126, sem leitura de conteúdos nem execução de Jobs: `/var/lib/conectaeduca/bacula-staging/{mariadb,openbao,catalog,recovery-state}` possuem **2 arquivos regulares por conjunto**, mtime mínimo e máximo idênticos `2026-10-05T18:43:41Z`. Bytes acumulados por conjunto: MariaDB `41672`, OpenBao `35952`, Catalog `83290`, Recovery State `2946`. Idade calculada para arquivo mais recente `696h` (~29 dias). Todos os diretórios existem e têm arquivos: `CONJUNTOS_COM_PROBLEMA=0` é **somente teste estrutural, NÃO freshness validada**. Resultados históricos Bacularis indicam jobs concluídos 05–06/10; não realizar backup manual novo desses mesmos artefatos antigos para produzir falsa atualidade.

**BAC-04** em 24/09 já demonstrou geração das fontes autoritativas (MariaDB dump consistente; OpenBao Raft snapshot por AppRole; Catalog pg_dump; Recovery State allowlist), 4 Jobs Backup + 4 Restore, hashes idênticos; **não repetir prova histórica completa**. **BAC-05** (25/09) permanece execução manual com risco RPO aceito, sem schedule. Antes de novo backup manual, localizar produtor existente para atualizar fontes de staging, verificar contrato de exclusão de root tokens/unseal shares, consistência/UID/ACL, e produzir evidência de materialização atual; jamais apenas `touch` para alterar mtime. Precedência: etapa de nome/código do produtor `scripts`, revisão de execução segura e sem segredos, e só então ação pontual com rollback. Usuária é operadora delegada da VM; respeitar filtro institucional de `sudo bash` proibido, executar scripts autorizados como `sudo ./arquivo.sh` apenas após revisão. Nenhum serviço, Schedules, Jobs ou dados modificados na GA09.11.

## GA-09.12 — encontrados checkpoints BAC-04 históricos, sem produtor de refresh operacional ainda confirmado (03/11)

`git grep` em scripts na EP126 localizou `scripts/evidencias/checkpoint_bacula_mariadb_sintetico.sh`, `checkpoint_bacula_openbao_raft_final.sh`, `checkpoint_openbao_bacula_readiness.sh`, `scripts/recuperacao/recuperar_approle_bacula_snapshot.py`; lista de nomes localizou também `scripts/bootstrap/materializar_bacula_workloads_lab.py`, `scripts/evidencias/checkpoint_bacula_backup_restore_lab.sh`. **Nenhum script foi executado.** Revisão do GitHub `main` demonstra:
- `checkpoint_bacula_mariadb_sintetico.sh`, `checkpoint_bacula_openbao_raft_final.sh`, `checkpoint_bacula_backup_restore_lab.sh` usam raiz histórica `/srv/www/htdocs/conectaeduca`, volumes de bancada de teste e contêm operações Docker de mudança, restauração e limpeza; **não rodar como refresher da EP126**.
- `materializar_bacula_workloads_lab.py` altera `bacula-dir.conf` com resources do FD de bancada (`/data/workloads`), não é materializador seguro de dumps operacionais atuais.
- `recuperar_approle_bacula_snapshot.py` altera configuração OpenBao HCL, recria contêiner e executa generate-root temporário, reservado a **recuperação extraordinária**, não refresh de snapshot Bacula.
- Próxima etapa não é novo inventário Docker/PGSQL: localizar pelo nome/assinatura no checkout os scripts e runbooks de *produção* BAC-04B materialização de `/var/lib/conectaeduca/bacula-staging`. Depois revisar origem, política de segredos e método de atualização atômica antes de aplicar, sem tocar nos Job/Schedule ou serviços.

## GA-09.13–15 — produtor operacional encontrado e AST inicial (03/11)

GA09.13 descobriu arquivo instalado **fora do repo** `/usr/local/sbin/conectaeduca-bacula-materializar-staging`. Não executar checkpoints históricos BAC04 de `scripts/evidencias` como substitutos. GA09.14, análise de metadados/AST sem execução: root:root 0755, 9717 bytes, SHA-256 `b655788eefad7b4d99e8f558d5a43779caa25d34b23f490ba11e4df9bd8040ac`, script Python com 276 linhas, sintaxe PASS. Identificou referências MariaDB dump, OpenBao Raft snapshot, Catalog pg_dump, recovery-state, staging, sha256, temporários, rename, Docker, remoções, credenciais. **Presença textual não equivale a verificação de funcionalidade, revisão de segredos ou autorização de refresh**.

GA09.15, inspeção AST sem executar: funções `die`, `run`, `container_running`, `sha256_file`, `check_mode`, `stream_docker_to_file`, `openbao_snapshot`, `make_recovery_tar`, `promote`, `materialize`, `main`. Chamadas potencialmente mutáveis incluem `subprocess.run`, `target.unlink` (erro/cleanup), `os.chown/chmod/replace`, `stmp.write_text` em `promote`, `tempfile.mkdtemp` e `shutil.rmtree` em `materialize`. Única flag literal encontrada: `--check`, **não foi encontrado `--dry-run`**. `--check` AINDA NÃO EXECUTADO e NÃO comprovado como read-only. Confirmar controle de fluxo `main/check_mode` e política de promoção/rollback de **quatro artefatos** antes de executar; `os.replace` é atômico por arquivo, não entre os quatro conjuntos. Nenhuma VM/serviço alterado.

## GA-09.16–17 — revisão de fluxo e check do materializador (03/11)

A responsável forneceu saída AST do materializador `/usr/local/sbin/conectaeduca-bacula-materializar-staging` (SHA256 `b655788eefad7b4d99e8f558d5a43779caa25d34b23f490ba11e4df9bd8040ac`). `main()` decide exclusivamente entre `--check` → `check_mode()` e ramo de materialização; `check_mode()` verifica root, conta `bacula`, contêineres, credenciais com modes 0600/0400, allowlist e subdiretórios staging com owner/mode 0700. `materialize()` produz quatro dados em work temporário primeiro, só depois invoca `promote()` em sequência. `promote()` executa `shutil.copyfile` para arquivo parcial, chown/chmod 0600, `os.replace()` para dado e depois sidecar SHA; **não há rollback de conjunto dos quatro alvos**, e falha durante uma promoção pode deixar dados e hash em gerações diferentes. `finally` remove temporário. GA-09.16 somente leitura, sem alteração.

Na GA09.17 a responsável executou `sudo ./conectaeduca-bacula-materializar-staging --check` dentro de `/usr/local/sbin`. Resultado `CHECK=PASS`, `BACULA_UID=130`, `BACULA_GID=139`, `SECRET_VALUES_PRINTED=0`. Aviso `sudo: unable to resolve host ep126-pucpr-br: Temporary failure in name resolution` persiste, **não bloqueou o --check** e deve ser tratado em frente distinta, sem alteração de DNS/hosts nesse gate. Nenhuma materialização nem Job executado. Próximo GA09.18: **backup privado root 0700 e TAR 0600 dos quatro diretórios staging, inclusive sidecars** com integridade gzip/tar/SHA e sem expor conteúdo; depois considerar refresh controlado e hash por conjunto, com plano de retorno se ocorrer falha parcial.

## GA09.18–19C — 03/11/2026

Backup do staging antes da atualização validado: `GA09_BACKUP=PASS`, SHA256 `e53ea63d0e56fb76289c8563accfe76e4ce191b9dea1d28647d79a2ad22904f9`. Materializador com hash conferido e `--check=PASS` falhou ao executar refresh. GA09.19A: os oito arquivos de staging (quatro conjuntos) continuam idênticos ao backup em conteúdo e mtime; nenhum Job executado. GA09.19C: OpenBao `initialized=true`, `sealed=true`, HTTP 503; `HTTPError` na função `openbao_snapshot` linha 159. Próximo bloqueio: execução operacional de unseal por custodiantes autorizados e validação de saúde, sem recriar OpenBao nem alterar AppRole. Não repetir materializador até resolver selo.

## GA09.19E — unseal OpenBao concluído (03/11/2026)

A responsável executou o helper versionado `scripts/recuperacao/unseal_shamir_cloud.py --normal` com Share 1 local e Share 2 criptografada externa. Resultado: `SHAMIR_RECOVERY_NORMAL_2_DE_3=APROVADO`; a segunda share foi descriptografada apenas em memória, sem exposição no chat. `docker exec conectaeduca-openbao bao status` confirmou: OpenBao 2.6.1, `Initialized=true`, `Sealed=false`, Shamir `Total Shares=3`, `Threshold=2`, `Storage Type=raft`, `HA Mode=active`, `Raft Committed Index=1048`, `Raft Applied Index=1048`. `Active Since=2026-11-03T23:43:30.875862213Z`. Não ocorreu reinicialização/recriação de cofre nem geração de novas chaves. Este gate remove o bloqueio por `sealed` da GA09.19C. **Ainda não comprova** AppRole funcional, materialização nova, Jobs Bacula ou restores. Próximo passo: retomar wrapper GA09.19 preexistente (confirma hashes binário e TAR privado, --check, --materialize, valida os quatro pares); confirmar ausência de Jobs concorrentes; não executar Bacula Jobs antes de PASS dos artefatos. Se qualquer falha, STOP, evitar repetição cega, analisar sanitizadamente.

## GA09.19 — refresh staging operacional PASS (03/11/2026)

Após unseal Shamir normal bem-sucedido, a responsável executou novamente o wrapper privado GA09.19. Resultado: `MATERIALIZADOR_INTEGRIDADE=PASS`, `BACKUP_PRE_REFRESH=PASS`, `PREFLIGHT=PASS`, `MATERIALIZACAO=EXECUTADA`; MariaDB 43927 bytes PASS, OpenBao Raft 35868 bytes PASS, Catalog PostgreSQL 84073 bytes PASS e Recovery State 2858 bytes PASS. `GA09_19=PASS`, `STAGING_ATUALIZADO=SIM`, `BACKUP_ANTERIOR_PRESERVADO=SIM`, `JOBS_BACULA=AINDA_NAO_EXECUTADOS`. O wrapper validou pares artefato/sidecar por SHA-256, dono bacula e permissões 0600, e data recente. Isso **não** prova ainda backup do Bacula nem restauração; manter BAC-05 execução manual sem Schedule. Próximo gate verificar nomes efetivos dos quatro Jobs operacionais/config e ausência de Jobs concorrentes, executar um por vez e conferir terminação T + Errors=0; depois restore em destino isolado e SHA comparado às fontes (nunca sobre MariaDB/OpenBao/Catalog ativo).

## GA09.20 — Jobs operacionais confirmados no Director (03/11/2026)

A usuária executou leitura filtrada de `/etc/bacula-runtime/bacula-dir.conf` dentro de `conectaeduca-bacula-director`: `JOBS_BACKUP_ENCONTRADOS=6`, nenhuma alteração/execução. Smoke: `InternaSmokeBackup` (`InternaSmokeSet`, `InternaSmokePool`) e `DmzSmokeBackup` (`DmzSmokeSet`, `DmzSmokePool`). Jobs operacionais exatos, todos no `ConectaEducaOperationalPool`: `ConectaEducaMariaDBBackup`/`ConectaEducaMariaDBSet`, `ConectaEducaOpenBaoBackup`/`ConectaEducaOpenBaoSet`, `ConectaEducaCatalogBackup`/`ConectaEducaCatalogSet`, `ConectaEducaRecoveryStateBackup`/`ConectaEducaRecoveryStateSet`. Próxima etapa GA09.21: iniciar primeiro MariaDB via Bconsole existente, confirmar ID enfileirado e resultado terminal `T` com zero erros, então sequenciar demais um por vez. **Não registrar backup concluído apenas com `Job queued`**. Smoke Jobs preservados, nenhum Schedule ativado.
