# WAF da DMZ — Fase 4H

## Objetivo

Adicionar **ModSecurity + OWASP Core Rule Set (CRS)** como reverse proxy WAF
versionado no deploy da DMZ do ConectaEduca.

Imagem fixada:

```text
owasp/modsecurity-crs:4.25.1-nginx-lts
```

## Estado da 4H-B

A 4H-B é propositalmente **não disruptiva**.

Ela adiciona o WAF à frente do Nginx real da aplicação:

```text
127.0.0.1:18080
        |
        v
      WAF
        |
        v
nginx:8080
        |
        v
   php-fpm:9000
```

O binding legado do Nginx em `127.0.0.1:8088` ainda permanece nesta etapa para
não alterar o deploy anteriormente validado.

A remoção da exposição direta do Nginx é requisito da **4H-C**, quando o WAF
passará a ser o único caminho HTTP/HTTPS de entrada para a aplicação.

## Privacidade dos audit logs

A configuração usa:

```text
MODSEC_AUDIT_ENGINE=RelevantOnly
MODSEC_AUDIT_LOG_FORMAT=JSON
MODSEC_AUDIT_LOG_PARTS=AFHZ
```

As partes `B` (request headers) e `C` (request body) não são registradas nesta
baseline. Isso reduz a possibilidade de persistir cookies, tokens, credenciais
ou corpos de formulários no audit log.

A 4H-D fará tuning adicional de logging e falsos positivos antes da integração
com o Wazuh.

## Paranoia level

A baseline começa com:

```text
BLOCKING_PARANOIA=1
DETECTION_PARANOIA=1
ANOMALY_INBOUND=5
ANOMALY_OUTBOUND=4
```

Níveis mais agressivos só serão avaliados depois que a aplicação real estiver
inteiramente atrás do WAF.
