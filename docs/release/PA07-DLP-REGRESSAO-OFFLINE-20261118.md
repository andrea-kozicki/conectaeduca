# PA-07 — reconciliação de testes DLP/Wazuh sem VM (18/11/2026)

**Tipo:** regressão offline de código-fonte já versionado. **Não é deploy nem homologação do Wazuh Manager/Ferret.** Alteração isolada da PR de testes, sem Dockerfile, regras Wazuh, imagem/TAR ou VMs.

## Proveniência e decisão

- O ruleset `deploy/interna/wazuh/config/rules/conectaeduca_dlp_rules.xml` da `main` já é **idêntico (Git blob `8d332c7adb8820789219c5c6e6b048eeecc178d2`)** ao arquivo na [PR histórica #206](https://github.com/andrea-kozicki/conectaeduca/pull/206), que introduzia severidades case-insensitive e a guarda de zero achados.
- As regras `110111/110112/110113` classificam LOW/MEDIUM/HIGH em níveis 5/8/12; a `110110` é fallback em nível 6. `110101` só admite silenciamento de resumo sem achados com contadores positivos/zero explicitamente reportados, sem inferir cobertura integral.
- A #206 também continha um validador e uma suíte sintética **ainda não presentes na `main`**. Esta PR extrai somente esses dois arquivos e adiciona workflow isolado. **Não faz merge da #206 inteira.**
- Origem Git: `scripts/evidencias/validar_regras_dlp_confidence.py` blob `6a7f0a08027d8a38dffacc0e31f4f1c183d30368`; `tests/python/test_dlp_wazuh_contract_pr206.py` blob `12aa169875717d6f54c26d1d20fab9e6c8560eb4` no commit `a7b3a763b8739445de234c6211404a7c0fc92bd4`.
- Ajustes editoriais no teste importado: sentinela claramente sintética e comentário atualizado. Os cenários e assertivas foram mantidos.

## Execução no GitHub Actions

`.github/workflows/pa07-dlp-wazuh-offline.yml` executa, em `pull_request` e `push` na `main` com mudanças pertinentes:

1. `python3 scripts/evidencias/validar_regras_dlp_confidence.py`
2. `python3 -m unittest discover -s tests/python -p 'test_dlp_wazuh_contract_pr206.py' -v`

Runner Ubuntu 24.04, `contents: read`, checkout fixado por SHA e sem credenciais persistentes. Testes usam fixtures sintéticas; **não utilizam Docker, VM, CLI Ferret real, rede ou credenciais**.

## O que a CI não prova

- Não executa PCRE2 no Manager, `wazuh-logtest`, parsing real do decoder, ingestão agent→Manager→Indexer→Dashboard ou política efetiva do ambiente institucional.
- `no_full_log` não garante, por si só, ausência de campos sensíveis no alerta; privacidade e retenção continuam dependentes do runtime.
- Não demonstra que a interface Web v5 seja fail-closed em todos os casos, que os launchers Fish tenham paridade com Bash, nem que Bacula/DLP/egress estejam homologados.
- **Sem acesso às VMs:** qualquer divergência entre regra no GitHub e regra carregada no Manager exige reconciliação futura e change control separado.

## PRs históricas relacionadas

- [#206](https://github.com/andrea-kozicki/conectaeduca/pull/206): regras já absorvidas, testes extraídos; manter em draft para triagem do material residual.
- [#207](https://github.com/andrea-kozicki/conectaeduca/pull/207), [#226](https://github.com/andrea-kozicki/conectaeduca/pull/226), [#227](https://github.com/andrea-kozicki/conectaeduca/pull/227): patches de UI, instaladores e launchers com sobreposições/guardas operacionais; **não incorporar em lote**.
- [#237](https://github.com/andrea-kozicki/conectaeduca/pull/237) e [#240](https://github.com/andrea-kozicki/conectaeduca/pull/240): reconciliações source-only já incorporadas à `main`.

**Gate:** só integrar esta PR após testes passarem; instalação na EP126 não está autorizada por este arquivo.
