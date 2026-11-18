# Login híbrido — IP do cliente e limite pré-criptografia

## Contexto

No overlay da DMZ, o tráfego chega pelo WAF e segue para o NGINX e o
PHP-FPM. O WAF sobrescreve `X-ConectaEduca-Client-IP` com o endereço do peer
observado. O NGINX encaminha os cabeçalhos HTTP ao PHP pelo FastCGI; sem
uma regra de confiança explícita, `REMOTE_ADDR` representa o WAF para
requisições encaminhadas.

## Regra de confiança implementada

`TrustedClientIp::current()` consulta o DNS interno do Docker para o
serviço `waf` e compara os endereços retornados com `REMOTE_ADDR`.

- **Peer é o WAF**: aceita um único IP válido no cabeçalho
  `X-ConectaEduca-Client-IP`.
- **Peer não é o WAF**: ignora o cabeçalho, mesmo que ele tenha sido
  enviado por um cliente direto, e usa `REMOTE_ADDR`.
- **DNS indisponível, cabeçalho ausente ou inválido**: usa `REMOTE_ADDR`
  sem ampliar a confiança.
- **`X-Forwarded-For`**: nunca participa dessa decisão.

A identificação é aplicada tanto ao bucket `login_ip` quanto ao bucket
`login_conta_ip`. IPs IPv4 e IPv6 são normalizados antes do hash.
Não se deve substituir essa regra por uma confiança irrestrita em
`X-Forwarded-For` nem aceitar cabeçalhos de clientes diretos.

## Ordem de processamento do POST /login.php

1. Exigir JSON e envelope híbrido v2, com corpo limitado a 16 KiB.
2. Validar `X-CSRF-Token` da sessão **antes de consumir o bucket**.
3. Aplicar limite `login_ip` utilizando a identificação confiável.
4. Descriptografar e validar a tipagem das credenciais.
5. Aplicar limite `login_conta_ip`; após senha correta, seguir ao MFA.

Um envelope com CSRF inválido recebe HTTP 419 sem consumir tentativas
e sem executar RSA/AES. O limite por IP continua antecedendo a
descriptografia. O WAF permanece responsável por bloquear abusos
volumétricos na borda, inclusive emissão repetida de sessões válidas.

## Homologação pendente nas VMs

Os testes locais e do GitHub não substituem a verificação no ambiente:

1. Confirmar que o container PHP resolve `waf` para o peer recebido
   pelo NGINX e que o header customizado é efetivamente sobrescrito
   pelo WAF.
2. Fazer dois acessos com clientes/IPs distintos pela entrada HTTPS
   do WAF e observar buckets `login_ip` distintos, sem registrar
   endereços ou tokens sensíveis em logs públicos.
3. Enviar `X-ConectaEduca-Client-IP` forjado pela entrada direta do
   NGINX (somente na janela de teste autorizada) e comprovar que não
   altera a identidade efetiva.
4. Confirmar HTTP 419 antes do bucket para CSRF inválido e HTTP 429
   para sessão legítima que exceda seu limite, sem expor credenciais.
5. Executar login com senha correta e MFA até o fim, verificando
   os controles TLS, certificado e WAF.

**Limitação conhecida:** diversos usuários sob o mesmo NAT ou sob um
único conector que o WAF enxergue como um peer continuarão compartilhando
o IP observado no WAF. Isso requer validação operacional e limites
adicionais de borda; a correção não afirma identificá-los individualmente
sem um proxy anterior explicitamente confiável.

Até a homologação, a PR #205 deve permanecer em *draft* e a `main`
não deve ser alterada por este conjunto de mudanças.
