# Requisitos de Segurança — OWASP ASVS 5.0.0

**Versão:** 2.0 pós-VMs
**Consolidação inicial:** 23/08/2026
**Revisão pós-implantação:** 04/09/2026
**Referência:** OWASP Application Security Verification Standard 5.0.0.

## 1. Objetivo e rigor

O ConectaEduca usa o ASVS como baseline de requisitos verificáveis.

**Level 2** é referência para os requisitos aplicáveis, mas o projeto não declara certificação nem conformidade integral formal.

A revisão 2.0 adiciona quatro dimensões a cada capítulo:

1. evolução;
2. teste/evidência;
3. resultado;
4. pendência residual.

## 2. Estado por capítulo

| ASVS | Evolução / implementação | Teste/evidência | Resultado | Estado |
|---|---|---|---|---|
| **V1 Encoding and Sanitization** | encoding de saída + validação server-side + WAF adicional | testes XSS/WAF e fluxos legítimos | probes bloqueadas; controle de aplicação continua necessário | **FORTE** |
| **V2 Validation and Business Logic** | `Csrf`, `SecureFormRequest`, `RateLimiter`, serviços/controllers | POST sem CSRF, login, MFA, rate limit | 419 sem CSRF; regras de negócio continuam server-side | **VALIDADO** |
| **V3 Web Frontend Security** | sessão segura e TLS no WAF; frontend atrás do WAF | cookies/sessão, HTTPS, WAF | superfície HTTPS funcional; revisão dedicada de headers nas VMs ainda útil | **PARCIAL/FORTE** |
| **V4 API and Web Service** | autenticação/autorização/validação nos endpoints | testes HTTP por estado e papel | 401/403 coerentes com estado/autorização | **FORTE** |
| **V5 File Handling** | nenhum upload arbitrário integra o baseline; chaves/configs fora da superfície pública | revisão de public root, DLP e regras YARA sintéticas | nenhuma necessidade de upload genérico foi introduzida | **APLICABILIDADE LIMITADA** |
| **V6 Authentication** | autenticação local + MFA + rate limiting + conta ativa | credencial inválida, MFA, rate limit | senha isolada não conclui login; 401/429 conforme teste | **VALIDADO** |
| **V7 Session Management** | cookie seguro, regeneração, logout, pré-auth separada | inspeção de sessão/logout | logout invalida; 401 após logout; replay de cookie roubado permanece risco residual | **FORTE/PARCIAL** |
| **V8 Authorization** | RBAC server-side | testes `usuario`/`empresa`/`admin` | acesso superior negado com 403 e auditoria | **VALIDADO** |
| **V9 Self-contained Tokens** | JWT não é mecanismo principal | revisão arquitetural | não aplicável à autenticação atual | **N/A** |
| **V10 OAuth and OIDC** | Cognito/OIDC retirado da arquitetura atual e preservado como legado | branch/tag histórica | não participa do baseline EC8 | **N/A ATUAL / HISTÓRICO PRESERVADO** |
| **V11 Cryptography** | AES-256-GCM + RSA-OAEP; phpseclib atualizado; OpenBao | testes de criptografia, PR phpseclib 4, checkpoints OpenBao | criptografia funcional após migração; segredos fora do Git | **VALIDADO** |
| **V12 Secure Communication** | TLS na borda; OpenBao mantido local em vez de liberar HTTP entre zonas | endpoint HTTPS; testes de portas; OpenBao loopback | 443 funcional; 8200 bloqueado entre zonas; TLS OpenBao remoto só será exigido se esse fluxo for habilitado | **VALIDADO NO BASELINE ATUAL** |
| **V13 Configuration** | imagens pinadas + non-root/read-only/cap drop + CI de configuração | Compose, Semgrep, hardening PHP/Nginx | superfície reduzida; novo freeze deve reconciliar runtimes já implantados | **FORTE / EVOLUTIVO** |
| **V14 Data Protection** | redaction, DLP sanitizado, OpenBao, backup/restore | Ferret/sanitizador, Wazuh, snapshot Raft, kit cifrado EP126 | conteúdo bruto não deve ir ao SIEM; recuperação possui evidência | **FORTE** |
| **V15 Secure Coding and Architecture** | STRIDE, DFD, DMZ/interna, CI/SAST/SCA, pfSense | PRs, checkpoints, testes bidirecionais de rede | arquitetura evoluiu conforme evidências, não apenas conforme desenho inicial | **VALIDADO COMO PROCESSO** |
| **V16 Security Logging and Error Handling** | `AuditLogger` + Wazuh + YARA + redaction + Semgrep | login/auditoria, `wazuh-logtest`, FIM/YARA, finding de exceção | eventos relevantes existem; YARA chega a regra 110211; erro interno foi corrigido | **VALIDADO / DLP E2E A CONSOLIDAR** |
| **V17 WebRTC** | não utilizado | revisão arquitetural | não aplicável | **N/A** |

## 3. Requisitos concretos e resultados

### 3.1 Autenticação

Requisitos:

- senha correta isoladamente não deve concluir login quando MFA estiver habilitado;
- falha de credencial usa mensagem genérica;
- tentativas sofrem rate limiting;
- conta inativa não autentica;
- recovery codes são controlados.

Testes/resultados observados:

- credencial inválida → **401**;
- MFA mantém estado de pré-autenticação antes da sessão final;
- excesso de tentativas → **429**;
- eventos de login/falha/rate limit são auditados.

**Estado:** VALIDADO.

### 3.2 Sessão

Requisitos:

- `HttpOnly`;
- `Secure` sob HTTPS;
- `SameSite`;
- regeneração após autenticação;
- logout destrutivo.

Resultado:

- fluxo de logout foi exercitado e rota privada volta a **401**;
- risco residual de replay de cookie já roubado permanece.

Melhorias futuras:

- timeout por inatividade;
- timeout absoluto;
- revogação explícita/reautenticação para ações sensíveis.

### 3.3 Autorização

Resultado de testes por papel:

- `usuario` não acessa área de empresa/admin;
- `empresa` não acessa administração;
- `admin` mantém acesso administrativo;
- negação → **403** + evento de auditoria.

**Estado:** VALIDADO.

### 3.4 CSRF / validação

Resultado:

- POST mutável sem token CSRF → **419**;
- token válido permite que a requisição siga para a regra de negócio;
- WAF complementa, mas não substitui a validação da aplicação.

**Estado:** VALIDADO.

### 3.5 Criptografia e segredos

Evolução:

- OpenBao operacional;
- AppRole de mínimo privilégio;
- segredo SMTP materializado em RAM/tmpfs no laboratório local;
- migração para phpseclib 4;
- snapshot Raft incluído no fluxo de backup.

Resultados:

- segredos reais não entram no Git;
- root temporário é revogado;
- snapshot restaurado teve integridade comparada;
- API OpenBao permanece local ao host interno no baseline;
- o consumo do segredo por arquivo é definido para o PHP, mas a entrega segura OpenBao EP126 → host DMZ ainda não foi validada.

**Estado:** OPENBAO E MATERIALIZAÇÃO LOCAL VALIDADOS; BRIDGE CROSS-VM PENDENTE SE O SMTP REAL FOR HABILITADO.

### 3.6 Logging e detecção

Evolução:

```text
AuditLogger
  -> Wazuh central
  -> regras DLP
  -> agentes nas VMs
  -> FIM
  -> Active Response
  -> YARA
```

Resultados:

- EP125/EP126 Active via TCP/1514;
- regra YARA final `110211`, nível 12;
- TCP/1515 fechado depois do enrollment;
- DLP continua limitado a eventos sanitizados.

**Estado:** WAZUH/YARA VALIDADO; DLP E2E A CONSOLIDAR SE NECESSÁRIO.

### 3.7 Configuração / supply chain

Controles:

- Actions pinadas por SHA;
- PRs/checks;
- PHPUnit;
- Semgrep;
- Composer Audit;
- Dependabot;
- Trivy;
- imagens pinadas;
- hardening pós-VMs.

Resultados:

- updates de dependências passaram por gates;
- Semgrep gerou correções reais;
- PHP/Nginx foram novamente endurecidos depois do primeiro deploy.

**Estado:** VALIDADO COMO CICLO.

### 3.8 Comunicação e segmentação

Princípio: somente fluxos funcionalmente necessários devem atravessar DMZ/interna.

Resultado observado:

**EP126 → EP125:** 80, 443 e 9102 alcançáveis; portas administrativas selecionadas bloqueadas.

**EP125 → EP126:** 3306, 9103 e 1514 alcançáveis; SSH, XRDP, OpenBao, Bacula Director, enrollment e API Wazuh bloqueados no teste.

ICMP entre as VMs permaneceu bloqueado.

**Estado:** SEGMENTAÇÃO FUNCIONAL OBSERVADA.

Limitação: a conta pfSense não permite auditoria administrativa integral; não atribuir cada efeito a uma regra específica sem evidência.

### 3.9 Resiliência

Evolução:

- política → Bacula core → restore sintético → snapshot Raft → recuperação EP126.

Resultados:

- restore em laboratório com verificação de hash;
- kit cifrado externo da EP126;
- snapshot Hyper-V;
- Git/freeze como camada de reprodutibilidade.

Risco residual:

- Storage Bacula no mesmo domínio físico da VM interna não cobre perda total desse disco/VM.

**Estado:** VALIDADO EM LABORATÓRIO; evidência pós-VM adicional somente quando necessária.

## 4. Critério para "VALIDADO"

Um requisito só recebe esse estado quando há:

1. artefato/configuração;
2. teste reproduzível;
3. resultado observado;
4. evidência sanitizada;
5. ausência de segredo no artefato;
6. risco residual registrado quando aplicável.

"Implementado" e "validado" não são sinônimos.

## 5. Pendências antes do encerramento acadêmico

- DAST/ZAP;
- Pentest A;
- Twingate;
- Pentest B;
- Ferret 2.4.3 reconciliado com Git;
- DLP E2E, se a evidência ainda não estiver fechada;
- NTP institucional;
- consolidação final das evidências.

## 6. Referências internas

- `docs/EVOLUCAO-ARQUITETURA-EC8.md`
- `docs/dfd.md`
- `docs/stride.md`
- `docs/plano-testes.md`
- `docs/matriz-owasp-cwe-cve.md`

## 7. Referência externa

- OWASP ASVS 5.0.0
