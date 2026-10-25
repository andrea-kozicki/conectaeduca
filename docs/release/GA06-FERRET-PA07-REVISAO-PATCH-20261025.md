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


## Homologação de navegador — v4 em 25/10/2026

**Ambiente:** openSUSE pessoal `opensuse-andrea`, Ferret Scan v2.4.3 commit `a5156d19` com patch v4; binário construído localmente com Go 1.26.10 em Podman, SHA-256 `95ed3f1666e715e3c062fda7e86036c8c56eec120388f10b89c64f23cae66216`; servidor web somente em `127.0.0.1:18089`, sem modificar EP125/EP126. Relatórios do operador: `GA06_TESTES_NODE.txt` com **20 testes PASS / 0 FAIL**, `GA06_RESULTADO.txt` com `PATCH_APLICAVEL=SIM`, `NODE_SYNTAX=PASS`.

**Cadeia de evidência do Firefox:**
- `ga06-teste-limpo.txt` enviado por formulário multipart `files`, acompanhado de `confidence=all`, `checks=all`; conteúdo totalmente fictício. `POST /scan` respondeu **HTTP 200**, `success:true`, `results:[]`. Isso comprova upload e resposta válida sem achados **reportados**, não detecção exaustiva universal.
- Interceptor `window.fetch` **somente na página do navegador local** devolveu um HTTP 403 sintético para `/scan`; o resultado mostrou mensagem temporária de erro com marcador `GA06_TESTE_SINTETICO_HTTP_403` e aviso persistente `Scan inconclusive: 0/1 files succeeded; 1 request(s) failed`. Passados os cinco segundos do alerta transitório, o banner inconclusivo permaneceu. **Não é evidência de HTTP 403 efetivo do servidor/EP126**.
- Após **recarregar a página** para desativar a interceptação, repetiu-se a requisição `POST /scan`, com **HTTP 200 / `success:true` / `results:[]`**, nas imagens do Firefox fornecidas em 25/10 por volta de 20h16 BRT. **Aprova recuperação após recarga**, não prova recuperação sem refresh nem reidentifica, sozinha, o conteúdo do novo payload.
- A imagem intermediária após recarga, mostrando painel com `Total Findings: 0` e ausência de warning, **não deve ser apresentada como prova independente de nova varredura**; esta prova somente apareceu com a captura da aba Rede/Resposta posterior.

**Conclusão delimitada:** tratamento da falha sintética, banner persistente e fluxo de varredura limpa v4 **aprovados localmente**. Risco residual de UX: painel de resultados oferece `Export Results` e mostra `Total Findings: 0` mesmo se `/scan` falhar — poderia confundir observador; exportação parcial com achados merece bloqueio. Não declarar PA-07 resolvida na EP126 nem promover PR até aceite dos controles.

## Candidata v5 — estado e exportação *fail-closed* (não aprovada ainda)

Para resolver o problema adicional de UX, foram criados **sem alterar a v4**:
- `deploy/interna/ferret/patches/ferret_pa07_v5_on_v4.patch`: **delta** que deve ser aplicado sobre o checkout contendo a v4, nunca isoladamente sobre o upstream 2.4.3; verificadas 5 seções de alteração por reconstrução textual exata do arquivo esperado.
- `tests/js/ferret-pa07-v5.test.cjs`: 26 cenários Node com mock DOM, **a executar em v5**; não confundir arquivo criado com 26 testes aprovados.
- `scripts/evidencias/GA06_FERRET_V5_OPEN_SUSE_TESTE.fish`: preserva a v4, cria cópia v5 local, confere SHA1 dos arquivos versionados, executa verificação de sintaxe/testes e, se tudo passar, compila com Podman/Go 1.26. Sem servidor ou deploy automático.

**Comportamento esperado:** bandeira permanente **COMPLETED** ou **INCONCLUSIVE** junto às estatísticas; quantidade de respostas aceitas, falhas e achados; botão/seleção de exportação desabilitados se inconclusivo ou sem achados; guarda real dentro de `exportResults()` impedindo exportação programática em análise incompleta. Registrar como **proposta** até evidências de execução, revisão de segurança, verificação visual e decisão de rollback/change control.


## Execução verificada da candidata v5 — 25/10/2026

**Origem do registro:** operadora anexou `GA06_V5_RESULTADO.txt` e `GA06_V5_TESTES.txt` gerados no openSUSE pessoal. Evidências textuais recebidas e conferidas em 25/10.

- `GA06_V5=VALIDACAO_LOCAL_APROVADA`; o arquivo de testes reporta **26 testes executados, 26 PASS, 0 FAIL, 0 skipped**, duração ~331,56 ms. Inclui os seis cenários v5: estado `INCONCLUSIVE` no painel e bloqueio de export; scan válido sem achados; scan parcialmente falho com achados; sinalização `incomplete` do backend; scan válido com achados; e nova análise sem recarga removendo estado anterior.
- `BUILD_GO_V5=PASS`; binário local: `/home/andrea/GA06-Ferret-v5-jOvXM4fP/out/ferret-scan-v5`, SHA-256 `98dcf3cdb196193faabd5f060c4722d2c4fb8f5be90ac8a5c95fed438edb37ee`.
- `PATCH_V4_PRESERVADO=SIM`; `DEPLOY_EP126=NAO_REALIZADO`; `TESTE_FIREFOX_V5=PENDENTE`.

**Interpretação:** o pacote v5 foi aplicado a checkout local isolado, passou nos testes automatizados e compilou. **A homologação visual no Firefox, a decisão sobre fluxo de exportação com dados reais/sintéticos completos, a revisão da imagem e a implantação na EP126 não ocorreram.** Manter PR #207 DRAFT até revisão/aceite e change control. As capturas da v4 continuam válidas somente para a v4; não reutilizá-las como prova visual da v5.
