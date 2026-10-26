# ConectaEduca EC8 — matriz de implantação e reconciliação dos PRs

**Revisão:** 26/10/2026 (BRT). **Janela de suporte solicitada:** quarta, 28/10/2026, 15h — **confirmar disponibilidade/escopo com o suporte**. **Estado desta matriz:** PLANO APROVÁVEL PARA EXECUÇÃO, **não autorização de mudança**. Checkout, VMs, pfSense, tenant Twingate e snapshots não foram alterados para elaborar esta matriz.

## 1. Decisão executiva e fonte de verdade

- **Objetivo do caminho crítico:** ter rede, identidade e certificados validados para ativar **somente os Resources privados autorizados** via Twingate, sob suporte institucional, até a meta de freeze **07/11**. Pentest B **08–14/11**, apresentação **17/11**.
- **Hoje 26/10:** fechar documentos, dependências e status da CI, sem realizar merge/deploy. **Amanhã 27/10 (se VMs online):** executar somente preflight READ-ONLY e reconciliação de estado; alterações com janela/operador/rollback formalizados separadamente. **Quarta 28/10:** tratar P0 com o suporte, instalar/validar o Connector somente se todos os gates forem aprovados.
- **Fonte de verdade de rede:** medições reais e recentes nas VMs + regras atuais pfSense/host; documentação histórica e CI não comprovam runtime.
- **Fonte de verdade de código:** \`main\` para baseline e os PRs abaixo para propostas; **nenhum PR está mesclado** nesta data. PR green individual não prova merge cruzado, versão instalada, autorização ou ausência de regressão.
- **Fonte de verdade de usuário:** a aplicação PHP mantém a regra **\`requireAuth()\`** nas candidaturas. **Dois usuários com MESMO papel** foram criados para reteste **BOLA horizontal** (PR #209). Não incluir restrição nova de papel, não antecipar o Pentest B.
- **Fonte de verdade de Zero Trust:** o Twingate controla acesso a **IP/FQDN e porta**, não rotas HTTP. Público segue pelo WAF HTTPS/443; área \`/admin\` só é privada em rede se ganhar endpoint distinto e rota pública negada. Sem isso, registrar **ZTNA parcial**, sem alegar isolamento administrativo exclusivo.

Referências: [arquitetura Zero Trust](../seguranca/FASE3-ARQUITETURA-ZERO-TRUST-GRUPOS-RECURSOS.md), [matriz de acesso](../seguranca/FASE3-MATRIZ-ACESSO-TWINGATE.md), [handoff ao suporte](GRUPOA-HANDOFF-SUPORTE-20261025.md), [checklist Bacula](GA09-BACULA-CRITERIOS-ACEITE-20261025.md), [runbook Twingate](../seguranca/TWINGATE-RUNBOOK-POS-PENTEST-A.md).

## 2. Reconciliação dos PRs — snapshot verificado em 26/10

Todos: **OPEN / DRAFT / não mesclados**, mergeable individualmente com \`main\`, checks do HEAD **SUCCESS** no GitHub Actions. SHAs abaixo são um snapshot e **exigem nova verificação antes de qualquer merge**.

| PR / SHA abreviado | O que muda | CI no HEAD | Dependência, impacto e recomendação |
|---|---|---|---|
| [#200](https://github.com/andrea-kozicki/conectaeduca/pull/200) \`afa1993\` | Arquitetura ZT, acesso/fluxos GA-08, ferramenta sintética GA-09, duas workflows e documentação | 6/6 SUCCESS | **Fonte do plano**; sem ativação do Connector. Revisão documental e dos controles antes de merge. Não é pré-requisito técnico para iniciar Compose Twingate existente em \`main\`. |
| [#203](https://github.com/andrea-kozicki/conectaeduca/pull/203) \`c72b791\` | GA-07: overlay opt-in audit.log PHP, política Wazuh, redação de arrays sensíveis e testes | 6/6 SUCCESS | **Reconciliar com runtime antes de aplicar**: persistência e evento sintético PHP→Wazuh foram comprovados em 23/10; não repetir deploy como se estivessem ausentes. Pendente retenção, rotação, minimização e restore/recreate autorizado. |
| [#205](https://github.com/andrea-kozicki/conectaeduca/pull/205) \`061a36e\` | Login híbrido v2 (JS + view + testes) | 4/4 SUCCESS | **Não é pré-requisito do Connector.** Mudança em login/MFA, alto risco funcional: homologar separadamente depois de baseline TLS, MFA e snapshot. Prioridade subordinada à decisão acadêmica, não misturar com ativação da rede. |
| [#206](https://github.com/andrea-kozicki/conectaeduca/pull/206) \`02f3a4d\` | Wazuh DLP Ferret LOW/MEDIUM/HIGH case-insensitive; altera regras + CI de integridade | 4/4 SUCCESS | Depende de Manager real: \`wazuh-logtest\`, fallback/quiet rule, histórico/compatibilidade CLI; **validar em conjunto com #207** após último commit. |
| [#207](https://github.com/andrea-kozicki/conectaeduca/pull/207) \`b30734a\` | UI Ferret v5 fail-closed, sanitizador, scripts CLI, políticas de TAR offline e supply chain | 6/6 SUCCESS | Exceção de TAR local aprovada **na CI**, não pelo suporte. Não iniciar sem aprovação institucional, SHA-256 do TAR real, Image ID/RootFS, \`compose config\`, UID/tmpfs e rollback. **Sem implantar junto ao Connector Twingate.** |
| [#209](https://github.com/andrea-kozicki/conectaeduca/pull/209) \`6acc813\` | Contrato offline BOLA para dois usuários do mesmo papel, sem modificar controller/regras funcionais | 4/4 SUCCESS | Revisão/teste podem ser integrados independentemente; os 13 testes são estruturais, não prova HTTP/BD. Não mudar RBAC por papel. |
| [#210](https://github.com/andrea-kozicki/conectaeduca/pull/210) \`3455353\` | Fail-closed de listas inline \`cap_add/cap_drop/security_opt/ports\` no parser de segurança Compose; 17 testes | 4/4 SUCCESS | Prevenção de regressão da PA-03, não correção de VM. Verificar coexistência com o workflow editado por #206. |

### Riscos de integração CRUZADA (não confundir com conflito já confirmado)

1. **\`.gitleaks.toml\`:** modificado nos PRs **#200, #203, #207, #209, #210**. As alterações da allowlist histórica da fixture fictícia GA-07 têm escopo semelhante. Antes do primeiro merge: criar **uma política única** em \`main\`, deduplicar, preservar regra/caminho/literal exatos e reexecutar Gitleaks após cada integração. Não declarar cinco conflitos textuais já ocorridos sem realizar merge simulado.
2. **\`.github/workflows/repository-static-integrity.yml\`:** PRs **#206 e #210** modificam o mesmo arquivo. É necessário compor **ambas** as etapas (classificação DLP + 17 testes Compose), sem sobrescrever a outra, e validar workflow final. Não promover com um dos dois checks silenciosamente ausente.
3. **#206 + #207:** houve **ensaio integrado offline 39/39 PASS** com versões \`#206=02f3a4d\` e \`#207=16dd92e\` (Seção 18 do pré-relatório). O **HEAD atual #207 é \`b30734a\`**, posterior ao ensaio. Logo, **39/39 não atestam a combinação final**. Repetir a suíte de integração conjunta em worktree isolada, com SHAs congelados, depois dos ajustes de código, antes de merge/deploy; manager real e Docker TAR permanecem pendentes.
4. **#200 + #203 + #207:** conjuntos distintos de testes/overlays dependem dos mesmos serviços. Green individual não prova que a ordem efetiva dos overlays Compose EP125/EP126 mantém \`audit.log\`, WAF, CA, tmpfs e porta. Reconciliar \`docker compose config\` com configurações existentes e **não imprimir variáveis secretas**.
5. **#205 com baseline da autenticação:** risco de regressão de login/MFA/CSRF/419 e identidade no Pentest B. Não promover apenas porque CI passou; fazer janela separada ou adiar com aceitação explícita.

### Ordem de revisão Git — **não é ordem automática de merge**

**Lote R0 (repo-only, sem depender das VMs):** revisar #200 (matriz/plano), #209 (BOLA sem mudança da regra de negócio) e #210 (CI Compose), resolver a **sobreposição de .gitleaks.toml** e eventual evolução da \`main\`. Podem permanecer DRAFT até aceite; não bloqueiam início dos gates de Twingate.

**Lote R1 (associado a runtime, conforme gate aprovado):** revisar #203 contra estado existente EP125/126; não forçar atualização se auditoria persistente já operar. Separadamente, revisar #206 + #207 juntos, com teste de integração no novo HEAD e política TAR autorizada.

**Lote R2 (mudança funcional opcional de maior risco):** #205 somente com janela própria e testes reais de login/MFA/WAF. Não misturar a homologação do novo login com a medição do impacto da ZT.

Para qualquer integração futura: comparar \`main\` atualizado, conflito/overlap, testes unitários + estáticos, assinatura do plano de mudança, snapshot e rollback **por componente**, e só então abrir change control de implantação na VM. **Nenhum merge foi autorizado por esta matriz.**

## 3. Matriz de implantação operacional — gates verificáveis

Legenda: **READY-OFFLINE** = documentação/código/teste CI pronto; **PENDENTE-CAMPO** = requer leitura real; **BLOQUEADO-APROVAÇÃO** = não executar sem suporte/professor.

| Ordem / gate | Ativo | Pré-requisito | Ação mínima / responsável | Critério para avançar | Estado em 26/10 |
|---|---|---|---|---|---|
| **G0 — baseline e autorização** | EP125, EP126, pfSense, Git | VMs online, operador, janela, escopo de rede, hashes Pentest A e snapshots identificados | **Suporte:** confirmar IDs, consistência e retenção de snapshots, reversão e privilégios temporários aprovados; **responsável:** preflight sem sudo | Evidência de snapshot/rollback **restaurável por operador**, repositório/versão/contêiner documentados | **BLOQUEADO-CAMPO** (IDs ainda não documentados) |
| **G1 — inventário read-only** | EP125/EP126 | G0 para qualquer ação, leitura sem mudanças pode ocorrer antes com autorização existente | Conferir Git HEAD/working tree, overlay efetivo, imagens, portas, serviços, Wazuh, Bacula, NTP e relógio | Reconciliar *o que já está aplicado* vs DRAFT; não reimplementar PHP 8.5.12/auditoria comprovados anteriormente sem motivo | **PENDENTE-CAMPO** |
| **G2 — TLS, DNS e SAN** | EP126→EP125 WAF e Client | CA legítima e operador de certificados | **Suporte:** diagnosticar verify code **20** (cadeia emissora), DNS \`g20.ciberseg.ep.pucpr.br\`, SAN/nome, CA aprovada e responsável pela renovação | TLS validado **sem** \`-k\`/\`verify=False\`; certificado e hostname/IP efetivos documentados | **BLOQUEADO-SUPORTE** |
| **G3 — segmentação/backends** | pfSense, EP125 WAF, Nginx Docker bridge | Decisão sobre portal público e entrada admin privada | **Professor/suporte:** aprovar direção de acesso, WAF→Nginx e política host/bridge; não bloquear PHP legítimo | Fluxos positivos válidos; tentativas diretas ao upstream de origens indevidas negadas; rollback pronto | **BLOQUEADO-DECISÃO DE REDE**; GA-08 14/14 apenas estático |
| **G4 — pré-requisitos Connector** | EP126 ou host alternativo | G0, G2, saída rede aprovada, identidade/tenant e imagem | **Suporte:** aprovar host/permissões Docker/egress; **responsável acadêmica:** tenant/Client/identidades e tokens fora de Git/chat | Digest/host/egress confirmados, rota até Resource mínimo, relógio/CA, política de tokens/revogação e rollback | **READY-OFFLINE; BLOQUEADO-APROVAÇÃO** |
| **G5 — piloto Twingate** | Connector/Remote Network | G0–G4 aprovados, operador e janela | **Responsável:** configurar uma política/Resource de teste **TCP 443 apenas**, grupo restrito + MFA; **suporte:** mudanças institucionais aprovadas | Connector **Online** no Console, allow com Client, deny de identidade sem grupo, deny portas extras, revogação e logs sanitizados | **NÃO IMPLANTADO** |
| **G6 — gestão realmente privada** | SSH, Wazuh, Bacularis, admin PHP | G3/G5 + listeners/ACLs efetivamente medidos | Criar Resources individuais somente para serviços **comprovados**; admin PHP requer entrada HTTPS **distinta** e bloqueio de \`/admin\` pela rota pública | Testes de Client permitido, negado, sem Client **e rota direta**; não expor OpenBao/DB/Catalog; se admin não isolado, registrar lacuna | **PROPOSTO, NÃO IMPLANTADO** |
| **G7 — remediações operacionais independentes** | GA-06/07/09, Wazuh e Bacula | Janela por serviço, PR aceito, snapshots e plano de fallback | Ferret v5 TAR (se exceção aprovada), Wazuh DLP Manager, auditoria rotação/retenção, Jobs + restore Bacula sintético | Testes reais separados, sem perturbar o piloto Twingate; SHA/evidência e rollback registrados | **CI pronta; operação pendente** |
| **G8 — freeze e Pentest B** | Laboratório integrado | G5/G6 aprovados ou limitações declaradas, G7 no escopo de entrega | Congelar alterações até 07/11; 08–14/11 repetir PA-01..07 comparáveis, **duas contas do mesmo papel para BOLA**, insider + deny/allow | Mesmas origens/URLs/perfis por cenário; evidências com horários/hash, efeitos e limites, sem inventar resultados | **FUTURO** |

**Dependência essencial:** não afirmar isolamento completo porque o Connector está Online. Se o acesso público 443 continuar alcançando a aplicação, documentar **caminho Twingate controlado em paralelo**; para \`/admin\`, isolamento só com ingresso privado distinto e negação no público. A bridge Docker e movimento lateral dentro da VM exigem ACLs próprias; Twingate não os resolve automaticamente.

## 4. O que fazer na terça, 27/10, se as VMs retornarem

**Bloco T1 — leitura autorizada, sem sudo de teste e sem alterar serviços**
1. Capturar nova evidência de **Git SHA**, branch, working tree e diferenças entre checkout EP125/EP126 e \`main\`/PRs; não aplicar \`git pull\`, \`git reset\` ou \`docker compose up\`.
2. Conferir imagem PHP em execução (EP125 anteriormente **8.5.12**), overlays realmente habilitados e onde o \`audit.log\` está persistido, evitando conteúdo do log e segredos.
3. Consultar estado atual Docker/WAF/Nginx/MariaDB/OpenBao/Wazuh/Bacula e NTP, **sem** iniciar restore, executar testes ofensivos ou reconfigurar regras.
4. Validar diagnóstico **read-only** do TLS EP126→EP125, exibindo apenas cadeia/código/subject/SAN sanitizados; se falhar, **não** contornar a CA.
5. Verificar estado de snapshots (identificadores/validade com suporte; não criar/rollback por conta própria), disponibilidade de cliente e pré-requisitos Twingate, **não** criar Resource/Connector.
6. Consolidar resultados por \`PASS/PENDENTE/BLOCK\` com origem, timestamp e SHA; **parar antes de mudanças** se qualquer pré-requisito faltar.

**Bloco T2 — somente se autorização e rollback já estiverem documentalmente aprovados**: selecionar UMA alteração mínima por janela, com antes/depois e teste funcional positivo/negativo. Se não houver autorização, guardar apenas o inventário para quarta. Não promover PRs DRAFT nem trocar regra \`requireAuth\` de candidatura.

**Itens deliberadamente NÃO executados na terça por este plano:** merge em massa; Connector sem G0–G4; firewall/bridge sem suporte; \`docker load/up/pull\` Ferret v5; mudança na conta de teste ou \`sudo\`; backup/restore; eventos Wazuh extras; Pentest B prematuro.

## 5. Reunião de 28/10, 15h — pauta de decisões e divisão do trabalho

| Minutos indicativos | Pergunta/decisão necessária | Quem deve deliberar/agir | Se a resposta for NÃO/PENDENTE |
|---|---|---|---|
| 0–10 | VMs disponíveis? Snapshots EP125/EP126 com IDs e rollback? Quais permissões temporárias e operador? | Suporte institucional | **Não executar mudanças** |
| 10–20 | Qual FQDN, DNS e CA/ZeroSSL? Como corrigir EP126 verify 20 e validar SAN sem bypass? | Suporte + responsável DNS/certificados | Não declarar TLS pronto |
| 20–30 | Qual política pfSense, WAF upstream/bridge e **entrada privada para Admin PHP**? Portal público 443 permanece? | Professor (desenho) + suporte (rede) | Piloto pode medir acesso controlado, mas **não afirmar isolamento completo** |
| 30–40 | Host/egress/digest/token/operador do Connector autorizados? Recurso piloto TCP443, grupos/MFA, Client e retorno? | Responsável Twingate + suporte | Não subir Connector |
| 40–50 | Janela posterior para GA-06/07/09 e Wazuh/Bacula, sem elevar usuário \`teste\`? | Suporte/operador | Manter findings operacionais abertos; priorizar o caminho crítico ZT |

A reunião não precisa concluir todos os Jobs de Bacula nem Ferret UI. **Precisa sair com responsáveis e decisão registrada nos G0–G4.** Evitar converter hipóteses de roteamento/portas de Dashboard/Bacularis em regras definitivas antes de medir.

## 6. Ordem e política de rollback por mudança

| Mudança | Preservar antes | Teste de aceite depois | Rollback se falhar |
|---|---|---|---|
| CA/DNS/TLS | Certificado/chain/trust store e DNS atuais; snapshot/config approved | Verificação completa da CA e SAN desde EP126/Client; HTTPS sem bypass | Restaurar material e resolução aprovados; suporte |
| pfSense/WAF/bridge | Regras e Compose efetivos, caminho público, snapshot | Origem autorizada mantém aplicação; origem interna indevida não atinge Nginx upstream; WAF não bypassado | Restaurar regras do change control; suporte |
| Connector Twingate | Baseline SEM Connector, console/Resource vazio, tokens protegidos | Online + allow/deny/revogação + nenhum serviço interno exposto extra | Desassociar Resource, parar/remover Connector e revogar/rotacionar tokens pelo operador; cuidado com \`restart: unless-stopped\` |
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
