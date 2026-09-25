# AUDIT-01 — Lynis pré-freeze nas EP125/EP126

## Objetivo

Executar uma auditoria de host independente antes do `FREEZE-01`, preservar a
saída bruta e transformar warnings/suggestions em uma triagem acadêmica
explicável.

O Lynis é usado como **fonte de findings**, não como mecanismo automático de
hardening. Nenhuma recomendação é aplicada sem análise de contexto.

## Princípios

- uma execução por VM: EP125 e EP126;
- cobertura completa com uma única elevação `sudo` antes do corte de
  privilégios;
- sem `sudo -s` ou shell root persistente;
- sem remediação automática;
- log, report, stdout/stderr e SHA-256 preservados;
- findings classificados manualmente;
- recomendações genéricas não reabrem arquitetura já comprovada sem evidência
  concreta de regressão.

## Precheck

Como usuário normal:

```bash
python3 scripts/evidencias/audit01_lynis_host.py --precheck
```

O precheck confirma que o binário Lynis existe e registra a versão. Se estiver
ausente, a instalação precisa ocorrer **antes** da retirada de sudo.

## Execução

Em cada VM, a partir do checkout canônico:

```bash
sudo python3 scripts/evidencias/audit01_lynis_host.py --run
```

A execução root é usada somente porque a auditoria completa do host possui maior
cobertura com privilégios administrativos. O script exige `SUDO_USER` válido e
recusa uma execução originada de root shell.

O Lynis é chamado com:

- `audit system`;
- `--quick`;
- `--no-colors`;
- `--log-file` e `--report-file` apontando para o diretório de evidência.

Os arquivos finais são devolvidos ao usuário que chamou `sudo`, com diretório
0700 e arquivos 0600.

## Evidências produzidas

```text
~/conectaeduca-audit01-lynis-<host>-<UTC>/
  lynis-screen.txt
  lynis.log
  lynis-report.dat
  TRIAGEM-LYNIS.tsv
  RESUMO-AUDIT01.txt
  SHA256SUMS-RAW
```

`TRIAGEM-LYNIS.tsv` nasce com todos os findings como
`PENDENTE_REVISAO`.

O manifesto `SHA256SUMS-RAW` cobre somente artefatos imutáveis da coleta
(`lynis-screen.txt`, `lynis.log`, `lynis-report.dat` e
`RESUMO-AUDIT01.txt`). A planilha de triagem não entra nesse manifesto porque
é intencionalmente editada na etapa seguinte.

## Classificação obrigatória

Cada warning/suggestion deve terminar em uma destas classes:

| Classe | Uso |
|---|---|
| `APLICAVEL` | finding real que exige correção ou controle compensatório |
| `JA_MITIGADO` | ferramenta não reconheceu um controle já comprovado por outra evidência |
| `N_A_LAB` | recomendação não aplicável ao desenho acadêmico, com justificativa técnica |
| `RISCO_ACEITO` | finding real mantido conscientemente, com impacto e escopo documentados |

Não usar `N_A_LAB` apenas porque uma correção é trabalhosa.

Depois de preencher a triagem, finalize o pacote **como usuário normal**:

```bash
python3 scripts/evidencias/audit01_lynis_host.py \
  --finalize ~/conectaeduca-audit01-lynis-<host>-<UTC>
```

O modo `--finalize`:

- rejeita qualquer linha que ainda esteja como `PENDENTE_REVISAO` ou com classe
  inválida;
- exige justificativa para todo finding;
- exige ação para `APLICAVEL` e `RISCO_ACEITO`;
- gera `RESUMO-TRIAGEM-AUDIT01.txt`;
- gera `SHA256SUMS-FINAL`, cobrindo também a triagem finalizada e o manifesto
  RAW.

Assim, editar a triagem não invalida a evidência bruta original e o pacote final
ganha um segundo manifesto consistente após a análise humana.

## Critério de fechamento

AUDIT-01 fecha somente quando:

1. EP125 e EP126 possuem coleta, `SHA256SUMS-RAW` e `SHA256SUMS-FINAL`;
2. todos os warnings/suggestions foram classificados e o `--finalize` retornou PASS;
3. itens `APLICAVEL` foram corrigidos ou transformados em risco aceito;
4. riscos residuais relevantes foram incorporados à matriz pré-freeze e ao
   relatório;
5. nenhum finding foi "corrigido" automaticamente apenas para elevar o
   hardening index.

O hardening index é evidência auxiliar, não nota acadêmica nem critério isolado
de sucesso.


## Consolidação EP125 + EP126

Depois de finalizar as duas triagens, usar o consolidador:

```bash
python3 scripts/evidencias/audit01_consolidar_duas_vms.py \
  --ep125-dir ~/conectaeduca-audit01-lynis-ep125-pucpr-<UTC> \
  --ep126-dir ~/conectaeduca-audit01-lynis-ep126-pucpr-<UTC>
```

Antes de produzir qualquer comparação, ele valida os manifests RAW e FINAL de
cada VM e recusa adulteração, arquivo faltante ou triagem incompleta.

O resultado inclui matriz de TEST_IDs comuns/exclusivos, resumo por
classificação e um documento que destaca `APLICAVEL` e `RISCO_ACEITO` sem
reclassificar findings automaticamente.

Para a metodologia de decisão, consulte
[`AUDIT-01-LYNIS-TRIAGEM-GUIA.md`](AUDIT-01-LYNIS-TRIAGEM-GUIA.md).

O tooling de consolidação possui CI dedicado com controle positivo e controle
negativo por adulteração proposital de uma fixture.
