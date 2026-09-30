# APPSEC-04/05 — revalidação Snyk Code canônica

## Objetivo

Fechar, sem suppression, os gates reabertos por:

- **APPSEC-04 / CWE-611** em `scripts/evidencias/ops01_ep126_readonly.py`;
- **APPSEC-05 / CWE-23** em `scripts/dlp/submeter_ferret_pentest.py` e
  `scripts/dlp/snapshot_ferret_input.py`.

Repository Static Integrity, PHPUnit, Semgrep, Gitleaks e o status Snyk do PR
continuam obrigatórios, mas não substituem a evidência final do scanner sobre a
`main` canônica.

## Boundary de evidência

A evidência final **não é mais produzida na workstation local**.

As revisões do PR #138 demonstraram que, se a mesma identidade local puder
recuperar `sudo` durante o scan, uma amostragem antes/depois não prova ausência
de alteração transitória. O desenho anterior baseado em `sudo -K`, timestamp
sudo e snapshot local foi aposentado.

A evidência canônica passa a ser produzida em GitHub Actions por:

- workflow `.github/workflows/appsec-snyk-final-evidence.yml`;
- helper `scripts/evidencias/appsec_snyk_ci_evidence.py`;
- identidade dedicada `conecta-snyk`, criada sem shell de login e sem sudo;
- snapshot do commit materializado por `git archive`, root-owned e sem bits de
  escrita;
- Snyk CLI pinado em **v1.1307.4** com SHA-256
  `b0baee4fa4d7d11b7df927a1046cf8137a8a89fafac8101a45c3c0e0777ddc35`;
- `actions/checkout` e `actions/upload-artifact` pinados por commit SHA;
- segredo Snyk entregue por arquivo efêmero modo `0400`, pertencente somente à
  identidade de scan, consumido e removido pelo helper antes do CLI;
- caminhos sensíveis do boundary são canônicos e fixos em
  `/opt/conectaeduca-snyk` (`snapshot`, `snyk`, `home`, `evidence`);
  o helper não aceita pathname desses recursos por variável de ambiente;
- SARIF bruto somente em memória;
- evidência persistida apenas como TXT sanitizado + SHA-256.

## Execução estrutural em PR

O PR executa somente o self-test do parser/contrato:

```bash
python3 scripts/evidencias/appsec_snyk_ci_evidence.py --self-test
```

Esperado:

```text
APPSEC_SNYK_CI_SELF_TEST=PASS
```

O wrapper histórico permanece apenas por compatibilidade:

```bash
python3 scripts/evidencias/appsec04_snyk_revalidation.py --self-test
```

Ele delega ao helper CI.

## Execução final

Depois que o PR #138 estiver mergeado e a `main` estiver estabilizada:

1. obter o SHA-1 de 40 caracteres da ponta de `main` escolhida para o freeze e
   registrá-lo como `<FREEZE_COMMIT>`;
2. abrir **Actions → APPSEC Snyk Final Evidence → Run workflow**;
3. informar exatamente `<FREEZE_COMMIT>` no campo `expected_sha`;
4. o workflow confirma que o SHA solicitado ainda é exatamente `origin/main`;
5. a execução final exige o repository secret `SNYK_TOKEN`;
6. preservar o artifact `appsec-snyk-final-<FREEZE_COMMIT>`;
7. validar o TXT e confirmar `EXPECTED_SHA=<FREEZE_COMMIT>`.

O workflow falha fechado se o SHA deixar de ser a `main` atual, se a identidade
dedicada tiver sudo, se o snapshot estiver gravável, se faltar autenticação, se
o SARIF for inválido, se o snapshot mudar durante o scan ou se houver qualquer
finding.

Se qualquer commit for mergeado depois desse scan, o SHA de freeze mudou: o
artifact anterior deixa de ser suficiente para o fechamento acadêmico e o scan
deve ser repetido para o novo `<FREEZE_COMMIT>`.

## Critério de fechamento

O TXT sanitizado deve conter simultaneamente:

```text
EXPECTED_SHA=<FREEZE_COMMIT>
APPSEC_CI_BOUNDARY=GITHUB_HOSTED_DEDICATED_NO_SUDO
CI_BOUNDARY=PASS
SCAN_IDENTITY_SUDO=BLOCKED
SNAPSHOT_ROOT_OWNED_READ_ONLY=PASS
SNAPSHOT_POSTSCAN_INTEGRITY=PASS
SNYK_SCAN_RC=0
SARIF_VALIDATION=PASS
SNYK_TOTAL_RESULTS=0
SNYK_CWE611_RESULTS=0
SNYK_TARGET_CWE611_RESULTS=0
APPSEC04_CWE611=PASS
SNYK_CWE23_RESULTS=0
SNYK_APPSEC05_TARGET_CWE23_RESULTS=0
APPSEC05_CWE23=PASS
APPSEC04_SNYK_REVALIDATION=PASS
APPSEC05_SNYK_REVALIDATION=PASS
```

O gate global continua exigindo `SNYK_TOTAL_RESULTS=0`: desaparecer CWE-611 e
CWE-23 não é suficiente se surgir outro finding.

## Evidência

O artifact final contém somente:

```text
appsec-snyk-final.txt
appsec-snyk-final.txt.sha256
```

O SARIF bruto não é persistido. Token, snippets de código e conteúdo de secrets
não entram no artifact.

Para o FREEZE-01, copiar esses dois arquivos sanitizados para o pacote externo
de evidências e validar:

```bash
sha256sum -c appsec-snyk-final.txt.sha256
```

## Estado antes da execução final

Enquanto o artifact válido da `main` não existir:

```text
APPSEC04_STATUS=REPO_GATE
APPSEC04_SNYK_REVALIDATION=PENDING
APPSEC05_STATUS=REPO_GATE
APPSEC05_SNYK_REVALIDATION=PENDING
```

Somente o artifact canônico cujo nome e TXT correspondam exatamente ao
`<FREEZE_COMMIT>` permite alterar esses marcadores para `DONE/PASS`. Se a
`main` avançar depois do scan, os marcadores voltam a permanecer bloqueados
até nova evidência Snyk sobre o novo commit de freeze.
