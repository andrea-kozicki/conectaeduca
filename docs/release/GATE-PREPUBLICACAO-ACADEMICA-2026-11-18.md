# ConectaEduca — gate pré-publicação do arquivo acadêmico

**Data do levantamento:** 18/11/2026 (America/Sao_Paulo).
**Tipo de entrega:** repositório-fonte, documentação, testes estáticos e
infográficos. **Sem imagem das VMs, dados operacionais ou homologação de
infraestrutura.**

## O que já é preservável no Git

| Elemento | Evidência que pode ser consultada sem VM | Limite |
| --- | --- | --- |
| Aplicação, testes e workflows | Arquivos versionados e execuções de CI por commit | Não reproduz chaves, dados ou configurações reais de runtime |
| Arquitetura e narrativa técnica | READMEs, diagramas PNG/SVG e documentação de decisões | Diagramas são lógicos, não captura de topologia de novembro |
| Pentest A e B | Matrizes de cobertura e evidências públicas sanitizadas | Metodologias e identidades nem sempre equivalentes; sem percentual causal de redução de risco |
| Ferret V5 e Wazuh V6 | PRs #237/#240, fonte com proveniência, verificadores estáticos | Source-only por PR; não prova novo deploy, rollback ou E2E total |
| Encerramento e autoria individual | PRs #243–#248, [histórico](../../CHANGELOG.md), [citação](../../CITATION.cff) | Não atribui autoria dos componentes de terceiros nem custódia das VMs |
| Inventário GitHub | [Triagem de 21 PRs e seis issues operacionais](../encerramento/GITHUB-TRIAGEM-PR-ISSUES-20261118.md) | Revisão por padrões não libera os patches históricos para publicação adicional |

## Matriz de autorização e prontidão

| Gate | Situação em 18/11 | Próxima evidência ou decisão |
| --- | --- | --- |
| Autoria, citação, infográficos e documentação principal | **DOCUMENTADOS** | Conferir links e metadados no commit final |
| Testes offline Wazuh/Compose/pfSense/YAML/XML | **PASS no corte de revisão #247** | Reexecutar no SHA final; `runtime=NOT_TESTED` |
| PRs #243–248 integradas | **CONFIRMADAS** | Novos merges alteram o SHA de referência |
| Classificação das 21 PRs antigas | **TRIAGEM DOCUMENTAL FEITA** | Revisão contextual dos patches, comentários e anexos ainda pendente |
| Riscos das seis issues operacionais | **CLASSIFICADOS, NÃO HOMOLOGADOS** | Decisão de aceitar/documentar limites ou executar testes autorizados |
| Publicabilidade de todo o histórico e dos assets | **PENDENTE** | Aprovação de privacidade/custódia; não interpretar ausência de achado em Gitleaks como liberação jurídica |
| Licença de redistribuição do código autoral | **NÃO DEFINIDA** | Autora decide direitos e licença compatíveis com terceiros/instituição |
| Estado final EP125/EP126 | **ÚLTIMA JANELA NÃO COMPROVADA NESTA RODADA** | Inventariar com autorização ou marcar `NÃO VERIFICÁVEL` após desligamento |
| Tag e GitHub Release específicos de novembro | **NÃO CRIADOS** | Selecionar SHA, aprovar nome e publicar apenas após os gates acima |

### Tratamento correto das issues

- [#201 — PHP2Shell](https://github.com/andrea-kozicki/conectaeduca/issues/201):
  registrar que duas superfícies PHP foram observadas com versões corrigidas
  em outubro; a issue segue aberta para inventário residual, integridade,
  rollback e regressões. Evitar afirmar que o P0 inicial está integralmente
  vulnerável **ou** totalmente homologado.
- [#195 — audit.log](https://github.com/andrea-kozicki/conectaeduca/issues/195)
  e [#194 — Ferret/Wazuh](https://github.com/andrea-kozicki/conectaeduca/issues/194):
  preservar os testes parciais positivos e distinguir correção observada de
  integração da fonte na `main`.
- [#196 — Bacula](https://github.com/andrea-kozicki/conectaeduca/issues/196),
  [#204 — bridge Nginx](https://github.com/andrea-kozicki/conectaeduca/issues/204)
  e [#220 — pfSense/Twingate](https://github.com/andrea-kozicki/conectaeduca/issues/220):
  manter limites de diagnóstico, teste de origem e RBAC/MFA documentados.

## Procedimento para selecionar o SHA futuro

Executar **somente em clone de revisão autorizado**, depois de integrar os
PRs documentais aprovados. Estes comandos são de leitura e não geram release:

```bash
git fetch origin main --tags
git status --short --branch
git rev-parse origin/main
git log -1 --format='%H %cs %s' origin/main
git tag --list 'v2026.11-ec8-archive-rc1'

python3 scripts/evidencias/pa06_validar_80710_v6.py
python3 scripts/evidencias/checkpoint_compose_security_invariants.py --self-test
python3 scripts/evidencias/pfsense_wazuh_decoder_regression.py --self-test
```

Para validação YAML/XML e respectivos 19 testes unitários, seguir a
[documentação reproduzível](../qualidade/VALIDACAO-CONFIGURACOES-OFFLINE.md)
com `PyYAML==6.0.3`. O resultado anterior foi
`CONFIG_OFFLINE=PASS yaml=55 xml=12 runtime=NOT_TESTED` no contexto do PR #247;
**não é um novo teste do SHA futuro**. Conferir também Gitleaks, Semgrep,
PHPUnit, Snyk e integridade estática nas ações/checagens desse corte.

O SHA final deve ser o **commit exato** da `main` depois das integrações
aprovadas, jamais uma referência móvel como `latest`. Se `main` avançar após
o inventário, repetir verificações ou descartar a alegação de corte final.

## Conteúdo e publicação

**Nome sugerido, sujeito a aprovação:** `v2026.11-ec8-archive-rc1`. Antes de
criar qualquer tag, verificar que esse nome não existe e que aponta ao SHA
correto. Os nomes históricos `FREEZE-*` e outras tags anteriores **não são
substitutos** do arquivo acadêmico de novembro.

**Incluir apenas:** código versionado liberado, READMEs, `CITATION.cff`,
`CHANGELOG.md`, diagramas públicos, testes offline e os documentos de
limitações. Um release do GitHub referencia o repositório; **não** adicionar
imagens de disco, TARs de contêiner, snapshots, arquivos `.env`, segredos,
registros com usuários reais ou backups da instituição.

**Antes de liberar publicamente:** verificar o [guia de privacidade](../portfolio/PRIVACIDADE-E-PUBLICACAO.md),
a [triagem das PRs antigas](../portfolio/PR_TRIAGE.md) e a
[issue central de acompanhamento #249](https://github.com/andrea-kozicki/conectaeduca/issues/249).
O fato de os branches antigos continuarem públicos e de alguns patches terem
marcadores **não autoriza** reproduzi-los na descrição do release.

**Direitos autorais:** `CITATION.cff` informa como citar. Uma futura licença
de reutilização é decisão separada da autora; verificar compatibilidade com
material institucional e componentes de terceiros antes de escolher qualquer
modelo. Na ausência de licença explícita, não presumir concessão de direitos
de reutilização.

**Decisão atual:** **NÃO PUBLICAR RELEASE FINAL AINDA**. A organização
documental está encaminhada, mas a revisão de privacidade e os aceites acima
continuam pendentes. O checklist registra limites sem impedir a preservação
do código já versionado no GitHub.
