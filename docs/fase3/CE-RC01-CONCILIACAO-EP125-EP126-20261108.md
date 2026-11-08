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


## CE-GA06-ALIGN01 — CLI e bootstrap v5 preparados na PR #227 — 08/11/2026

**Solicitação da responsável:** implementar as correções dos PAs sem repetir baterias extensas. Após CE-GA06-CUT01 (Ferret Web v5 implantado), preparou-se [PR #227](https://github.com/andrea-kozicki/conectaeduca/pull/227), **DRAFT** e **ainda não executada na EP126**, para alinhar lançadores CLI Bash/Fish e bootstrap ao override v5.

**Governança de supply chain:** tentativa inicial em branch de trocar a imagem do `deploy/interna/ferret/compose.yml` principal para uma tag local falhou em `Supply Chain Build Gate` (ausência de digest de registry). **Esse diff foi revertido na mesma branch antes de qualquer comando na VM** e o Compose original voltou ao blob `9f4e17461d2179607343780fed922153050f1e86`. Não enfraquecer o gate. A solução final aplica o override v5 exato `decf0a8b5d5b18b6122b4afcc12a17e5ee5627f2` apenas pelos launchers do projeto.

**Artefato operacional:** `ops/pa07/ce_ga06_align01.py` (blob Git `d37c709376bc59cf6e35b69acd5cddf4e1747363`), HEAD da PR `2063ea7c53f028f8f52fba72c7d5bfb04448271a`. Execução prevista: usuário normal `andrea.kiew` na EP126, sem sudo, `--apply`, valida host, HEAD Git 04f88d27, imagem v5 realmente ativa por Docker Image ID, Compose-base intocado, override e drop-in do monitor v5 intactos, faz backup privado de três scripts e os substitui atomicamente com hashes verificados a partir de commit remoto imutável. Não executa Docker up/run, scans, reinicializações, pull nem alteração de dados.

**Blobs finais para instalação controlada:** Bash `d980a038243876ad853b374d0e9895bc19e9e77e`, Fish `ef71366206ae9ee655a89fffb2a2299fd898204d`, bootstrap Fish `b3535947424a143e27a3cec6009cec4ee2538b6a`. Se o monitor v5 estiver instalado, os scripts selecionam automaticamente o override com hash aprovado; bootstrap usa TAR de custódia já validado em GA06.5/6. **O Compose principal não é alterado**. Outros comandos Docker Compose feitos manualmente só com a base continuam risco residual.

**CI final PR #227:** GitHub Actions `PA07 Ferret launcher alignment syntax`, `Repository Static Integrity`, `PHPUnit Security Tests`, `Semgrep SAST`, `Gitleaks Secret Scanning` — **5/5 SUCCESS**, e Snyk success. CI não prova execução na EP126.

**Evidência pendente:** saída real `CE-GA06-ALIGN01_CONCLUIDO`. Se a instalação for aprovada, os três scripts rastreados da EP126 ficarão **intencionalmente modificados** sob HEAD `04f88d27`, exigindo conciliação futura e bloqueando novos fast-forwards cegos. Continuar distinguindo `CLI_BASH_FISH=ALINHADOS` (seleção de configuração) de execução efetiva de scanner v5 e do defeito UI HTTP 403 (ainda aguardam provas pontuais; PA-07 global não fechado).


## CE-GA06-ALIGN01 — executado na EP126 em 08/11/2026 17:05 BRT

**Fonte da evidência:** saída do terminal da responsável `andrea.kiew`, data `2026-11-08T17:05:38-03:00` (backup gerado às 17:05:39). Procedimento `ops/pa07/ce_ga06_align01.py` da [PR #227](https://github.com/andrea-kozicki/conectaeduca/pull/227), aplicado **sem sudo**.

```text
RUNTIME_WEB_V5=CONFIRMADO
BACKUP_SCRIPTS=VERIFICADO
BACKUP_PRIVADO=/home/andrea.kiew/.CE-GA06_ALIGN01_BACKUP_20261108_170539
SCRIPTS_ATUALIZADOS=3
OVERRIDE_ATIVO_POR_MONITOR_V5=SIM
CLI_BASH_FISH=ALINHADOS
BOOTSTRAP_FISH=ALINHADO
COMPOSE_BASE_ALTERADO=NAO
WORKTREE_TRACKED=MODIFICACOES_CONTROLADAS_NA_EP126
DADOS_DLP_ALTERADOS=NAO
CONTÊINER_RECRIADO=NAO
SERVICOS_REINICIADOS=NAO
CE-GA06-ALIGN01_CONCLUIDO
```

**Estado comprovado:** alinhamento dos 3 launchers (processamento CLI Bash, processamento CLI Fish e bootstrap Fish) ao override Ferret v5 **IMPLEMENTADO na EP126**; seleção automática condicionada à presença do drop-in de monitor v5 e à integridade do overlay. A imagem Web candidata v5 continuava ativa na guarda da instalação. O Compose-base permanece imagem oficial 2.4.3 pinada por digest, preservando gate supply chain. Backup de scripts íntegro em pasta privada. Nenhuma alteração de inbox/dados DLP, reconstrução de contêiner, reinicialização ou ação privilegiada nessa etapa.

**Limites e ressalvas:**
- A saída comprova promoção/configuração dos launchers **mas não processamento real de arquivo via CLI**; ainda não demonstra HTTP403 sintético→`INCONCLUSIVE` persistente e exportação impedida. Aceite PA-07 **PARCIAL**.
- Comandos manuais Docker Compose que ignoram o override v5 ainda podem recriar a 2.4.3. O risco foi mitigado **nos três launchers**, não globalmente.
- A EP126 mantém 3 arquivos tracked **intencionalmente modificados** sob HEAD `04f88d275064a005d0ffcd4f9372a371c28c32d5`; não repetir CE-RC08, `git restore`, `reset --hard` ou merge automático. PR #227 permanece **DRAFT**, sem merge na `main`. EP125 permanece intocada.
- Backup da versão do contêiner de 16:43 armazenado separadamente em `/var/backups/GA06-CUT01-EP126-RRLgwphD`, rollback ainda **não ensaiado**. Backup de scripts deste CE-GA06-ALIGN01 **não** substitui cópia dos dados.
- Não repetir inventários gerais ou pentest. Priorizar correções de maior impacto no próximo PA, com evidência mínima dirigida.


## PA-04 / CE-PA04-ACL01 — controle de acesso OpenBao preparado — 08/11/2026

Após recuperação OpenBao `CE-OB01/CE-OB02` (unsealed, running/healthy, restart count 0), foi criada [PR #228](https://github.com/andrea-kozicki/conectaeduca/pull/228) **DRAFT**, derivada de `main@04f88d27`, para implementar KV v2 isolado e AppRole de **menor privilégio** na **EP126**, sem reinicialização, scan de pentest nem exposição de credenciais.

**Artefato:** `ops/pa04/ce_pa04_acl01.py` (Git blob `923d264313c103da14e2ae3ca9c989c1a00c3414`, branch `fix/pa04-openbao-approle-least-privilege-20261108`), com runbook e workflow sintático. Usa apenas API local `127.0.0.1:18200/v1/`; operador digita token com `getpass` sem registrá-lo em CLI, env, arquivos ou repositório. **Não utilizar shares Shamir como token.**

**Recursos previstos:** mount KVv2 `ce-app/`, auth `ce-approle/`, política `ce-app-runtime-read-v1` somente `read` sobre o caminho exato `ce-app/data/runtime/app`, role `ce-app-runtime-read` com SecretID obrigatório (1 uso, TTL 10 min), token sem política default (TTL 15 min, máximo 1h), sem outras permissões ou segredos criados. Nenhum SecretID ou RoleID é coletado/exibido. Não dá acesso inter-VM nem integra a aplicação: listener OpenBao continua somente HTTP local; acesso da aplicação EP125 exige TLS e custódia/fluxo autenticado próprios.

**Guardas:** usuário normal `andrea.kiew`, hostname `ep126-pucpr-br`, Git HEAD `04f88d27` (sem apagar modificações tracked PA-07), saúde OpenBao, consultas prévias de mount/auth/policy/role com nomes exatos e recusa de colisões; consulta `sys/capabilities-self` **antes da primeira gravação** para exigir capacidade adequada e `sudo` da API OpenBao quando aplicável. Não há operação `sudo` do Linux. Os recursos existentes com identidade divergente não são sobrescritos; mount preexistente sem política gerenciada é rejeitado.

**ESTADO:** preparado no GitHub, **nenhuma execução de CE-PA04-ACL01 na EP126 demonstrada**. Para fechar controle de provisionamento, exigir saída `CE-PA04-ACL01_CONCLUIDO` sem tokens. **Não fechar PA-04 globalmente**: falta vincular app a segredo real, credenciais administradas, acesso positivo/negativo e Wazuh para stdout auditável.


## PA-05 — hardening de candidaturas e UPDATE por empresa preparado (08/11)

**Código e escopo:** PR [#229](https://github.com/andrea-kozicki/conectaeduca/pull/229) DRAFT, branch `fix/pa05-ownership-publication-20261108`, base `main@04f88d275064a005d0ffcd4f9372a371c28c32d5`. O patch está no GitHub, mas **ainda não entrou na imagem PHP que roda na EP125**.

**Gap 1 — publicação:** `InscricaoRepository::criar` inseria candidatura diretamente por `oportunidade_id` fornecido, sem verificar `oportunidades.status`. A listagem pública ocultava oportunidades não publicadas, mas isso não protegia o endpoint de criação. A PR #229 usa `INSERT ... SELECT` condicionado por `o.status = :status_publicada` na mesma operação, gerando resposta JSON genérica HTTP 404 em caso de oportunidade não disponível. Nenhum vazamento de status de rascunho por mensagem. **Achado de revisão de código, não exploração HTTP demonstrada**.

**Gap 2 — propriedade horizontal:** `InscricaoService::atualizarStatusPorEmpresaOuAdmin` autorizava via `buscarPorIdEEmpresa`, porém gravava por `UPDATE inscricoes WHERE id=:id` sem repetir o vínculo, sujeito a janela TOCTOU. A nova rotina `atualizarStatusComObservacaoAutorizado` executa `UPDATE inscricoes INNER JOIN oportunidades` com `o.empresa_id=:empresa_id` para empresa e `i.status <> cancelada_pelo_usuario` no mesmo SQL, preservando escopo global de admin; retorno falso bloqueia auditoria de sucesso. O método antigo continua para compatibilidade de outros chamadores. Operação idempotente com rowcount=0 pode gerar negativa genérica: conservador/fail-closed.

**Política de negócio mantida:** segundo retificação da responsável em 26/10, **qualquer perfil autenticado pode candidatar-se**. Não foi acrescentado `requireRole('usuario')` e as duas contas fictícias de mesmo papel podem ser usadas apenas na prova dirigida futura, sem novos fixtures. RBAC vertical anterior já foi comprovado e não será reexecutado.

**CI #229:** GitHub Actions `PHPUnit Security Tests`, `Semgrep SAST`, `Gitleaks Secret Scanning`, `Repository Static Integrity` **4/4 SUCCESS** na última revisão; novo arquivo `tests/Unit/Security/Pa05OwnershipPublicationContractTest.php` contém 4 asserts estruturais pontuais (sem base, sem VM). Os testes não provam runtime.

**Próximo passo operacional indispensável:** EP125 PHP usa `COPY src/` no Dockerfile (`deploy/dmz/php/Dockerfile`), portanto não há correção ativa somente pela PR ou cópia no checkout. Antes do cutover, capturar **uma vez** o Compose efetivo, labels do container `php`, imagem em execução, montagens relevantes e projeto; a EP125 já teve GA-08 fail-closed por variável ausente. Construir imagem candidata versionada sem sobrescrever baseline, aplicar com **todos os overlays/env efetivos**, rollback seguro; um caso de candidatura fictícia não publicada 404 e um controle positivo bastam, sem repetir toda a bateria S05. Nenhuma alteração operacional de EP125 feita por esta PR. Preservar mudanças Git intencionais EP126 PA-07 e estado OpenBao healthy.


## CE-PA05-DEP01 / CE-PA05-DEP02 — baseline EP125 confirmado e cutover preparado (08/11/2026, 17:30 BRT)

**Saída real CE-PA05-DEP01 na EP125:** usuário `andrea.kiew`, GIT HEAD `04f88d275064a005d0ffcd4f9372a371c28c32d5`; Compose projeto `conectaeduca-dmz` e working dir `/opt/conectaeduca/deploy/dmz`. Exatamente dez Compose files nos labels do contêiner PHP (ordem): `compose.yml`, `compose.database.yml`, `compose.app-secrets.yml`, `compose.waf.yml`, `compose.waf-tls.yml`, `compose.waf-policy.yml`, `compose.host.yml`, `compose.vm.yml`, `compose.database-tls.yml`, `compose.audit-persistent.yml`. Imagem operacional: `conectaeduca/php-fpm:dmz`, ID `sha256:3c8b6fe0c9905ddfe13c5b5b5fc408726bdff89290a1a99a74abb912d9a609f4`. Montagens em `/run/secrets/conectaeduca_db_password`, `...db_tls_ca`, `...private_key`, `...public_key`, e `/var/www/conectaeduca/storage/logs`. A leitura foi só metadados, `CE-PA05-DEP01_CONCLUIDO`, `ALTERACOES=NAO`. Não há bind de `src/`: patch deve entrar em nova **imagem**.

**Código PA-05 na [PR #229](https://github.com/andrea-kozicki/conectaeduca/pull/229):** (1) `INSERT ... SELECT` condiciona inserção ao estado `publicada`, 404 genérico caso contrário; (2) `UPDATE inscricoes JOIN oportunidades` revalida `empresa_id` e nega candidatura cancelada dentro do próprio UPDATE. A regra correta de negócio **permite candidatura por qualquer papel autenticado**. Sem refazer RBAC S05-DYN14.

**Ferramenta operacional CE-PA05-DEP02:** `ops/pa05/ce_pa05_dep02.py` da mesma PR e runbook `ops/pa05/CE-PA05-DEP02-RUNBOOK.md`. Usar como `andrea.kiew`, **sem sudo**, obtido por commit imutável/blob verificado, `--apply`. Guardas de hostname, GIT HEAD, 10 labels Compose, Image ID baseline, health de PHP/Nginx/WAF, checksum dos 3 arquivos PHP atuais versus main, origem remota aprovada dos 3 patches. Reconstrói parâmetros Compose **exclusivamente** a partir de metadados de `docker inspect` (valores não impressos, tokens não lidos), incluindo paths de secrets, bind ports, DB_HOST/APP_URL e grupos. Aborta **antes do corte** se o modelo ativo divergir, evitando o problema de `GA-08 FAIL_CLOSED`.

**Build:** camada local nova `conectaeduca/php-fpm:pa05-10328ab6` com `FROM conectaeduca/php-fpm:dmz` **verificada pelo ID acima**, copia só 3 fontes alterados; usa `docker build --pull=false --network=none`, verifica PHP `-l` desses arquivos sem rede nem segredos. Nenhum rebuild de Nginx/WAF/Composer e nenhuma alteração da tag baseline. Configuração de runtime candidata é um 11º overlay privado e persistente em `$HOME/.config/conectaeduca/pa05/compose.pa05-10328ab6.yml`, testado em `docker compose config` para só mudar imagem/build/pull_policy do PHP.

**Cutover condicionado ao sucesso integral do preflight:** `docker compose up -d --no-deps --no-build --pull never --force-recreate php` com os 11 overlays; health do novo PHP e invariância de montagens (auditoria+secrets), rootfs read-only, cap drop, grupo e IDs de Nginx/WAF. Em falha, tentativa de rollback com dez overlays e tag/ID originais; **rollback ainda não ensaiado**. Se instalado, as manutenções futuras do PHP deverão incluir o 11º overlay para não regressar silenciosamente à imagem antiga.

**Evidência:** CI final PR #229, `PHPUnit Security Tests`, `Repository Static Integrity`, `PA05 EP125 deploy syntax`, `Gitleaks Secret Scanning`, `Semgrep SAST` **5/5 SUCCESS**, Snyk success. **A EXECUÇÃO DO CE-PA05-DEP02 NA VM AINDA NÃO FOI REPORTADA**; não classificar deploy, HTTP 404 real ou PA-05 PASS até saída operacional. Não publicar logs de build/config completos nem valores das variáveis. A EP126 permanece com 3 lançadores Ferret v5 modificados controladamente.


## CE-PA05-DEP02 — corte real PHP corrigido na EP125 — 08/11/2026, 17:40:01 -03:00

**Fonte:** saída real do terminal EP125 encaminhada pela operadora `andrea.kiew`, execução `ops/pa05/ce_pa05_dep02.py --apply` após download de commit imutável `88581f8efb58b25cc8bb4788743c5276ac61824f`, verificação `git hash-object` do blob `7d84529076608587370323425701f41bd3f947cc` e AST Python (`SCRIPT_VALIDADO`).

```text
RUNTIME_BASELINE=CONFIRMADO
COMPOSE_ATIVO=10_ARQUIVOS
COMPOSE_E_SECRETS=RECONCILIADOS_SEM_EXPOSICAO
PATCH_3_ARQUIVOS=HASHES_CONFIRMADOS
BUILD_CANDIDATA=INICIANDO
IMAGEM_CANDIDATA=CRIADA
PHP_SINTAXE=PASS
COMPOSE_CANDIDATA=PASS
SERVICOS_AFETADOS=APENAS_PHP
OVERLAY_PERSISTENTE=/home/andrea.kiew/.config/conectaeduca/pa05/compose.pa05-10328ab6.yml
DEPLOY_PHP_PA05=CONFIRMADO
PHP_HEALTH=HEALTHY
AUDIT_BIND_E_SECRETS=PRESERVADOS
WAF_NGINX_RECRIADOS=NAO
ROLLBACK_BASELINE=PREPARADO_NAO_ENSAIADO
GIT_TRACKED=NAO_MODIFICADO
RETTESTE_BOLA=AINDA_NAO_EXECUTADO
CE-PA05-DEP02_CONCLUIDO
```

**Referência operacional:** o caminho literal informado pela EP125 é `/home/andrea.kiew/.config/conectaeduca/pa05/compose.pa05-10328ab6.yml`; esse caminho é a referência operacional autorizada. O instalador executou: reconciliação dos 10 arquivos Compose e de caminhos de segredos sem divulgar valores; validação dos três hashes de patch; nova imagem derivada `conectaeduca/php-fpm:pa05-10328ab6` construída e lint PHP PASS; 11º overlay persistente somente para selecionar a imagem candidata; cutover **somente do contêiner PHP**. `PHP_HEALTH=HEALTHY`, bind persistente de auditoria e secrets preservados, contêineres WAF e Nginx **não recriados**. Nenhum arquivo rastreado do checkout EP125 foi modificado. Tag/ID de imagem base preservados para rollback, **rollback não exercitado**.

**Aceite limitado:** **PA-05 — duas remediações SQL em runtime na EP125 IMPLANTADAS** (INSERÇÃO somente para oportunidade publicada e UPDATE empresarial revalidando proprietário/status na própria gravação). Não equivale a comprovação HTTP/BD de caso BOLA horizontal ou resposta 404, nem a encerramento global do PA-05. Não repetir bateria RBAC vertical. A próxima prova, somente quando apropriada, pode ser um ensaio mínimo com dados fictícios: 404 para oportunidade não publicada, candidatura publicada positiva, negativa cruzada entre duas contas do mesmo papel.

**Proteção contra regressão:** enquanto a imagem patchada permanecer em uso, toda nova operação Compose do PHP deve incluir o 11º arquivo `/home/andrea.kiew/.config/conectaeduca/pa05/compose.pa05-10328ab6.yml`. `docker compose up` somente com dez arquivos ou uma reconciliação Git mal coordenada pode restaurar a imagem anterior. A `main` permanece congelada no commit `04f88d27`, PR #229 DRAFT. A EP126 mantém os 3 launchers Ferret v5 intencionalmente modificados; não resetar.


## CE-PA02-RW01 — pré-condição final de escrita HTTP e preservação do PA-05 (08/11/2026)

Após `CE-PA05-DEP02_CONCLUIDO` às 17:40 BRT, PA-05 passa a ter **PHP em imagem filha** `conectaeduca/php-fpm:pa05-10328ab6` e **11º override persistente obrigatório** `/home/andrea.kiew/.config/conectaeduca/pa05/compose.pa05-10328ab6.yml`. O antigo driver GA08/PR #217 conserva pressupostos de 10 arquivos e imagem de baseline anterior para o PHP. Portanto, **não o executar nem realizar reconciliação/rollback antigos**, sob risco de desfazer o hardening de candidaturas/propriedade e a auditoria persistente.

Histórico GA08 consolidado: dois cutovers em 03 e 04/11 interrompidos (PHP ou Nginx unhealthy), seguidos de rollback 3/3 healthy e HTTPS 3x200; GA08.31/32 validaram a correção de sobreposição de tmpfs `/run` canônico no Nginx e candidatos dual Unix socket em sandbox; GA08.33 comprovou escrita real no bind FPM, mas a escrita HTTP ficou inconclusiva por possível corrida de leitura instantânea após inicialização de container `-d`. Repetir GA08.32/33 seria redundante e não atende ao pedido de implantações diretas.

Criada [PR #230](https://github.com/andrea-kozicki/conectaeduca/pull/230) **DRAFT**, branch `fix/pa02-ga08-preserve-pa05-http-write-20261108`, com `ops/pa02/ce_pa02_rw01.py` (Git blob `6b92a0e38d1d849eadc2c5547c7f4b5711616575`) e runbook. O script usa um **único contêiner Nginx descartável e síncrono**, UID101/GID101, rootfs RO, sem rede, sem segredos, sem Compose: cria e remove diretório aleatório dentro do bind HTTP host `/var/lib/conectaeduca-ga08/http`, sem tocar no socket de produção. Se confirmar `BIND_HTTP_RW=PASS` e `BIND_HTTP_LIMPEZA=PASS`, resolve apenas esta pendência operacional, **não** atesta isolamento em produção.

**Mudança efetiva PA-02 ainda NÃO executada.** Um novo cutover precisará de novo driver com 10 arquivos base + 11º overlay PA-05 + 3 candidatos de sockets incluindo runtimefix `/run`, snapshot/rollback atualizados após o PHP PA-05 (snapshot institucional antigo 03/11 não o preserva) e único smoke positivo WAF + negativo TCP bypass. Não reutilizar G0/approve antigo e não reiniciar serviços enquanto essa base não for preservada.


## CE-PA02-RW01 — confirmação final RW e limpeza do socket HTTP — 08/11/2026, 17:50:12 -03:00

**Proveniência:** saída efetiva EP125 entregue pela operadora `andrea.kiew` para o script operacional da [PR #230](https://github.com/andrea-kozicki/conectaeduca/pull/230) (`ops/pa02/ce_pa02_rw01.py`, Git blob `6b92a0e38d1d849eadc2c5547c7f4b5711616575`), validado antes da execução.

```text
SCRIPT_VALIDADO
BIND_HTTP_PERMISSOES=PASS
NGINX_BASELINE=HEALTHY
BIND_HTTP_RW=PASS
BIND_HTTP_LIMPEZA=PASS
CONTEINER_CANARIO=DESCARTADO
NGINX_PRODUCAO_ALTERADO=NAO
PHP_PA05_ALTERADO=NAO
DOCKER_COMPOSE_EXECUTADO=NAO
CE-PA02-RW01_CONCLUIDO
```

**Aceite:** o bind host HTTP preparado para o socket Unix permite criar/remover diretório único **sob UID101 do Nginx** e a operação não afetou a produção. A falha inconclusiva da GA08.33 no recorte HTTP RW está resolvida; nenhum novo canário ou bateria prévia requerida.

**Estado PA-02:** **o isolamento dual Unix ainda NÃO foi aplicado em runtime**. Preparar driver de corte novo, com **dez overlays base + 11º overlay PHP PA-05 + três overlays candidatos GA08** e rollback que preserve `conectaeduca/php-fpm:pa05-10328ab6`, TLS, auditoria e secrets. O antigo `ga08-change-control.py --execute` da PR #217 não reconhece a imagem atual e **permanece bloqueado**. Snapshot institucional datado de 03/11 antecede PA-05 e não substitui recuperação coerente com o estado de 08/11. Só após novo G0 aprovado, snapshot/rollback factíveis e implantação real usar rótulo `PA02_MITIGACAO_IMPLANTADA`.


## CE-PA02-CUT01 — driver de corte GA08 preservando PHP PA-05, somente GitHub — 08/11/2026

Após CE-PA02-RW01 PASS (17:50 BRT), criada e revisada a versão PA05-safe do driver de implantação dual Unix socket na [PR #230](https://github.com/andrea-kozicki/conectaeduca/pull/230) (DRAFT), **sem execução de novo cutover na EP125**.

**Entregas versionadas:** `ops/pa02/ce_pa02_cut01.py`, runbook `ops/pa02/CE-PA02-CUT01-RUNBOOK.md` e validação estática CI. Script em três modos: `prepare` cria contexto privado (sem reiniciar), confere baseline PHP PA05 **11 arquivos Compose** mais candidatos GA08 e valida hashes Git blob do commit congelado da PR #217; `apply` só após aprovação real de snapshot restaurável **posterior ao PA-05 de 08/11 às 17:40:01 BRT** e janela de manutenção; `rollback` usa plano persistente para recriar PHP/Nginx/WAF **com o 11º overlay PA05**. O procedimento v2 se distingue do script GA08 antigo (PR #217) que poderia regredir o PHP para a imagem vulnerável de 03/11.

O modelo candidato é 10 Compose base + 11º overlay PA05 + três GA08 (socket, dual socket, runtimefix `/run`); verifica manutenção da mesma imagem PHP PA05, paths audit/secrets, ausência de upstream TCP, redes segregadas, hashes das configs de Nginx/FPM, owner/mode dos bind sockets e ausência de sockets residuais. O cutover ainda não executado pretende recriar apenas PHP→Nginx→WAF e verificar health/Image ID, sockets Unix, acesso único WAF→app HTTP200 em `/api/public_key.php` e negação TCP direto Nginx8080/PHP9000; não comprova CA estrita/MFA/RBAC. Erros pós-mutação acionam rollback best-effort para estado de 08/11, não ensaiado nesta versão.

**G0 PENDENTE (BLOQUEADOR EXTERNO):** snapshot institucional `ubuntu.33` de 03/11 é anterior à implantação PA05 e não deve ser declarado restauração válida da configuração de 08/11. É necessária nova referência verificável após 17:40:01 BRT, abrangendo imagem Docker PA05, overlay privado e mounts dos segredos/TLS/auditoria, com recuperação/suporte e autorização de janela. O `approval.json` começa com **seis flags false** e nunca deve ser marcado como aprovado sem evidência; o código verifica declarações da operadora, não a API do hipervisor. Não executar `--mode apply` nem usar a PR217 antiga. **Estado PA02: controle de dependências e código de implantação preparado; correção em runtime AINDA ABERTA**.

**CI da PR #230:** workflow PA02 static, PHPUnit, Gitleaks, Repository Static Integrity e Semgrep **5/5 SUCCESS**; Snyk success. Os checks comprovam integridade e sintaxe do código, **não** snapshot, retorno ou a implantação. Não iniciar nova bateria de testes da EP125 até haver necessidade de prova pós-corte.


## CE-PA02-RC01 — alternativa local ao backup de imagens Docker sem suporte (08/11/2026)

Diante da indisponibilidade de snapshot institucional novo na EP125, foi acrescentado na **PR #230** (DRAFT) o `ops/pa02/ce_pa02_rc01.py` (Git blob `d9d8b62de25bd6667853cbb53a05bc549412912f`) e `ops/pa02/CE-PA02-RC01-RUNBOOK.md`, para **capturar autonomamente** um ponto de retorno limitado a **imagens Docker + 11 Compose**, sem alterar serviços.

**Escopo exato:** guardar as imagens efetivas de PHP (com PA05), Nginx e WAF por `docker image save` em gzip, arquivos Compose base (10) e overlay privado PA05 (11º), manifest de refs/IDs e **caminhos** dos binds, hashes e CRC verificados. Não copiar valores de secrets nem conteúdo dos volumes/banco/audit.log. Pasta privada 0700, arquivos 0600, tamanho livre estimado antes da gravação; nenhum `docker compose`, sudo, restart ou build. **Ainda não executado na EP125**; saída `CE-PA02-RC01_CONCLUIDO` pendente.

**Limites:** pacote local não equivale a snapshot hipervisor nem plano de recuperação de perda de VM/disco, dados persistentes, banco MariaDB ou credenciais; restauração de imagens não demonstrada. Se backup ficar no mesmo host, uma falha do próprio host pode destruí-lo. Pode permitir estudar uma janela de corte autocustodiada com rollback local de serviços, desde que o risco residual seja explicitamente autorizado e **não se simulem campos de snapshot** no G0 do `CE-PA02-CUT01`. O driver de corte ainda exige G0 snapshot real e está **bloqueado**; não executar `--mode apply` nem driver GA08 antigo. A evidência RW01 PASS 17:50 permanece suficiente para diretório HTTP; não repetir.


## CE-PA02-RC01 — pacote local gerado e modalidade de G0 local-service preparada (08/11/2026 18:31 BRT)

**Prova real EP125:** `SCRIPT_VALIDADO`, `RUNTIME_3_SERVICOS=HEALTHY`, `PHP_PA05_E_11_COMPOSE=CONFIRMADOS`, `AUDITORIA_BIND=PRESENTE`, `ESPACO_PARA_EXPORTAR=PASS`, `BACKUP_11_COMPOSE=PASS`, `IMAGENS_EXPORTADAS=3_SERVICOS`, `ARQUIVO_COMPACTADO_INTEGRIDADE=PASS`, `MANIFEST_INTEGRIDADE=PASS`, `CE-PA02-RC01_CONCLUIDO`. Backup privado `/home/andrea.kiew/.local/share/conectaeduca/pa02-recovery/CE-PA02-RC01-20261108-183146`. Contêineres não reiniciados nem modificados.

**Escopo estrito:** três imagens Docker PHP PA05/Nginx/WAF + 11 arquivos Compose e manifesto; não contém conteúdo de banco/volumes/binds/segredos; não é snapshot e não prova restore. O pacote está no mesmo host da produção. Pode subsidiar rollback local das imagens e configuração em falhas restritas ao cutover, mas não recupera perda da VM ou corrupção da base. Não enviar pacote/manifesto ao chat nem GitHub.

**Evolução PR #230:** o novo driver `ops/pa02/ce_pa02_cut01.py` recebeu modalidade de aprovação **`local-service` separada de `hypervisor-snapshot`**, usando pacote RC01 pós-PA05 e validação local do SHA256 de imagem compactada, SHA256 de 11 Compose atual/salvo, identificadores Docker e data. Flags de aceitação explícita cobrem (a) falha/perda do próprio host, (b) não inclusão de DB/volumes/segredos e (c) restauração não ensaiada; `secrets_current_mounts_present_accepted` reconhece dependência dos mounts atuais. Nenhuma dessas flags é aprovada automaticamente. **O caminho local nunca marca `snapshot_restorable` nem `secrets_recoverable` como verdadeiro**. O modo `prepare` é não disruptivo e gera template privado `approval.json` em estado FALSE. O modo `apply` **não foi executado nem autorizado**; PA-02 permanece ABERTO até corte real e prova HTTP/TCP mínima. A política institucional de snapshot/autorizações prevalece se obrigatória.

**Próximo trabalho sem suporte:** criar contexto `CE-PA02-CUT01_PREPARACAO_CONCLUIDA` em EP125 via `--mode prepare`, sem alterar serviços; avaliar e autorizar explicitamente riscos antes de qualquer `--mode apply`. Não repetir GA08.32/33/RW01 nem usar driver antigo PR #217; preservar imagens e 11º overlay do PA05.
