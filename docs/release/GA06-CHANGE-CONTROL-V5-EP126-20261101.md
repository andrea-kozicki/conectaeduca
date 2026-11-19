# GA-06 / PR #207 — Change control de implantacao controlada Ferret v5 na EP126

**Data-base:** 01/11/2026, BRT.  
**Estado:** PR DRAFT; **PLANO APENAS, NENHUM DEPLOY AUTORIZADO OU REALIZADO NESTE REGISTRO**.  
**Objetivo:** corrigir o comportamento fail-closed da interface Ferret PA-07 mantendo baseline 2.4.3 reversivel, pipeline CLI e monitoramento coerentes.  

## 1. Evidencia de prontidao que NAO sera repetida

| Gate | Comprovacao / limite |
| --- | --- |
| GA06.1, 16:53 | EP126 Docker: Ferret 2.4.3 operacional; candidata alias `localhost/conectaeduca/ferret-scan:2.4.3-pa07-v5-candidate` disponivel localmente. |
| GA06.2, 16:57 | Image ID candidata `sha256:535ec9efb590dbaaeca41123321d773ba6d26d338686d89605492380ae9e187d`; USER 1000:1000; linux/amd64; 7 camadas. Baseline `sha256:7a1b36050ae20a74632ac05b5c34e4aeb26b69836ca6703e10c1392b724b270f` preservado. |
| GA06.3, 16:59 | Blob Git do override PR #207 `decf0a8b5d5b18b6122b4afcc12a17e5ee5627f2` conferido; Compose candidato PASS; somente `image` e `pull_policy: never` diferem do original. Sem checkout PR #207 na EP126. |
| GA06.4, 17:03 | Monitor `conectaeduca-ferret-healthcheck.service` carregado, executa script Ferret; timer ativo; nenhum drop-in/envfile; script espera versao 2.4.3; imagem original local e Compose original valido. |
| Evidencia de 25/10 | Smoke no openSUSE e canario temporario EP126 v5 PASS com dados ficticios; **nao representa homologacao da imagem como servico principal**. |
| CI PR #207 | Seis workflows PASS apos commit `807055f`; CI nao valida runtime institucional nem autoriza deploy. |

**Diagnosticos encerrados:** nao refazer inventario geral de Docker, imagens, UID, Compose ou Wazuh.  
**Gates NAO satisfeitos:** autorizacao institucional explicita, custodia/verificacao atual do TAR original na EP126, snapshot/copia de estado e retorno testado, mudanca do monitor, cutover, UI/CLI/SIEM pos-cutover.

## 2. Diferenca do monitor e arquivo candidato

A v5 retorna `/health version=2.4.3+ce.pa07.v5`. O script `scripts/observabilidade/verificar_ferret_health.sh` compara exatamente `FERRET_EXPECTED_VERSION`, cujo default e `2.4.3`.

Template versionado **apenas na branch da PR #207**, NAO no systemd:
`deploy/interna/ferret/pa07-v5/90-ga06-ferret-v5-healthcheck.conf`

```ini
[Service]
Environment="FERRET_EXPECTED_VERSION=2.4.3+ce.pa07.v5"
```

Destino condicionado a aprovacao: `/etc/systemd/system/conectaeduca-ferret-healthcheck.service.d/90-ga06-ferret-v5.conf`. Instalar **somente o drop-in dedicado**, sem editar a unit original nem usar `systemctl revert` generico. Preservar a configuracao anterior em backup de custodia. O timer deve ficar pausado **apenas na janela de transicao autorizada** e ser reativado assim que o health e a versao forem validados; registrar eventual intervalo de observabilidade.

## 3. Condicoes obrigatorias para autorizar APPLY

1. Professor/suporte e responsavel pelo projeto aprovam por escrito host EP126, excecao de TAR offline, janela, operador, tempo de indisponibilidade, preservacao de dados e criterios de retorno.
2. Confirmar o TAR original sob guarda aprovada, SHA-256 `5786c56b47d7bb93604126e30cfbfb4fc549f5b1f791262fbe591555ead785a2`, manifesto e identidade da imagem realmente importada (config TAR `1fab3fc1c35e4e33210cfd306364dc3ce672d16cd33f0505d51214647e6033ce`, descriptor Docker `535ec9ef...`). **Hashes representam objetos diferentes; alias local nao e digest imutavel de registry.** Se TAR nao estiver no host, a imagem presente nao substitui o gate de custodia; solicitar operador/artefato autorizado, sem `docker load` automatico.
3. Efetuar preflight existente `scripts/evidencias/ga06_preflight_tar_local.sh --archive CAMINHO_PRIVADO` com material do PR #207 previamente revisado; exigir PASS e verificar procedencia do script. NAO imprimir `docker image inspect` bruto, variaveis de ambiente, tokens nem segredo.
4. Registrar baseline 2.4.3 e snapshot/copia de seguranca dos mounts persistentes `.runtime/state`, `inbox`, `reports` e arquivos de configuracao necessarios **somente em custodia institucional**, nunca em Git/Trello/chat. Validar destino e capacidade; distinguir recuperacao de dados de simples retorno de imagem.
5. Aprovar o local do override e seu blob Git `decf0a...`; compor com base `deploy/interna/ferret/compose.yml`, sem escrever sobre o Compose base. Nenhuma imagem adicional/volume/porta/rede/privilegio pode divergir.
6. Confirmar como os scripts CLI Bash/Fish receberao `FERRET_COMPOSE_OVERRIDE`, ou documentar explicitamente que permanecem no baseline e **NAO** declarar integracao v5 completa. Validar temporarios, sanitizacao JSONL e regra Wazuh sem dados reais.
7. Definir rollback acionavel, operador responsavel e criterios de corte: indisponibilidade ou versao health inesperada, permutacao de mounts/UID/ACL, erro CLI, regressao UI ou evento nao sanitizado.

## 4. Sequencia do cutover — SOMENTE DURANTE JANELA APROVADA

A equipe autorizada deve transformar o roteiro abaixo em procedimento de campo validado, com caminhos absolutos revisados. **Nao executar comandos desta secao durante mera leitura ou antes das aprovacoes acima.**

A. Capturar hashes, Compose e estado de monitor anteriores, snapshot/custodia aprovada e confirmacao do operador. Pausar brevemente o timer de saude **na janela registrada**; manter evidencias e anotacao da lacuna.

B. Conferir novamente o TAR contra manifesto e image store; o candidato ja esta na EP126, portanto **nao recompilar, nao puxar e nao executar `docker load` sem necessidade**.

C. Com `BASE` definido como Compose original e `OVERRIDE` como arquivo versionado validado, executar sob operador:
```bash
docker compose --project-directory /opt/conectaeduca/deploy/interna/ferret \
  -f "$BASE" -f "$OVERRIDE" config --quiet

docker compose --project-directory /opt/conectaeduca/deploy/interna/ferret \
  -f "$BASE" -f "$OVERRIDE" up -d --no-deps --pull never ferret
```
**Observacao:** esse `up` recria o servico Ferret; constitui alteracao de producao, ainda NAO executada.

D. Ler somente `GET /health` loopback, exigir `healthy` e versao `2.4.3+ce.pa07.v5`. Instalar entao o drop-in dedicado `90-ga06-ferret-v5.conf`, `systemctl daemon-reload`, validar a unit e reativar timer; acionar uma execucao supervisionada do healthcheck e registrar resultado. Se nao for possivel instalar/configurar o drop-in, abortar e retornar ao baseline.

E. Confirmar UID 1000 efetivo, `tmpfs` 0700 e escrita real do scanner ficticio, RootFS read-only, capabilities, mounts **sem expor origens e segredos**, bind loopback `127.0.0.1:18082`, limites de CPU/memoria e persistencia de suppressions. Ausencia de Docker HEALTHCHECK nao invalida o endpoint/monitor externo.

F. Retestes dirigidos e artificiais:
- Browser UI: um scan sintético 200 com 0 achados, um HTTP 403 simulado e um erro 500/timeout; `INCONCLUSIVE` permanece visivel **apos pelo menos 15 segundos**, exportacao desabilitada; repetir duas varreduras. Nao confundir 0 achados com analise completa quando coberturas nao provadas.
- CLI: arquivo inocuo; fluxo `inbox -> reports/raw -> sanitizador -> events/dlp.jsonl`; nenhum dado bruto, token ou PII no SIEM.
- Manager Wazuh: executar casos sintéticos e confirmar classificacoes/regras carregadas de fato. Compatibilidade com PR #206 precisa de autorizacao e teste separados; um PASS da #207 nao implica que regras da #206 estejam em producao.
- Validar que monitor, logica de retencao e demais servicos EP126 permanecem funcionais.

G. Registrar `Job/Run ID`, timestamp BRT, resultado, hash de evidencias sanitizadas, operador e aceite. **So considerar GA-06 remediado apos deploy + reteste positivo/negativo + rollback disponivel**.

## 5. Retorno (rollback) — condicionado, nao testado

Acionar ao primeiro erro de gate critico, sem apaga de dados:
1. Pausar timer temporariamente na janela; registrar falha, manter imagens e volumes.
2. Executar pelo operador `docker compose --project-directory /opt/conectaeduca/deploy/interna/ferret -f "$BASE" up -d --no-deps --pull never ferret` **sem** override v5; isso restaura a referencia digest do baseline. Nao executar `down`, `prune`, `rm -v`, nem reescrever `.runtime`.
3. Retirar **somente** `90-ga06-ferret-v5.conf` se tiver sido criado nesta mudanca; `systemctl daemon-reload`, reativar monitor e confirmar que espera `2.4.3`.
4. Verificar `/health` `healthy/version=2.4.3`, CLI sintético, timer, mounts e Wazuh. Se volumes/dados mudaram, escalar restauracao seletiva com custodiante — **nao fazer restore cego**.
5. Registrar tempo e causa do rollback e preservar hash de artefatos de evidencia.

**ROLLBACK_TESTADO=NAO** no GA06.4. Imagem original local e Compose valido sao pre-requisitos, nao comprovacao de reversao real.

## 6. Estado final em 01/11/2026

```text
GA06_1_IMAGE_LOCAL=PASS
GA06_2_IDENTITY=PASS
GA06_3_COMPOSE_STATIC=PASS
GA06_4_MONITOR_AND_BASELINE_READONLY=PASS
GA06_V5_ACTIVE=NO
GA06_ORIGINAL_IMAGE_AVAILABLE=YES
GA06_MONITOR_DROPIN_INSTALLED=NO
GA06_TAR_CUSTODY_ON_EP126=NOT_VERIFIED
GA06_INSTITUTIONAL_APPROVAL=NOT_CONFIRMED
GA06_ROLLBACK_EXECUTED=NO
GA06_PA07_CLOSED=NO
```

**Proximo passo util:** obter aceite de change control para esta janela. Nao repetir preflights gerais; durante a janela autorizada realizar verificacao de TAR/snapshot pontual, cutover, monitor, testes sinteticos e, se necessario, rollback.


## 7. GA-06.5 — verificacao de custodia TAR de 01/11/2026

Evidencia enviada pela operadora, EP126 `ep126-pucpr-br`, 17:13:33 BRT:

- TAR localizado em `/home/andrea.kiew/Downloads/ferret-pa07-v5-candidate-docker-archive.tar`;
- tamanho de 15.661.568 bytes;
- SHA-256 `5786c56b47d7bb93604126e30cfbfb4fc549f5b1f791262fbe591555ead785a2` **PASS** contra manifesto aprovado;
- `CUSTODIA_SHA256=PASS`, `DOCKER_LOAD=NAO_EXECUTADO`, `DOCKER_COMPOSE_UP=NAO_EXECUTADO`, sem restart/permissoes alteradas.

**Limite:** hash confere os bytes do archive, mas ainda e necessario executar o gate de proveniencia interna do TAR e relacao com imagem Docker e observar autorizacao de mudanca/backup institucional. A imagem candidata e o baseline ja existem no Docker local: nao reconstruir, baixar nem `docker load` novamente.

**Proxima acao de campo, sem mais inventarios gerais:** conferir os prerequisitos institucionais de `sudo -n` para alteracao da unit/timer e evidencia de backup de estado persistente, obter aceite da janela e so entao iniciar cutover da secao 4. Se qualquer gate falhar, nao executar `compose up`; voltar a correcoes offline e registrar bloqueio.

## 8. Atualização GA-06.6–GA-06.8 — 03/11/2026, autoridade operacional e mounts

**Divisão de responsabilidades confirmada pela responsável:** a operadora do ConectaEduca administra e aplica as mudanças Docker/serviços nas EP125/EP126 dentro de sua delegação. O **suporte institucional provê os snapshots/restaurações do hipervisor e atua em escopo institucional externo às VMs**, e não é executor obrigatório do cutover Ferret. Onde este runbook menciona `suporte/professor` como aprovador de *toda* mudança no Docker, leia-se: aprovação e janela sob controle da responsável técnica, respeitadas eventuais políticas institucionais específicas **se conhecidas** (p.ex., instalação via TAR), e evidência do suporte apenas para proteção/restauração do snapshot. **Não marcar a exceção TAR como formalmente aprovada por terceiros sem evidência**, mas não transformar o fato de o suporte não atuar nas VMs em bloqueio burocrático fictício.

**GA06.6:** após integrar seis arquivos do commit da PR #207 `1c7b8e12524f07cea400e83a35775dc49755807b` — incluindo o manifesto `GA06_CANDIDATE_PROVENANCE.json` — o script `ga06_preflight_tar_local.sh` retornou `GA06_PREFLIGHT=PASS`, com TAR/config SHA-256, descriptor/rootfs Docker, proveniência e Compose apenas `image + pull_policy` PASS. `CUTOVER=NAO_EXECUTADO`.

**GA06.7:** Compose baseline `PASS`; Ferret 2.4.3 `RUNNING=true`; imagem original preservada por digest e ID; timer health `active`; drop-in v5 `AUSENTE`. A verificação direta sem privilégio dos subdiretórios `.runtime` retornou `NAO_LOCALIZADO`, mas isso foi **reclassificado** depois do diagnóstico GA06.8 abaixo.

**GA06.8:** `docker inspect .Mounts` identifica `bind` com fontes exatamente iguais aos caminhos esperados pelo Compose do Ferret, para `config/ferret.yaml`, `.runtime/state`, `.runtime/inbox`, `.runtime/reports`. A origem de configuração é `ARQUIVO`; os três diretórios protegidos retornam `PERMISSAO_NEGADA` para o usuário e **não ausência comprovada**. `.runtime` raiz é diretório; `.runtime/events` também retorna `PERMISSAO_NEGADA`; este último pertence ao pipeline DLP/Wazuh e não integra os bind mounts do Ferret. **Não relaxar ACLs, não recriar diretórios e não presumir perda de dados**.

**Próximo gate dirigido, sem inventário geral:** sob a própria conta da operadora, confirmar acesso não interativo `sudo -n`, existência e tipo dos caminhos protegidos com `stat` via privilégio autorizado e montagem/volume subjacente via `findmnt`. Preservar backup/snapshot dos diretórios sensíveis sob custódia, sem copiar material para o Git/chat; registrar ID de snapshot e caminho de restauração. Preparar e testar reversibilidade do drop-in do health monitor e rollback Docker antes do `compose up`. Não repetir proveniência/Compose GA06.6 por rotina; não declarar remediação PA-07 antes dos testes pós-cutover UI/CLI/Wazuh.

## 9. GA-06.10B — backup isolado concluído na EP126 (03/11)

A responsável executou **com sucesso** o script `GA06_10B_backup_ferret.sh` por meio de `sudo ./GA06_10B_backup_ferret.sh`, conforme a política do host, sem `sudo bash`/shell root interativo. O procedimento bloqueou previamente o uso do diretório compartilhado `/var/backups/conectaeduca` porque sua ACL não correspondeu à política estrita do script, **não** porque tenha sido demonstrada insegurança nesse diretório. O novo backup foi criado em diretório exclusivo `/var/backups/GA06-EP126-.../` `0700 root`, contendo `ferret-precutover.tar.gz` `0600 root`.

Evidência fornecida:

```text
HOST=VALIDADO
PRIVILEGIOS=VALIDADOS
ORIGENS=VALIDADAS
DESTINO_PRIVADO=CRIADO
BACKUP_INTEGRIDADE=PASS
BACKUP_SHA256=6b91681ccd83c7f5b99c06d606d8c8783ada125d40639d634ce464233134e5c3
BACKUP_PERMISSOES=600
DIRETORIO_PERMISSOES=700
GA06_BACKUP=PASS
CONTEINERES_MODIFICADOS=NAO
DADOS_ORIGINAIS_MODIFICADOS=NAO
CUTOVER=NAO_EXECUTADO
```

Inclui `config/ferret.yaml`, `.runtime/state`, `.runtime/inbox`, `.runtime/reports`, `.runtime/events`, com `tar --acls --xattrs --numeric-owner`; `gzip -t` e `tar -tzf` PASS. **Cuidado:** validação estrutural de TAR sem ensaio de restore não prova recuperabilidade funcional; cópia feita com o serviço ativo não assegura consistência transacional entre todos os arquivos. Não publicar conteúdo de backup, logs de tar ou segredos. Não modificar ACLs de outros backups.

**Status após GA06.10B:** GATE imagem/Compose/proveniência PASS, baseline 2.4.3 preservado, backup isolado PASS, timer ainda ativo e drop-in v5 ainda não instalado, cutover não efetuado. Avançar para plano operacional do monitor + rollback com pausa mínima do timer na janela; identificar snapshot EP126 integral (ID, data, confirmação de recuperação do suporte), sem delegar o cutover Docker ao suporte. Não marcar PA-07 fechado antecipadamente. Analisar migração do scanner CLI `FERRET_COMPOSE_OVERRIDE` separadamente, para evitar serviço v5 coexistindo silenciosamente com scanner CLI v2.4.3.

