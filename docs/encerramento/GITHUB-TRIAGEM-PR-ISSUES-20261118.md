# ConectaEduca — segunda triagem do GitHub, sem acesso às VMs

- **Data:** 18/11/2026 (America/Sao_Paulo).
- **Base de comparação:** `main` em
  [`7bb0a6432deab379a605dac7467a2be751594828`](https://github.com/andrea-kozicki/conectaeduca/commit/7bb0a6432deab379a605dac7467a2be751594828),
  após o merge da PR #247.
- **Método:** consulta de estado das 21 PRs e seis issues existentes, obtenção das
21 referências `refs/pull/*/head` e comparação de cada branch com seu ancestral
comum à `main`. **Não houve execução de scripts das PRs, merge dessas branches,
acesso às VMs, validação de runtime ou investigação forense de segredos.**

## Resultado e regras de decisão

- **21/21 PRs históricas verificadas como abertas** em 18/11; a condição de
  *draft* de cada PR deve ser confirmada individualmente antes de alterar seu
  estado. O total de **332 entradas de arquivos modificados** representa a soma
  das diferenças por PR, **não 332 arquivos únicos** e nem 332 riscos.
- A triagem textual das **linhas adicionadas** encontrou marcadores de identidade,
  caminhos privados, endereços de laboratório ou padrões associados a credenciais
  em **17 das 21 PRs** com um conjunto delimitado de expressões. O inventário
  anterior, com expressões mais amplas, sinalizou **18**. São **candidatos a
  revisão**, não confirmação de vazamento; uma ocorrência pode ser exemplo,
  fixture de teste, endereço não sensível ou falso positivo.
- **Nenhum PR antigo é recomendado para merge em lote.** Classificar primeiro
  privacidade e sobreposição com os merges #237, #240 e #243–247; mudanças de
  autenticação, redes, segredos e runtime exigem seu próprio aceite.
- A revisão nesta rodada não elimina o risco de **commits anteriores,
  comentários, anexos ou revisões de descrição**. Não reescrever histórico,
  forçar push, excluir branch ou apagar evidência por automatismo.

## Decisão individual recomendada para as 21 PRs

| PR | Entradas de arquivos no diff original | Classe de triagem | Decisão nesta rodada |
| --- | ---: | --- | --- |
| [#235](https://github.com/andrea-kozicki/conectaeduca/pull/235) | 1 | Documentação Pentest B | **Revisar texto e privacidade**; aproveitar apenas conteúdo não duplicado, sem substituir relatório já entregue |
| [#232](https://github.com/andrea-kozicki/conectaeduca/pull/232) | 1 | Documento histórico Fase 3 | **Conferir data e evidências**; considerar citação no histórico, não tratar como situação atual |
| [#230](https://github.com/andrea-kozicki/conectaeduca/pull/230) | 13 | Runtime DMZ / GA-08 | **Bloquear integração operacional** sem inventário EP125, regressões de WAF/PA-05 e rollback autorizado |
| [#229](https://github.com/andrea-kozicki/conectaeduca/pull/229) | 8 | Autorização da aplicação | **Revisão de segurança e testes locais**; não promover regra de ownership/publicação sem contrato e regressões |
| [#228](https://github.com/andrea-kozicki/conectaeduca/pull/228) | 3 | OpenBao / credenciais | **Revisão reservada de política e placeholders**; sem ativar AppRole ou publicar material de acesso |
| [#227](https://github.com/andrea-kozicki/conectaeduca/pull/227) | 6 | Ferret / launchers Fish | **Comparar com #237 e EP126**; Fish atende ao openSUSE pessoal, sem alegar execução na VM Ubuntu |
| [#226](https://github.com/andrea-kozicki/conectaeduca/pull/226) | 3 | Ferret / cutover | **Avaliar sobreposição com #237**; não repetir cutover nem declarar rollback ensaiado |
| [#225](https://github.com/andrea-kozicki/conectaeduca/pull/225) | 2 | Rotação de audit.log | **Manter operacionalmente bloqueada**; retenção, UID/GID e continuidade Wazuh carecem de homologação |
| [#224](https://github.com/andrea-kozicki/conectaeduca/pull/224) | 2 | Sincronização de checkouts | **Não executar nem integrar cegamente** diante de worktrees e arquivos locais conhecidos |
| [#221](https://github.com/andrea-kozicki/conectaeduca/pull/221) | 5 | Inventário EP125/126 | **Comparar utilidade com planos atuais**; revisar caminhos e metadados antes de qualquer reaproveitamento |
| [#219](https://github.com/andrea-kozicki/conectaeduca/pull/219) | 45 | Kit Pentest B | **Revisar código, escopo e licitude das fixtures**; execução histórica não é evidência de reteste novo |
| [#218](https://github.com/andrea-kozicki/conectaeduca/pull/218) | 10 | Planos de novembro | **Arquivar como planejamento histórico** após triagem de dados; não transformar roteiros datados em execução |
| [#217](https://github.com/andrea-kozicki/conectaeduca/pull/217) | 36 | Candidato GA-08/PA-02 | **Revisão extensa de sobreposição com #230** e estado EP125; sem merge de runtime |
| [#215](https://github.com/andrea-kozicki/conectaeduca/pull/215) | 10 | Preflights antigos | **Comparar pressupostos de conector** com documentação posterior; não executar como procedimento atual |
| [#214](https://github.com/andrea-kozicki/conectaeduca/pull/214) | 22 | Twingate / evidências | **Revisar identificadores, endereços e scripts**; eventual integração apenas de documentação sanitizada |
| [#213](https://github.com/andrea-kozicki/conectaeduca/pull/213) | 15 | Conector Twingate DMZ | **Bloquear deploy**; revisar credenciais/variáveis e modelo do conector antes de reaproveitar fonte |
| [#207](https://github.com/andrea-kozicki/conectaeduca/pull/207) | 35 | Ferret UI / fail-closed | **Revisão de compatibilidade V5 e segurança**; testes de UI/E2E pendentes |
| [#206](https://github.com/andrea-kozicki/conectaeduca/pull/206) | 5 | Classificação DLP/Wazuh | **Confrontar fonte com regra observada em 02/11** e #240; aplicação histórica não significa merge |
| [#205](https://github.com/andrea-kozicki/conectaeduca/pull/205) | 9 | Autenticação/MFA | **Alto impacto:** só discutir merge com revisão de downgrade, MFA, sessão e testes negativos |
| [#203](https://github.com/andrea-kozicki/conectaeduca/pull/203) | 14 | Auditoria PHP/Wazuh | **Separar persistência observada de source-only**; rotação/recreate não homologados |
| [#200](https://github.com/andrea-kozicki/conectaeduca/pull/200) | 87 | Arquitetura ZT + código | **Tratar como histórico e propostas misturadas**; 87 entradas impedem merge documental por presunção |

**Alcance da leitura:** contagens verificadas no Git de cada PR, corpo das
issues relevantes e matriz de triagem anterior. As decisões são **pareceres de
governança**, não auditoria linha a linha ou aprovação de publicação de cada
arquivo. Para execução e critérios detalhados, consultar a
[triagem original](../portfolio/PR_TRIAGE.md) e o
[guia de privacidade](../portfolio/PRIVACIDADE-E-PUBLICACAO.md).

## Seis issues abertas: estado observado versus critério de fechamento

| Issue | Estado técnico documental | O que falta para encerrá-la |
| --- | --- | --- |
| [#201 — PHP2Shell](https://github.com/andrea-kozicki/conectaeduca/issues/201) | Issue P0 **aberta**; a descrição registra versões corrigidas nos dois contêineres PHP inspecionados em 24/10 | Inventário residual de outros runtimes, integridade/rollback e regressão funcional. **Não dizer que os dois contêineres continuam vulneráveis** sem nova evidência |
| [#220 — pfSense/Twingate](https://github.com/andrea-kozicki/conectaeduca/issues/220) | Bloqueios interzona SSH e permissões pontuais documentados; acesso ao Dashboard Wazuh via alias e matriz RBAC/MFA ainda com limites | Prova de DNS/identidades/rotas exigiria laboratório; caso contrário, fechar apenas por aceitação explícita de risco documental |
| [#195 — audit.log](https://github.com/andrea-kozicki/conectaeduca/issues/195) | Persistência e ingestão Wazuh E2E sintética **observadas** em outubro | Política de retenção, rotação real, troca de inode/recreate e proveniência da fonte ainda pendentes |
| [#194 — DLP](https://github.com/andrea-kozicki/conectaeduca/issues/194) | Regras aplicadas e testes Wazuh pontuais documentados em 02/11 | Resolver divergência com PRs #206/#207 e avaliar fluxo Ferret V5 completo; não confundir aplicação observada com merge |
| [#196 — Bacula](https://github.com/andrea-kozicki/conectaeduca/issues/196) | Director instável e falha de conexão ao Catalog relatados pelo suporte no contexto do pentest | Causa raiz, estabilidade e restauração real não confirmadas por esta rodada; registrar **NÃO VERIFICÁVEL** se não houver janela |
| [#204 — Nginx bridge](https://github.com/andrea-kozicki/conectaeduca/issues/204) | Porta 8088 **não publicada no host** no teste de 24/10; risco residual de acesso interno pela bridge | Revisar com testes de origem restrita/GA-08 se possível; não afirmar exposição externa |

Não encerrar automaticamente as seis issues: uma issue pode permanecer aberta
para registrar dívida técnica mesmo quando parte de seus controles já foi
demonstrada. O desligamento do laboratório não transforma falha ou teste ausente
em sucesso.

## Ações seguras sem VMs

1. Fazer **revisão humana restrita** dos patches sinalizados; identificar tipo
   de informação, autorização e eventual segredo real **sem copiar valores**
   para a issue pública. Encaminhar revogação de segredo confirmado pelo canal
   institucional, caso exista.
2. Classificar primeiro #235/#232/#218 (documentação), depois #214/#200
   (histórico misturado), e em seguida a sobreposição #226/#227/#206/#203.
3. Manter #205/#229/#228/#213 e todas as mudanças de runtime sob critérios de
   teste/aceite separados. Não usar merge documental para habilitar deploy.
4. Atualizar o [gate de publicação acadêmica](../release/RELEASE-ACADEMICO-CANDIDATO-2026-11-18.md)
   com resultado de privacidade e SHA final **somente depois** das revisões.
5. Registrar a última janela de VM como **EXECUTADA**, **NÃO EXECUTADA** ou
   **NÃO VERIFICÁVEL**, com data, responsável e fonte, sem preencher por suposição.

**Status:** TRIAGEM GIT/ISSUES CONCLUÍDA; REVISÃO CONTEXTUAL DE PRIVACIDADE E
ACEITES DE RUNTIME PENDENTES. Nenhuma PR histórica foi integrada ou encerrada
por esta rodada.
