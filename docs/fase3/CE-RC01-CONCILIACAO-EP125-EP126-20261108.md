# CE-RC01 — Reconciliação factual GitHub ↔ EP125 ↔ EP126

**Data/hora das coletas (BRT):** EP125 08/11/2026 14:34:28; EP126 08/11/2026 14:36:05.  
**Responsável:** Andréa Kozicki.  
**Proveniência:** saídas de terminal fornecidas pela responsável em 08/11/2026; não são execuções remotas pela ferramenta do GitHub.  
**Escopo:** coleta read-only CE-RC01; não equivale à validação integral dos runtimes, do Zero Trust, da integridade do OpenBao, dos PAs ou à comprovação de correções implantadas.

## Baseline do repositório

`main` observado no GitHub em 08/11/2026: `b74ea581a0814d86a99b6b455d5569f12fa967e5`. Comparação GitHub do commit EP126 `4bf7ac688b1ea738cd158f03a20b07732cdd90a3` ao baseline: **27 commits à frente, zero atrás**, dez arquivos distintos. A consulta não foi um `git fetch` nas VMs.

## EP125 — DMZ

- Host `ep125-pucpr`; branch `main`, `HEAD` e cache local `origin/main` iguais a `b74ea581a0814d86a99b6b455d5569f12fa967e5`.
- `DIRTY_TRACKED_COUNT=0`; `ALTERACOES_AREAS_TOTAL=0`; **`UNTRACKED_AREAS_TOTAL=7`** nas áreas examinadas (não inclui arquivos ignorados).
- Connector **nativo** Twingate `systemd`: `loaded/active/running/enabled`; versão `1.95.0`; `NRestarts=0`.
- Docker: WAF, Nginx e PHP-FPM `Up (healthy)` na amostra.
- **Interpretação:** checkout alinhado ao baseline GitHub; ainda NÃO foi comprovado que conteúdos de imagens Docker e configurações em execução reproduzem o código Git. Sete arquivos não rastreados merecem classificação antes de qualquer limpeza.

## EP126 — Intranet

- Host `ep126-pucpr-br`; branch `main`; `HEAD` e cache local `origin/main`: `4bf7ac688b1ea738cd158f03a20b07732cdd90a3`, **27 commits atrás do baseline GitHub** (linearidade confirmada pela API).
- `DIRTY_TRACKED_COUNT=3`; `ALTERACOES_AREAS_TOTAL=1`; alteração nomeada **na área inspecionada**: `deploy/interna/wazuh/config/rules/conectaeduca_dlp_rules.xml`. Os outros dois caminhos rastreados alterados estão fora das áreas selecionadas no CE-RC01 e ainda NÃO foram classificados.
- **`UNTRACKED_AREAS_TOTAL=3`** nas áreas examinadas, sem nomes divulgados.
- Connector **nativo** Twingate `systemd`: `loaded/active/running/enabled`; versão `1.95.0`; `NRestarts=1`.
- Docker: 12 serviços listados em execução; nove com status explicitamente `healthy`; **OpenBao 2.6.1 `Up (unhealthy)`**; Bacularis e Ferret `Up` sem indicação de `healthy` nesse inventário.
- **Interpretação:** preservar alterações locais, sobretudo regra Wazuh DLP, antes de qualquer sincronização. `unhealthy` não prova por si só indisponibilidade ou causa raiz; investigar de modo read-only, sem restart/unseal ou divulgação de credenciais.

## Comparação entre commits remotos GitHub

Arquivos diferentes entre o commit da EP126 e o baseline:
- `.github/workflows/repository-static-integrity.yml`
- `.gitleaks.toml`
- `composer.lock`
- `docs/seguranca/PA03-COMPOSE-STATIC-GATE-20261026.md`
- `docs/seguranca/PA05-RBAC-NEGATIVOS-CANDIDATURAS-20261026.md`
- `scripts/evidencias/checkpoint_compose_security_invariants.py`
- `src/Security/AuditLogger.php`
- `tests/Unit/AuditLoggerRedactionTest.php`
- `tests/Unit/Security/HorizontalOwnershipContractTest.php`
- `tests/python/test_pa03_compose_inline_lists.py`

Esses são *arquivos entre commits versionados*, NÃO o inventário de diferenças em runtime, e não incluem o delta local da regra DLP.

## Próximos gates e decisões

1. **Read-only EP126:** classificar os três arquivos rastreados alterados, sem expor caminhos ou conteúdo de segredos; distinguir mudanças de código, regras Wazuh e configurações locais. Conferir `git diff --check` sem alterar arquivos.
2. **Read-only ambas:** classificar apenas diretórios/categorias dos sete + três arquivos não rastreados, sem copiar certificados, tokens, chaves, `.env` ou configurações para o GitHub.
3. **OpenBao EP126:** conferir status técnico/healthcheck limitado e o impacto funcional com operador autorizado; não realizar unseal/restart/recreate.
4. **Mudanças candidatas:** selecionar PR isolada para cada delta seguro; CI, snapshot/rollback demonstrado, testes funcionais e evidências. Não executar `git pull`, `git reset`, `git clean`, `docker compose up` ou alterar pfSense por este registro.
5. **Pentest B 08–14/11; relatório/apresentação até 17/11:** diferenciar controles implementados e retestados, testes parciais e riscos residuais.

**Status:** CE-RC01 executado nas duas VMs; reconciliação operacional **em andamento**. Nenhum commit nas VMs, nenhum deploy, nenhuma correção de PA e nenhuma homologação declarados por este documento.

## CE-RC02 — classificação factual (08/11/2026)

**Fonte:** duas saídas CE-RC02 enviadas pela responsável, coletadas nas VMs; scripts não fizeram alterações de serviço, repositório ou conteúdo.

| Item | EP125 (14:43:23 BRT) | EP126 (14:41:48 BRT) |
|---|---|---|
| Tracked modificados no repositório | 0 | 3 |
| Categoria dos tracked | — | 2 em `SCRIPTS`; 1 em `WAZUH_REGRAS` |
| Regra Wazuh DLP modificada | NÃO | SIM |
| Untracked não ignorados nas áreas | 7 | 3 |
| Categoria untracked | 7 em `EP125_DEPLOY` | 3 em `EP126_DEPLOY` |
| OpenBao Docker | Não consultado | `running`, `unhealthy`, `RestartCount=0` |

**Limite:** CE-RC02 não exibiu caminhos individuais dos arquivos não rastreados nem dos dois scripts alterados. Não há prova de que os overlays sejam seguros para publicação ou de que a configuração executada corresponda exatamente às fontes. Arquivos ignorados não foram inventariados. `OpenBao unhealthy` requer apuração independente, sem inferir indisponibilidade.

**Gate de reconciliação seguinte:** identificar exclusivamente nomes seguros de dois scripts rastreados e possíveis manifestos Compose não rastreados sem exibir segredos; preservar qualquer arquivo local de produção; comparar deltas com PRs #206/#207/#203 e então decidir eventual PR específico. Nenhum `git pull`/merge/reset/clean ou deploy foi autorizado por essas coletas.



## CE-RC03 — identificação não destrutiva de candidatos (08/11/2026)

**EP125, 14:48:13 BRT:** nenhum script rastreado modificado. Foram identificados quatro manifestos Compose entre os sete untracked na área deploy/dmz:
- `compose.audit-persistent.yml` — correspondente ao overlay de persistência PA-06 na PR #203, historicamente reportado como aplicado no runtime EP125; não remover/reaplicar sem prova;
- `compose.ga08-dual-socket.candidate.yml`, `compose.ga08-runtimefix.candidate.yml`, `compose.ga08-socket.candidate.yml` — candidatos PA-02 da PR #217, não homologados por esta coleta.

**EP126, 14:49:20 BRT:** os dois scripts tracked alterados foram identificados como `scripts/dlp/sanitizar_ferret.py` e `scripts/dlp/validar_eventos_ferret.py`. A PR #207 documenta promoção local controlada desses dois scripts com GA07.8R 6/6 PASS, mas **não** documenta cutover da imagem Ferret v5. Entre os três untracked de deploy/interna há um `compose.pa07-v5.override.yml`, associado à proposta Ferret v5 da PR #207 (não equivale a deploy). A terceira alteração tracked é a regra DLP Wazuh associada à PR #206.

**Restante desconhecido:** EP125 3 untracked não classificados individualmente; EP126 2 untracked não classificados individualmente. Não copiar esses arquivos ao GitHub.

**Próximo gate CE-RC04:** comparar apenas fingerprints Git blob de arquivos locais conhecidos com versões imutáveis nas PRs #203/#206/#207/#217, imprimindo MATCH/DIFF sem conteúdo. Nenhuma sincronização/merge/deploy autorizado por CE-RC03.

## CE-RC04 — EP126: hashes comparados com PRs (08/11/2026, 14:59:01 BRT)

**Proveniência:** saída do CE-RC04 executado pela responsável na EP126. Nenhuma modificação de Git ou runtime.

| Arquivo (identificador de verificação) | Fonte | Resultado |
|---|---|---|
| `scripts/dlp/sanitizar_ferret.py` | PR #207 | `MATCH_PR_MAIN_DIFF` |
| `scripts/dlp/validar_eventos_ferret.py` | PR #207 | `MATCH_PR_MAIN_DIFF` |
| `deploy/interna/wazuh/config/rules/conectaeduca_dlp_rules.xml` | PR #206 | `MATCH_PR_MAIN_DIFF` |
| `compose.pa07-v5.override.yml` não rastreado | PR #207 | `MATCH_PR` |

**Interpretação:** identidade byte a byte de cada arquivo local com o blob de sua PR correspondente. Os três arquivos rastreados diferem do blob `main`; são candidatos para PR específica de reconciliação. O override Ferret v5 é apenas candidato local; **a versão v5 não foi comprovada em runtime**. O último inventário registra Ferret 2.4.3 em operação. A integridade do arquivo não implica aplicação, segurança, nem aprovação de merge. **CE-RC04 EP125 ainda pendente**.


## CE-RC04 — EP125: comparação com PRs (08/11/2026, 15:00:01 BRT)

**Proveniência:** saída CE-RC04 executada pela responsável na EP125; não foi realizado deploy, mudança no Git ou alteração de runtime.

| Identificador | PR | Resultado |
|---|---|---|
| `AUDIT_PERSISTENT_PR203` | #203 | `MATCH_PR` |
| `GA08_DUAL_SOCKET_PR217` | #217 | `MATCH_PR` |
| `GA08_RUNTIMEFIX_PR217` | #217 | `MATCH_PR` |
| `GA08_SOCKET_PR217` | #217 | `MATCH_PR` |

**Interpretação:** os quatro arquivos locais da EP125 correspondem byte a byte aos blobs verificados nas PRs indicadas. Histórico da PR #203 registra `compose.audit-persistent.yml` aplicado ao runtime de auditoria da EP125, mas CE-RC04 **não testou se overlay está atualmente ativo**. Os três overlays GA-08 da PR #217 continuam **candidatos**; não alegar cutover de sockets, E2E do PA-02, nem ausência de risco residual com base apenas em `MATCH_PR`.

### Fechamento da coleta CE-RC01 a CE-RC04 — 08/11

- **EP125:** `main` alinhada à referência GitHub da data, sem modificações em arquivos rastreados; 7 untracked nas áreas, dos quais 4 manifestos identificados e 4/4 blob matches PR #203/#217. Restam 3 untracked sem classificação individual.
- **EP126:** `main` local 27 commits atrás da referência GitHub; 3 tracked modificados, todos `MATCH_PR_MAIN_DIFF` (#206/#207); 3 untracked na área, 1 override candidato Ferret v5 `MATCH_PR`, 2 não individualizados.
- **Twingate:** connectors systemd 1.95.0 ativos nas duas VMs; isso não testa políticas de autorização.
- **OpenBao:** `running` com health `unhealthy`, `RestartCount=0`; triagem funcional ainda pendente.
- **GitHub:** PR #222 criada em DRAFT com somente os 3 tracked reconciliados da EP126; CI do commit `e9950d6d3ebf85d4879560292da9a0d0da339fc4` com 4 workflows concluídos com sucesso (Repository Static Integrity, Gitleaks Secret Scanning, Semgrep SAST, PHPUnit Security Tests) e combined status Snyk success. Não equivale a E2E na EP126.
- **Nenhum merge, git pull/reset/clean, mudança de configuração, restart ou deploy nas VMs** foi realizado em CE-RC01..04.

**Próximo gate:** checar de forma não destrutiva se o overlay de auditoria integra os caminhos de Compose associados ao contêiner PHP; não inferir que os candidatos GA-08 estejam ativos; analisar de maneira separada o healthcheck OpenBao. Para PR #222, revisar testes específicos DLP/Wazuh e considerar merge somente sob change control. 

## CE-RC05 — referência dos overlays no runtime EP125 (08/11/2026, 15:07:15 BRT)

**Proveniência:** saída de terminal CE-RC05 enviada pela responsável; observação read-only do metadata de Docker do host `ep125-pucpr`.

| Contêiner | Estado | `compose.audit-persistent.yml` | Três candidatos GA-08 da PR #217 |
|---|---|---|---|
| `conectaeduca-dmz-php-1` | `running` | `REFERENCIADO` em `com.docker.compose.project.config_files` | `NAO_REFERENCIADO` |
| `conectaeduca-dmz-nginx-1` | `running` | `NAO_REFERENCIADO` | `NAO_REFERENCIADO` |
| `conectaeduca-dmz-waf-1` | `running` | `NAO_REFERENCIADO` | `NAO_REFERENCIADO` |

**Persistência:** a montagem inspecionada no PHP apresenta origem `/var/log/conectaeduca/php-audit` no destino `/var/www/conectaeduca/storage/logs`; `BIND_AUDITORIA=CONFIRMADO`.

**Juízo técnico controlado:**
- **PA-06:** há prova atual de referência ao overlay de auditoria no metadata do PHP e do bind persistente configurado, além do fingerprint `MATCH_PR` da PR #203 em CE-RC04. Registro histórico da PR #203 indica E2E de ingestão demonstrado em 23/10, mas CE-RC05 não retesta geração, coleta, classificação, rotação ou retenção. **Implementação estrutural confirmada no recorte observado; aceitação integral PA-06 não deve ser inferida.**
- **PA-02/GA-08:** os três overlays candidatos não aparecem nos metadados Compose dos três contêineres. Isso não prova que não existam mecanismos manuais equivalentes, mas **não há evidência de cutover desses candidatos no runtime examinado**. O risco residual de bypass interno do WAF/isolamento por sockets deve permanecer documentado, conforme PR #217.
- **Segurança da coleta:** `SEGREDOS_EXIBIDOS=NAO`, `RUNTIME_MODIFICADO=NAO`.

**Próximo gate recomendado:** evitar repetir um cutover GA-08 em fase de apresentação; preservar EP125 estável e correlacionar testes positivos/negativos do controle Zero Trust com a matriz PA01–PA07. Priorizar a revisão/aceite seletivo das PRs de reconciliação e diagnosticar o OpenBao na EP126 por investigação isolada.

### Reconciliação documental PA-06 — PR #223

Após CE-RC05 foi preparada a [PR #223](https://github.com/andrea-kozicki/conectaeduca/pull/223), **DRAFT**, exclusivamente com `deploy/dmz/compose.audit-persistent.yml` (blob `bfb1abca81b0a5f84e8ccda69c3c2da75294f2a1`), idêntico à PR #203 e ao arquivo identificado na EP125 por CE-RC04. GitHub confirma exatamente **um arquivo alterado** na PR #223. **Não houve deploy/merge nem alteração das VMs.** No instante da verificação os workflows de PR #223 estavam queued/in_progress e Snyk pending; não registrar sucesso antes dos resultados finais.

**Atualização CI PR #223:** verificações concluídas com SUCCESS para Supply Chain Build Gate, Gitleaks Secret Scanning, PHPUnit Security Tests, Repository Static Integrity, Semgrep SAST e Snyk, no commit `95413bc9c61cee9845ed778f67dde4d51df5b9cd`. Os gates de runtime, rotação/retenção e aprovação de merge continuam pendentes.


## CE-RC06R — OpenBao selado na EP126 (08/11/2026, 15:18:45 BRT)

**Fonte:** saída real do CE-RC06R na EP126, após tentativa CE-RC06 interrompida no prompt Bash por colagem truncada (sem prova de alteração de runtime). Coleta CE-RC06R somente leitura.

| Campo | Valor |
|---|---|
| Host | `ep126-pucpr-br` |
| OpenBao (Docker) | `STATE=running`; `RESTARTS=0` |
| Healthcheck | `HEALTH=unhealthy`; `FAILING_STREAK=5953` |
| Cinco últimos exit codes do healthcheck | `2, 2, 2, 2, 2` |
| `bao status -format=json` | `INITIALIZED=True`; `SEALED=True`; `STANDBY=INCONCLUSIVO` |

**Diagnóstico:** OpenBao inicializado porém selado. Segundo a documentação oficial, `bao status` retorna exit code 2 no estado selado; os cinco `EXIT_CODE=2` coletados são do **healthcheck Docker**, cujo comando não foi identificado neste ensaio. A associação é fortemente consistente, mas não se deve atribuir o exit code 2 do healthcheck diretamente ao `bao status` sem inspecionar sua configuração.

**Histórico de recuperação:** cartões do Trello de **22/10/2026** documentam incidente anterior de estado `sealed/unhealthy`, recuperado por procedimento preexistente de custódia **Shamir 2-de-3**, sem `init`, restart ou recriação de volumes, com estado posterior `SEALED=False` e `healthy` (EP126-F2-0039/0040/0041/0044). O incidente de outubro permanece historicamente resolvido; **08/11 é ocorrência nova**. Não há ainda prova da causa do retorno ao estado selado (por exemplo, reboot, recriação, perda de mecanismo de unseal).

**Ação segura:** verificar somente `StartedAt`, método/estado de selagem sem imprimir segredos nem comandos com tokens; confirmar custódia e autorização antes de qualquer recuperação pelo procedimento já existente. Proibido publicar partes de chave, tokens, senha, passphrase, saída de `docker inspect .Config.Env` ou logs integrais. **Não executar `bao operator init`, unseal automatizado, restart, recreate, troca de configuração ou mudança do healthcheck apenas para tornar o indicador verde.**

**Estado:** incidente aberto, causa da recorrência não determinada, recuperação de 08/11 **não realizada**.

**Rastreabilidade Trello:** nova ocorrência de selagem em 08/11 registrada no cartão P1 [OpenBao selado novamente — CE-RC06R](https://trello.com/c/WMh3tRV5). Os cartões de 22/10 permanecem concluídos como evidência de uma recuperação anterior, sem implicar continuidade do estado saudável.

## CE-RC07 — cronologia e decisão de reconciliação (08/11/2026, 15:23:23 BRT)

**Fonte:** saída real da EP126, somente leitura. Host boot: `2026-10-31 10:34:05` (hora local). OpenBao Docker `CREATED_AT=2026-09-27T20:48:41.49136586Z`, `STARTED_AT=2026-11-07T17:12:02.027079202Z` (14:12:02 BRT), `RESTARTS=0`. `bao status`: `SEAL_TYPE=shamir`, `KEY_THRESHOLD=2`, `KEY_SHARES=3`, `SEALED=True`. O start do contêiner é posterior à recuperação confirmada em 22/10 e é **consistente** com nova necessidade de unseal; não prova qual operação iniciou o contêiner em 07/11 ou se existiu outra causa. Shamir 2-de-3 confirmado sem acessar shares.

**Decisão operacional para minimizar testes:** encerrar inventários CE-RC01..07, implementar inicialmente apenas reconciliação GitHub por PRs restritas:
- **PR #223:** somente `deploy/dmz/compose.audit-persistent.yml`, blob igual ao overlay EP125; metadata runtime PHP associa overlay e bind de auditoria. Draft, merge pendente de aprovação.
- **PR #222:** somente dois scripts DLP + regra Wazuh, blobs iguais aos arquivos modificados EP126. Draft, merge pendente de aprovação.
- Ambas as PRs: `mergeable=true`, CI e Snyk concluídos com sucesso nas consultas de 08/11. **Nenhum merge foi executado nesta decisão.**
- Não utilizar `git pull` nas VMs após eventual merge sem procedimento de conciliação dos estados locais: EP125 contém overlay untracked com mesmo nome que arquivo novo rastreado; EP126 contém três arquivos tracked modificados igual aos arquivos propostos. `git pull` indiscriminado pode falhar ou causar risco de sobreposição.
- **OpenBao:** evento selado atual exige recuperação **autorizada** com runbook de custódia preexistente Shamir 2/3; nenhuma chave/token/passo sensível em GitHub/Trello; após recuperação verificar somente estado `sealed/health`, não declarar AppRole funcional sem evidência.
- **GA-08 PA-02:** não iniciar cutover de candidatos antes da apresentação sem janela e rollback aprovados.

**Gates ainda abertos:** PRs draft precisam revisão/aceite (checks genéricos verdes não significam E2E), incidentes OpenBao e risco residual PA-02, além de política de retenção de auditoria PA-06.


## Reconciliações concluídas na main — 08/11/2026

A pedido da responsável, iniciada a incorporação das alterações já identificadas nas VMs com escopo estritamente GitHub, após comprovar conteúdo dos blobs, checks CI/Snyk aprovados, inexistência de alterações fora do escopo e capacidade de merge do GitHub.

**PR #223 — PA-06 EP125 [MERGED]:** versão exata do overlay `deploy/dmz/compose.audit-persistent.yml`, PR de origem #203 e EP125, incorporada por merge commit `da29a07ca7a4a08cdaf4681067a1ff082412635c`. Método `squash` recusado pelo GitHub com HTTP 405 (“Squash merges are not allowed on this repository”); utilizou-se merge convencional. Nenhum deploy ou alteração na VM. Revisão final de retenção/rotação ainda pendente.

**PR #222 — PA-07 EP126 [MERGED]:** somente `scripts/dlp/sanitizar_ferret.py`, `scripts/dlp/validar_eventos_ferret.py` (PR #207) e `deploy/interna/wazuh/config/rules/conectaeduca_dlp_rules.xml` (PR #206), merge commit `04f88d275064a005d0ffcd4f9372a371c28c32d5`. Não inclui patch/interface Ferret v5 ou `compose.pa07-v5.override.yml`. Sem deploy nem alteração na EP126.

**Verificação posterior direta na `main` do GitHub:** os quatro arquivos possuem os quatro blobs Git esperados: audit overlay `bfb1abca81b0a5f84e8ccda69c3c2da75294f2a1`; DLP sanitizer `551accd9c2d3422b8d57428f2e21b556f1852698`; DLP validator `7b4ed11f422d4d67491f99ec5d6341f7d68958e1`; Wazuh rule `8d332c7adb8820789219c5c6e6b048eeecc178d2`.

**Situação comparativa nova:** `main` em `04f88d275064a005d0ffcd4f9372a371c28c32d5`, 6 commits à frente do `HEAD` EP125 coletado em CE-RC01 (`b74ea581...`) e 33 commits à frente da EP126 (`4bf7ac68...`) na comparação do GitHub, ambas sem divergência de ancestralidade. **As VMs continuam nos mesmos checkouts**, pois nenhuma operação Git local foi realizada após as coletas.

**Risco da atualização local:** não executar `git pull`, `reset` ou `clean` de forma indiscriminada. EP125 guarda o overlay `compose.audit-persistent.yml` como untracked e a `main` passou a rastreá-lo; EP126 guarda como modificados três tracked agora idênticos à `main`. Antes de eventual atualização na VM, planejar conciliação segura com backup, escopo conhecido e verificação de `git status` preservando os demais 3 untracked EP125 e 2 EP126 não classificados.

**Classificação do resultado:** GitHub **reconciliado para quatro arquivos comprovados**; reconciliação dos checkouts e configuração dos serviços nas VMs **não realizada**; PA-02 GA08 permanece residual; OpenBao EP126 segue selado aguardando recuperação autorizada; E2E específicos continuam pendentes. Nenhuma PR ampla #203/#206/#207/#217 foi mesclada por esta operação.

## CE-RC08 — atualização de checkouts em preparação (08/11/2026)

A responsável solicitou também a **atualização da `main` local nas VMs**, não somente o merge GitHub. Preparada [PR #224](https://github.com/andrea-kozicki/conectaeduca/pull/224), em DRAFT, com o script `ops/reconcile/ce-rc08-update-vms.py` e runbook próprio.

**Alvo Git fixo:** `04f88d275064a005d0ffcd4f9372a371c28c32d5`. EP125 deve migrar de `b74ea581...` (4 caminhos versionados diferentes) e EP126 de `4bf7ac68...` (14 caminhos diferentes), sem reimplementar serviços. O script preserva sem reescrita o overlay audit-persistent já igual ao alvo da EP125 e os dois scripts DLP + regra Wazuh da EP126. Guardas: branch, host, SHA remoto, blobs esperados, ausência de mudanças fora do escopo, colisões, backups privados, mounts Docker ativos; utiliza `git reset --mixed` apenas para HEAD/index e restaura somente os arquivos distintos restantes, nunca `--hard` ou `git clean`.

**Execução EP125/EP126 AINDA NÃO RELATADA.** Não registrar conclusão de atualização VM até receber `CE-RC08_CONCLUIDO` e `HEAD_FINAL` de cada máquina. Execução EP125 precede EP126. Não há impacto no estado da selagem OpenBao ou cutover GA08 por esta preparação.


## CE-RC08 — atualização da EP125 confirmada (08/11/2026 15:50:21 BRT)

**Proveniência:** saída do CE-RC08 fornecida pela responsável, executado como `andrea.kiew` no host EP125. Script validado pelo hash do blob Git e sintaxe antes da execução. **Houve alteração do checkout Git local**, diferentemente das coletas anteriores; nenhum deploy/serviço reiniciado pelo procedimento.

| Verificação | Resultado real |
|---|---|
| `origin` | `ORIGIN_VALIDADO=SIM` |
| `git fetch origin main` | iniciado e alvo fixo validado pelo script |
| Blobs preservados | `BLOBS_PRESERVADOS=1` (overlay `compose.audit-persistent.yml`) |
| Arquivos restaurados da nova `main` | `ARQUIVOS_A_RESTAURAR=3` |
| Montagens Docker inspecionadas | `DOCKER_BINDS_VERIFICADOS=8` |
| Intersecção com binds ativos | `ALTERACOES_COM_BIND_ATIVO=0` |
| Backup privado | `/home/andrea.kiew/.CE-RC08_BACKUP_EP125_20261108_155027`; `BACKUP_VERIFICADO=SIM` |
| `HEAD_FINAL` | `04f88d275064a005d0ffcd4f9372a371c28c32d5` |
| Working tree rastreado | `WORKTREE_TRACKED=SEM_ALTERACOES` |
| Outros untracked | `NAO_EXCLUIDOS` |
| Serviços reiniciados pelo script | `NAO` |
| Conclusão | `CE-RC08_CONCLUIDO` |

**Aceite limitado:** Git e working tree rastreado da EP125 alinhados ao commit de referência, com bytes do overlay preservados. Não implica que novos arquivos de código tenham sido aplicados a contêineres em execução nem que GA-08 tenha sido implantado. Verificação do runtime pós-atualização ainda não apresentada.

**EP126:** execução CE-RC08 **pendente** na data deste registro. Não registrar sincronização das duas VMs antes de saída da EP126.


## CE-RC08 — atualização da EP126 confirmada e conciliação bilateral (08/11/2026, 15:54:16 BRT)

**Proveniência:** saída CE-RC08 real fornecida pela responsável, execução sob usuário `andrea.kiew` no host `ep126-pucpr-br`, após a execução bem-sucedida na EP125 às 15:50. O script foi obtido de commit fixo, validado por hash Git blob e análise sintática AST antes da execução.

| Verificação | Resultado na EP126 |
|---|---|
| `ORIGIN_VALIDADO` | `SIM` |
| `GIT_FETCH_MAIN` | `INICIANDO`; o script verificou SHA fixo antes da alteração do checkout |
| `BLOBS_PRESERVADOS` | `3` — dois scripts DLP e regra Wazuh |
| `ARQUIVOS_A_RESTAURAR` | `11` |
| `DOCKER_BINDS_VERIFICADOS` | `56` |
| `ALTERACOES_COM_BIND_ATIVO` | `0` |
| `BACKUP_PRIVADO` | `/home/andrea.kiew/.CE-RC08_BACKUP_EP126_20261108_155422` |
| `BACKUP_VERIFICADO` | `SIM` |
| `HEAD_FINAL` | `04f88d275064a005d0ffcd4f9372a371c28c32d5` |
| `WORKTREE_TRACKED` | `SEM_ALTERACOES` |
| `OVERLAYS_NAO_RASTREADOS` | `NAO_EXCLUIDOS` |
| `SERVICOS_REINICIADOS` | `NAO` |
| Estado | `CE-RC08_CONCLUIDO` |

### Síntese CE-RC08 — duas VMs concluídas

| Ponto de verificação | EP125 | EP126 |
|---|---|---|
| Commit HEAD | `04f88d275064a005d0ffcd4f9372a371c28c32d5` | `04f88d275064a005d0ffcd4f9372a371c28c32d5` |
| Blobs locais preservados sem reescrita | 1 | 3 |
| Arquivos restaurados | 3 | 11 |
| Binds Docker examinados | 8 | 56 |
| Sobreposições com binds ativos | 0 | 0 |
| Backups | Privado e verificado | Privado e verificado |
| Tracked worktree | Sem alterações | Sem alterações |
| Reinicializações pelo procedimento | Nenhuma | Nenhuma |

**Conclusão factual:** os **dois checkouts locais `main`** foram efetivamente atualizados ao mesmo commit de referência, com os quatro blobs previamente conciliados preservados, após aplicação controlada com backups. A `main` do GitHub foi observada no commit `04f88d275064a005d0ffcd4f9372a371c28c32d5` na janela do procedimento. Para manter esta equivalência exata, não promover merges adicionais durante o freeze sem atualizar explicitamente o baseline; em particular, as PRs documentais/operacionais #221 e #224 devem permanecer DRAFT por ora.

**Limites:** a conclusão é do estado Git rastreado; arquivos untracked/ignored, estados Docker e integridade de serviços não são igualados por esse resultado. A comparação com binds ativos foi feita **somente** para os caminhos que o script iria reescrever. O procedimento **não** faz prova E2E das PAs; OpenBao EP126 continua selado desde CE-RC06R/07, GA-08 PA-02 permanece não homologado, e dados persistentes/segredos não foram movimentados entre VMs.

**Próxima ação recomendada:** fechar a frente de sincronização de checkouts como concluída no Trello; sem novas baterias de testes. Priorizar documentação acadêmica, evidências positivas/negativas Zero Trust e recuperação autorizada do OpenBao, apenas se necessária para a apresentação.


## Balanço PA-01 a PA-07 após reconciliação Git — 08/11/2026

**Âmbito da conclusão:** reconciliação da main/EP125/EP126 **não equivale a reteste nem homologação dos sete PAs**. Fonte cruzada: matriz da PR #218, cartões Trello por PA, issues #196/#220, PRs #203/#205/#207/#217 e execuções CE-RC01..08.

| PA | Status defensável neste recorte | Provas e lacunas |
|---|---|---|
| PA-01 — movimento lateral | **MITIGADO NO RECORTE LAN33↔LAN49; PA GLOBAL ABERTO** | CE-ZT47 de 05/11: 6/6 conexões TCP autorizadas, dois SSH/22 negados com BLOCK correlacionado nos logs do pfSense; Guacamole preservado. Default allow restante para outras redes e ZT de acesso remoto não homologado globalmente. |
| PA-02 — bypass WAF | **ABERTO, GA-08 EM HOLD** | WAF/CRS e HTTPS básicos funcionais; backend Nginx acessível internamente no baseline anterior; CE-RC05 confirma três overlays candidatos PR #217 não referenciados no runtime. Houve cutover fail-closed/rollback no passado; não repetir sem G0/snapshot/rollback/novas autorizações. |
| PA-03 — escalada host/contêiner | **PASS NA PRIMEIRA CAMPANHA EM RECORTE; RETESTE PÓS-ZT PENDENTE** | Conta teste não demonstrou escalada nos caminhos examinados; scanner Compose da main incorpora hardening estático PR #210. CI e scanner não substituem privilégios efetivos da VM após alterações. |
| PA-04 — exposição de segredos | **PASS LIMITADO NA PRIMEIRA CAMPANHA; RISCO OPERACIONAL ATUAL** | Nenhum segredo reutilizável obtido no recorte. OpenBao EP126 em 08/11 `initialized=true, sealed=true, Shamir 2/3`; contêiner iniciado 07/11; recuperar somente com procedimento/custódia existentes e autorização. AppRole e menor privilégio ainda pendentes. |
| PA-05 — login/MFA/RBAC/BOLA | **PARCIAL** | Autorização vertical 200/403 e recortes Twingate/Wazuh favoráveis; BOLA horizontal com duas contas fictícias do mesmo papel e objetos próprios não demonstrado por teste dinâmico comparável. PR #205 de login híbrido continua DRAFT, sem deploy, requer aceite de compatibilidade e regressão MFA. |
| PA-06 — auditoria/telemetria | **CORREÇÃO IMPLANTADA NO RECORTE; PA INTEGRAL PENDENTE** | Overlay `compose.audit-persistent.yml` ativo no metadata do PHP e bind persistente confirmado CE-RC05; E2E PHP→Agent001→Wazuh rule110250 histórico PASS 23/10; arquivo reconciliado por PR #223 e CE-RC08. Falta política de retenção/rotação, prova de ingestão pós-giro, minimização PII e cobertura FIM/YARA atual. Template logrotate PR #203 contém `@GA07_...@` e explicitamente PROÍBE instalação direta: não ativar cegamente. |
| PA-07 — DLP/egress/Bacula | **REMISTURAÇÃO PARCIAL IMPLANTADA; PA ABERTO** | Dois scripts de sanitização/validação e regras Wazuh PRs #206/#207 já estavam na EP126 e foram incorporados à main pela PR #222, CE-RC08 manteve blobs. Smoke GA07.8R 6/6 e Wazuh DLP histórico favorável. Interface Ferret em runtime 2.4.3 ainda pode sinalizar falso "limpo" após HTTP 403, candidato v5 PR #207 sem cutover. Egress global e Bacula schedules/restore sem aceite. |

**Priorização de ações de VM sob prazo da apresentação 17/11:**
1. **EP126 / PA-04 operacional:** recuperar selagem OpenBao exclusivamente pelo runbook de 22/10 (Shamir 2/3) com duas shares sob custódia e autorização, não publicar chaves/tokens, não executar `operator init` nem reiniciar contêiner. O estado `sealed=false/healthy` encerra incidente operacional, não todo PA-04.
2. **EP125 / PA-06:** planejar rotação/retencão em mudança mínima, com política aprovada, identidade UID/GID correta e prova Wazuh após giro. Não instalar `deploy/dmz/logrotate/php-audit.logrotate.conf.in` diretamente: é modelo deliberadamente incompleto.
3. **EP126 / PA-07:** se janela/snapshot/backup e rollback autorizados, candidato Ferret v5 da PR #207 tem canário prévio; cutover exige regressão UI fail-closed + CLI/Wazuh. Adiar se risco incompatível com prazo.
4. **PA-02:** não repetir GA-08 sem novo G0 e rollback. **PA-05:** maior retorno é prova horizontal BOLA com duas identidades/objetos fictícios, se disponíveis, antes de alterar lógica PHP. **PA-01:** interzona foi implementada no pfSense; demais lacunas dependem revisão cuidadosa e não devem ser fechadas por Twingate isoladamente.

**Não foram executadas novas alterações ou testes nas VMs nesta revisão.**

## CE-OB01 — Recuperação Shamir OpenBao EP126 (08/11)

**Proveniência:** saída de execução fornecida pela responsável, `andrea.kiew`, 08/11/2026 16:09:06 BRT, EP126. Recuperação executada com script preexistente `scripts/recuperacao/unseal_shamir_cloud.py`, hash Git de conteúdo `e238ea69f0b5de9b0307c74261fd3a537235d8c4`, procedimento de custódia já usado em 22/10; nenhum valor de share ou passphrase coletado/publicado.

| Indicador | Resultado observado |
|---|---|
| Preflight script/custódia | `VALIDACAO_PREVIA=OK` |
| Método | Share 1 local + Share 2 externa criptografada, Shamir 2/3 |
| Recuperação | `SHAMIR_RECOVERY_NORMAL_2_DE_3=APROVADO` |
| Processamento share externa | Descriptografada somente em memória (declaração do script) |
| Estado do Docker imediatamente após execução | `STATE=running HEALTH=unhealthy RESTARTS=0` |
| Estado do cofre pós-recuperação | `INITIALIZED=True SEALED=False` |
| Indicador standby do comando de conferência | `STANDBY=INCONCLUSIVO` porque o campo consultado não estava presente no JSON de `bao status` |
| Encerramento | `CE-OB01_RECUPERACAO_EXECUTADA` |

**Interpretação:** unseal concluído com êxito: o script somente imprime `SHAMIR_RECOVERY_NORMAL_2_DE_3=APROVADO` após a segunda share e depois de `wait_active()` confirmar `sealed=false` e `standby=false` na API `sys/health` (código analisado da main), portanto há forte prova operacional de cofre ativo. A saída `unhealthy` do Docker **não pode ser tratada como `healthy` antes de um novo ciclo de healthcheck**; falta confirmar se houve recuperação do indicador. Nenhum restart foi executado por este procedimento, e `RESTARTS=0` foi observado.

**Classificação:** recorrência de selagem de 08/11 **desbloqueada operacionalmente**, health Docker **pendente de confirmação curta**, AppRole/ACL/auditoria e cobertura global do PA-04 **não homologadas**. Não executar novamente unseal, operator init ou restart. O histórico do incidente resolvido de 22/10 é preservado separadamente.


## CE-OB02 — healthcheck OpenBao saudável (08/11/2026, 16:13:20 BRT)

**Proveniência:** saída CE-OB02 da EP126 fornecida pela responsável, executada por `andrea.kiew`. Verificação `docker inspect` exclusivamente leitura, realizada após recuperação Shamir CE-OB01 às 16:09.

```text
STATE=running
HEALTH=healthy
FAILING_STREAK=0
RESTARTS=0
ALTERACOES=NAO
CE-OB02_CONCLUIDO
```

**Correção temporal:** a observação `HEALTH=unhealthy` imediatamente após o unseal CE-OB01 foi transitória no intervalo constatado; a verificação subsequente CE-OB02 confirma que o Docker reconheceu o OpenBao como saudável. CE-OB01 já havia confirmado `INITIALIZED=True`, `SEALED=False`, quórum Shamir 2/3 e API `sys/health` ativa por `wait_active()`. Nenhum reinício feito pelo procedimento, nenhum segredo/token/share publicado, nenhuma mudança de configuração entre CE-OB01 e CE-OB02.

**Resultado do incidente de 08/11:** **RESOLVIDO NO RECORTE OPERACIONAL** — OpenBao inicializado/desbloqueado, processo running, Docker health healthy, failing streak 0, restart count 0. O incidente anterior de 22/10 permanece historicamente distinto.

**Limite PA-04:** restabelecimento de disponibilidade **não** comprova autorização AppRole, políticas de mínimo privilégio, integridade dos segredos, trilha de auditoria ou retestes negativos. Esses critérios permanecem abertos em cartão próprio; não classificar PA-04 integralmente solucionado.

**Próxima intervenção proposta, não executada:** avaliar PA-06 logrotate/retencão apenas com parâmetros institucionais aprovados e prova de continuidade de ingestão Wazuh; evitar substituição do template PR #203 diretamente no sistema.


## PA-06 / CE-PA06-ROT01 — implantação de retenção preparada (08/11/2026)

Foi criada a [PR #225](https://github.com/andrea-kozicki/conectaeduca/pull/225) **DRAFT** para implantação pontual de `logrotate` na **EP125**, sem modificar a `main` congelada e sem deploy Docker. Contém `ops/pa06/ce_pa06_rot01_install.sh` e `ops/pa06/CE-PA06-ROT01-RUNBOOK.md`.

**Ação operacional proposta:** instalar `/etc/logrotate.d/conectaeduca-php-audit` sob root:root 0644, com `daily`, `maxsize 16M`, `rotate 30`, `compress/delaycompress`, `su :82 :82`, `create 0600 :82 :82`; usar o agendamento normal do sistema. Configuração **provisória laboratorial**, 30 gerações não correspondem a prazo fixo de 30 dias. Evita `copytruncate`, `logrotate -f`, novos eventos sintéticos, restart de PHP/Wazuh, mudança de Compose e qualquer acesso ao conteúdo dos logs.

**Guardas implementadas:** hostname EP125; Git HEAD `04f88d275064a005d0ffcd4f9372a371c28c32d5`; usuário normal; autorização `sudo -v` sem shell root; identidade do arquivo `82:82/0600` e diretório `82:82/0700`; não sobrescrever outra política; checar duplicidade em `/etc/logrotate*`, verificar sintaxe com `logrotate -d`, conferir inode do arquivo ativo antes/depois, garantir existência de agendamento `logrotate.timer` ou cron daily.

**Estado atual:** código da PR #225 com CI/Snyk aprovada, **instalação na EP125 AINDA NÃO EXECUTADA OU COMPROVADA**. Exigir `CE-PA06-ROT01_CONCLUIDO` e `POLITICA_INSTALADA=SIM` em saída de campo para classificar política como instalada. Rotação real, ingestão Wazuh após giro, retenção institucional e minimização de PII seguem controles pendentes.


## CE-PA06-ROT01 — execução parcial e correção da comparação sudo (08/11/2026, 16:23 BRT)

**Evidência da operadora na EP125:** `SCRIPT_VALIDADO`; `PERMISSOES_AUDITORIA=82:82_0600_DIR_0700`; `AGENDA_LOGROTATE=SYSTEMD_TIMER`; `REGRA_DUPLICADA=NAO`; `CONFIGURACAO_SINTAXE=PASS`. Na etapa seguinte, mecanismo institucional reportou *"Comando 'sudo -s' detectado, uso não permitido! Incidente reportado ao administrador"*, seguido de `CE-PA06-ROT01_ABORTADO=INSTALACAO_DIVERGENTE`.

**Causa provável:** o script continha `sudo cmp -s` em dois pontos, que pode ter sido interpretado pelo filtro do ambiente como invocação de shell `sudo -s`. A responsável não executou esse comando explicitamente. A sequência do script executa `sudo install` antes do `sudo cmp -s`; assim, **o arquivo pode já ter sido instalado em disco**, apesar do abort. Não repetir a versão original nem executar outros comandos sudo neste momento.

**Correção GitHub isolada:** PR #225 atualizada para comparar sem sudo (`cmp -s` legível em arquivo root:root 0644), validando também identidade/mode; runbook atualizado. **Status de instalação INCONCLUSIVO** até conferência somente leitura, sem sudo: owner/mode esperado `0:0:644` e SHA256 de política `f0d9fe60ca866f9bee435665e67b7705dcb302bcf1daa18ce71928b0959e5e2d` em `/etc/logrotate.d/conectaeduca-php-audit`.

**Nenhuma rotação forçada/restart foi solicitada ou relatada.** Manter distinção entre regra instalada, rotação automática executada e ingestão Wazuh pós-giro.


## CE-PA06-ROT02 — política de rotação instalada e íntegra (08/11/2026, 16:27:53 BRT)

**Proveniência:** saída real fornecida pela responsável na EP125, usuário `andrea.kiew`. A conferência CE-PA06-ROT02 foi realizada **sem sudo e sem alteração do sistema** após o erro de compatibilidade de filtro sudo na rotina original CE-PA06-ROT01.

```text
POLITICA_INSTALADA=SIM
INTEGRIDADE=PASS
PERMISSOES=PASS
SUDO_UTILIZADO=NAO
CE-PA06-ROT02_CONCLUIDO
```

A verificação recebeu a política `/etc/logrotate.d/conectaeduca-php-audit` como **arquivo regular e legível**, com identidade **`0:0:644` (root:root, 0644)** e hash SHA-256 **`f0d9fe60ca866f9bee435665e67b7705dcb302bcf1daa18ce71928b0959e5e2d`** do conteúdo aprovado. Na execução anterior, o parser dry-run `logrotate -d` passou, a política duplicada não existia, o agendamento `SYSTEMD_TIMER` estava presente e o log ativo era UID/GID 82:82 modo 0600 em diretório 0700. **O arquivo de configuração foi instalado pela operação de `sudo install` na primeira tentativa, apesar do aborto posterior provocado pelo uso de `sudo cmp -s`**. Não executar instalador novamente; o script na PR #225 foi corrigido para não utilizar `sudo cmp -s`.

**Aceite específico PA-06:** `logrotate` instalado e íntegro, configuração de agendamento presente. Política laboratorial: `daily`, `maxsize 16M`, `rotate 30`, `compress`, `delaycompress`, `su :82 :82`, `create 0600 :82 :82`. A instalação não executou `logrotate -f` e **não comprova primeiro giro real** ou ingestão Wazuh após troca de inode. Retenção institucional e minimização PII no Manager continuam pendentes. O **PA-06 não está globalmente fechado**.

**Próxima frente recomendada:** PA-07 falha de resultado limpo na interface Ferret 2.4.3 (candidato v5 já testado em canário na PR #207). Implantação em produção deve seguir janela com snapshot/rollback e teste dirigido de erro HTTP; não mesclar PR #207 ampla indiscriminadamente nem reimplantar scripts DLP/Wazuh já sincronizados.


## PA-07 / CE-GA06-CUT01 — corte Ferret v5 preparado (08/11/2026)

Diante do pedido da responsável para **implementar remediações nas VMs com mínimo de testes**, foi criada [PR #226](https://github.com/andrea-kozicki/conectaeduca/pull/226) **DRAFT**, derivada do freeze `04f88d275064a005d0ffcd4f9372a371c28c32d5`, contendo `ops/pa07/ce_ga06_cut01.sh`, runbook e workflow de validação sintática.

**Escopo:** somente **Ferret UI/Web EP126** e health monitor; não interferir no DLP/Wazuh já reconciliado, CLI ainda sujeita à seleção da imagem, egress, Bacula, Twingate, OpenBao ou pfSense. Preexistem candidata local `2.4.3+ce.pa07.v5` (`sha256:535ec9ef...`), TAR SHA `5786c56...`, override Git `decf0a...`, preflight GA06.6 PASS e backup GA06.10B PASS de 03/11 (restauração não ensaiada).

**Execução prevista** somente com `sudo ./ce_ga06_cut01.sh --apply` na EP126 pela operadora; usa `bash -n` e blob verificado no download, guardas de host/usuário/head, imagem/base/preflight, health baseline; cria backup root 0700/0600 de config/state/inbox/reports/events com SHA e integridade antes de qualquer cutover. Pausa timer só durante troca, roda `docker compose up -d --no-deps --pull never ferret` com override, exige `/health healthy version=2.4.3+ce.pa07.v5`, instala drop-in exclusivo de versão para serviço systemd, reativa timer e exige health. Se houver falha após cutover, aciona **rollback best effort** à imagem 2.4.3 e monitor original. Não usa Docker load/pull/down/prune, não publica dados brutos nem reconstrói imagens.

**Risco residual importante:** snapshot institucional EP126 foi informado, mas ID e recuperação não comprovados no conjunto de evidências; backup local novo não substitui snapshot restaurável. O rollback automático é uma tentativa documentada, não garantia de recuperação. O patch UI v5 só estará operacional após saída real `CE-GA06-CUT01_CONCLUIDO` da EP126; nenhum corte executado por esta PR. O único teste de defeito posterior necessário é HTTP403 fictício que deve permanecer `INCONCLUSIVE` e impedir exportação (sem nova bateria de pentest).


## CE-GA06-CUT01 — Ferret v5 efetivamente implantado EP126 (08/11/2026, 16:43:56 BRT)

**Proveniência:** saída real da operadora `andrea.kiew`, EP126, execução do script operacional da PR #226 via `sudo ./ce_ga06_cut01.sh --apply`. Script obtido de commit imutável e hash de blob Git verificado; `SCRIPT_VALIDADO` emitido. A entrada `root` em `whoami` **é esperada** por execução pontual via `sudo ./script`; a operação não iniciou shell interativo de root.

```text
PREFLIGHT=PASS
BACKUP_NOVO_VERIFICADO=SIM
BACKUP_DIRETORIO=/var/backups/GA06-CUT01-EP126-RRLgwphD
FERRET_V5_HEALTH=PASS
MONITOR_V5=PASS
TIMER_ATIVO=SIM
PA07_FERRET_V5_IMPLANTADO=SIM
CLI_DLP=NAO_MODIFICADA_NESTE_CORTE
ROLLBACK_BASELINE=PREPARADO_NAO_ENSAIADO
CE-GA06-CUT01_CONCLUIDO
```

**Aceite estrito:** imagem candidata Ferret v5, `version=2.4.3+ce.pa07.v5`, foi aplicada ao contêiner WEB da EP126 via Compose candidato e retornou health apropriado; monitor dedicado foi atualizado e timer retomado. O script verificou container `Image ID` igual ao artefato aprovado. Backup novo de configuração, `state`, `inbox`, `reports` e `events` foi gerado e teve integridade gzip/TAR/SHA verificada, armazenado em pasta privada local (não publicar conteúdo). Nenhum `docker load/pull/down/prune` ou alteração de Wazuh, pfSense, Git ou OpenBao pelo procedimento.

**Limites importantes:**
- **PA-07-DLP-01: remediação de interface IMPLANTADA, mas regressão do sintoma original HTTP403→estado `INCONCLUSIVE` persistente, exportação bloqueada, ainda NÃO demonstrada em produção pós-corte.** Um único teste dirigido em navegador com dado sintético é suficiente; evitar novas baterias gerais.
- CLI DLP **não foi alterada** e pode continuar selecionando imagem oficial 2.4.3. Não declarar migração integral UI+CLI.
- Rollback para imagem original e monitor original está **preparado porém não ensaiado**; não afirmar recuperação verificada. Snapshot hipervisor ID/restaurabilidade ausentes do conjunto documental.
- **Possível drift futuro:** chamadas subsequentes do Docker Compose **sem** `-f compose.pa07-v5.override.yml` podem recriar o Ferret com imagem original. Preservar o override opt-in e não executar bootstrap de base sem análise de imagem/monitor. Agendar correção específica de persistência da seleção v5 para os fluxos de manutenção e CLI, sem mexer em volumes.

**Status do PA-07 global:** PARCIAL (interface Web v5 em runtime, DLP/Wazuh já reconciliados, mas CLI, egress e Bacula sem aceite integral). O cutover não altera o congelamento Git `04f88d27` em EP125/EP126.
