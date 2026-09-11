# WAF da DMZ

## Arquitetura

O ConectaEduca usa **ModSecurity + OWASP Core Rule Set (CRS)** como reverse
proxy WAF na frente do Nginx da aplicação.

```text
cliente
  |
  | HTTPS
  v
ModSecurity + CRS
  |
  | HTTP privado na rede Docker frontend
  v
Nginx
  |
  v
PHP-FPM
```

O Nginx e o PHP-FPM não possuem binding no host quando o WAF está ativo.

## Arquivos Compose

```text
compose.yml          base Nginx + PHP-FPM
compose.waf.yml      WAF + ingresso exclusivo
compose.waf-tls.yml  terminação TLS no WAF
```

O nome do arquivo descreve sua função; os identificadores de fase permanecem
somente nos scripts de evidência.

## TLS

A terminação TLS ocorre no WAF. O certificado e a chave privada são fornecidos
em runtime por caminhos externos ao repositório:

```text
CONECTAEDUCA_WAF_TLS_CERT_FILE
CONECTAEDUCA_WAF_TLS_KEY_FILE
```

Dentro do container eles aparecem somente como:

```text
/run/secrets/waf_tls_cert
/run/secrets/waf_tls_key
```

Nenhum certificado/chave privada real deve ser versionado.

A baseline aceita TLS 1.2 e TLS 1.3.

Na implantação da EP125, a cadeia TLS foi promovida e validada com uma CA interna
exclusiva do laboratório. O certificado do WAF contém SAN para
`conectaeduca.local` e `192.168.6.34`, e a validação foi comprovada por
OpenSSL, `curl` sem bypass e Chrome.

A documentação completa da PKI interna, cadeia de confiança, evidências e
procedimento de renovação está em:

```text
deploy/dmz/TLS-PKI-INTERNA.md
```

O HTTP permanece habilitado somente para redirecionamento para HTTPS.

## Contexto encaminhado ao backend

O WAF envia ao backend:

```text
X-Forwarded-Proto: https
X-Forwarded-Port: 443
X-ConectaEduca-Client-IP: <peer observado pelo WAF>
```

`X-ConectaEduca-Client-IP` é deliberadamente um header interno próprio. O WAF
sobrescreve o valor recebido do cliente antes de encaminhá-lo.

O backend nunca deve confiar em `X-Forwarded-For` arbitrário vindo de clientes.
Quando os access logs forem consolidados, o modelo de confiança será baseado
no fato de que o Nginx não é publicamente acessível e recebe tráfego web do WAF.

## Audit log do ModSecurity

Mantemos:

```text
MODSEC_AUDIT_ENGINE=RelevantOnly
MODSEC_AUDIT_LOG_FORMAT=JSON
MODSEC_AUDIT_LOG_PARTS=AFHZ
```

As partes `B` (request headers) e `C` (request body) permanecem omitidas para
reduzir persistência desnecessária de cookies, tokens e conteúdo de formulários.

## Laboratório x implantação

No laboratório:

```text
127.0.0.1:18080 -> HTTP do WAF (redireciona)
127.0.0.1:18443 -> HTTPS do WAF
```

Na VM real, o binding/port-forward será adequado à arquitetura pfSense e às
portas externas 80/443. A chave privada de produção continuará fora do Git.

## Estado atual e próximos passos

O TLS do WAF na EP125 está validado ponta a ponta e não depende de bypass de
certificado no cliente.

Próximos passos do WAF:

1. manter a documentação e a política de renovação do certificado;
2. testar rotas reais e tratar falsos positivos do CRS de modo mínimo;
3. manter a política de logs e privacidade;
4. preservar o encaminhamento de eventos relevantes ao Wazuh;
5. incluir a validade do certificado nos checkpoints operacionais.
