# Privilégio mínimo — conta de aplicação `teste@pucparana.com`

## Objetivo

Documentar a criação, autenticação e validação de **menor privilégio** da conta de aplicação exigida na atividade de Experiência Criativa 8, sem alterar o código-fonte da aplicação nesta etapa.

A conta foi criada pelo fluxo público normal do ConectaEduca e validada em produção de laboratório na **EP125 / DMZ**.

Nenhuma senha, TOTP, código de recuperação, cookie, token ou hash de autenticação é versionado neste documento.

## Identidade validada

```text
Conta: teste@pucparana.com
Nome exibido: Usuário Teste PUCPR
Role: usuario
ID observado: 1
MFA: ativo
```

A senha padrão definida pelo professor possui 10 caracteres e atende à política atual da aplicação, que exige no mínimo 8 caracteres. O valor da senha não é registrado.

## 1. Pré-validação do fluxo público

Antes do cadastro foi executado um preflight somente leitura na EP125.

Resultado:

```text
PASS=14
WARN=2
FAIL=0
GAP=0
```

Foram confirmados:

- HTTPS válido sem `-k` / `--insecure`;
- página de cadastro respondendo HTTP 200;
- formulário com `role=usuario` como padrão;
- indicação de envio pelo fluxo de criptografia híbrida;
- interface com senha mínima de 8 caracteres;
- endpoint de chave pública respondendo HTTP 200;
- algoritmo público RSA-OAEP.

Os dois WARNs vieram de um GET não mutante no endpoint de processamento: o pedido recebeu HTTP 403 antes de chegar ao comportamento esperado de 405 da aplicação. Nenhum cadastro foi criado por esse teste.

## 2. Criação pelo fluxo público e menor privilégio

A conta foi criada pela própria interface pública com o tipo **Usuária/candidata**, correspondente a:

```text
role=usuario
```

O backend limita o cadastro público aos papéis `usuario` e `empresa`, impedindo a criação pública de `admin`.

A auditoria registrou:

```json
{"event":"usuario_cadastrado","context":{"usuario_id":1,"role":"usuario","origem":"formulario_criptografado","email":"teste@pucparana.com"}}
```

Isso comprova simultaneamente:

- criação da identidade;
- papel mínimo `usuario`;
- uso do fluxo de formulário criptografado.

## 3. MFA obrigatório

Após a validação da senha, o fluxo exigiu MFA TOTP.

Eventos correlacionados:

```text
login_password_verified
mfa_setup_completed
mfa_recovery_codes_generated
```

A aplicação gerou 10 códigos de recuperação. Nenhum código é registrado em Git, relatório ou Trello.

## 4. Custódia dos códigos de recuperação

Os códigos foram tratados como segredo sensível.

Fluxo adotado:

```text
códigos exibidos
    ↓
/dev/shm na EP125
    ↓
AES-256-CBC
PBKDF2-HMAC-SHA256
300000 iterações
    ↓
ciphertext .enc
permissão 600
    ↓
transferência transitória pelo Google Drive
    ↓
validação SHA-256 na EP126
    ↓
custódia final na zona INTERNA
    ↓
remoção das cópias transitórias
```

O plaintext foi removido de `/dev/shm` após a validação da descriptografia.

Ciphertext validado:

```text
c9a42f99e15a3adca1788aee546b2f47fc683a8c98938ca4df0375103978d341
```

Custódia final:

```text
EP126:
/home/andrea.kiew/.local/share/conectaeduca/segredos/teste-pucparana-mfa-recovery.enc
permissões: 600
```

A EP125 não mantém cópia persistente do ciphertext após a conclusão da transferência.

### Decisão arquitetural sobre SSH

Foi tentado primeiro o transporte direto por SSH/SCP.

Os diagnósticos mostraram:

- EP125 → EP126: rota presente, TCP/22 em timeout;
- EP126: SSH escutando em `0.0.0.0:22` e respondendo localmente;
- EP126 → EP125: rota presente, TCP/22 em timeout.

A decisão foi **não abrir uma nova exceção de firewall entre DMZ e INTERNA apenas para transportar um segredo já cifrado**. O Google Drive foi usado somente como canal transitório de transporte do ciphertext, com validação SHA-256 na chegada e remoção das cópias transitórias.

## 5. Autenticação completa

Após o MFA, o dashboard apresentou a identidade autenticada com:

```text
Nome: Usuário Teste PUCPR
E-mail: teste@pucparana.com
Perfil: usuario
```

A auditoria registrou:

```json
{"event":"login_success","user_id":1,"context":{"user_id":1,"role":"usuario","mfa":true}}
```

Isso prova que a sessão só foi concluída depois do segundo fator e permaneceu com o papel mínimo `usuario`.

## 6. Validação do RBAC

Com a mesma sessão autenticada foi solicitado:

```text
/admin/auditoria.php
```

Esse recurso exige explicitamente o papel `admin`.

Resultado visual:

```text
Acesso negado.
```

A auditoria registrou:

```json
{"event":"forbidden_access_attempt","user_id":1,"context":{"required_role":"admin","actual_role":"usuario"}}
```

Portanto, o controle de acesso não depende apenas da interface: o backend aplicou o RBAC e bloqueou a elevação indevida de privilégio.

## 7. Evidência consolidada

A coleta sanitizada do `audit.log` efêmero do container PHP terminou com:

```text
PASS=16
WARN=0
FAIL=0
GAP=1
```

Foram comprovados:

- `usuario_cadastrado`;
- `role=usuario`;
- `origem=formulario_criptografado`;
- `login_password_verified`;
- `mfa_setup_completed`;
- geração de 10 recovery codes;
- `login_success` com `role=usuario` e `mfa=true`;
- `forbidden_access_attempt`;
- `required_role=admin`;
- `actual_role=usuario`.

## 8. GAP não bloqueante — acknowledgment dos recovery codes

O único GAP foi a ausência do evento:

```text
mfa_recovery_codes_acknowledged
```

A causa observada foi operacional: durante a etapa de custódia segura dos códigos, a janela de pré-autenticação expirou. O fluxo de apresentação dos códigos mantém uma janela curta e, após a expiração, um novo login com MFA já configurado pôde prosseguir normalmente.

A aplicação atualmente não persiste um estado de negócio equivalente a “recovery codes reconhecidos/salvos pelo usuário”.

### Melhoria futura

Sem alterar o código nesta entrega, fica registrado para backlog:

1. persistir o estado de acknowledgment dos códigos de recuperação;
2. diferenciar “códigos gerados” de “códigos confirmados como salvos”;
3. impedir que o onboarding MFA seja considerado totalmente concluído enquanto essa confirmação não estiver registrada;
4. manter o comportamento sem exposição dos códigos em logs.

Esse GAP **não invalida o requisito de menor privilégio**, pois a configuração do MFA, o login completo e o bloqueio RBAC foram comprovados independentemente.

## 9. Integridade das principais evidências

```text
1686f6b866ff6c26c94a300f4bd238c0354c02db9fedbbbd76bbb409294328b1  conectaeduca-preflight-cadastro-aplicacao-ep125-20260911-224351.txt
c72d51cd0d5ce41e51bf067b055353ff27e2fba46321d7387351da5991b4e7e6  conectaeduca-evidencia-custodia-mfa-teste-20260911-231333.txt
f6fa76d09019781bcdc923c8217b45dbfba18fd8022660337dc6813a89689507  conectaeduca-evidencia-importacao-mfa-drive-ep126-20260912-003151.txt
d23c40cf3fc46d4e077626d96641986d4dd5dddbf645de125471bd03dfbca0a5  conectaeduca-evidencia-rbac-aplicacao-ep125-v2-20260912-004219.txt
```

Evidências complementares da decisão de transporte:

```text
b5048d7e4b0d564abe4dc66124f435fe6b68831dfcbd55b8e7f020e7f29612e4  conectaeduca-evidencia-transferencia-mfa-ep125-ep126-20260911-231640.txt
e28c5ee0168fb4706e3b1f8f48acd9ced2a7c2b5743010c06b2b2b744f6f3e24  conectaeduca-diagnostico-ssh-ep125-20260911-231822.txt
e437666d0e69e9423054703b5137359aca94ea89538aa14a482046e90487101c  conectaeduca-diagnostico-ssh-ep126-20260911-234353.txt
bc4a94dcb2986e62163348b0f0107d22ac3346be6f21c841ced61398308ac83c  conectaeduca-diagnostico-ssh-reverso-ep126-ep125-20260911-234706.txt
```

## Estado

**Conta de aplicação `teste@pucparana.com`: requisito de privilégio mínimo concluído e validado.**

O GAP de acknowledgment dos recovery codes permanece documentado como melhoria futura e não será corrigido nesta PR.
