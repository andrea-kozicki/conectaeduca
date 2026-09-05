# Matriz OWASP Top 10:2025 × CWE × CVE × Controles

**Versão:** 2.0 pós-VMs
**Consolidação inicial:** 23/08/2026
**Revisão pós-implantação:** 04/09/2026
**OWASP Top 10 usado:** edição 2025.

## 1. Objetivo

Esta matriz relaciona classes OWASP, exemplos de CWE, fatos/CVEs observados, controles implementados e evidências do ConectaEduca.

O objetivo não é transformar presença de CVE em vulnerabilidade automaticamente explorável. O processo usado no projeto é:

```text
finding
  -> identificar componente
  -> verificar versão e superfície exposta
  -> analisar pré-condições / alcançabilidade
  -> corrigir, atualizar ou registrar risco residual
  -> repetir checkpoint
```

A revisão 2.0 também explicita **evolução, teste e resultado**, para diferenciar controle apenas planejado de controle efetivamente observado.

## 2. Matriz pós-VMs

| OWASP Top 10:2025 | CWEs relevantes | Evolução do projeto | Teste/evidência | Resultado observado | Estado |
|---|---|---|---|---|---|
| **A01 — Broken Access Control** | CWE-862; CWE-863 | autorização saiu de desenho para RBAC server-side com `usuario`, `empresa`, `admin` | testes HTTP por papel; rotas privadas; auditoria | sem sessão → 401; papel insuficiente → 403; `forbidden_access_attempt` registrado | **VALIDADO** |
| **A02 — Security Misconfiguration** | CWE-1188; CWE-276 | de containers funcionais para hardening progressivo; depois das VMs PHP-FPM e Nginx receberam `read_only`, `cap_drop=ALL`, limite de PIDs e tmpfs | Compose, build, healthchecks, Semgrep, inspeção de runtime | superfícies de escrita/privilégio reduzidas; configurações continuaram funcionais | **VALIDADO NO GIT / reconciliar novo freeze nas VMs** |
| **A03 — Software Supply Chain Failures** | CWE-1104; CWE-1395 | Composer Audit/Dependabot/Trivy foram complementados por Actions pinadas, Semgrep e PRs de atualização | Composer validate/audit, PHPUnit, Semgrep, Trivy, revisão de CVEs e PRs | atualizações de phpseclib/phpdotenv/PHPUnit passaram gates; merges registraram 119 testes/351 assertions; findings de configuração geraram correções | **VALIDADO COMO PROCESSO** |
| **A04 — Cryptographic Failures** | CWE-312; CWE-319; CWE-321 | criptografia da aplicação + OpenBao + segredo fora do Git + TLS no WAF; OpenBao permaneceu local na EP126 em vez de abrir HTTP entre zonas | testes `CryptoHybrid`, checkpoints OpenBao, materialização em tmpfs no laboratório local, TLS do endpoint web | AES-256-GCM/RSA-OAEP mantidos; segredo não versionado; API OpenBao não atravessa DMZ; bridge segura cross-VM ainda não foi habilitada | **VALIDADO NO LAB LOCAL / CROSS-VM PENDENTE SE NECESSÁRIO** |
| **A05 — Injection** | CWE-79; CWE-89 | validação da aplicação ganhou WAF/OWASP CRS como defesa adicional | XSS/SQLi/path traversal sintéticos + tráfego legítimo | probes hostis bloqueadas em 403 sem transformar WAF em substituto da validação | **VALIDADO LOCALMENTE; DAST DEDICADO PENDENTE** |
| **A06 — Insecure Design** | CWE-799; CWE-840 | STRIDE, trust boundaries, rate limiting, MFA, DMZ/interna e desenho A/B com Twingate | revisão arquitetural, checkpoints, testes de segmentação e controles de autenticação | controles foram promovidos por evidência; Twingate foi adiado deliberadamente para permitir Pentest A antes/depois | **FORTE / EVOLUTIVO** |
| **A07 — Authentication Failures** | CWE-287; CWE-307 | login local passou a exigir MFA e rate limiting persistente | credencial inválida, MFA, conta/papel, limite de tentativas | 401 em falha; MFA impede conclusão apenas com senha; 429 no limite; eventos de auditoria | **VALIDADO** |
| **A08 — Software or Data Integrity Failures** | CWE-345; CWE-494 | integridade ampliada de lockfiles/Actions para imagens, handoff e restore | pinagem por SHA/digest, SHA256SUMS, restore com comparação de hash | artefatos e snapshots restaurados podem ser comparados; imagem só é promovida após checkpoint | **VALIDADO COMO PROCESSO** |
| **A09 — Security Logging & Alerting Failures** | CWE-778 | de `AuditLogger` local para Wazuh central e depois agentes/FIM/YARA nas VMs | eventos app, `wazuh-logtest`, agentes EP125/EP126, FIM → YARA → regra 110211 | agentes Active via 1514; match YARA classificado em nível 12; 1515 fechado após enrollment | **VALIDADO PARA WAZUH/YARA; DLP E2E A CONSOLIDAR** |
| **A10 — Mishandling of Exceptional Conditions** | CWE-209; CWE-703 | Semgrep passou de gate preventivo a ferramenta que encontrou casos concretos de configuração/erro | regras Semgrep, fixtures positivas e revisão de findings | mensagem interna de exceção foi corrigida; finding de permissão foi tratado com justificativa explícita | **VALIDADO COM CASOS REAIS** |

## 3. CVEs e triagem contextual

### 3.1 Wazuh

A triagem registrou CVEs Critical/High em dependências presentes nas imagens 4.14.7.

A decisão do projeto não foi "scanner limpo". Foi:

- manter versão estável suportada;
- impedir exposição de 9200/55000 entre zonas;
- restringir Dashboard;
- fixar imagens por digest;
- não substituir bibliotecas internas isoladamente;
- reavaliar quando houver release estável apropriado.

A implantação posterior reforçou a superfície mínima: depois do enrollment, TCP/1515 deixou de ser publicado e os agentes permaneceram operacionais por TCP/1514.

**Resultado:** risco residual acompanhado com controles compensatórios reais.

### 3.2 MariaDB / `gosu`

Na triagem registrada, os findings da imagem `mariadb:12.3.2-ubi10` foram atribuídos ao `gosu`, não ao servidor MariaDB.

A CVE crítica analisada foi classificada como não alcançável no uso do `gosu` como mecanismo de troca de UID/GID no entrypoint.

**Resultado:** manter imagem oficial pinada e reavaliar em atualização upstream, sem adulterar manualmente a imagem apenas para reduzir contagem de scanner.

### 3.3 PHP/Nginx pós-VMs

O hardening de setembro alterou a baseline:

- PHP-FPM: `php:8.5.9-fpm-alpine3.24`, build deps removidas, runtime read-only;
- Nginx: nova base/digest, usuário explícito, read-only, capabilities removidas.

**Resultado:** a supply chain continuou sendo revista após a primeira implantação; "freeze" não significou abandonar manutenção.

### 3.4 Ferret

A baseline Git ainda é 2.2.1, enquanto runtime 2.4.3 foi observado na VM interna.

**Resultado:** classificar como drift a reconciliar. Não alterar versão documental sem PR com digest + formatter JSON + sanitizador + checkpoint DLP/Wazuh.

## 4. Evidências de evolução

| Data/fase | Evidência | O que mudou |
|---|---|---|
| 15–17/08 | autenticação/MFA/rate limit | aplicação deixou de depender do Cognito atual |
| 18–21/08 | Wazuh/OpenBao/Ferret | arquitetura passou de app segura para plataforma defensiva |
| 22/08 | Bacula/restore/CVE triage | recuperabilidade e supply chain ganharam critérios verificáveis |
| 23/08 | Semgrep/Actions/pfSense/VM runbooks | DevSecOps e implantação passaram a ser declarativos |
| 27/08 | recuperação EP126 | Git + kit cifrado + snapshot formaram camadas independentes |
| 01–04/09 | Wazuh/YARA + hardening PHP/Nginx | controles "preparados" foram testados e runtime foi novamente reduzido |

## 5. Lacunas reais após a revisão

- OWASP ZAP/DAST dedicado nas VMs;
- Pentest A;
- Twingate;
- Pentest B;
- DLP ponta a ponta via Wazuh Agent, se a evidência ainda não estiver fechada;
- reconciliação Ferret 2.4.3;
- evidência administrativa de pfSense limitada ao que a conta institucional permite;
- NTP ainda dependente do suporte institucional;
- IAST fora do escopo por decisão.

Não são mais lacunas:

- "implantar as VMs" genericamente;
- "ativar Wazuh Agent/FIM/YARA";
- "provar qualquer restore Bacula";
- "provar qualquer segmentação".

Esses itens já possuem evidência em graus diferentes e devem ser descritos com precisão, não como totalmente pendentes.

## 6. Referências internas

- `docs/EVOLUCAO-ARQUITETURA-EC8.md`
- `docs/stride.md`
- `docs/requisitos-seguranca-asvs.md`
- `docs/plano-testes.md`
- `docs/dfd.md`
- `deploy/interna/wazuh/`
- `deploy/interna/bacula/`
- `deploy/pfsense/`
- `docs/evidencias/backup-recuperacao-ep126-20260827.md`

## 7. Referências externas utilizadas pelo projeto

- OWASP Top 10:2025
- OWASP ASVS 5.0.0
- CWE
- NVD
- CISA KEV
- FIRST EPSS
