# ConectaEduca EC8 — matriz de implantação e reconciliação dos PRs

**Revisão:** 26/10/2026 (BRT). **Janela de suporte solicitada:** quarta, 28/10/2026, 15h — **confirmar disponibilidade/escopo com o suporte**. **Estado desta matriz:** PLANO APROVÁVEL PARA EXECUÇÃO, **não autorização de mudança**. Checkout, VMs, pfSense, tenant Twingate e snapshots não foram alterados para elaborar esta matriz.

## 1. Decisão executiva e fonte de verdade

- **Objetivo do caminho crítico:** ter rede, identidade e certificados validados para ativar **somente os Resources privados autorizados** via Twingate, sob suporte institucional, até a meta de freeze **07/11**. Pentest B **08–14/11**, apresentação **17/11**.
- **Hoje 26/10:** fechar documentos, dependências e status da CI, sem realizar merge/deploy. **Amanhã 27/10 (se VMs online):** executar somente preflight READ-ONLY e reconciliação de estado; alterações com janela/operador/rollback formalizados separadamente. **Quarta 28/10:** tratar P0 com o suporte, instalar/validar o Connector somente se todos os gates forem aprovados.
- **Fonte de verdade de rede:** medições reais e recentes nas VMs + regras atuais pfSense/host; documentação histórica e CI não comprovam runtime.
- **Fonte de verdade de código:** `main` para baseline e os PRs abaixo para propostas; **nenhum PR está mesclado** nesta data. PR green individual não prova merge cruzado, versão instalada, autorização ou ausência de regressão.
- **Fonte de verdade de usuário:** a aplicação PHP mantém a regra **`requireAuth()`** nas candidaturas. **Dois usuários com MESMO papel** foram criados para reteste **BOLA horizontal** (PR #209). Não incluir restrição nova de papel, não antecipar o Pentest B.
- **Fonte de verdade de Zero Trust:** o Twingate controla acesso a **IP/FQDN e porta**, não rotas HTTP. Público segue pelo WAF HTTPS/443; área `/admin` só é privada em rede se ganhar endpoint distinto e rota pública negada. Sem isso, registrar **ZTNA parcial**, sem alegar isolamento administrativo exclusivo.

Referências: [arquitetura Zero Trust](../seguranca/FASE3-ARQUITETURA-ZERO-TRUST-GRUPOS-RECURSOS.md), [matriz de acesso](../seguranca/FASE3-MATRIZ-ACESSO-TWINGATE.md), [handoff ao suporte](GRUPOA-HANDOFF-SUPORTE-20261025.md), [checklist Bacula](GA09-BACULA-CRITERIOS-ACEITE-20261025.md), [runbook Twingate](../seguranca/TWINGATE-RUNBOOK-POS-PENTEST-A.md).

## 2. Reconciliação dos PRs — snapshot verificado em 26/10

Todos: **OPEN / DRAFT / não mesclados**, mergeable individualmente com `main`, e checks do HEAD **SUCCESS na leitura inicial de 26/10**. Os SHAs dos demais PRs são um snapshot e **exigem nova verificação antes de qualquer merge**. **Exceção:** o próprio PR #200 recebeu commits deste plano; seu HEAD é móvel e deve ser lido no GitHub, não fixado nesta tabela. Verificar de novo a CI após cada atualização documental.

| PR / SHA abreviado | O que muda | CI no HEAD | Dependência, impacto e recomendação |
|---|---|---|---|
| [#200](https://github.com/andrea-kozicki/conectaeduca/pull/200) **HEAD móvel** | Arquitetura ZT, acesso/fluxos GA-08, ferramenta sintética GA-09, duas workflows e documentação | 6/6 SUCCESS | **Fonte do plano**; sem ativação do Connector. Revisão documental e dos controles antes de merge. Não é pré-requisito técnico para iniciar Compose Twingate existente em `main`. |
| [#203](https://github.com/andrea-kozicki/conectaeduca/pull/203) `c72b791` | GA-07: overlay opt-in audit.log PHP, política Wazuh, redação de arrays sensíveis e testes | 6/6 SUCCESS | **Reconciliar com runtime antes de aplicar**: persistência e evento sintético PHP→Wazuh foram comprovados em 23/10; não repetir deploy como se estivessem ausentes. Pendente retenção, rotação, minimização e restore/recreate autorizado. |
| [#205](https://github.com/andrea-kozicki/conectaeduca/pull/205) `061a36e` | Login híbrido v2 (JS + view + testes) | 4/4 SUCCESS | **Não é pré-requisito do Connector.** Mudança em login/MFA, alto risco funcional: homologar separadamente depois de baseline TLS, MFA e snapshot. Prioridade subordinada à decisão acadêmica, não misturar com ativação da rede. |
| [#206](https://github.com/andrea-kozicki/conectaeduca/pull/206) `02f3a4d` | Wazuh DLP Ferret LOW/MEDIUM/HIGH case-insensitive; altera regras + CI de integridade | 4/4 SUCCESS | Depende de Manager real: `wazuh-logtest`, fallback/quiet rule, histórico/compatibilidade CLI; **validar em conjunto com #207** após último commit. |
| [#207](https://github.com/andrea-kozicki/conectaeduca/pull/207) `b30734a` | UI Ferret v5 fail-closed, sanitizador, scripts CLI, políticas de TAR offline e supply chain | 6/6 SUCCESS | Exceção de TAR local aprovada **na CI**, não pelo suporte. Não iniciar sem aprovação institucional, SHA-256 do TAR real, Image ID/RootFS, `compose config`, UID/tmpfs e rollback. **Sem implantar junto ao Connector Twingate.** |
| [#209](https://github.com/andrea-kozicki/conectaeduca/pull/209) `6acc813` | Contrato offline BOLA para dois usuários do mesmo papel, sem modificar controller/regras funcionais | 4/4 SUCCESS | Revisão/teste podem ser integrados independentemente; os 13 testes são estruturais, não prova HTTP/BD. Não mudar RBAC por papel. |
| [#210](https://github.com/andrea-kozicki/conectaeduca/pull/210) `3455353` | Fail-closed de listas inline `cap_add/cap_drop/security_opt/ports` no parser de segurança Compose; 17 testes | 4/4 SUCCESS | Prevenção de regressão da PA-03, não correção de VM. Verificar coexistência com o workflow editado por #206. |

### Riscos de integração CRUZADA (não confundir com conflito já confirmado)

1. **`.gitleaks.toml`:** modificado nos PRs **#200, #203, #207, #209, #210**. As alterações da allowlist histórica da fixture fictícia GA-07 têm escopo semelhante. Antes do primeiro merge: criar **uma política única** em `main`, deduplicar, preservar regra/caminho/literal exatos e reexecutar Gitleaks após cada integração. Não declarar cinco conflitos textuais já ocorridos sem realizar merge simulado.
2. **`.github/workflows/repository-static-integrity.yml`:** PRs **#206 e #210** modificam o mesmo arquivo. É necessário compor **ambas** as etapas (classificação DLP + 17 testes Compose), sem sobrescrever a outra, e validar workflow final. Não promover com um dos dois checks silenciosamente ausente.
3. **#206 + #207:** houve **ensaio integrado offline 39/39 PASS** com versões `#206=02f3a4d` e `#207=16dd92e` (Seção 18 do pré-relatório). O **HEAD atual #207 é `b30734a`**, posterior ao ensaio. Logo, **39/39 não atestam a combinação final**. Repetir a suíte de integração conjunta em worktree isolada, com SHAs congelados, depois dos ajustes de código, antes de merge/deploy; manager real e Docker TAR permanecem pendentes.
4. **#200 + #203 + #207:** conjuntos distintos de testes/overlays dependem dos mesmos serviços. Green individual não prova que a ordem efetiva dos overlays Compose EP125/EP126 mantém `audit.log`, WAF, CA, tmpfs e porta. Reconciliar `docker compose config` com configurações existentes e **não imprimir variáveis secretas**.
5. **#205 com baseline da autenticação:** risco de regressão de login/MFA/CSRF/419 e identidade no Pentest B. Não promover apenas porque CI passou; fazer janela separada ou adiar com aceitação explícita.

### Ordem de revisão Git — **não é ordem automática de merge**

**Lote R0 (repo-only, sem depender das VMs):** revisar #200 (matriz/plano), #209 (BOLA sem mudança da regra de negócio) e #210 (CI Compose), resolver a **sobreposição de .gitleaks.toml** e eventual evolução da `main`. Podem permanecer DRAFT até aceite; não bloqueiam início dos gates de Twingate.

**Lote R1 (associado a runtime, conforme gate aprovado):** revisar #203 contra estado existente EP125/126; não forçar atualização se auditoria persistente já operar. Separadamente, revisar #206 + #207 juntos, com teste de integração no novo HEAD e política TAR autorizada.

**Lote R2 (mudança funcional opcional de maior risco):** #205 somente com janela própria e testes reais de login/MFA/WAF. Não misturar a homologação do novo login com a medição do impacto da ZT.

Para qualquer integração futura: comparar `main` atualizado, conflito/overlap, testes unitários + estáticos, assinatura do plano de mudança, snapshot e rollback **por componente**, e só então abrir change control de implantação na VM. **Nenhum merge foi autorizado por esta matriz.**

## 3. Matriz de implantação operacional — gates verificáveis

Legenda: **READY-OFFLINE** = documentação/código/teste CI pronto; **PENDENTE-CAMPO** = requer leitura real; **BLOQUEADO-APROVAÇÃO** = não executar sem suporte/professor.

| Ordem / gate | Ativo | Pré-requisito | Ação mínima / responsável | Critério para avançar | Estado em 26/10 |
|---|---|---|---|---|---|
| **G0 — baseline e autorização** | EP125, EP126, pfSense, Git | VMs online, operador, janela, escopo de rede, hashes Pentest A e snapshots identificados | **Suporte:** confirmar IDs, consistência e retenção de snapshots, reversão e privilégios temporários aprovados; **responsável:** preflight sem sudo | Evidência de snapshot/rollback **restaurável por operador**, repositório/versão/contêiner documentados | **BLOQUEADO-CAMPO** (IDs ainda não documentados) |
| **G1 — inventário read-only** | EP125/EP126 | G0 para qualquer ação, leitura sem mudanças pode ocorrer antes com autorização existente | Conferir Git HEAD/working tree, overlay efetivo, imagens, portas, serviços, Wazuh, Bacula, NTP e relógio | Reconciliar *o que já está aplicado* vs DRAFT; não reimplementar PHP 8.5.12/auditoria comprovados anteriormente sem motivo | **PENDENTE-CAMPO** |
| **G2 — TLS, DNS e SAN** | EP126→EP125 WAF e Client | CA legítima e operador de certificados | **Suporte:** diagnosticar verify code **20** (cadeia emissora), DNS `g20.ciberseg.ep.pucpr.br`, SAN/nome, CA aprovada e responsável pela renovação | TLS validado **sem** `-k`/`verify=False`; certificado e hostname/IP efetivos documentados | **BLOQUEADO-SUPORTE** |
| **G3 — segmentação/backends** | pfSense, EP125 WAF, Nginx Docker bridge | Decisão sobre portal público e entrada admin privada | **Professor/suporte:** aprovar direção de acesso, WAF→Nginx e política host/bridge; não bloquear PHP legítimo | Fluxos positivos válidos; tentativas diretas ao upstream de origens indevidas negadas; rollback pronto | **BLOQUEADO-DECISÃO DE REDE**; GA-08 14/14 apenas estático |
| **G4 — pré-requisitos Connector** | EP126 ou host alternativo | G0, G2, saída rede aprovada, identidade/tenant e imagem | **Suporte:** aprovar host/permissões Docker/egress; **responsável acadêmica:** tenant/Client/identidades e tokens fora de Git/chat | Digest/host/egress confirmados, rota até Resource mínimo, relógio/CA, política de tokens/revogação e rollback | **READY-OFFLINE; BLOQUEADO-APROVAÇÃO** |
| **G5 — piloto Twingate** | Connector/Remote Network | G0–G4 aprovados, operador e janela | **Responsável:** configurar uma política/Resource de teste **TCP 443 apenas**, grupo restrito + MFA; **suporte:** mudanças institucionais aprovadas | Connector **Online** no Console, allow com Client, deny de identidade sem grupo, deny portas extras, revogação e logs sanitizados | **NÃO IMPLANTADO** |
| **G6 — gestão realmente privada** | SSH, Wazuh, Bacularis, admin PHP | G3/G5 + listeners/ACLs efetivamente medidos | Criar Resources individuais somente para serviços **comprovados**; admin PHP requer entrada HTTPS **distinta** e bloqueio de `/admin` pela rota pública | Testes de Client permitido, negado, sem Client **e rota direta**; não expor OpenBao/DB/Catalog; se admin não isolado, registrar lacuna | **PROPOSTO, NÃO IMPLANTADO** |
| **G7 — remediações operacionais independentes** | GA-06/07/09, Wazuh e Bacula | Janela por serviço, PR aceito, snapshots e plano de fallback | Ferret v5 TAR (se exceção aprovada), Wazuh DLP Manager, auditoria rotação/retenção, Jobs + restore Bacula sintético | Testes reais separados, sem perturbar o piloto Twingate; SHA/evidência e rollback registrados | **CI pronta; operação pendente** |
| **G8 — freeze e Pentest B** | Laboratório integrado | G5/G6 aprovados ou limitações declaradas, G7 no escopo de entrega | Congelar alterações até 07/11; 08–14/11 repetir PA-01..07 comparáveis, **duas contas do mesmo papel para BOLA**, insider + deny/allow | Mesmas origens/URLs/perfis por cenário; evidências com horários/hash, efeitos e limites, sem inventar resultados | **FUTURO** |

**Dependência essencial:** não afirmar isolamento completo porque o Connector está Online. Se o acesso público 443 continuar alcançando a aplicação, documentar **caminho Twingate controlado em paralelo**; para `/admin`, isolamento só com ingresso privado distinto e negação no público. A bridge Docker e movimento lateral dentro da VM exigem ACLs próprias; Twingate não os resolve automaticamente.

## 4. O que fazer na terça, 27/10, se as VMs retornarem

**Bloco T1 — leitura autorizada, sem sudo de teste e sem alterar serviços**
1. Capturar nova evidência de **Git SHA**, branch, working tree e diferenças entre checkout EP125/EP126 e `main`/PRs; não aplicar `git pull`, `git reset` ou `docker compose up`.
2. Conferir imagem PHP em execução (EP125 anteriormente **8.5.12**), overlays realmente habilitados e onde o `audit.log` está persistido, evitando conteúdo do log e segredos.
3. Consultar estado atual Docker/WAF/Nginx/MariaDB/OpenBao/Wazuh/Bacula e NTP, **sem** iniciar restore, executar testes ofensivos ou reconfigurar regras.
4. Validar diagnóstico **read-only** do TLS EP126→EP125, exibindo apenas cadeia/código/subject/SAN sanitizados; se falhar, **não** contornar a CA.
5. Verificar estado de snapshots (identificadores/validade com suporte; não criar/rollback por conta própria), disponibilidade de cliente e pré-requisitos Twingate, **não** criar Resource/Connector.
6. Consolidar resultados por `PASS/PENDENTE/BLOCK` com origem, timestamp e SHA; **parar antes de mudanças** se qualquer pré-requisito faltar.

**Bloco T2 — somente se autorização e rollback já estiverem documentalmente aprovados**: selecionar UMA alteração mínima por janela, com antes/depois e teste funcional positivo/negativo. Se não houver autorização, guardar apenas o inventário para quarta. Não promover PRs DRAFT nem trocar regra `requireAuth` de candidatura.

**Itens deliberadamente NÃO executados na terça por este plano:** merge em massa; Connector sem G0–G4; firewall/bridge sem suporte; `docker load/up/pull` Ferret v5; mudança na conta de teste ou `sudo`; backup/restore; eventos Wazuh extras; Pentest B prematuro.

## 5. Reunião de 28/10, 15h — pauta de decisões e divisão do trabalho

| Minutos indicativos | Pergunta/decisão necessária | Quem deve deliberar/agir | Se a resposta for NÃO/PENDENTE |
|---|---|---|---|
| 0–10 | VMs disponíveis? Snapshots EP125/EP126 com IDs e rollback? Quais permissões temporárias e operador? | Suporte institucional | **Não executar mudanças** |
| 10–20 | Qual FQDN, DNS e CA/ZeroSSL? Como corrigir EP126 verify 20 e validar SAN sem bypass? | Suporte + responsável DNS/certificados | Não declarar TLS pronto |
| 20–30 | Qual política pfSense, WAF upstream/bridge e **entrada privada para Admin PHP**? Portal público 443 permanece? | Professor (desenho) + suporte (rede) | Piloto pode medir acesso controlado, mas **não afirmar isolamento completo** |
| 30–40 | Host/egress/digest/token/operador do Connector autorizados? Recurso piloto TCP443, grupos/MFA, Client e retorno? | Responsável Twingate + suporte | Não subir Connector |
| 40–50 | Janela posterior para GA-06/07/09 e Wazuh/Bacula, sem elevar usuário `teste`? | Suporte/operador | Manter findings operacionais abertos; priorizar o caminho crítico ZT |

A reunião não precisa concluir todos os Jobs de Bacula nem Ferret UI. **Precisa sair com responsáveis e decisão registrada nos G0–G4.** Evitar converter hipóteses de roteamento/portas de Dashboard/Bacularis em regras definitivas antes de medir.

## 6. Ordem e política de rollback por mudança

| Mudança | Preservar antes | Teste de aceite depois | Rollback se falhar |
|---|---|---|---|
| CA/DNS/TLS | Certificado/chain/trust store e DNS atuais; snapshot/config approved | Verificação completa da CA e SAN desde EP126/Client; HTTPS sem bypass | Restaurar material e resolução aprovados; suporte |
| pfSense/WAF/bridge | Regras e Compose efetivos, caminho público, snapshot | Origem autorizada mantém aplicação; origem interna indevida não atinge Nginx upstream; WAF não bypassado | Restaurar regras do change control; suporte |
| Connector Twingate | Baseline SEM Connector, console/Resource vazio, tokens protegidos | Online + allow/deny/revogação + nenhum serviço interno exposto extra | Desassociar Resource, parar/remover Connector e revogar/rotacionar tokens pelo operador; cuidado com `restart: unless-stopped` |
| PR #203 auditoria | Log histórico, owner/mode, collector e configuração real | JSONL/Wazuh preservados após rotação/recreate, sem conteúdo sensível | Reverter overlay/config por operador, preservar log anterior e audit trail |
| PRs #206/#207 Ferret | Imagem baseline digest, SHA TAR, diretórios privados e Wazuh original | CLI/UI com fixtures, no falso "clean" em erro, regras LOW/MEDIUM/HIGH no Manager | Voltar à imagem/rules baseline por change control; nenhum digest registry inventado |
| Bacula restore sintético | Jobs, FileSet/Client/Storage, configuração, staging e snapshot | Job corrente e restore isolado com SHA-256 da amostra fictícia | Parar ensaio e restaurar apenas **sandbox**, nunca substituir dados reais |

## 7. Checkpoints de aceite e sinalização ao professor

- **READY-OFFLINE**: PR/CI/documentos alinhados. **Não** encerra PA nem achados.
- **APTO-PILOTO**: G0–G4 completos com autorização, CA/DNS, egress e rollback.
- **ZTNA-CONTROLADO**: G5 com allow/deny real, credencial revogável e port restrictions.
- **ISOLAMENTO-COMPROVADO**: somente para destinos cujo caminho direto foi **negado** e acesso legítimo positivo comprovado; **/admin depende de G6**.
- **BLOQUEADO/PARCIAL**: documentar causa específica e responsável, não simular teste, não reduzir requisitos silenciosamente.

**Ponto de parada:** sem CA/egress/operador/snapshot/Resource aprovado, não iniciar instalação Twingate nem alegar segundo pentest. O resultado do próximo passo deve ser registro de decisão técnica e evidência mínima sanitizada, não um grande log bruto.

## 8. Rastreabilidade

- GitHub issues: [#194 DLP confidence](https://github.com/andrea-kozicki/conectaeduca/issues/194), [#195 auditoria](https://github.com/andrea-kozicki/conectaeduca/issues/195), [#196 Bacula](https://github.com/andrea-kozicki/conectaeduca/issues/196), [#201 PHP runtimes](https://github.com/andrea-kozicki/conectaeduca/issues/201), [#204 WAF bridge](https://github.com/andrea-kozicki/conectaeduca/issues/204).
- Trello Fase 3: Grupo A, ZT-02/03/06/07/09/10, marco freeze 07/11; cronograma e handoff acima.
- Pré-relatório cumulativo **v14**: contexto PA-01..07 e resultados GA-06/07/08/09/PA-03/PA-05; **este documento de reconciliação é um artefato complementar e não atesta execução operacional**.


## 9. Resultado posterior — compatibilidade de PRs comprovada offline (26/10)

Após o fechamento inicial desta matriz, foi executado [PA07 Cross PR Offline Integration](https://github.com/andrea-kozicki/conectaeduca/actions/runs/40417679842) usando apenas GitHub Actions e worktrees temporários. **Não foi feito merge na branch main, não houve acesso às VMs nem execução de Docker/Wazuh.**

| Par de PRs | HEADs congelados | Resultado real do ensaio | Limite |
|---|---|---|---|
| #206 + #207 | `02f3a4d` + `b30734a` | **51/51 testes PASS**, merge temporário PASS; DLP confidence + política TAR PASS | Manager, CLI real, TAR e tmpfs ainda sem validação na EP126 |
| #206 + #210 | `02f3a4d` + `3455353` | **27/27 testes PASS**, merge temporário PASS, duas etapas do workflow preservadas; 36 arquivos Compose/59 serviços PASS | Reexecutar CI depois dos merges efetivos |

Os dois ensaios têm **10 testes DLP em comum**: os números 51 e 27 não representam 78 casos distintos. São evidências de compatibilidade **somente dos pares e SHAs fixados**. O ensaio anterior de 39/39 usava HEAD antigo do #207 e foi superado para essa finalidade. Scripts: `scripts/evidencias/pa07_cross_pr_offline.sh` e `scripts/evidencias/pa03_pa07_ci_cross_pr.sh`; workflow `.github/workflows/pa07-cross-pr-offline.yml`, todos na branch do PR #200.

### Política Gitleaks compartilhada — como reconciliar

Foi inspecionado `.gitleaks.toml` em `main` e nos PRs #200, #203, #207, #209 e #210. PR #200 e PR #203 têm **conteúdo idêntico**, contendo uma única exceção sintética GA07. PR #209 e #210 têm a **mesma condição de regra, arquivo e expressão**, mas descrições distintas. `main` e #207 ainda não incluem essa exceção.

Ao fazer os merges **autorizados**, manter **exatamente uma** entrada GA07: regra `generic-api-key`, arquivo exato `tests/Unit/AuditLoggerRedactionTest.php`, literal `GA07-FICTICIO-NAO-SECRETO`, `condition = "AND"`. Não concatenar blocos duplicados; não permitir que a integração de #207 remova a exceção; depois executar Gitleaks na integração final. Esta regra não permite segredos reais nem dispensa a triagem de novos alertas.

**Status atualizado:** riscos específicos de merge dos pares #206/#207 e #206/#210 foram **testados com sucesso offline**. Ainda faltam testes reais de segurança nas VMs, reconciliação de configuração efetiva e aprovação institucional. Este adendo prevalece quando a seção 2 menciona os pares como ainda não retestados.


## 10. Reconciliação read-only recebida — EP125 em 26/10/2026

**Origem da evidência:** relatório gerado na VM pelo script `RECONCILIACAO_BASELINE_READ_ONLY_V1`, timestamp `2026-10-26T23:29:43+00:00` / 20:29:43 BRT, host `ep125-pucpr`, checksum SHA-256 do TXT `aebf3eec1842237cc4f42eb5a0ad926e01e1da7ca50d5690db9f90d85516375e`. O TXT original fica sob custódia privada, **não anexar logs/secrets ao GitHub**. EP126 ainda pendente nesta revisão.

| Verificação | EP125 observada | Limitação / ação |
|---|---|---|
| Código Git | `main@4bf7ac688b1ea738cd158f03a20b07732cdd90a3`; `tracked_changes=0` | `origin/main` era referência local em cache; **não houve fetch**. Comparar com main remoto antes de escolher PR de runtime |
| Arquivos no checkout | Compose DMZ, overlay de auditoria, Compose Twingate/Ferret e ruleset DLP presentes | Override GA06 TAR e ruleset GA07 não encontrados **nesse checkout**. Não concluir ausência de implantação no host/Manager |
| Systemd | `docker.service`, `wazuh-agent.service`, `bacula-fd.service` active | Estado de contêineres NÃO VERIFICADO: usuário atual **sem acesso à Docker API**, sem sudo / sem mudança de grupos |
| Tempo e memória | `NTP_SYNC=yes`; RAM 4014/6596 MB; swap **2047/2047 MB** | 100% de swap ocupada **não prova paginação ativa**; antes da mudança, revisão `free/vmstat` read-only |
| Listeners | `192.168.6.34:80`, `:443`; `0.0.0.0:22`, `[::]:22`; `0.0.0.0:9102` | Escuta em todas as interfaces **não comprova alcance externo**; revisar regras pfSense/firewall; sem 8088 nessa amostra de ss, mas bridge não comprovada |
| Audit log host | `AUSENTE_OU_SEM_PERMISSAO` | **INCONCLUSIVO** por permissão; preservar evidência anterior de persistência e PHP→Wazuh E2E até revisão pelo operador |
| Snapshot/rollback | IDs e consistência não verificáveis | P0 suporte 28/10; nenhuma alteração operacional autorizada ou realizada neste ensaio |

**Diário privado EP125:** adendo foi preparado para `~/ConectaEduca_Fase2_Evidencias/EP125/diario.md` com marcador `CE-F3-RECON-EP125-20261026T202957-V1`, backup, cópia 0600 e prevenção de duplicação. **A atualização no filesystem da VM depende de execução explícita pela responsável**; publicação desta matriz **não** significa que o diário privado já foi modificado.

**Próximo passo:** aguardar relatório da EP126, comparar Git/serviços/TLS sem escalar privilégios e consolidar decisão de suporte. Manter todos os PRs DRAFT.


## 11. Reconciliação das duas VMs concluída no escopo read-only — EP126 recebida em 26/10

**Evidência:** `ConectaEduca_RECONCILIACAO_EP126_ep126-pucpr_20261026T211913.txt`, procedimento `RECONCILIACAO_BASELINE_READ_ONLY_V1`, `2026-10-27T00:18:55+00:00` (26/10 21:18:55 BRT). **SHA-256:** `24916a8baa2d2d1059443c76b845fce7de62ce0295d36a62b8cf82918b4f3799`. Original sob custódia privada da responsável, não enviado ao GitHub. Comparação com EP125 de 26/10 20:29 BRT e SHA `aebf3eec1842237cc4f42eb5a0ad926e01e1da7ca50d5690db9f90d85516375e`.

### Resultado confirmado — Git/estado dos checkouts

**EP125 = EP126 = GitHub remoto `main@4bf7ac688b1ea738cd158f03a20b07732cdd90a3`**; ambas `main`, `TRACKED_CHANGES_COUNT=0` e cache local `origin/main` igual. A `main` remota foi consultada separadamente pelo conector GitHub após recepção dos TXT. **Isso comprova alinhamento do código rastreado**, mas não equivalência de arquivos não rastreados, overlays aplicados, imagens Docker, diretórios `.runtime` ou configurações efetivas dos serviços. Nenhum `git fetch/pull/merge` foi executado nas VMs.

| Medida | EP125 DMZ | EP126 interna | Leitura conservadora |
|---|---|---|---|
| Kernel | `6.8.0-142-generic` | `6.8.0-147-generic` | Divergência observada, **não indica** patch necessário sem inventário de pacotes/planejamento |
| NTP | `yes` | `yes` | Sincronia observada |
| RAM usada/total | 4.014/6.596 MB | 4.585/16.202 MB | EP125 exige cautela operacional |
| Swap usada/total | **2.047/2.047 MB** | 0/2.047 MB | Swap EP125 ocupada, **não prova** paging ativo; read-only `vmstat` e `free` autorizados antes de intervenção |
| Docker/Wazuh agent/Bacula FD | Systemd `active` | Systemd `active` | Sem prova de integridade/efetividade dos contêineres |
| Docker API | **Inacessível ao usuário** | **Inacessível ao usuário** | Principal bloqueio observacional: não concluir Compose/imagens/containers reais; não conceder docker group ou sudo para contornar |
| Overlay audit DMZ no checkout | **Presente** | **Ausente no checkout** | Não é erro da EP126 por si só: overlay da DMZ; não comprova aplicação efetiva na EP125 |
| Twingate Compose / Ferret / Wazuh DLP repo | presentes | presentes | Código de configuração presente ≠ serviço configurado/operacional |
| GA06 override TAR / regras GA07 no checkout | ausentes | ausentes | PRs em draft; regra do Wazuh pode existir em outros caminhos/volumes e não foi inspecionada |
| Listeners relevantes | `192.168.6.34:80/443`, `0.0.0.0:22/9102` | `127.0.0.1:443,9097,9101,9443,18082,18200`; `192.168.6.50:1514,3306,9103`; `0.0.0.0:22,9102` | Não inferir exposição externa ou segurança da bridge por bind; firewall/pfSense requerem inspeção com operador |
| Auditing/backup | audit.log host `AUSENTE_OU_SEM_PERMISSAO` | timers Ferret healthcheck/retention `active`; Bacula FD `active` | Auditoria EP125: **inconclusiva** por permissão. Timer `active` não equivale a scan/backup ou restore recente |
| Twingate tokens na EP126 | — | `AUSENTE_OU_SEM_PERMISSAO` | Não atesta presença nem ausência real. Não iniciar Connector até gates de autorização |
| Snapshots | ID/consistência não verificados | ID/consistência não verificados | Bloqueio institucional para mudanças |
| TLS EP126→EP125 | origem/destino WAF na EP125 | **TCP443 alcançável; verify code 20** (`unable to get local issuer certificate`) | Cadeia/CA não confiável no cliente atual; **SAN ainda não comprovado**. Não utilizar `-k`/`verify=False` |

**Gates atualizados para o suporte de 28/10:** (1) identificadores/alcance de snapshots e operador de rollback; (2) diagnóstico de CA/trust chain EP126→EP125 e decisão de FQDN/ZeroSSL; (3) read-only privilegiado dos metadados necessários dos contêineres por operador institucional, **sem conceder Docker à conta `teste`**; (4) CPU/memória/swap da EP125 sem `swapoff` ou reinício; (5) restrições pfSense, WAF upstream e ZT por Resource; (6) host/egress/tokens revogáveis Twingate somente após autorização.

**Artefato diário EP126:** script privado `ConectaEduca_ADENDO_DIARIO_EP126_20261026.py` preparado/testado localmente (dry-run, SHA-256, backup 0600, cópia privada do TXT, idempotência). A gravação em `~/ConectaEduca_Fase2_Evidencias/EP126/diario.md` **ainda depende de execução manual na EP126**; este commit não modifica o diário da VM. `manifesto.tsv` não é alterado.

**Resultado:** reconciliação READ-ONLY executada e comparada; Git rastreado alinhado, mas **runtime permanece NÃO VERIFICADO**. PRs e change control não são promovidos automaticamente; operações e Pentest B continuam dependentes das autorizações e evidências.


## 12. EP126 → EP125 TLS: cadeia não validada, SAN IP presente (27/10)

**Evidência read-only da EP126:** `EP126_TLS_20261027T145927.txt`, 27/10/2026 14:59:27 BRT, **SHA-256 `9b956acf6fa21b88e92866a9f795c90acad289a40f1ad12a071d12bdc86ac11c`** (custódia privada; sem certificado/segredo versionado).

- Servidor EP125 `192.168.6.34:443` apresentou **1 certificado**. Subject: `CN=conectaeduca.local`, emissor `CN=ConectaEduca Lab Root CA` (CA interna); validade 11/09/2026 a 13/10/2027.
- SANs do certificado de folha **incluem `DNS:conectaeduca.local` e `IP Address:192.168.6.34`**. **A ausência de SAN IP não é a causa observada**. Não afirmar que o certificado é confiável até cadeia validada.
- `openssl s_client -verify_return_error -verify_ip 192.168.6.34`: **verify code 20**, `unable to get local issuer certificate`. A falha ocorreu na construção da cadeia de confiança (depth 0); **não comprova ausência da CA no trust store, cadeia incompleta no WAF, nem falha de nome isoladamente**. Se a folha for assinada diretamente pela CA raiz privada, apresentar apenas a folha é comportamento possível e legítimo; a raiz confiável deve existir no cliente.
- **Próximo diagnóstico read-only:** confirmar se a CA de laboratório consta das CAs confiáveis pelo cliente TLS da EP126, e conferir a origem/autenticidade do certificado raiz com suporte. **Não instalar trust, não usar bypass TLS `-k` ou `verify=False`, não emitir cert novo apenas por SAN**.
- **P0 suporte 28/10:** identificar a CA aprovada e o responsável pelo certificado, confirmar trust store da EP126 e de Client autorizado, cadeia/validade/revogação, e a decisão institucional DNS/ZeroSSL; proceder com alteração somente em change control e depois retestar com verificação completa.

**Estado:** `TLS-BLOCK-01` pendente de confiança da CA/cadeia; SAN IP demonstrado presente, mudança operacional **não executada**. Esse diagnóstico não comprova que a instalação de Twingate dependa de TLS da aplicação para comunicação do Connector com o serviço de nuvem: são fluxos diferentes; validação HTTPS do Resource continua pendente.


## 13. EP126 — CA interna ausente do contexto Python/OpenSSL testado (27/10)

**Evidência read-only:** `EP126_CA_TRUST_20261027T150618.txt`, coletado em 27/10/2026 15:06:18 BRT, **SHA-256 `5db087afaead9d964fa5e1e833c83cf055ceb27bc072bcade734c1251a7efdab`**. Arquivo original em custódia privada da responsável; não contém CA PEM, chaves ou segredos e não foi anexado ao repositório.

**Resultados efetivamente obtidos:** contexto `ssl.create_default_context()` no Python carregou **120** certificados de CA; nenhuma entrada com `commonName=ConectaEduca Lab Root CA` foi encontrada; `CAFILE_EXISTE=True`, `CAPATH_EXISTE=True`; nenhuma modificação no sistema. O diagnóstico é **restrito ao conjunto de CA carregado por esse cliente Python e à busca literal pelo commonName**. Não prova ausência da CA em todos os armazenamentos, nem substitui validação criptográfica da cadeia.

**Correlação:** evidência EP126 TLS de 14:59 BRT (Seção 12) demonstrou `openssl s_client -verify_return_error -verify_ip 192.168.6.34` com `verify code 20`. A folha do WAF tem SAN IP `192.168.6.34`, não expirada, e emissor `ConectaEduca Lab Root CA`. A falta de CA confiável no cliente testado **explica de forma consistente o erro 20**, mas a identidade/autenticidade do certificado raiz deve ser comprovada antes de qualquer instalação.

**Ação solicitada ao suporte em 28/10:** identificar a CA raiz legítima a partir da custódia institucional, confrontar fingerprint SHA-256 por canal independente, confirmar se o WAF serve a cadeia apropriada, aprovar a instalação somente do certificado **público** da CA no armazenamento adequado da EP126 e do Client (quando necessário), sem alterar chaves privadas ou CA de produção. Retestar HTTPS `192.168.6.34:443` sem `-k`, `verify=False` e com SAN/hostname verificado. Se o plano institucional optar por ZeroSSL/FQDN, registrar essa escolha como *change control separado*. Verificar acesso ao admin privado e regras pfSense independentemente.

**Status:** `TLS-BLOCK-01` continua **PENDENTE DE CHANGE CONTROL**. Evidência de diagnóstico suficiente para pauta do suporte; não repetir checks semelhantes sem nova hipótese, não instalar a CA nem iniciar Connector como consequência automática. A comunicação Connector→Twingate Cloud é distinta do HTTPS entre EP126→WAF, e o resultado do TLS da aplicação não prova conectividade com o serviço Twingate.


## 14. PRs 209/210 revisados e cadeia de custódia da CA documentada (27/10)

**PR #209 HEAD 6acc8137 — APTO A INTEGRAÇÃO CONTROLADA:** foi lido o diff completo. Apenas contrato offline de propriedade horizontal (13 testes), documentação de casos BOLA e allowlist restrita; **sem alteração de controller/endpoint/DB**. Os três handlers de candidaturas preservam `Authorization::requireAuth()`, sem inventar `requireRole('usuario')`. CI 4/4 SUCCESS; PHPUnit 132 testes/428 asserções. Testes estruturais não comprovam negação HTTP/BD real. Recomendação: primeiro merge eventual, após aceitação explícita, e sem deploy automático.

**PR #210 HEAD 3455353 — APTO A INTEGRAÇÃO CONTROLADA:** lidos diff completo e os 17 testes de listas inline do verificador Compose. Conservadoramente rejeita listas inline não vazias em vez de ignorá-las; não altera nenhum Compose operacional. CI 4/4 SUCCESS; teste integrado #206/#210 em worktree isolada 27/27 PASS. Recomendação: eventual segundo merge, após #209, preservando exatamente uma allowlist GA07 e ambas as etapas CI; reexecutar checks após atualização da `main`. Ambos permanecem DRAFT, **nenhum merge foi realizado**.

**Descoberta importante no repositório principal:** [`deploy/dmz/TLS-PKI-INTERNA.md`](../../deploy/dmz/TLS-PKI-INTERNA.md) registra que a `ConectaEduca Lab Root CA` foi **criada fora da EP125 em ambiente administrativo**, em 11/09/2026, e sua **CA pública** foi instalada no trust store da EP125. A chave privada da CA não foi transferida ao host ou ao Git e NÃO deve ser solicitada. O fingerprint público SHA-256 histórico da CA consta como:

`C4:CF:23:F1:1F:3C:2D:71:13:4D:4F:63:61:D3:6B:1F:E1:F2:D9:72:E6:37:9C:E7:42:9F:F7:FD:18:48:59:D4`

**Encaminhamento:** suporte ou responsável pela estação que gerou a PKI deve localizar a cópia autêntica do **certificado público raiz** (PEM `.crt`), conferir identidade e fingerprint por fonte confiável, confirmar `CA:TRUE` e cadeia para a folha da EP125 e, somente por change control e com autorização, instalar a raiz pública no trust store da EP126/Client que necessitarem. Não pedir chave privada da CA nem a chave privada do WAF. Não instalar CA genérica, não desabilitar validação TLS. Se a entrada migrar para o domínio institucional `g20.ciberseg.ep.pucpr.br`, o certificado atual **não inclui esse FQDN no SAN** — é uma decisão de DNS/emissão separada; não confundir com falta de confiança no certificado atual por IP.


## 15. Integração GitHub concluída: PR209 + PR211 + PR210 (27/10)

**Mudança na fonte de verdade:** esta seção substitui os estados históricos **DRAFT/OPEN** das tabelas anteriores para os PRs #209 e #210. A integração abaixo ocorreu **exclusivamente no GitHub**, com permissões e CI do repositório. **EP125 e EP126 não receberam fetch, pull, merge, deploy ou reinício**, e permanecem no último HEAD rastreado confirmado `4bf7ac688b1ea738cd158f03a20b07732cdd90a3` até verificação/alteração operacional autorizada. Mudanças da CI não demonstram o runtime do Docker.

| Ordem | PR | Alteração integrada | Merge SHA / CI |
|---|---|---|---|
| 1 | [#209](https://github.com/andrea-kozicki/conectaeduca/pull/209) | Teste estrutural BOLA/IDOR horizontal do mesmo papel; preservado `requireAuth()`; política Gitleaks GA07 pontual | `115a3e6ae53bc8b58080c8c257c76faa5480d9e9`; 4/4 PR checks aprovados, PHPUnit 132 testes/428 asserções |
| 2 | [#211](https://github.com/andrea-kozicki/conectaeduca/pull/211) | Correção emergente de dependência de **desenvolvimento**: `phpunit/phpunit` 13.4.1 → **13.4.5**, `sebastian/git-state` 1.0.0 → 1.1.0; `composer.lock` apenas | `f8644c0632b23ec9e1f5e1f459ef2eea2883dd89`; **5/5 checks PASS**, `composer audit --locked` sem avisos, `composer install` aprovado, PHPUnit 132/428 PASS |
| 3 | [#210](https://github.com/andrea-kozicki/conectaeduca/pull/210) | Gate fail-closed de arrays de segurança Compose inline, **17 testes**, workflow de integridade; `.gitleaks.toml` idêntico à `main` para evitar segunda exceção | `f3163bbf54dc80325b8f52bc4aad0fef26f4c727`; **4/4 checks PASS** sobre a base corrigida, `composer audit` sem advisory, testes Compose 17/17 PASS, inspeção estática 36 arquivos/59 serviços PASS |

### Achado de cadeia de suprimentos durante o merge

O primeiro teste de `#210` após `#209` falhou (de forma **correta**) em `composer audit --locked` devido à divulgação em **27/10/2026** do advisory **[GHSA-9vw2-f4vp-x7gf](https://github.com/advisories/GHSA-9vw2-f4vp-x7gf)** / `PKSA-qhjm-rpqc-qkn6`: PHPUnit `>=13.4.0,<13.4.4` apresenta risco de execução de código por outros usuários locais no tratamento de diretório temporário PHPT/cobertura. **Não houve bypass do auditor**, desativação de gate nem merge do #210 enquanto a CI estava vermelha. Release assinada do upstream conferida, e `#211` reparou a dependência em `composer.lock`; reexecutada a CI do #210 posteriormente com sucesso.

O Dependabot [#208](https://github.com/andrea-kozicki/conectaeduca/pull/208), que propunha somente PHPUnit 13.4.3 **ainda afetado pelo alerta**, não foi integrado; a correção aprovada foi #211 com 13.4.5. Não reabrir/mesclar #208.

### Reconciliação atual dos PRs e ambientes

- **`main@f3163bbf54dc80325b8f52bc4aad0fef26f4c727`** — HEAD remoto verificado após os três merges. Os PRs #200, #203, #205, #206 e #207 continuam **OPEN/DRAFT**.
- No **PR #200**, `.gitleaks.toml` foi normalizado ao blob exato da `main`, evitando apagar/duplicar a allowlist GA07 em eventual merge posterior. **PR #200 não foi mesclado.**
- **Não aplicar `git pull` nas VMs ainda**: ambos os checkouts estavam na `main@4bf7ac6` em 26/10 e todos os metadados Docker/overlays estavam inacessíveis ao usuário; a aplicação pode estar em um deploy separado do checkout. Conferir source runtime e compatibilidade de overlays pelo operador autorizado com snapshot/rollback antes de reconciliação operacional.
- A troca de `composer.lock` é **dev-only** no repositório; não implica nem autoriza instalar PHPUnit dentro da imagem PHP de produção, nem reiniciar contêineres.
- **Gates ainda abertos:** `TLS-BLOCK-01` CA interna não encontrada na EP126 (seções 12-14); snapshots/rollback, inspeção Docker, decisão de endpoint admin privado, Twingate Connector, Pentest B e PRs operacionais #203/#206/#207.

**Decisão de liberação:** integração de **#209 + #211 + #210 = CONCLUÍDA (GitHub)**; reconciliação **EP125/EP126 = PENDENTE DE INSPEÇÃO E CHANGE CONTROL**. Nenhuma conclusão de fechamento de PA-03 ou PA-05 em runtime foi produzida por esses merges.


## 16. EP125: acesso Docker real confirmado com andrea.kiew (27/10)

**Evidência de 27/10/2026 16:10:02 BRT:** `EP125_DOCKER_PRIVILEGIOS_20261027T161002.txt`, SHA-256 `5d60f5a6c4e9be974a4915a6b5f25e9419ff5685b231fb0a7be847fefddb4858`, original custodiado privadamente, sem upload de logs/segredos ao repositório.

- EP125, usuário **`andrea.kiew`**, filiação ao grupo **`docker` GID 999**. `/var/run/docker.sock` acessível a `root:docker` no modo 660.
- `docker ps -a` **exit 0**, `docker info` **exit 0**; Docker Engine **29.8.1**, Docker Compose **v5.5.1**, contexto `default`.
- **Três contêineres presentes e HEALTHY** no recorte de verificação: `conectaeduca-dmz-php-1`, `conectaeduca-dmz-waf-1` e `conectaeduca-dmz-nginx-1` (`Up 3 days`). Não inferir por esse resultado que auditoria persistente, isolamento dos fluxos e controle de acesso já estejam validados.
- **Retificação ao inventário de 26/10:** o campo `DOCKER=INACESSIVEL_PARA_USUARIO` do script antigo NÃO prova ausência permanente de privilégios. Contraprovado por acesso funcional posterior. Causa da divergência não estabelecida; pode haver falha transitória ou contexto de execução diverso. **Não solicitar habilitação desnecessária de Docker para a EP125.**
- **EP126 permanece não verificada neste novo aspecto**: não extrapolar grupos e permissões da EP125.
- **Próximo passo:** inventário somente leitura dos metadados selecionados (imagem, status, mounts, published ports, rede, labels Compose, caminhos dos Compose YAMLs e hashes), sem `sudo`, `docker exec`, `docker inspect` completo/`Env`, logs, segredos, `compose config`, `up/down/pull/restart`. Script privado preparado `ConectaEduca_EP125_DOCKER_INVENTARIO_READONLY_20261027.py`, SHA-256 `c4d408a2b14d4a2e2e1b81dfee78f5e5be3efe8fe6dfed46251bdedaf5c9c62a`, sintaxe e smoke sintético verificados; **não executado na VM pelo assistente**.
- Nota de segurança: participar do grupo `docker` geralmente equivale a capacidade de administração do host; o script foi deliberadamente limitado a consultas. Mudanças de runtime, snapshots, rollback e implantação Twingate continuam dependendo de aprovação institucional.


## 17. 27/10 — decisão de parar inventários repetidos e executar reconciliação por deltas

**Decisão de condução:** os inventários completos da EP125/EP126 já foram produzidos em 18/10, 24/10 e na baseline de 26/10. **Não executar outro inventário abrangente** `ConectaEduca_EP125_DOCKER_INVENTARIO_READONLY_20261027.py` apenas para redescobrir a infraestrutura. Só solicitar leitura pontual caso uma diferença concreta bloqueie a execução aprovada. Evitar repetição antes da janela institucional de **28/10 15h BRT**.

### Evidências anteriores que DEVEM ser reaproveitadas

- 24/10: fast-forward dos checkouts **EP125 e EP126** de `c37bdce` para **`main@4bf7ac6`**, sem reiniciar automaticamente serviços; hash alinhado ao GitHub à época.
- EP125: **PHP 8.5.12** e HTTPS 200 confirmados em registro de 24/10; os 3 contêineres `php/waf/nginx` foram novamente observados **healthy** em 27/10 com Docker Engine acessível a `andrea.kiew`.
- EP125: overlay **`compose.audit-persistent.yml` local/não rastreado** foi observado operacional em 24/10; persistência de `audit.log`, hash host/contêiner e marcadores de auditoria ponta a ponta já evidenciados em `EP125-F2-0039`, 24/10. **Não tratar overlay como ausente porque o checkout EP126 ou host da aplicação não contém arquivo esperado no local presumido**; verificar *somente a diferença de implementação* quando houver mudança.
- EP126: configurações do Wazuh/Manager e regras **110250–110252** já aplicadas e revalidadas (`EP126-F2-0060` 8/8, Manager HEALTHY). O fluxo sintético **PHP → audit.log → Agent 001 → Manager → regra 110250** foi demonstrado `EP126-F2-0062` (23/10); `EP126-F2-0064` 16 PASS, 0 alertas, 2 inconclusivos. Não pedir novo teste E2E genérico sem alteração no pipeline; retenção/rotatividade permanecem distintas do caminho E2E.
- EP126: inventários prévios já identificaram **12 contêineres** (18/10), e diagnósticos de Bacula/PG e Ferret ocorreram ao longo de 21–24/10; **não inferir que todos continuam íntegros hoje** sem gatilho concreto, mas evitar varredura total redundante.
- 27/10: GitHub `main@f3163bb` após merges `#209` (testes BOLA), `#211` (`composer.lock` dev-only, PHPUnit 13.4.5) e `#210` (gate CI Compose). **Nenhum desses três PRs altera o código de aplicação PHP ou o Compose operacional**, portanto o descompasso Git `4bf7ac6 → f3163bb` **não demanda, por si só, reconstrução nem restart de container**.

### Matriz de DELTAS acionáveis — sem novo inventário geral

| Delta | Classificação | Próxima ação mínima | Gate |
|---|---|---|---|
| `main` remoto f3163bb vs. checkouts EP125/EP126 4bf7ac6 | Fonte Git está atrás, **runtime app não comprovadamente divergente por esses merges** | Preparar fast-forward Git **sem reset/force** após aprovação de change control; preservar artefatos locais não rastreados, especialmente overlay audit; confirmar diff file list antes de aplicar | Janela/autorização + backup/checkpoint + rollback dos checkouts |
| PR #203 com overlay auditoria declarado vs. overlay local já operacional; Wazuh regras já aplicadas | **Alto risco de duplicar/quebrar correção existente** | Comparar **somente** overlay real local vs. PR #203 e metadados de coleta, preferir incorporação do estado válido ao Git; não reimplantar o pipeline já aprovado sem justificativa | Garantir que não há alteração regressiva no runtime e quem é dono da configuração |
| PR #206 e #207 Ferret | Correções propostas em draft; prova offline de 51/51 NÃO é deploy | Tratar como mudança própria após consolidar baseline, reconciliar contra config e patch já aplicado; fazer teste negativo dirigido de UI após implantação, não escanear tudo outra vez | Aprovação/rollback EP126 |
| TLS EP126→EP125 | Erro 20 + CA Lab Root não encontrada no store Python, SAN IP 192.168.6.34 presente | Solicitar certificado público CA aprovado e fingerprint C4:CF:...:59:D4; instalar com suporte e retestar verify0, sem bypass TLS | Validação de autenticidade, change control |
| Twingate | Planejado, não implantado | Especificar grupos/Resources/FQDN/portas e implantar Connector apenas na janela liberada; manter site público público e serviço administrativo realmente privado | Snapshots + autorização professor/suporte |

**Regra explícita de execução:** avançar diretamente para correções/promoções aprovadas. Não repetir listagem de contêineres, inventário de bridges, baseline de memória, enumeração geral de permissões nem diagnóstico TLS até que algum resultado tenha mudado. Os relatórios antigos são evidência, não um motivo para testar tudo novamente. A equipe deve preservar o diário privado, scripts de reversão e controles institucionais, sem supor que o assistente executou comandos na VM.

**Pendências reais de confirmação institucional em 28/10:** snapshots e rollback, acesso da pessoa operadora, cópia autêntica CA Lab Root e autorização de implantação Twingate.


## 18. GA07 / PR203: reconciliação por equivalência, sem reinstalar o pipeline (27/10)

**Correção do fluxo de trabalho:** por decisão da responsável, NÃO executar novos inventários Docker abrangentes. Comparar o estado da EP125/EP126 com o PR #203 a partir dos artefatos e resultados já arquivados em 23–24/10.

### Artefatos já equivalentes/implantados

| Artefato do PR #203 | Situação antes da integração Git | Decisão |
|---|---|---|
| `deploy/dmz/compose.audit-persistent.yml` | **Já materializado na EP125** em `/opt/conectaeduca/deploy/dmz/compose.audit-persistent.yml` (arquivo local não rastreado). SHA-256 runtime **`36469d6694b9eb2e802822946efd788ffb1e97c95170d0f2680731a98699998e`**, blob Git PR #203 **`bfb1abca81b0a5f84e8ccda69c3c2da75294f2a1`**, correspondência comprovada anteriormente. PHP-FPM usa 10 Compose; WAF/Nginx usam os 9 anteriores. | **Preservar byte a byte, não reaplicar/recriar PHP.** Publicar definição canônica no Git apenas após planejamento da colisão arquivo local não rastreado × novo arquivo versionado. |
| Persistência `/var/log/conectaeduca/php-audit/audit.log` | **Ativa e testada** em EP125-F2-0038/0039; bind RW do PHP, modo 0600/UID/GID 82:82, hash host/contêiner equivalente. | Reutilizar evidência, não repetir cutover nem copiar log bruto. |
| Grupo Wazuh `conectaeduca-dmz` e regras 110250–110252 | **Aplicadas anteriormente no Manager EP126**; E2E evento sintético `CE-AUD07-20261023-E2E-02` pela regra 110250 com Agent 001 confirmado em EP126-F2-0062, e revalidações EP126-F2-0064. | Não duplicar `localfile`, não substituir config em produção; incorporar como código-fonte declarado com identificação de origem. |
| Correção `src/Security/AuditLogger.php` | Risco offline de reintroduzir arrays sensíveis sob chave mascarada na `main` anterior; patch+6 testes estavam incluídos no PR #203, ainda não implantados na imagem PHP. | **PR [#212](https://github.com/andrea-kozicki/conectaeduca/pull/212) INTEGRADO na `main`** em commit `b74ea581a0814d86a99b6b455d5569f12fa967e5`, isolando correção sem bloqueá-la por pendências de retenção. 4/4 CI SUCCESS, PHPUnit **138 testes/482 asserções**, `composer audit` sem advisory; **não houve deploy na EP125**. |

### O que de fato continua pendente

1. **Retenção e rotação:** não existe aceite institucional da política, houve bloqueio de `euid/egid` no teste anterior de `logrotate`; confirmar estratégia de inode/offset Wazuh, identidade executora, backup e privacidade. Não declarar operação pós-rotação validada.
2. **PR #203 é documental/configuração em DRAFT**, não mais veículo de aprovação do redaction patch já integrado no #212. A descrição do PR foi atualizada para referir explicitamente as evidências operacionais e as pendências de governança. A única allowlist GA07 do `.gitleaks.toml` foi alinhada ao blob exato já em `main` via PR #209; evitar duplicá-la no merge futuro.
3. **Git checkout da EP125:** `main` anterior `4bf7ac6` × atual `b74ea58`. **NÃO executar `git pull` indiscriminado**, porque a EP125 tem o `compose.audit-persistent.yml` local não rastreado; depois que o PR #203 versionar esse arquivo, o Git pode impedir sobrescrever o untracked mesmo se o conteúdo for idêntico. Uma migração planejada deve preservar hash, ACL, backup, ordem dos 10 overlays e capacidade de rollback; nenhuma migração feita automaticamente.
4. **Implantação da correção de mascaramento:** atualizar imagem PHP apenas na janela autorizada com snapshot/rollback; um merge de código no Git não modifica contêiner existente. Evitar recompilar a imagem inteira simplesmente para alinhar commits de testes/CI.
5. **EP126:** CA pública interna ainda precisa ser autenticada/instalada por operador autorizado (TLS code20); Twingate ainda não implantado. Não bloquear a documentação do pipeline já demonstrado por esse fluxo separado.

**Diff Git confirmado sem novo inventário:** comparação oficial `4bf7ac6...b74ea58` (27 commits, **10 arquivos efetivamente diferentes**, **0 arquivos Compose de runtime modificados**). Alterações restritas a workflow CI, `.gitleaks.toml`, `composer.lock`, documentação PA03/PA05, parser de invariantes, `src/Security/AuditLogger.php` e três arquivos de testes. **A `main` ainda não contém o overlay `compose.audit-persistent.yml`**, pois ele permanece no PR #203 em DRAFT; portanto o descompasso com o overlay local deve ser tratado separadamente da atualização deste lote. O Dockerfile PHP copia `src/` para a imagem no **build**, sem bind de código fonte declarado no `compose.yml` base — um fast-forward do checkout não substitui automaticamente os bytes da imagem já construída. Nenhum fast-forward foi executado nas VMs pelo assistente.

**Status desta reconciliação:** *comparação PR203 × runtime existente = CONCLUÍDA com base nas evidências anteriores*; *correção PHP no Git = CONCLUÍDA via PR #212*; *versionamento total do overlay/Wazuh via PR203 = DRAFT, pendente de decisão de promoção e cuidado com untracked local*; *retensão/rotação = pendente de aprovação e teste controlado*. Nenhum inventário adicional ou mudança operacional foi realizado.
