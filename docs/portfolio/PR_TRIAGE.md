# ConectaEduca — Triagem das PRs históricas em rascunho

**Inventário remoto:** 18/11/2026; descrições revisadas após a integração das PRs #241 e #242.  
**Autora responsável pela decisão final:** Andréa Kozicki.  
**Escopo desta matriz:** revisão documental **sem merge, fechamento, alteração de histórico ou execução em VM**.

**Segunda checagem em 18/11/2026:** as **21 PRs listadas continuavam abertas**
no GitHub. Seus 21 branches foram confrontados com a `main` após o merge
[#247](https://github.com/andrea-kozicki/conectaeduca/pull/247), totalizando
332 entradas de arquivos nos diffs históricos (não arquivos únicos). O
[relatório de triagem e das seis issues abertas](../encerramento/GITHUB-TRIAGEM-PR-ISSUES-20261118.md)
registra a classificação individual, os marcadores que exigem revisão contextual
de privacidade e os limites operacionais. **A verificação do estado `open` não
homologa as PRs nem equivale à revisão humana de todas as linhas.**

**Auditoria individual posterior (18/11):** veja [análise das 23 PRs históricas, com decisão por escopo e comparação completa do `composer.lock`](PR_AUDITORIA_INDIVIDUAL_20261118.md). Registra a atualização isolada PHPMailer da #264, a candidata phpdotenv #265 e os bloqueios operacionais. É uma nova fotografia; **não altera** a contagem e os relatos históricos abaixo.

## Atualização incremental após as integrações de 18/11/2026

**Nova consulta remota:** 20 PRs abertas, todas em *draft*, após integrar as alterações de PA-05. A contagem histórica de 21 PRs acima representa **outro corte do mesmo dia** e foi mantida como registro; não deve ser lida como estado atual permanente.

| Referência | Situação verificada nesta atualização | Limite / encaminhamento |
| --- | --- | --- |
| [#229](https://github.com/andrea-kozicki/conectaeduca/pull/229) | **MERGED na `main`**: autorização por publicação e ownership com correção idempotente da #251 | **Código versionado ≠ deploy na EP125**; MariaDB sintético e CI não homologam o runtime |
| [#251](https://github.com/andrea-kozicki/conectaeduca/pull/251) e [#255](https://github.com/andrea-kozicki/conectaeduca/pull/255) | **MERGED em branches intermediárias**, depois incluídas no merge de #229 | Script/runbook de cutover antigos retirados da árvore operacional; hashes e links preservados em `docs/fase3/PA05-DEP02-HISTORICO-NAO-EXECUTAR.md`; não executar instalador antigo |
| [#256](https://github.com/andrea-kozicki/conectaeduca/pull/256) | **MERGED na `main`**: gatilho de regressão PA-05 em `push` relevante da `main` | O arquivo do workflow está na branch principal; cada execução deve ser verificada separadamente, sem inferir implantação |
| [#235](https://github.com/andrea-kozicki/conectaeduca/pull/235) ← [#257](https://github.com/andrea-kozicki/conectaeduca/pull/257) | #257 incorporada **apenas à branch de #235**; #235 permanece **DRAFT** | Documento de 10–12/11 anterior à versão final; IPs generalizados na versão atual, mas **não eliminados dos commits históricos**; publicação institucional/privacidade pendente |
| [#232](https://github.com/andrea-kozicki/conectaeduca/pull/232) ← [#258](https://github.com/andrea-kozicki/conectaeduca/pull/258) | #258 incorporada **apenas à branch de #232**; #232 permanece **DRAFT** | Relato histórico de deploy PA-05 em 08/11 diverge da proveniência posterior: `PENDENTE_DE_CONCILIACAO`. Não tomar o relato como prova de imagem implantada nem afirmar o contrário sem evidências primárias |
| [#205](https://github.com/andrea-kozicki/conectaeduca/pull/205) e [#200](https://github.com/andrea-kozicki/conectaeduca/pull/200) | **DRAFT**; #205 depende de homologação WAF/MFA; #200 segue sem merge textual pelo Dockerfile | Não promover o login a produção sem testes autorizados; não resolver o digest da imagem PHP por tentativa ou alterar Dockerfile sem decisão específica |

**Governança:** nenhum dos merges documentais #257/#258 incorporou os relatos completos à `main`. Nenhum documento novo dispensa o [guia de privacidade](PRIVACIDADE-E-PUBLICACAO.md) e o [gate pré-publicação](../release/GATE-PREPUBLICACAO-ACADEMICA-2026-11-18.md). Versões de branches antigas e o histórico Git podem continuar públicos mesmo após uma sanitização na ponta. **Nenhuma VM ou release final foi alterado por esta revisão.**

As PRs abaixo permaneciam abertas em modo **draft** na consulta inicial. Algumas representam propostas de implantação, outras preservam evidências ou materiais superados por merges posteriores. Uma PR em draft não prova implantação, teste completo ou aprovação institucional.

| PR | Tema | Encaminhamento proposto | Validação obrigatória antes de qualquer decisão |
| --- | --- | --- | --- |
| [#235](https://github.com/andrea-kozicki/conectaeduca/pull/235) | Relato Pentest B | **Revisão editorial / possível integração documental** | Sanitização de evidências, coerência com relatório final e limites PA-01..07 |
| [#232](https://github.com/andrea-kozicki/conectaeduca/pull/232) | Consolidado Fase 3 | **Consolidação histórica** | Datas, resultados observados vs. pretendidos e links a PRs integradas |
| [#230](https://github.com/andrea-kozicki/conectaeduca/pull/230) | Socket HTTP GA-08/PA-02 | **Manter bloqueada para revisão de runtime** | Paridade EP125, imagem PA-05, testes WAF, rollback e permissões institucionais |
| [#229](https://github.com/andrea-kozicki/conectaeduca/pull/229) | Autorização UPDATE PA-05 | **Revisão de segurança de aplicação** | Testes negativos de ownership/publicação, efeitos sobre autorização e migrations |
| [#228](https://github.com/andrea-kozicki/conectaeduca/pull/228) | OpenBao AppRole | **Revisão, sem implantação presumida** | Políticas KV2, identidades limitadas, eventual exposição de credenciais |
| [#227](https://github.com/andrea-kozicki/conectaeduca/pull/227) | Launchers Ferret CLI | **Comparar com #237 antes de integrar** | Diffs de Fish/Bash, compatibilidade SUSE, override V5 e ausência de conflitos |
| [#226](https://github.com/andrea-kozicki/conectaeduca/pull/226) | Cutover Ferret V5 | **Analisar sobreposição com #237** | Quais ações já executadas, artefatos redundantes e rollback não ensaiado |
| [#225](https://github.com/andrea-kozicki/conectaeduca/pull/225) | Logrotate auditd EP125 | **Revisão operacional** | Configuração instalada, simulação segura, permissões e efeito sobre coleta Wazuh |
| [#224](https://github.com/andrea-kozicki/conectaeduca/pull/224) | Sincronização de checkouts | **Não aplicar automaticamente** | Existência de alterações locais, mudanças na `main`, política de backup e drift atual |
| [#221](https://github.com/andrea-kozicki/conectaeduca/pull/221) | Inventário EP125/126 | **Reaproveitar metodologia, sem executar cegamente** | Atualizar base de commits, filtrar nomes institucionais e dados privados |
| [#219](https://github.com/andrea-kozicki/conectaeduca/pull/219) | Kit Pentest B | **Revisão de código/testes** | Execução segura, scripts sem privilégio, evidência sanitizada, código de terceiros |
| [#218](https://github.com/andrea-kozicki/conectaeduca/pull/218) | Pacote Fase 3 | **Consolidação documental histórica** | Instruções de janela antiga não devem ser reproduzidas como plano atual |
| [#217](https://github.com/andrea-kozicki/conectaeduca/pull/217) | Candidato dual socket | **Comparar com GA-08 da EP125** | Source/runtime, rollback, compatibilidade PA-05 e material sensível |
| [#215](https://github.com/andrea-kozicki/conectaeduca/pull/215) | Kits de preflight | **Revisão de reutilização** | Semântica read-only, comandos que exigem sudo e links obsoletos |
| [#214](https://github.com/andrea-kozicki/conectaeduca/pull/214) | Evidências Twingate | **Revisão editorial / possível integração documental** | Remover identificadores de contas, sem alegar MFA/RBAC E2E concluído |
| [#213](https://github.com/andrea-kozicki/conectaeduca/pull/213) | Conector Twingate DMZ | **Revisar fonte contra runtime conhecido** | Identidade do conector, tokens nunca no Git, ausência de deploy por merge |
| [#207](https://github.com/andrea-kozicki/conectaeduca/pull/207) | Ferret UI/fail-closed | **Revisão técnica; reteste pendente** | Compatibilidade com V5, cadeia de eventos e comportamento de erro |
| [#206](https://github.com/andrea-kozicki/conectaeduca/pull/206) | Severidades DLP | **Revisão de integração Wazuh** | Testes LOW/MEDIUM/HIGH, regras efetivas e telemetria minimizada |
| [#205](https://github.com/andrea-kozicki/conectaeduca/pull/205) | Login híbrido v2 | **Revisão de risco elevada; não implantar sem teste** | MFA, regressões de autenticação, proteção contra downgrade e casos negativos |
| [#203](https://github.com/andrea-kozicki/conectaeduca/pull/203) | Persistência audit.log | **Revisão de operação/privacidade** | Coleta real, persistência, proteção de logs e conflitos com V6 Wazuh |
| [#200](https://github.com/andrea-kozicki/conectaeduca/pull/200) | Arquitetura Zero Trust proposta | **Manter como histórico ou integrar com ressalvas** | Diferenciar projeto pretendido, configuração observada e testes concluídos |

## Conciliação Ferret/Wazuh — revisão de 18/11

**Atualização do mesmo dia (posterior à #261):** a [PR #262](https://github.com/andrea-kozicki/conectaeduca/pull/262) integrou **somente** os patches Ferret UI V4/V5, os mocks Node e o gate reprodutível de origem à `main` (merge `2e0f7f356edc9c0fe1f59b04814986134d84c797`). O gate verificou o upstream fixado e **20/20 + 26/26** testes sintéticos, além de 7/7 workflows; não houve Dockerfile, Containerfile, Compose, deploy nem acesso à EP126. A #207 permanece DRAFT para artefatos não mesclados e verificação de UI no runtime.

A [reconciliação de código e PRs Ferret/Wazuh](FERRET-WAZUH-PR-RECONCILIACAO-20261118.md) encontrou duplicidades confirmadas por Git blob, sem afirmar equivalência operacional: regras DLP LOW/MEDIUM/HIGH da **#206** já na `main`; o Bash Ferret da **#227** já integrado pela **#237**; e persistência Compose + `AuditLogger` da **#203** já existentes. A **#260** incluiu testes offline DLP/Wazuh na `main`, **não** um deploy. Os patches UI **V4/V5 e seus mocks** foram isolados e integrados pela #262 (fonte/testes somente); permanecem em análise a implantação/UI operacional e os demais artefatos da #207, o Fish/instalador antigo da #227, o cutover #226, artefatos adicionais da #203 e o logrotate #225. Nenhuma VM foi acessada nesta conciliação.

## Alertas de privacidade no histórico público

Uma segunda triagem das **21 descrições de PR** encontrou marcadores de conta/caminho institucional em **oito descrições** e referências a endereços privados em **cinco descrições**, com sobreposição; o total foi de **11 PRs distintas**. Em 18/11/2026, essas **11 descrições foram anonimizadas pontualmente**, preservando o conteúdo técnico sempre que possível. Uma nova leitura das 21 descrições abertas não encontrou os marcadores específicos tratados.

O exame adicional dos **patches de 332 entradas de arquivos** identificou ocorrências de identificadores, endereçamento e padrões que exigem revisão contextual em **18 PRs**. Trata-se de uma **triagem por padrões, não de 18 vazamentos ou vulnerabilidades confirmadas**. Um marcador inicial de chave privada na PR #205 era parte de uma verificação negativa do teste, não evidência de uma chave publicada.

**Limite essencial:** editar uma descrição **não modifica os patches, commits, comentários, anexos ou versões anteriores** da PR. Seu histórico público ainda exige revisão e autorização específicas. Não fazer `force-push`, reescrita de histórico ou fechamento em massa para tentar apagar conteúdo: isso pode comprometer rastreabilidade e evidências, sem garantir a eliminação de cópias anteriores.

O procedimento de revisão e os critérios de divulgação estão no [guia de privacidade e publicação](PRIVACIDADE-E-PUBLICACAO.md). O relatório de triagem detalhada foi entregue separadamente à autora, sem publicar valores de contas, endereços ou segredos.

## Ordem sugerida

1. **Privacidade:** descrições atuais anonimizadas; revisar individualmente patches, commits, anexos e comentários antes de divulgação adicional ou merge.
2. **Documentação:** analisar #235, #232, #218, #214 e #200, mantendo uma narrativa histórica única e datada.
3. **Sobreposição:** comparar #226/#227/#207 com #237 (Ferret) e #203/#206 com #240 (Wazuh), evitando merges redundantes.
4. **Mudanças operacionais:** manter #230/#217/#225/#224/#213 em revisão até o encerramento/documentação da infraestrutura.
5. **Aplicação e testes:** revisar #229/#228/#205/#219 com casos positivos e negativos, CI e avaliação de autorização.

Esta lista é **proposta de triagem baseada nos títulos, descrições e no estado conhecido da infraestrutura**. A decisão sobre fechar, converter, atualizar ou integrar cada PR depende de inspeção do diff, da autora e das evidências atuais; não houve alteração automática das PRs listadas.
