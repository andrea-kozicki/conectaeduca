# GA-06 / PA-07 — gate reprodutível da interface Ferret V4/V5

**Data:** 18/11/2026. **Estado:** candidata de fonte e testes; **não é homologação de VM, container ou navegador**.

## Escopo e origem

Esta PR extrai da [#207](https://github.com/andrea-kozicki/conectaeduca/pull/207) apenas quatro artefatos de fonte já revisados historicamente: patches `ferret_pa07_v4.patch` e `ferret_pa07_v5_on_v4.patch`, e testes Node V4/V5 (licença de origem Apache-2.0; preservar os cabeçalhos). Não extrai Dockerfile, Containerfile, Compose, imagem, scripts de cutover nem evidências institucionais.

A base remota foi fixada no upstream público `awslabs/ferret-scan` em `a5156d1950df19276e6cfd8335603d73187a3841`, arquivo `internal/web/assets/app.js`, Git blob **`68192bc16891887240089e08634b5d41bf2588c1`**, verificado pelo conector GitHub em 18/11. O gate faz download HTTPS desse **commit imutável**, compara `git hash-object` antes de executar qualquer JavaScript, e falha fechado se os bytes divergirem. Não persiste o upstream no repositório ConectaEduca.

## Como executar sem VM

Requisitos: Bash, Git, curl, awk, grep e Node. Execute na raiz do clone:

```bash
bash scripts/evidencias/ga06_verify_ferret_ui_source.sh
```

O verificador cria diretório temporário, aplica **V4 sobre upstream limpo** e **V5 somente após V4**, faz `node --check`, extrai os fragmentos de funções do `app.js` patchado e roda as suites Node com DOM/fetch simulados. Limpa os temporários ao sair. Não inicia serviço, não conecta a EP125/EP126, não usa credenciais nem altera imagem. O acesso de rede serve **somente para baixar o arquivo upstream público fixado**.

## Critérios e limites

- CI verde demonstra aplicabilidade dos patches ao arquivo de origem fixado, integridade da fonte, sintaxe JS e regressões **simuladas** (V4: 20 cenários históricos; V5: 26). Os resultados efetivos precisam ser verificados no Actions.
- Testes de `window.fetch` e DOM são mocks: não demonstram o navegador, HTTP 403 do servidor, WAF, Ferret Web V5 implantado ou bloqueio de exfiltração.
- **Não** mesclar a #207 completa: ela contém candidate image, scripts históricos e deploys que dependem de proveniência e autorização institucionais.
- Mesmo que a CI passe, manter este PR em *draft* até inspeção do diff e decisão sobre integração **apenas de source/tests**. Nenhum deploy é autorizado por esta PR.
- Teste funcional de persistência visual por mais de 15 segundos, exportação com erro sintético, identidade/digest da imagem e rollback ensaiado são gates operacionais separados.

Referências: [reconciliação Ferret/Wazuh](../portfolio/FERRET-WAZUH-PR-RECONCILIACAO-20261118.md), [#237](https://github.com/andrea-kozicki/conectaeduca/pull/237) (Bash/proveniência), [#260](https://github.com/andrea-kozicki/conectaeduca/pull/260) (DLP/Wazuh offline).
