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
- com o remoto `origin` identificado como o repositório canônico `andrea-kozicki/conectaeduca`;
- com `HEAD` igual ao SHA fresco de `refs/heads/main` consultado explicitamente em `https://github.com/andrea-kozicki/conectaeduca.git`, sem confiar na identidade configurável de `origin`;
- com a consulta remota executada em diretório temporário fora do worktree, com `GIT_CEILING_DIRECTORIES` impedindo descoberta de repositório/config local ancestral e com configurações Git global/system/command isoladas, impedindo redirecionamento por `url.*.insteadOf`;
- com a verificação da worktree executada com `core.fsmonitor=false`, para não confiar em um hook fsmonitor stale/malicioso;
- sem entradas rastreadas marcadas com `assume-unchanged`, `skip-worktree`, fsmonitor-clean ou outros estados especiais do índice; o helper consome saídas `-z` com NUL real de `git ls-files -v` e `git ls-files -f`;
- com o Snyk CLI autenticado;
- sem Ignore/suppression para o finding.

O helper canônico é:

```bash
python3 scripts/evidencias/appsec04_snyk_revalidation.py
```

Ele executa `snyk code test --sarif --include-ignores`, mantém o SARIF bruto apenas em memória e
persiste somente metadados mínimos: commit, contagens, rule id, path e presença
de CWE-611. Nenhum token Snyk ou snippet de código é gravado na evidência.

## Pré-check

Antes de executar:

```bash
git switch main
git -c core.fsmonitor=false status --short --untracked-files=all
git ls-files -v -z
git ls-files -f -z
git rev-parse HEAD
git config --local --no-includes --get-all remote.origin.url
git ls-remote --exit-code https://github.com/andrea-kozicki/conectaeduca.git refs/heads/main
snyk --version
```

Não prosseguir se a worktree estiver suja, **incluindo arquivos untracked**, se `origin` não apontar para o repositório canônico, se a consulta remota canônica falhar ou se
`HEAD` divergir do SHA retornado para `refs/heads/main`. O helper lê o valor **bruto** de `remote.origin.url` com `git config --local --no-includes --get-all`, em vez de `git remote get-url`, para que `url.*.insteadOf` não possa maquiar um origin externo como canônico. Deve existir exatamente uma URL de origin e ela precisa corresponder ao repositório canônico. A consulta fresca por `git ls-remote` roda contra a URL canônica em um diretório temporário dedicado, com `GIT_CEILING_DIRECTORIES` apontando para esse próprio diretório e sem config de sistema/global/command herdada. Isso impede inclusive que um `.git/config` ancestral do diretório de execução injete `url.*.insteadOf`. A verificação da worktree desativa `core.fsmonitor` e o gate também rejeita entradas marcadas como fsmonitor-clean, para que cache/hook fsmonitor não consiga ocultar bytes divergentes do HEAD. A validação do hostname usa comparação ASCII estrita; caracteres Unicode visualmente semelhantes a `github.com` são rejeitados. Ele não confia apenas na ref local `origin/main`.

## Critério de fechamento

Para APPSEC-04:

```text
ORIGIN_RAW_URL_COUNT=1
ORIGIN_CANONICAL=PASS
REMOTE_QUERY_GIT_CONFIG_ISOLATED=YES
REMOTE_QUERY_LOCAL_CONFIG_DISCOVERY=BLOCKED_BY_TEMP_CEILING
WORKTREE_STATUS_FSMONITOR_DISABLED=YES
INDEX_TRACKING_FLAGS=PASS
INDEX_FSMONITOR_FLAGS=PASS
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
- `tool` deve existir e ser um objeto SARIF; string, lista, `null` ou ausência bloqueiam o gate antes de qualquer acesso a `driver`;
- `tool.driver.name` deve ser uma string não vazia; objetos/listas ou outros tipos são SARIF inválido e bloqueiam o gate;
- propriedades opcionais ausentes podem usar o default previsto pelo helper, mas `results: null` e `tool.driver.rules: null` são estruturalmente inválidos e bloqueiam o gate;
- quando `tool.driver.rules` estiver presente, cada descritor deve ser objeto com `id` string não vazia; `null`, string, objeto vazio ou `id` inválido bloqueiam o gate;
- IDs de regra em `tool.driver.rules` devem ser únicos; IDs duplicados tornam o SARIF ambíguo e bloqueiam o gate;
- em cada resultado, `ruleId` (quando presente) deve ser string não vazia e `ruleIndex` (quando presente) deve ser inteiro válido dentro de `rules`;
- quando `ruleId` e `ruleIndex` coexistirem, ambos devem identificar a mesma regra; divergência é SARIF inconsistente e bloqueia o gate;
- `locations` (quando presente) deve ser lista; cada location e os objetos `physicalLocation`/`artifactLocation` presentes devem ser objetos, e `uri` presente deve ser string não vazia;
- se `invocations` estiver presente, deve ser lista de objetos; cada invocation deve conter `executionSuccessful` booleano e igual a `true`; ausência do campo, `false` ou tipo não booleano bloqueiam o gate;
- o scan usa `--include-ignores`, portanto findings marcados como ignorados no Snyk continuam entrando no SARIF e bloqueiam o fechamento; suppression remota não pode produzir falso PASS;
- `ruleId`, IDs de regras, nome do driver e `artifactLocation.uri` rejeitam controles, separadores de linha e surrogates Unicode para impedir injeção/quebra da evidência TXT;
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
