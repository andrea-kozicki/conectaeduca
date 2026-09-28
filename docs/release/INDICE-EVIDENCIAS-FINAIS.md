# Índice de evidências finais — ConectaEduca

## Objetivo

Concentrar em um único lugar **o que precisa existir como prova** antes do FREEZE-01 e da entrega acadêmica.

Este índice não substitui os TXT/checkpoints originais. Ele serve como mapa de rastreabilidade entre controle, cenário S01–S13, evidência e estado.

## Convenção

- **DONE** — evidência operacional já existe;
- **HOST_GATE** — depende de EP125/EP126/pfSense;
- **SEQUENCED** — só deve acontecer depois do freeze ou de pré-requisito;
- **BOUNDARY** — depende de suporte/professor;
- **FUTURE** — não bloqueia a entrega atual.

## 1. Arquitetura e segmentação

| Controle | Cenários | Estado | Evidência mínima |
|---|---|---|---|
| pfSense cross-zone | S01, S03 | DONE / revalidar no freeze | matriz de portas permitidas/bloqueadas + regra/alias + timestamp |
| Suricata | S01, S03, S09 | DONE | EVE/alerta correlacionável no Wazuh |
| Egress mínimo | S11, S13 | DONE / revalidar no pentest | tentativa permitida e negada + log/alerta |
| SSH pfSense | complementar | BOUNDARY | conta/porta/origem/privilégio fornecidos pelo suporte, se habilitado |

## 2. Aplicação, WAF e identidade

| Controle | Cenários | Estado | Evidência mínima |
|---|---|---|---|
| WAF/CRS | S02 | DONE / DAST sequenciado | probe sintético + HTTP esperado + evento Wazuh |
| MFA | S04 | DONE | inválido negado, válido aceito, auditoria |
| RBAC/ownership | S05 | DONE / repetir no pentest | 403/deny para recurso/papel não autorizado |
| Auditoria da aplicação | S04, S05 | DONE / consolidar | eventos de login/RBAC correlacionáveis |

## 3. Dados, segredos e containers

| Controle | Cenários | Estado | Evidência mínima |
|---|---|---|---|
| MariaDB menor privilégio | S06 | DONE | grants sanitizados + 3306 segmentado + login/SELECT permitido + DML negado no phpMyAdmin |
| Segredos fora do Git | S07 | DONE / contínuo | Gitleaks/CI + ausência de material runtime versionado |
| Hardening de containers | S08 | DONE no Git/runtime histórico | user/caps/mounts/privileged/socket + prova negativa do usuário teste |
| Docker boundary | S08 | HOST_GATE zero-sudo | teste sem grupo docker e sem RW no socket |

## 4. Detecção e monitoramento

| Controle | Cenários | Estado | Evidência mínima |
|---|---|---|---|
| Wazuh/SIEM | S09 | DONE | evento produzido e localizado no Dashboard/Indexer |
| FIM/YARA | S10 | DONE histórico; HOST_GATE user-writable | alteração controlada + alerta + hash |
| pfSense → Wazuh | S09 | HOST_GATE pós-reboot | evento identificável pós-reboot correlacionado no Manager/alerta; usar `pfsense_wazuh_postreboot_readonly.py` |
| Suricata EP125 → Wazuh | S09 | DONE pós-reboot | evento/alerta correlacionado + correção `event_type=stats` sem regressão do analysisd |

## 5. DLP, backup e privacidade

| Controle | Cenários | Estado | Evidência mínima |
|---|---|---|---|
| Ferret/DLP | S11, S13 | DONE pipeline; HOST_GATE user-writable | marcador fictício + evento sanitizado |
| BAC-04 operacional | S12 | DONE | backup/restore E2E + hashes origem/restaurado + jobs T/R |
| Privacidade/LGPD | S13 | HOST_GATE | dado fictício não aparece bruto no SIEM |
| Domínio físico independente | S12 | FUTURE/risco residual | negativa do segundo disco registrada |

## 6. Zero-sudo

Antes do corte:

- `pentest_no_sudo_readiness.py` em EP125;
- `pentest_no_sudo_readiness.py` em EP126;
- clientes instalados;
- configs legíveis por `teste`;
- path FIM user-writable;
- path DLP user-writable;
- grants/admin evidence capturados;
- nenhuma dependência de `docker exec`.

Depois do corte, executar como `teste`:

- `pentest_sem_sudo_runtime_check.py`;
- positivos/negativos de autorização de cada serviço.

## 7. Bacula

Guardar juntos:

- readiness pré-apply;
- BAC-04 v2.4 apply;
- BAC-04 v2.5 E2E;
- jobs executados;
- restore isolado;
- SHA-256 origem/restaurado;
- prova de preservação dos SmokeJobs;
- exclusão de material de custódia/secrets.

## 8. WebGUIs de demonstração

| GUI | Estado | Evidência |
|---|---|---|
| OpenBao | DONE | login teste + path permitido + path/admin negado + credencial antiga rejeitada |
| Bacularis | DONE | login teste + consulta + operação mutante negada |
| phpMyAdmin | DONE | container hardened + HTTPS-only + SELECT permitido + DML negado |
| Wazuh Dashboard | DONE | autenticação real read-only + consulta permitida + admin negado |

## 8A. CRED-01 — identidade técnica `teste`

Fechado em 27/09/2026:

- EP125: `REQUIRED_PASS=1`, `N_A=4`, `PENDING=0`, `BLOCK=0`;
- EP126: `REQUIRED_PASS=7`, `N_A=1`, `PENDING=0`, `BLOCK=0`;
- `CRED01_STATUS=PASS` nas duas VMs;
- OpenBao comprova rejeição da credencial antiga/incorreta após a correção;
- PostgreSQL/PgBouncer comprova SCRAM via socket Unix e negativos de privilégio;
- evidências finais possuem SHA-256 e não persistem senha/segredo.

Não reabrir CRED-01 sem regressão nova.

## 9. Gates estáticos finais

O finding **APPSEC-04 / CWE-611** em
`ops01_ep126_readonly.py` foi corrigido sem suppression e mergeado pelo
PR #132 na `main` (`f9202fecbfa8f3862cd581017ef8ed07c1d662fa`).

O gate permanece **REPO_GATE** até existir evidência de Snyk Code sobre a ref
corrigida sem o CWE-611. Repository Static Integrity, PHPUnit, Semgrep e
Gitleaks verdes não substituem o scanner que originou o finding.

Executar na `main` limpa e sincronizada:

```bash
python3 scripts/evidencias/appsec04_snyk_revalidation.py
```

Preservar o TXT e o `.sha256`. O fechamento exige
`APPSEC04_SNYK_REVALIDATION=PASS` e `SNYK_TOTAL_RESULTS=0`.
Referência: `docs/seguranca/APPSEC-04-SNYK-REVALIDATION.md`.

No FREEZE-01, repetir o conjunto completo de gates e registrar o estado
efetivamente observado na ref congelada.

No commit de freeze, repetir:

- Repository Static Integrity;
- PHPUnit;
- Semgrep;
- Snyk;
- Gitleaks;
- `prefreeze_repo_gate.py`;
- `git diff --check`;
- `git status --short` limpo.

O Lynis pré-freeze de EP125/EP126 já está concluído e triado. Não reabrir
AUDIT-01 sem regressão nova; incorporar apenas o resumo final ao pacote de
evidências/freeze.

## 9A. Preflight EP126 pós-reboot

Antes dos probes live finais, usar:

```bash
python3 scripts/evidencias/ops01_ep126_readonly.py
```

Referência:
`docs/seguranca/OPS01-EP126-READONLY.md`.

Esse preflight não substitui os testes correlacionados; ele apenas comprova
readiness de receiver, Manager, Rootcheck e rule 110300 sem mutar o runtime.

Para o gate pfSense → Wazuh pós-reboot, usar também:

```bash
python3 scripts/evidencias/pfsense_wazuh_postreboot_readonly.py
python3 scripts/evidencias/pfsense_wazuh_postreboot_readonly.py --marker '<marcador-ja-gerado>'
```

Sem `--marker`, o script comprova somente readiness. Com marcador, tenta
correlacionar no Manager o evento já produzido externamente; o próprio script
não gera tráfego nem altera runtime.

## 10. Pacote de entrega

Antes da apresentação, deve existir um diretório externo ao Git contendo apenas evidências sanitizadas:

```text
evidencias-finais/
  01-arquitetura-segmentacao/
  02-aplicacao-waf-rbac/
  03-dados-segredos-containers/
  04-wazuh-fim/
  05-dlp-privacidade/
  06-bacula/
  07-zero-sudo/
  08-pentest-s01-s13/
  09-twingate-comparativo/
  SHA256SUMS
```

Não copiar para esse pacote senhas, tokens, RoleID/SecretID, root tokens, unseal/recovery shares, private keys ou dumps contendo dados não sanitizados.


## 11. Automação do manifesto

Depois da revisão humana do pacote:

```bash
python3 scripts/evidencias/gerar_manifesto_evidencias_finais.py ~/evidencias-finais
```

Esperado: `MANIFEST_READY=YES` e `FAIL=0`.

O roteiro de execução dos cenários está em `docs/seguranca/PENTEST-COMANDOS-S01-S13.md`.
