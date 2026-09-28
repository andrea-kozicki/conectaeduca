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

## APPSEC-04 — reabertura posterior por CWE-611

Depois do baseline limpo de 26/09, um scan Snyk Code posterior encontrou
`CWE-611 / Insecure XML Parser` em
`scripts/evidencias/ops01_ep126_readonly.py`, na função
`exact_receiver_block_count()`.

Isso **reabriu o gate AppSec**; portanto, os resultados limpos acima devem ser
lidos como baseline histórico daquele commit, não como autorização automática
para o FREEZE-01 atual.

A correção preparada:

- remove o uso de `xml.etree.ElementTree.fromstring()` nesse caminho;
- não adiciona parser XML alternativo nem dependência externa;
- usa scanner estrito apenas para o subconjunto simples de `<remote>` lido do
  `ossec.conf`;
- rejeita DTD/declaration, processing instruction, entidades, atributos,
  markup aninhado, tags duplicadas e fragmentos incompletos;
- inclui self-tests negativos para XXE/DOCTYPE e formatos malformados;
- não usa Ignore/Snyk suppression.

Marcadores canônicos após o merge da correção:

```text
APPSEC-04=CWE-611_OPS01_XML_PARSER
APPSEC04_REMEDIATION=STRICT_NON_XML_REMOTE_SCANNER
NO_SNYK_SUPPRESSION=YES
APPSEC04_STATUS=REPO_GATE
APPSEC04_MERGE=f9202fecbfa8f3862cd581017ef8ed07c1d662fa
APPSEC04_SNYK_REVALIDATION=PENDING
```

A correção foi mergeada pelo PR #132. Repository Static Integrity, PHPUnit
Security Tests, Semgrep SAST e Gitleaks concluíram com sucesso na `main`
desse commit, mas isso não substitui a revalidação do Snyk Code que originou o
CWE-611. O APPSEC-04 somente muda para `DONE` após Snyk Code confirmar a
ausência do finding na ref corrigida.

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

APPSEC-04 permanece em `REPO_GATE` até a revalidação Snyk Code da ref
corrigida. O FREEZE-01 deve registrar o estado real observado no commit
congelado após repetir o conjunto completo de gates. O AppSec não substitui os
HOST_GATEs ainda abertos, em especial a correlação pfSense -> Wazuh e o
readiness zero-sudo.
