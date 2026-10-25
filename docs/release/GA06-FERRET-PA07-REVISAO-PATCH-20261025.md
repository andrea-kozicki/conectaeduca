# GA-06 — Revisão do patch de feedback inconclusivo Ferret Scan (PA-07-DLP-01)

**Data:** 25/10/2026 • **Status:** CANDIDATO PRESERVADO / EM REVISÃO, **NÃO PRONTO PARA DEPLOY**  
**Origem:** `GA06_FERRET_REVIEW_20261025T122609.zip` entregue pela responsável acadêmica; SHA-256 ZIP `fbe694129f46ac856cd6549fe613a032270b6ef6527d6f86b3084dd4180be9c7`; relatório interno `GA06_RESULTADO.txt`.  
**Patch original:** `deploy/interna/ferret/patches/ferret_pa07_v3.patch` • SHA-256 `de41f15fcabdcab638e0a78de1c45dfcfabbec5efa94d6a95c4325f8068aca76`. Não reformular bytes do patch histórico.

## Diagnóstico original e escopo preciso

Na campanha PA-07, a interface da versão Ferret Scan 2.4.3 mostrou a mensagem positiva *No sensitive data found* mesmo após a requisição de varredura HTTP 403. O código upstream em `internal/web/assets/app.js`, tag `v2.4.3`, commit `a5156d1950df19276e6cfd8335603d73187a3841`, chama `displayResults()` após a captura de erros de `scanSingleFile`; assim, `currentResults=[]` pode ser tratado equivocadamente como varredura limpa.

**O patch v3 entregue**, preparado sobre essa tag, instrumenta `window.scanCoverage` por requisições, incrementa falhas no `catch` e evita o alerta positivo *clean* quando há falhas ou `incompleteReasons`. Os **9/9 testes Node com mocks** realizados em **24/10 no openSUSE** foram aprovados no escopo: fila vazia, HTTP 403, HTTP 500, timeout, `success:false`, parcial+403, incompleto, varredura limpa, varredura com achados. O TXT do ZIP informa expressamente **TESTES_NESTA_EXECUCAO=NAO_EXECUTADOS** e **DEPLOY_EP126=NAO_REALIZADO**. Esses testes não equivalem à execução do navegador nem demonstram controle de exfiltração.

## Revisão de 25/10 — barreiras de aceite detectadas

**B1 • Aviso não persistente [BLOQUEADOR].** No upstream 2.4.3, `showAlert()` executa `setTimeout(() => alert.remove(), 5000)` **inclusive para warning**. O v3 continua usando `showAlert(..., 'warning')` no resultado inconclusivo. A mensagem desaparece após ~5 s; não é suficiente para assegurar que uma falha permaneça visível ao examinador na tabela de resultados. Ajustar o código para um status persistente `INCONCLUSIVO` vinculado ao resultado atual, com semântica visual e acessibilidade (`role=alert`/`aria-live`), removendo-o **somente** ao iniciar novo scan ou navegação controlada.

**B2 • Resposta malformada [BLOQUEADOR DE ROBUSTEZ].** O upstream verifica `data.success` mas retorna `data.results || []`. Se `success:true` vier acompanhado de `results` ausente/nulo ou não-array, poderá haver contagem de sucesso e apresentação de *clean* indevido. A adaptação deve exigir `Array.isArray(data.results)` antes de contar `succeeded`; caso contrário, marcar como falha/inconclusivo. Verificar contrato real da API para resultado vazio válido (`results: []`).

**B3 • Integração/implantação [BLOQUEADOR].** O ConectaEduca fixa a imagem `public.ecr.aws/awslabs/ferret-scan:2.4.3@sha256:7a1b3605…` em `deploy/interna/ferret/compose.yml`. O `app.js` é incorporado ao **binário Go** (declaração upstream), portanto um patch textual versionado em outro repositório não altera a interface da EP126. Exige branch upstream/fork aprovado, build reproduzível de binário/imagem, digest próprio verificado e **plano de rollback para o digest anterior**. Não editar contêiner scratch em execução, não bind-mountar JS como suposta substituição do binário.

**B4 • Teste de integração [PENDENTE].** Validar no navegador/homologação, sem dados reais: HTTP 403, 500, timeout, erro JSON, `success:false`, `success:true` com `results` malformado, incompleto, parcial com achados, sem achados válido, achados válidos, 0 arquivos, duas execuções consecutivas e permanência do aviso depois de >5 s. Distinguir estado `INCONCLUSIVO` de `CONCLUÍDO COM ACHADOS` / `CONCLUÍDO SEM ACHADOS`; nunca usar success verde para execução incompleta.

## Fluxo proposto sem alterar EP125/EP126

1. **Preservar v3 imutável** e SHA-256. Preparar proposta **v4** separadamente para B1/B2, com regressões locais por Node sem chamadas de rede; comparar upstream 2.4.3 conhecido.
2. Verificar assinatura/supply chain da origem e licença Apache-2.0 upstream; manter atribuição e termos exigidos.
3. Homologar com build isolado/reproduzível, varreduras 100% sintéticas e teste de UI real com status persistente.
4. Submeter nova imagem/digest e rollback a revisão e change control do laboratório. Até lá, **não alterar** o `compose.yml` de produção, imagem em execução, Wazuh nem serviço Ferret.
5. Somente após autorização: aplicar versão em janela, comparar antes/depois e registrar prova sanitizada. Falha ou regressão → rollback pela imagem pinned anterior, sem perder estado/relatórios de auditoria.

**Relacionamentos:** PA-07-DLP-01 = UI de varredura. **NÃO confundir** com issue #194 / PR #206 (regras de confiança LOW/MEDIUM/HIGH no Wazuh). Pentest B e ensaios de egress são verificações separadas, pós-Twingate e pós-autorização.

## Critério objetivo para tirar do Draft

- [ ] B1 aviso persistente implementado e verificado após 5 segundos;
- [ ] B2 `data.results` tipado e erro malformado inconclusivo;
- [ ] testes automatizados e teste de navegador/homologação documentados;
- [ ] build de imagem isolada reproduzível, assinatura/versão/digest e rollback definidos;
- [ ] revisão, autorização institucional e janela de implantação aprovadas;
- [ ] nenhuma indicação de DLP preventivo ou de exfiltração bloqueada baseada apenas no resultado da UI.

**Estado conclusivo do GA-06 em 25/10:** patch histórico v3 **íntegro e rastreável**, lógica de classificação básica melhorada; B1/B2/B3 **não encerrados**. PR aberto exclusivamente para controle de mudanças e revisão.

## Atualização técnica v4 — 25/10/2026

**Nova proposta repo-only:** `deploy/interna/ferret/patches/ferret_pa07_v4.patch` (gerada por comparação direta com o `app.js` oficial da revisão `a5156d19`, oito âncoras originais verificadas como únicas). O patch **v3 permanece arquivado, sem alterações**.

**Comportamento da v4:** uma falha de request, cobertura incompleta, resposta `success:false`, JSON inválido ou `success:true` sem `results` em formato array gera status `Scan inconclusive`, persistentemente inserido na região de alertas com `role=alert`, `aria-live=assertive` e sem temporizador. O status anterior é removido antes de uma nova varredura; sucesso efetivo com array vazio ou achados mantém sua mensagem normal. Erros inesperados na renderização acionam o status persistente no catch de submit.

**Validação isolada do pacote 25/10:** `git apply --check` e `git apply` sobre um recorte controlado do upstream no workspace isolado; `node --check` aprovou; `node --test` aprovou **20 de 20** casos Node com mock DOM/fetch, incluindo cronômetro simulado e duas varreduras consecutivas. O conteúdo do patch v4 versionado foi **regenerado a partir da fonte GitHub oficial**; sua formatação contextual pode diferir do artefato de teste local, embora as oito transformações semânticas sejam equivalentes. **Não houve** build do binário Go, teste de aplicação completa no navegador, integração real ou implantação EP126; não interpretar os 20 mocks como fechamento operacional.

**Pacote de auditoria local:** `ConectaEduca_GA06_Ferret_v4_Candidato_Testes_20261025.zip` contém gerador e patch v4 de ensaio, 20 testes, fragmento de fixture e `GA06_RESULTADO_V4.txt`. SHA-256 do ZIP: `e4b7bc6f8f3efbfb12e758097f5869aff2221c4f10b7c9bc902035090ee3fe47`.

**Próximo gate:** validar `git apply --check` do patch v4 do PR contra checkout *completo* e limpo do Ferret 2.4.3; rodar o teste Node diretamente sobre esse checkout patchado; executar testes funcionais reais/Go em homologação, revisar a construção da imagem com digest próprio e obter autorização de rollout. Não promover o PR para Ready nem alterar a VM neste momento.
