# Pré-seleção de evidências pré-freeze — 29/09/2026

## Objetivo

Adiantar a montagem do pacote final sem inventar resultado e sem exigir acesso
às VMs. Este documento separa:

- evidências já existentes que podem ser **selecionadas/revisadas**;
- evidências que ainda dependem de HOST_GATE/BOUNDARY;
- material que nunca deve entrar no pacote por conter segredo ou dado bruto.

A cópia final deve usar os TXT/checkpoints e respectivos SHA-256 reais já
produzidos no repositório externo de evidências. Este documento não inventa
nomes de arquivos runtime que não estejam versionados.

## 01 — Arquitetura e segmentação

### Já selecionar
- evidência histórica de segmentação/cross-zone;
- evidência de egress mínimo;
- topologia final EP125/DMZ ↔ pfSense ↔ EP126/interna;
- Suricata ativo e correlação já comprovada;
- risco TIME-01 documentado.

### Ainda pendente
- inventário/sync final das VMs com
  `df2ebd5e509c671640efddc524ec5ffbbc4714a3`;
- marker pós-reboot pfSense→Wazuh do OPS-01.

## 02 — Aplicação, WAF e RBAC

### Já selecionar
- WAF/CRS com probe sintético bloqueado;
- WAF → journald → Wazuh rule 110300 pós-reboot;
- MFA válido/ inválido;
- RBAC de `teste@pucparana.com`;
- auditoria de login e acesso proibido.

### Ainda pendente
- screenshots finais de demonstração apenas após confirmar que a prova técnica
  correspondente continua válida na ref de freeze.

## 03 — Dados, segredos e containers

### Já selecionar
- MariaDB/phpMyAdmin: SELECT permitido + DML negado;
- evidências CRED-01 de menor privilégio;
- Gitleaks/secret scanning;
- hardening de containers já validado;
- TLS/PKI sanitizado sem chave privada.

### Ainda pendente
- runtime check zero-sudo final após sync das VMs.

## 04 — Wazuh, FIM e detecção

### Já selecionar
- WAZ-02;
- WAF rule 110300;
- Suricata→Wazuh;
- FIM/YARA histórico;
- CRED-01/Wazuh read-only.

### Ainda pendente
- FIM/readiness final após sync, se exigido pelo cenário;
- pfSense→Wazuh pós-reboot.

## 05 — DLP e privacidade

### Já selecionar
- hardening/ACL declarativa do Ferret;
- correções #134/#141;
- documentação LGPD/minimização;
- evidência sanitizada histórica que não contenha payload bruto.

### Ainda pendente
- G3 live na EP126 após sync;
- S11/S13 com marcador fictício;
- prova de que o dado sintético não aparece bruto no SIEM.

## 06 — Bacula

### Já selecionar
- BAC-04B apply;
- backup E2E dos quatro conjuntos;
- restore E2E;
- SHA-256 origem=restore;
- jobs T/R;
- preservação de SmokeJobs;
- BAC-05/risco de Schedule manual;
- registro do risco `PHYSICAL_ISOLATION=0`.

### Não repetir
Não reexecutar backup/restore apenas para obter screenshot melhor.

## 07 — Zero-sudo

### Já selecionar
- CRED-01 EP125/EP126;
- UID/identidade EP126 histórica;
- G2/FIM EP126 já comprovado;
- contratos/documentação de menor privilégio.

### Ainda pendente
- contrato UID + readiness atualizado EP125;
- sync e readiness atualizado EP126;
- G3/Ferret;
- runtime check pós-corte como `teste`.

## AppSec final — raiz do pacote

### Já concluído
- PR #138 mergeado;
- `main=df2ebd5e509c671640efddc524ec5ffbbc4714a3`;
- Static Integrity, PHPUnit, Semgrep e Gitleaks passaram no push da `main`.

### Ainda pendente
Executar **APPSEC Snyk Final Evidence** com:

```text
expected_sha=df2ebd5e509c671640efddc524ec5ffbbc4714a3
```

Preservar:

```text
appsec-snyk-final.txt
appsec-snyk-final.txt.sha256
```

Só fechar APPSEC-04/05 se o TXT contiver:

```text
CI_BOUNDARY=PASS
SCAN_IDENTITY_SUDO=BLOCKED
SNAPSHOT_POSTSCAN_INTEGRITY=PASS
SNYK_TOTAL_RESULTS=0
SNYK_CWE611_RESULTS=0
SNYK_TARGET_CWE611_RESULTS=0
SNYK_CWE23_RESULTS=0
SNYK_APPSEC05_TARGET_CWE23_RESULTS=0
APPSEC04_SNYK_REVALIDATION=PASS
APPSEC05_SNYK_REVALIDATION=PASS
```

## 08 — Pentest S01–S13

**Não preencher antecipadamente.**

Criar somente a estrutura do diretório. Resultados, screenshots, TXT e hashes
entram depois de cada cenário realmente executado.

## 09 — Twingate comparativo

**Não preencher antecipadamente.**

Esse diretório permanece vazio até Pentest A → ativação Twingate → Pentest B.

## Material proibido no pacote final

Não copiar:

- senha;
- token;
- RoleID/SecretID;
- root token;
- unseal/recovery shares;
- PSK;
- chave privada;
- `.env`;
- dump com dado não sanitizado;
- SARIF bruto do Snyk;
- payload bruto de DLP/syslog contendo conteúdo sensível.

## Critério de seleção

Cada evidência escolhida precisa responder, de forma rastreável:

1. qual controle/cenário ela prova;
2. qual origem e destino;
3. qual identidade;
4. qual esperado;
5. qual observado;
6. PASS/FAIL/BLOCK;
7. timestamp;
8. SHA-256;
9. se é evidência histórica, pré-freeze ou pós-freeze.

Screenshots são complemento visual e não substituem TXT/checkpoint técnico.
