# ZT-01 — comparador offline e limitado para evidências

**Origem da necessidade:** [PR #219](https://github.com/andrea-kozicki/conectaeduca/pull/219) contém um comparador de relatórios de duas identidades Twingate, mas importa módulos do kit de pentest com sondas ativas. Esta implementação é **independente**, usa exclusivamente Python stdlib e **não** realiza rede, autenticação, consultas ao tenant Twingate nem alterações nas VMs.

## Contrato de entrada

- Dois arquivos JSON já coletados e sanitizados, com sidecar de SHA-256 de mesmo nome acrescido de `.sha256`;
- arquivos regulares, propriedade do usuário atual, modo privado 0600 e diretório de origem privado; links simbólicos recusados; relatórios limitados a 64 KiB;
- `schema=CE-PB-FIELD-20261109-R1`, `role=client`, `stage=exploit`, `pa=PA-01`, `gate=OPEN`, `zt_profile=portal` ou `soc` de acordo com a entrada;
- hostname igual em ambos os relatórios, sem emissão desse dado no resultado;
- três observações obrigatórias: `ZT_RESOURCE_VISIBILITY`, `ZT_PROFILE_APP` e `ZT_PROFILE_WAZUH`, sem duplicações ou valores arbitrários de status.

**Exemplo (somente em máquina autorizada, usando arquivos já existentes e previamente sanitizados):**

```bash
python3 scripts/evidencias/zt01_compare_offline.py \
  --portal-report /caminho/privado/portal.json \
  --soc-report /caminho/privado/soc.json
```

A saída contém exclusivamente estados de observação permitidos e indicadores de revisão humana. Ela não inclui hostname, caminho dos arquivos, tokens, cookies, corpos HTTP nem dados de identidade. Os testes automatizados usam somente objetos de teste e arquivos temporários fictícios.

**Critérios explícitos:** `TCP_REACHABLE` não prova autorização RBAC; DNS não prova negação por política; rótulos de identidade são declarações do operador e exigem corroboração independente no Twingate. Para aceitar MFA/Zero Trust, ainda serão necessários logs de acesso, políticas e testes controlados separados. SHA-256 indica integridade de bytes, **não autenticidade do operador**.

Não importar relatórios brutos para este repositório público. Nenhum teste aqui comprova acesso real ao Wazuh nem corrige a PR #219 inteira.
