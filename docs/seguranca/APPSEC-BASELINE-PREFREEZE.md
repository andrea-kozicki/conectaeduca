# Baseline AppSec pré-freeze — ConectaEduca

## Escopo

Este documento é a referência canônica do estado AppSec do repositório após o
merge do PR #127 em 26/09/2026. Ele consolida SAST e SCA executados sobre a
`main`, sem substituir os relatórios históricos dos PRs anteriores.

O objetivo é evitar que findings já corrigidos continuem aparecendo como
pendência no backlog pré-freeze.

## Correções consolidadas

O ciclo AppSec anterior tratou, entre outros pontos:

- fontes de path controláveis por ambiente/argumento em scripts de evidência;
- neutralização de células com prefixo de fórmula em TSV/CSV;
- escrita de evidências por descritor, com proteção contra symlink quando
  aplicável;
- hardening de diretórios/artefatos de evidência sem ampliar permissões;
- reconciliação do sanitizador OpenBao com o baseline Python atual;
- gate zero-sudo sem literal interpretável como credencial;
- nenhum Ignore/Snyk suppression usado como mecanismo de fechamento.

## Validação pós-merge na `main`

### Semgrep SAST

Comando:

```bash
semgrep scan --config auto .
```

Resultado observado:

```text
Findings: 0
Blocking: 0
Rules run: 1742
Targets scanned: 561
```

Estado:

```text
SEMGREP_SAST_MAIN=PASS
```

### Snyk Code

Comando:

```bash
snyk code test
```

Resultado observado:

```text
Total issues: 0
```

Estado:

```text
SNYK_CODE_MAIN=PASS
```

Após a atualização da `main`, a operadora também confirmou visualmente no
painel web do Snyk que o projeto passou a aparecer sem ocorrências conhecidas.
Essa observação visual complementa, mas não substitui, o gate reproduzível da
CLI.

### Semgrep Supply Chain / SCA

Comando:

```bash
semgrep ci --supply-chain
```

Resultado sobre a ref `main`:

```text
Dependency source: composer.lock
Ecosystem: Composer
Dependencies: 40
Supply Chain rules loaded: 6537
Basic rules: 6028
Reachability rules: 502
Malicious rules: 7
Rule evaluations: 137448
Findings: 0
Blocking: 0
```

Estado:

```text
SEMGREP_SCA_MAIN=PASS
```

O `Targets scanned: 1` do SCA representa o lockfile usado como fonte de
dependências; não significa que apenas um arquivo de aplicação foi auditado.

## Resultado consolidado

```text
SEMGREP_SAST_MAIN=PASS findings=0
SNYK_CODE_MAIN=PASS issues=0
SEMGREP_SCA_MAIN=PASS findings=0
SNYK_WEB_MAIN=NO_KNOWN_OCCURRENCES_OPERATOR_OBSERVED
APPSEC_POSTMERGE_MAIN=PASS
```

## Critério de reabertura

Reabrir o gate AppSec somente se ocorrer ao menos uma destas condições:

- novo finding SAST/SCA em `main` ou em PR destinado à `main`;
- mudança de lockfile/dependências que introduza finding;
- regressão de um controle corrigido;
- divergência entre checkout escaneado e commit/ref declarado;
- falha dos gates de CI obrigatórios.

Findings históricos não devem ser reabertos apenas porque permanecem no
histórico de execução de uma ferramenta.

## Relação com o freeze

O estado AppSec do repositório pode ser registrado no FREEZE-01 como:

```text
APPSEC_POSTMERGE_MAIN=PASS
APPSEC_SAST_FINDINGS=0
APPSEC_SCA_FINDINGS=0
```

Isso não substitui os HOST_GATEs ainda abertos na EP126.
