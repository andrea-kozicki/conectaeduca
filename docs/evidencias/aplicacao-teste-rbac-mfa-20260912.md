# Evidência sanitizada — aplicação `teste@pucparana.com` / MFA / RBAC

Data operacional: 11–12/09/2026  
Host principal da aplicação: `ep125-pucpr`  
Zona: DMZ

## Escopo

Evidência resumida da criação da conta de aplicação exigida na atividade, configuração de MFA, autenticação completa e teste negativo de acesso administrativo.

Nenhuma senha, TOTP, recovery code, token, cookie ou hash de autenticação é incluído.

## Preflight do cadastro

```text
HTTP cadastro=200
TLS VERIFY=0
role padrão=usuario
criptografia híbrida presente
senha mínima=8
public key=200
RSA-OAEP confirmado

PASS=14 WARN=2 FAIL=0 GAP=0
```

SHA-256:

```text
1686f6b866ff6c26c94a300f4bd238c0354c02db9fedbbbd76bbb409294328b1
```

## Linha do tempo sanitizada da auditoria

Os timestamps abaixo são os registrados pelo runtime da aplicação.

```json
{"timestamp":"2026-09-12T01:48:22+00:00","event":"usuario_cadastrado","user_id":null,"context":{"usuario_id":1,"role":"usuario","origem":"formulario_criptografado","email":"teste@pucparana.com"}}
{"timestamp":"2026-09-12T01:50:15+00:00","event":"login_password_verified","user_id":null,"context":{"user_id":1,"mfa_configurado":false}}
{"timestamp":"2026-09-12T01:51:36+00:00","event":"mfa_setup_completed","user_id":null,"context":{"user_id":1}}
{"timestamp":"2026-09-12T01:51:39+00:00","event":"mfa_recovery_codes_generated","user_id":null,"context":{"user_id":1,"count":10}}
{"timestamp":"2026-09-12T03:36:19+00:00","event":"login_password_verified","user_id":null,"context":{"user_id":1,"mfa_configurado":true}}
{"timestamp":"2026-09-12T03:36:40+00:00","event":"login_success","user_id":1,"context":{"user_id":1,"role":"usuario","mfa":true}}
{"timestamp":"2026-09-12T03:37:17+00:00","event":"forbidden_access_attempt","user_id":1,"context":{"required_role":"admin","actual_role":"usuario"}}
```

## Resultado da coleta

```text
TARGET_USER_ID=1
REGISTRATION_ROLE=usuario
COUNT_USUARIO_CADASTRADO=1
COUNT_LOGIN_PASSWORD_VERIFIED=2
COUNT_MFA_SETUP_COMPLETED=1
COUNT_MFA_RECOVERY_CODES_GENERATED=1
COUNT_MFA_RECOVERY_CODES_ACKNOWLEDGED=0
COUNT_LOGIN_SUCCESS=1
COUNT_FORBIDDEN_ACCESS_ATTEMPT=1

PASS=16
WARN=0
FAIL=0
GAP=1
```

## Prova de menor privilégio

Sessão autenticada:

```text
role=usuario
mfa=true
```

Recurso privilegiado solicitado:

```text
/admin/auditoria.php
```

Política exigida:

```text
required_role=admin
```

Papel efetivo:

```text
actual_role=usuario
```

Resultado:

```text
HTTP 403 / Acesso negado
forbidden_access_attempt
```

## Custódia dos recovery codes

Foram gerados 10 códigos de recuperação.

Tratamento:

```text
plaintext temporário em /dev/shm
→ AES-256-CBC
→ PBKDF2-HMAC-SHA256 / 300000 iterações
→ ciphertext com permissão 600
→ transferência transitória
→ SHA-256 validado na EP126
→ cópias transitórias removidas
```

SHA-256 do ciphertext:

```text
c9a42f99e15a3adca1788aee546b2f47fc683a8c98938ca4df0375103978d341
```

Relatórios:

```text
c72d51cd0d5ce41e51bf067b055353ff27e2fba46321d7387351da5991b4e7e6  conectaeduca-evidencia-custodia-mfa-teste-20260911-231333.txt
f6fa76d09019781bcdc923c8217b45dbfba18fd8022660337dc6813a89689507  conectaeduca-evidencia-importacao-mfa-drive-ep126-20260912-003151.txt
```

## GAP conhecido

`mfa_recovery_codes_acknowledged` não foi registrado porque a janela de pré-autenticação expirou durante a custódia segura dos recovery codes.

A correção foi deliberadamente adiada para backlog. Nenhuma mudança de código faz parte desta documentação.

## Integridade da evidência RBAC

```text
d23c40cf3fc46d4e077626d96641986d4dd5dddbf645de125471bd03dfbca0a5  conectaeduca-evidencia-rbac-aplicacao-ep125-v2-20260912-004219.txt
```

## Conclusão

```text
[PASS] Cadastro com role mínimo.
[PASS] MFA configurado.
[PASS] Login completo com role=usuario e mfa=true.
[PASS] Acesso administrativo bloqueado.
[PASS] Bloqueio registrado em auditoria.
[GAP] Acknowledgment persistente dos recovery codes pendente como melhoria futura.
```
