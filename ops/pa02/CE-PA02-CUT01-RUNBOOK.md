# CE-PA02-CUT01 — GA08 dual Unix PA-05-safe, change control real

**Data:** 08/11/2026. **Responsável:** Andréa Kozicki. **EP125.** **Estado:** driver operacional preparado no GitHub, **NÃO executado na VM**. A rotina antiga `scripts/ga08-change-control.py --execute` da PR #217 **NÃO é compatível com o PHP PA-05 implantado**; continuar bloqueada.

## Situação técnica confirmada

- CE-PA05-DEP02 (08/11 17:40 BRT): PHP corrigido `conectaeduca/php-fpm:pa05-10328ab6` HEALTHY, segredos/auditoria preservados; utiliza 11º Compose `/home/andrea.kiew/.config/conectaeduca/pa05/compose.pa05-10328ab6.yml`.
- CE-PA02-RW01 (08/11 17:50 BRT): bind HTTP de socket UID101/GID101 modo0700 **RW e limpeza PASS**, Nginx HEALTHY, produção não alterada. GA08.33 havia comprovado FPM RW; não repetir baterias.
- GA08.31/32: `/run` canônico com Nginx saudável em sandbox; candidata `compose.ga08-runtimefix.candidate.yml` resolve tmpfs /var/run sobrepondo os sockets.
- Dois cutovers de 03 e 04/11 haviam sido revertidos (3/3 healthy). O snapshot de 03/11 **não inclui** o PA-05 de 08/11; não o tratar como plano de recuperação suficiente.

## Implementação versionada nesta PR

`ops/pa02/ce_pa02_cut01.py` possui três modos separados:

**`--mode prepare` (sem restart):** só aceita EP125 `andrea.kiew`, Git HEAD `04f88d27`, **11 Compose do PHP em produção**, imagem PA05 por tag + Image ID efetivo, três serviços healthy, diretórios socket host (HTTP 101:101/0700; FPM 82:82/0770) sem sockets raiz residuais. Em **uma única etapa**, baixa cinco artefatos candidatos da PR #217 pelo commit imutável `aa67a149ddcd14fdcbb28a66ea8785ac77579047`, valida Git blob, e reconstrói apenas o ambiente de interpolação de Compose com dados não secretos dos containers (host/porta, caminhos de mount; **não lê conteúdo das credenciais**). Exige que modelo Compose base (10+11º) e candidato (10+11º+3 GA08) mantenham **a MESMA imagem PHP PA05**, WAF/Nginx imagens constantes, sem upstream TCP, redes segregadas, /run canônico, bind de audit e secrets, read-only preservado. Cria diretório privado 0700 por change ID, `state.json` 0600 com imagens pré-corte e parâmetros não secretos (caminhos de secrets), e `approval.json` 0600 **com todos os seis gates false**. **Não criar nem marcar aprovações automaticamente.**

**`--mode apply --ack APLICAR_PA02_EP125` (MUDANÇA REAL):** só permite se o `approval.json` privado foi atestado pela responsável com nova **referência de snapshot pós-PA05**, `snapshot_created_at` timezone-aware **depois de 08/11/2026 17:40:01 -03:00**, evidência de restore, cobertura das mudanças PA05, recoverabilidade de TLS/secrets, janela aprovada e autorização de rollback; os booleans só podem ser `true` se fatos reais e verificáveis. Isso é **atestação documental da operadora**, não consulta direta ao hipervisor. Confere images/container IDs atuais sem drift, modelos Compose e hash dos artefatos; grava estado de início em disco; recria **sequencialmente** PHP→Nginx→WAF com `up -d --no-deps --no-build --pull never --force-recreate`. Aguarda healthy de cada contêiner na imagem original (PHP PA05 continua sendo imagem ativa). Confere Unix sockets FPM/HTTP, backend WAF Unix, bridge TCP 8080 e 9000 negados ao host EP125, e **uma única requisição** a `https://<bind WAF>:<porta>/api/public_key.php` com resposta HTTP200 (sem imprimir corpo; smoke sem validação CA estrita). Em sucesso grava `CUTOVER_HEALTHY` e `CE-PA02-CUT01_CONCLUIDO`.

**`--mode rollback --ack ROLLBACK_PA02_EP125` (MUDANÇA REAL):** usa o `state.json` privado e as referências anteriores mesmo se os contêineres falharem; recria PHP, Nginx, WAF usando **10 Compose base + 11º PA05**, **não** os dez originais sozinhos. Exige `healthy` e **Image ID** de cada baseline. O rollback é best effort; se falhar, escalar para restauração institucional, sem repetições cegas. Erros durante o cutover também acionam esta tentativa de retorno automaticamente.

**Nenhum script é executado automaticamente pelo GitHub.** A PR fica DRAFT, não altera a `main` ou o checkout das VMs.

## Proteções específicas

- Não executa `sudo`, não altera pfSense/Twingate/OpenBao/Wazuh/Ferret, nem recria contêiner diferente de PHP/Nginx/WAF.
- Não faz `docker build`, pull/prune/down, não remove segredos, não gera `.env`, não publica `docker compose config` nem env/logs; arquivos candidatos são publicados e seus Git blobs verificados. O contexto privado **deve permanecer no host enquanto os sockets estiverem ativos**, pois as configurações Nginx/FPM e o overlay do Compose são bind mounts/arquivos de controle.
- Interrompe se existir `nginx.sock`/`php-fpm.sock` residuais nos dois binds antes de cortar; nunca apaga socket à força.
- `state.json` armazena **caminhos de arquivos secretos, não valores**; por isso é 0600 e não deve ser publicado.
- O smoke de HTTPS não substitui TLS CA estrita, MFA/RBAC ou pentest. A comprovação relevante do PA-02 é a **negação de conexões TCP diretas** e o encadeamento via WAF HTTP200 após corte, ainda limitado à origem testada.
- Depois de implantar, a operação de manutenção precisa continuar usando **todos os 14 Compose** (10 originais, 11º PA05, 3 GA08) até promoção canônica; reaplicar somente 10 ou 11 pode reabrir bypass ou retornar código antigo. O script guarda o contexto como fonte operacional da sequência.

## Dependência externa bloqueadora — snapshot pós-PA05

Solicitar ao suporte **nova imagem/snapshot EP125 posterior à implantação de 08/11 17:40 BRT**, incluindo discos/volumes/binds, com ID não ambíguo, hora/fuso, operadora autorizada e procedimento de restauração que preserve:
- a imagem PHP `conectaeduca/php-fpm:pa05-10328ab6` e o 11º overlay;
- certificados, CA, segredos/ACL e log persistente de auditoria;
- os artefatos e permissões dos sockets GA08;
- a configuração funcional WAF/Nginx e acesso institucional.

**Sem essa evidência e janela aprovada, NÃO solicitar ao usuário `--mode apply` nem criar aprovações simuladas.** `--mode prepare` é uma montagem mínima de plano e não outra bateria de testes, mas também não precisa ser executada até existir uma janela concreta.

## Critério documental

- [x] Gate HTTP RW resolvido CE-PA02-RW01 08/11 17:50 BRT.
- [x] Novo driver de corte PA05-safe e rollback versionados no GitHub.
- [ ] Snapshot pós-PA05, comprovação da recuperabilidade e janela G0 real.
- [ ] Preparação privada `CE-PA02-CUT01_PREPARACAO_CONCLUIDA` na EP125.
- [ ] Cutover real `CE-PA02-CUT01_CONCLUIDO`, WAF→app HTTP200 e bypass 8080/9000 negado.
- [ ] Avaliação dos riscos residuais (operador Docker/root e egress).
- [ ] **PA-02 ainda ABERTO em runtime.** Não confundir script preparado, gate estático ou aprovação documental com isolamento aplicado.


## Nova modalidade G0 — recuperação LOCAL de serviços (08/11/2026, após RC01)

**Prova real:** CE-PA02-RC01 executado pela operadora na EP125 em 08/11/2026 18:31:46 -03:00. Saída confirma 3 imagens Docker exportadas com gzip/SHA íntegro, 11 Compose preservados, pacote privado criado em:

`/home/andrea.kiew/.local/share/conectaeduca/pa02-recovery/CE-PA02-RC01-20261108-183146`

**NÃO é snapshot**, não protege a perda total do host e não contém dados/volumes/DB/secrets, nem prova restauração. Não publicar artefatos. A estratégia supõe a integridade do host e dos binds, TLS e base de dados durante um rollback de contêiner. Uma perda de host ou corrupção de volumes permanece risco SEM COBERTURA, mesmo com recuperação local.

**Código atualizado:** `ops/pa02/ce_pa02_cut01.py` aceita agora duas modalidades *mutuamente exclusivas* de G0 no `approval.json` privado. O modelo gerado por `--mode prepare` traz `recovery_mode="unselected"` e todos os flags FALSE; nenhum modo fica aprovado automaticamente.

1. `recovery_mode="hypervisor-snapshot"`: continua exigindo `snapshot_restorable=true`, `snapshot_includes_pa05=true`, referência de snapshot nova, data após 08/11 17:40:01 BRT e evidência de retorno. Essa modalidade **não foi realizada** pela operadora.
2. `recovery_mode="local-service"`: permite prosseguir **apenas quando a responsável autorizar conscientemente o risco**. Exige `local_backup_dir` apontando ao pacote CE-PA02-RC01, `same_host_loss_risk_accepted=true`, `volumes_database_secrets_excluded_accepted=true`, `restore_not_tested_risk_accepted=true` e `secrets_current_mounts_present_accepted=true`, além de três gates gerais `operator_approved`, `rollback_approved` e `outage_window_approved`. A modalidade local **não** marca `secrets_recoverable=true`, pois o backup **não** inclui conteúdo de segredos; quem aprova deve reconhecer que o rollback depende dos mesmos mounts permanecerem acessíveis. A modalidade snapshot continua exigindo `secrets_recoverable=true`. Na conferência, o driver **recalcula SHA256 do arquivo de imagens e dos 11 Compose**, compara manifesto, data pós-PA05, IDs/refs dos três contêineres e hashes locais. Imprime explicitamente `G0_SNAPSHOT_HIPERVISOR=NAO`, `G0_VOLUME_BANCO_SEGREDOS_BACKUP=NAO`, `G0_RESTAURACAO_NAO_ENSAIADA=SIM`. **Nunca** alterar `snapshot_restorable` ou `snapshot_includes_pa05` para TRUE nessa modalidade. Isso não inventa snapshot ou substitui exigência institucional quando ela for obrigatória.

O `CE-PA02-CUT01` preserva `PA05_IMAGE=conectaeduca/php-fpm:pa05-10328ab6`, a sequência **10+11º+3 Compose** no candidato e rollback com **10+11º**. A geração do pacote RC01 **não permite automaticamente** o corte: ela oferece um segundo *modo de recuperação documentado e verificável*, sujeito a risco/autorizações reais.

**Próximo passo sem mutação:** executar apenas `--mode prepare` para criar contexto local e validar Compose/identidade/imagens; não aplicar, não simular G0 e não repetir os testes de socket já concluídos. A preparação é útil para detectar incompatibilidades dos modelos antes de uma janela aprovada. Caso a instituição exija snapshot, não usar a modalidade local como atalho de governança.

**Rollback de emergência:** script tenta restaurar imagens previamente preservadas no daemon via 11 Compose; o pacote RC01 é salvaguarda adicional para importação manual `docker image load` sob nova intervenção caso tag/imagem se percam. Ele **não faz carga automática**, não reverte banco ou conteúdo de binds. Não declarar rollback ensaiado.


## CE-PA02-CUT01 prepare — aborto PermissionError em 08/11 18:43:07 BRT

**Evidência enviada pela responsável EP125:** `SCRIPT_VALIDADO`, `CE-PA02-CUT01_ABORTADO=PermissionError`, sem os marcadores `CONTEXTO_PRIVADO=CRIADO`, `PREFLIGHT_11MAIS3=PASS` ou qualquer mutação. O driver original chamava `socket_roots()` como primeira ação do `prepare`; ali, ao consultar `(directory/sock).exists()`/`.is_symlink()` em diretórios protegidos `/var/lib/conectaeduca-ga08/http` (101:101, 0700) e `fpm` (82:82, 0770), a conta `andrea.kiew` pode receber `PermissionError`. **Causa provável fundamentada no código, ainda sem traceback sanitizado; não afirmar root cause independente.**

**Correção candidata:** `socket_roots()` passa a inspecionar somente os metadados host acessíveis do diretório e faz a prova de **ausência de socket residual** por `docker run --rm --pull never --network none --read-only`, montando **somente o diretório dedicado de socket em read-only** com o **UID/GID apropriados**, usando a imagem exata do serviço atualmente healthy (Nginx para HTTP, PHP para FPM). O sandbox testa ausência de `nginx.sock`/`php-fpm.sock` e de symlink com nomes exatos, sem imprimir caminhos privados de segredos, sem usar `sudo`, `chmod`, `docker compose up` ou apagar arquivos. Se o sandbox falhar ou detectar socket, **aborta fechado**. Nenhuma alteração nas permissões do bind.

**Estado:** script corrigido no GitHub, exige novo download com commit/blob após CI; execução real da nova preparação ainda pendente. A tentativa anterior não apresenta prova de alteração de serviços e ocorreu no gate inicial, portanto **não repetir cutover** nem alterar G0. Se o segundo preparo falhar por outro marcador, não entrar em ciclo de tentativas: avaliar resultado específico e preservar o pacote CE-PA02-RC01 de 18h31.


## CE-PA02-CUT01 prepare — aborto MOUNT_PHP_NAO_PRESERVADO em 08/11 18:49 BRT

**Evidência real EP125:** `SCRIPT_CORRIGIDO_VALIDADO`, `SOCKETS_HOST_PREPARADOS=PASS`, `CE-PA02-CUT01_ABORTADO=MOUNT_PHP_NAO_PRESERVADO`. Foi executado **somente `--mode prepare`**; não houve `--mode apply` nem recriação de serviços.

**Causa comprovada pela análise do repositório:** `assert_config()` confundia duas representações distintas do Docker Compose. A auditoria PHP é um verdadeiro volume `bind` em `services.php.volumes` (`compose.audit-persistent.yml`), enquanto senha DB, CA DB TLS e chaves privada/pública são **secrets de Compose** em `services.php.secrets` e `secrets` de nível superior, com destino em `/run/secrets`. A comparação antiga procurava `/run/secrets/conectaeduca_db_password` e `/run/secrets/conectaeduca_db_tls_ca` em `volumes`, provocando falso negativo. A leitura do Docker runtime no CE-PA05-DEP02 comprovou os mounts reais sem perder configuração.

**Patch de fail-closed:** a verificação agora exige `audit bind` presente e igual no modelo Compose base (10+11º PA05) e candidato (10+11º+3 GA08); compara **sem diferenças** as definições globais de secrets e a lista de secrets por serviço; exige quatro credenciais de PHP no modelo e as variáveis de caminhos preservadas; só acusa erro quando a propriedade de segurança realmente divergir. O workflow executa casos isolados: normalização correta aprovada, remoção de secrets negada e remoção de audit bind negada.

**Contexto parcial:** a versão anterior criava `~/.local/share/conectaeduca/pa02/PA02-20261108-LOCAL01` e baixava assets antes de falhar, porém **não gravou `state.json` ou `approval.json`** (a lógica grava ambos somente após `assert_config`). A nova versão permite reutilizar esse diretório somente se próprio do usuário, modo 0700, sem `state.json`, `approval.json` ou outros arquivos inesperados, e checa os Git blobs de todos os assets novamente. Não faz `rm`, `chmod` nos diretórios de serviço, `sudo` ou manipulação de dados. Se o contexto estiver diferente do esperado, **aborta**, exigindo análise específica.

**Situação:** script retificado no GitHub; novo `--mode prepare` ainda não executado na VM. `SOCKETS_HOST_PREPARADOS=PASS` e backups prévios RW01/RC01 continuam válidos, sem necessidade de repetição. `--mode apply` continua bloqueado até G0 real, informado e autorizado. PA-02 continua aberto em runtime.


## CE-PA02-DRY01 — ensaio nao disruptivo do plano de corte e retorno (08/11/2026)

**Pedido da responsável:** antes de aprovar G0, ensaiar rollback sem depender do suporte, preferindo alternativa que não interrompa os contêineres de produção.

O driver `ops/pa02/ce_pa02_cut01.py` recebeu um **quarto modo** `--mode dry-run --backup-dir <pacote-local-RC01>`, que não exige nem altera `approval.json`. Usa contexto `PA02-20261108-LOCAL01` **já aprovado tecnicamente em `--mode prepare`** (18:59:35 BRT); não baixar/recriar assets ou diretório, não gerar novos backups.

O `dry_run()` é estritamente **read-only**: valida os IDs dos contêineres PHP/Nginx/WAF e imagens/tag ainda ativos, PHP PA05 com 11 labels Compose; reconstitui somente metadata não secreta e caminhos dos mounts e exige igualdade com parâmetros preparados; verifica manifesto e SHA-256 do arquivo `docker-images.tar.gz` RC01 e dos 11 Compose **copiados e atuais**, conferindo refs/IDs dos três serviços e hora pós-PA05. Lê `docker compose config --format json` para os dois modelos: **retorno = 11 Compose** e **candidato = 11+3**; confirma não troca de imagens, isolamento previsto de rede/sockets, preservação de audit bind e quatro secrets. Não imprime Compose expandido, senha, dados ou logs; não toca no banco.

**Interlock por design:** nenhuma função `up`, `deploy`, `do_rollback`, `write_json`, `fetch_assets` ou `docker image load` é chamada pelo dry-run; CI inspeciona AST. Não aceita `--ack` e não aprova G0. As únicas operações Docker são consultas `ps`/`inspect` e `compose config`. Se houver drift/falta de pacote, falha fechada sem modificar a produção. Saída relevante:

```text
DRY_RUN_BASELINE_3_SERVICOS=HEALTHY
DRY_RUN_IMAGENS_BASELINE=INTEGRIDADE_PASS
G0_PACOTE_LOCAL_3_IMAGENS_11_COMPOSE=VERIFICADO
AUDITORIA_BIND=INTEGRIDADE_PASS
SECRETS_PHP=INTEGRIDADE_PASS
DRY_RUN_ROLLBACK_11_COMPOSE=PASS
DRY_RUN_CANDIDATO_14_COMPOSE=PASS
DRY_RUN_PHP_PA05_NO_RETORNO=PASS
DOCKER_COMPOSE_UP_EXECUTADO=NAO
DOCKER_IMAGE_LOAD_EXECUTADO=NAO
CONTEINERES_RECRIADOS=NAO
ROLLBACK_REAL_ENSAIADO=NAO
SNAPSHOT_HIPERVISOR=NAO
CE-PA02-DRY01_CONCLUIDO
```

**Não é rollback real**: não prova subida/sockets/saúde de contêineres restaurados, nem recuperação de dados. O termo correto é **reconciliação e simulação de configurações + verificação criptográfica dos arquivos**. Uma prova de restauração isolada exigiria ambiente/test container dedicado e planejamento para não colidir com redes e segredos de produção. A prova real de retorno em um cutover é operação disruptiva e **não deve ocorrer sem G0**.

**Estado atual:** script DRY01 versionado e CI, execução real na EP125 ainda NÃO comprovada. PA-02 continua ABERTO em runtime; aplicar só quando G0 permitir. Não repetir CE-PA02-CUT01 `--mode prepare`, RW01, RC01 ou GA08 antigos.


## CE-PA02-DRY01 PASS 19:18 e CE-PA02-ISO01 — próximo ensaio isolado (08/11/2026)

**Prova real EP125 de 19:18:37 BRT:** `SCRIPT_DRY01_VALIDADO`, `DRY_RUN_BASELINE_3_SERVICOS=HEALTHY`, `DRY_RUN_IMAGENS_BASELINE=INTEGRIDADE_PASS`, `G0_PACOTE_LOCAL_3_IMAGENS_11_COMPOSE=VERIFICADO`, `AUDITORIA_BIND=INTEGRIDADE_PASS`, `SECRETS_PHP=INTEGRIDADE_PASS`, `DRY_RUN_ROLLBACK_11_COMPOSE=PASS`, `DRY_RUN_CANDIDATO_14_COMPOSE=PASS`, `DRY_RUN_PHP_PA05_NO_RETORNO=PASS`, `CE-PA02-DRY01_CONCLUIDO`. O dry-run **não** executou `docker compose up` nem `docker image load` e não recriou serviços; `ROLLBACK_REAL_ENSAIADO=NAO`.

**Ensaio adicional seguro preparado (ISO01):** `ops/pa02/ce_pa02_iso01.py --check`. Diferente de DRY01, o script percorre o `docker-images.tar.gz` em leitura sequencial (sem extração para o host), verifica manifesto interno do formato `docker save`, presença das camadas declaradas e SHA-256 dos **arquivos de configuração das três imagens**, comparando aos Image IDs dos contêineres healthy. Depois realiza `docker run --rm` com **cada imagem já instalada**, `--network none --read-only --cap-drop ALL --security-opt no-new-privileges:true --pids-limit 32`, sem mounts e sem secrets, sob UID mínimo; executa `php -v` + `php -l` nos três arquivos PA05 e `nginx -v` nas imagens Nginx/WAF.

**Limite explícito:** ISO01 não reimporta o arquivo exportado (`docker image load`), não cria stack de teste e não comprova que a recuperação da imagem ou o rollback real funcionaria. A capacidade de executar as imagens no teste deriva das **imagens já carregadas no daemon**, enquanto a confiabilidade do arquivo exportado é verificada por estrutura, configurações e hashes. Não cobre banco/volumes/certificados, rede WAF→Nginx, tempo de retorno ou perda de VM. É uma **prova isolada de artefatos e execução mínima**, não recuperação ensaiada.

**Status ISO01:** criado no GitHub e condicionado a CI; ainda não executado na EP125. Não repetir DRY01/prepare/RC01/RW01, não executar `apply` ou `rollback` de produção.


## CE-PA02-ISO01 19:25 — divergencia no Image ID do arquivo exportado (08/11/2026)

**Saída real da operadora EP125 `andrea.kiew`:** `SCRIPT_ISO01_VALIDADO`, `ISO01_BASELINE_3_SERVICOS=HEALTHY`, `CE-PA02-ISO01_ABORTADO=ARQUIVO_TAR_IMAGE_ID_DIVERGENTE`. O script abortou **dentro de `inspect_tar_archive()`**, antes de `isolated_smoke()`; **nenhum `docker run`, `docker image load`, Compose ou cutover foi efetuado por essa execução**. DRY01 das 19:18 havia comprovado SHA-256 do arquivo comprimido e 11 Compose; não equiparar integridade externa ao sucesso de restauração interna.

**Hipótese a confirmar, sem substituir evidência:** `ISO01` exige `sha256(config JSON no tar) == ImageID reportado por docker inspect`. A implementação Docker usa modelos diferentes conforme armazenamento de imagens (legado vs containerd), versões e plataformas; essa hipótese de igualdade universal pode ser incorreta quando a ID representa manifest/index digest. Não descartar o RC01 nem afirmar corrupção por esse marcador isolado. Referência: https://docs.docker.com/engine/storage/containerd/ e https://docs.docker.com/reference/cli/docker/image/save/.

**Diagnóstico direcionado CE-PA02-ISO02:** script `ops/pa02/ce_pa02_iso02_diag.py --diagnose`, sem mutações, abre o mesmo tar.gz em modo stream somente leitura; identifica Docker image store via `docker info --format '{{json .DriverStatus}}'`, compara por serviço (PHP/Nginx/WAF) **prefixos dos IDs runtime e SHA dos configs exportados** com o hash inferível do nome do config JSON, além da quantidade de camadas declaradas. Não imprime conteúdo, nomes de tags ou paths sensíveis, não reexporta imagens e não executa sandboxes. Esperar `CE-PA02-ISO02_DIAGNOSTICO_CONCLUIDO`; se falhar ou divergir novamente, analisar as três linhas por serviço sem marcar ISO01 PASS.

**Estado de risco:** até explicar a discrepância, **não declarar backup importável/restore apto**, embora CRC/SHA externo RC01 e DRY01 tenham PASS; manter G0 não aprovado e não executar `--mode apply`. O ISO01 parcial e o diagnóstico ISO02 não são ensaio de rollback. Todos os artefatos RC01 devem permanecer intactos.


## CE-PA02-ISO02 PASS — causa do false positive do ISO01 e correção v2 (08/11/2026, 19:32:46 -03:00)

**Evidência real EP125:** `SCRIPT_ISO02_VALIDADO`, `PRODUCAO_3_SERVICOS=HEALTHY`, `ARMAZENAMENTO_IMAGENS=CONTAINERD`, `TAR_MANIFEST=3_ENTRADAS`, `CONFIG_NOME_HASH_COINCIDE=SIM` em **PHP, Nginx, WAF**, `CONFIG_SHA_VS_IMAGE_ID=DIFERENTE` nos três, `CAMADAS_DECLARADAS=24/12/28`, `BACKUP_MODIFICADO=NAO`, `CONTEINERES_CRIADOS=NAO`, `DOCKER_LOAD_SAVE_EXECUTADO=NAO`, `CE-PA02-ISO02_DIAGNOSTICO_CONCLUIDO`.

**Correção da hipótese:** em armazenamento `containerd`, o Image ID mostrado pelo Docker pode identificar o manifesto/índice OCI, em vez do digest do JSON de configuração. O validador v1 do ISO01 exigia `sha256(config.json)==ImageID(runtime)`, gerando **falso negativo nas três imagens**. O ISO02 demonstrou que cada arquivo config JSON possui nome SHA256 coerente com seu conteúdo, mas ainda não provou integridade de *cada layer* ou importabilidade do pacote. Fundamentação pública: Docker CLI image inspect (campo `Descriptor` OCI), Docker `RootFS.Layers` e documentação `docker image save`.

**ISO01 v2 corrigido:** em `ops/pa02/ce_pa02_iso01.py`, o parser do arquivo exportado mantém tag/manifest/camadas e valida **SHA256 do JSON de configuração contra o nome do próprio arquivo** (observado ISO02 `SIM`), analisa `rootfs.diff_ids` do JSON, compara **SHA256 do conteúdo de cada layer TAR** à lista de diffIDs em ordem e compara os diffIDs do arquivo ao retorno de `docker image inspect <tag> --format '{{json .RootFS.Layers}}'`. A comparação incorreta com Image ID do containerd foi removida; a identidade runtime permanece verificada separadamente por tag/ID e manifesto RC01. Sandboxes mínimos `docker run` passam a referenciar tags ativas comprovadas por `docker inspect`, em vez de supor que um digest OCI isolado seja executável diretamente.

**Testes de regressão da correção:** CI monta arquivo TAR sintético com SHA config válido e Image ID propositadamente **diferente** (simulando containerd) e exige `PASS`; depois altera conteúdo de um layer e exige rejeição `ARQUIVO_LAYER_DIFFID_DIVERGENTE`. O código v2 ainda não foi executado na EP125; os scripts ISO01 v1 e ISO02 não devem ser repetidos. Se v2 abortar, anotar marcador exato e não alterar/reatribuir hashes ou arquivos para fazê-lo passar.

**Situação operacional:** G0 continua **NÃO APROVADO** e PA02 dual Unix ainda não implantado. `RC01` e `DRY01` permanecem PASS apenas para integridade externa de artefatos/modelos. `docker image load` e um rollback efetivo continuam **não ensaiados**. Não cortar produção com base apenas no ISO01 v2.


## CE-PA02-ISO01 v2 — aborto por nome do config OCI sem sufixo e correção v3 (08/11/2026, 19:39:47 -03:00)

**Evidência EP125:** `SCRIPT_ISO01_V2_VALIDADO`, `ISO01_BASELINE_3_SERVICOS=HEALTHY`, `CE-PA02-ISO01_ABORTADO=ARQUIVO_CONFIG_NOME_SHA256_DIVERGENTE`. Esse aborto ocorre no parser do arquivo exportado **antes da tentativa de qualquer sandbox**, sem carregar nem recriar imagem, contêiner ou serviço de produção.

**Causa identificada no código, comprovada em conjunto com ISO02:** o ISO02 19:32 havia verificado `CONFIG_NOME_HASH_COINCIDE=SIM` nas três imagens pelo nome `basename.removesuffix(".json")`, mas o ISO01 v2 exigia exclusivamente `basename == digest + ".json"`. Isso rejeita objetos OCI containerd em caminhos `blobs/sha256/<64-hex>` sem sufixo, embora seu SHA-256 do conteúdo esteja correto. Não foi detectada corrupção por esse erro; **importabilidade real continua não comprovada**.

**Correção v3 do ISO01:** aceita nome de config com digest puro ou digest `+.json`, preservando igualdade com SHA-256 do arquivo. Além disso, conforme a especificação OCI, o hash do blob comprimido não é o `DiffID` da camada descomprimida: foi adicionada leitura de gzip interno em fluxo com limite de saída, comparação SHA-256 do blob com nome do caminho OCI `blobs/sha256/<hash>`, comparação SHA-256 descomprimido com `rootfs.diff_ids` da configuração e correspondência de `RootFS.Layers` com runtime. Nenhum conteúdo é extraído para o host. Referências: https://github.com/opencontainers/image-spec/blob/main/config.md (DiffID over *uncompressed* tar), https://docs.docker.com/engine/storage/containerd/.

**Regressões versionadas no CI:** fixture mista contendo (i) imagem PHP em OCI `blobs/sha256/<hash>` com camada gzip, (ii) Nginx no formato legado `<hash>.json` com layer cru e (iii) WAF com nome OCI e layer cru; todos devem PASS com ImageID OCI diferente de config SHA. Corrupção do layer Nginx deve falhar por `ARQUIVO_LAYER_DIFFID_DIVERGENTE`; corrupção de blob OCI PHP por `ARQUIVO_BLOB_OCI_SHA256_DIVERGENTE`; corrupção da configuração Nginx por `ARQUIVO_CONFIG_NOME_SHA256_DIVERGENTE`.

**Estado:** ISO01 v3 foi versionado e testado no GitHub, **ainda não foi executado na EP125**; não repetir os scripts anteriores ou exportar novo RC01. G0 continua NAO APROVADO, PA-02 runtime ABERTO, rollback real e imagem importada ainda não ensaiados. Se v3 falhar, priorizar o marcador isolado sem alterar dados ou afrouxar integridade.
