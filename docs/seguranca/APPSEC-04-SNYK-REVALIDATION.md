# APPSEC-04 — revalidação Snyk Code do CWE-611

## Objetivo

Fechar o gate que permaneceu aberto após o PR #132. A correção técnica já
removeu o parser XML do caminho `scripts/evidencias/ops01_ep126_readonly.py`,
mas o scanner que originou o finding precisa revalidar a **ref corrigida**.

Checks de GitHub, Semgrep e Gitleaks não substituem essa evidência.

## Regra de proveniência

Executar somente quando o checkout estiver:

- na branch `main`;
- limpo;
- com `HEAD` igual ao SHA fresco de `refs/heads/main` consultado no remoto `origin`;
- com o Snyk CLI autenticado;
- sem Ignore/suppression para o finding.

O helper canônico é:

```bash
python3 scripts/evidencias/appsec04_snyk_revalidation.py
```

Ele executa `snyk code test --sarif`, mantém o SARIF bruto apenas em memória e
persiste somente metadados mínimos: commit, contagens, rule id, path e presença
de CWE-611. Nenhum token Snyk ou snippet de código é gravado na evidência.

## Pré-check

Antes de executar:

```bash
git switch main
git status --short --untracked-files=all
git rev-parse HEAD
git ls-remote --exit-code origin refs/heads/main
snyk --version
```

Não prosseguir se a worktree estiver suja, **incluindo arquivos untracked**, se a consulta remota falhar ou se
`HEAD` divergir do SHA retornado para `refs/heads/main`. O helper faz essa
consulta fresca por `git ls-remote`; ele não confia apenas na ref local
`origin/main`.

## Critério de fechamento

Para APPSEC-04:

```text
PROVENANCE=PASS
SNYK_SCAN_PARSE=PASS
REMOTE_MAIN_QUERY=PASS
SNYK_SCAN_EXIT_CLEAN=PASS
SNYK_CWE611_RESULTS=0
SNYK_TARGET_CWE611_RESULTS=0
APPSEC04_CWE611=PASS
SNYK_CODE_MAIN=PASS
APPSEC04_SNYK_REVALIDATION=PASS
```

Além disso:

- `SNYK_SCAN_RC=0` e `SNYK_SCAN_EXIT_CLEAN=PASS`; um retorno 1 nunca pode ser reinterpretado como scan limpo;
- `SNYK_TOTAL_RESULTS=0` para o gate AppSec completo da `main`;
- resultados SARIF que usem somente `ruleIndex` também precisam resolver os metadados da regra antes da classificação CWE;
- `tool.driver.name` deve ser uma string não vazia; objetos/listas ou outros tipos são SARIF inválido e bloqueiam o gate;
- propriedades opcionais ausentes podem usar o default previsto pelo helper, mas `results: null` e `tool.driver.rules: null` são estruturalmente inválidos e bloqueiam o gate;
- se `invocations` estiver presente, deve ser lista de objetos; cada invocation deve conter `executionSuccessful` booleano e igual a `true`; ausência do campo, `false` ou tipo não booleano bloqueiam o gate;
- nenhuma suppression/Ignore adicionada;
- TXT + `.sha256` preservados no pacote de evidências.

Se o CWE-611 desaparecer mas surgir outro finding, APPSEC-04 específico pode
estar tecnicamente corrigido, porém o freeze AppSec continua bloqueado até
triagem do novo finding.

## Evidência

O helper grava:

```text
~/conectaeduca-appsec04-snyk-<UTC>.txt
~/conectaeduca-appsec04-snyk-<UTC>.txt.sha256
```

O relatório não persiste SARIF bruto.

## Self-test de parser

O parser pode ser validado sem Snyk e sem rede:

```bash
python3 scripts/evidencias/appsec04_snyk_revalidation.py --self-test
```

Esperado:

```text
APPSEC04_SNYK_REVALIDATION_SELFTEST=PASS
```

## Estado até a execução

Enquanto a evidência real na `main` não existir:

```text
APPSEC04_STATUS=REPO_GATE
APPSEC04_SNYK_REVALIDATION=PENDING
```

Somente depois de um scan válido na ref corrigida esses marcadores podem ser
atualizados para `DONE/PASS`.
