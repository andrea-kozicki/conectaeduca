# WAF da DMZ

## Papel arquitetural

O WAF do ConectaEduca é baseado em **ModSecurity + OWASP Core Rule Set (CRS)** e
atua como reverse proxy na frente do Nginx da aplicação.

Imagem fixada:

```text
owasp/modsecurity-crs:4.25.1-nginx-lts
```

## Topologia após a Fase 4H-C

```text
host / futura interface pública
            |
            v
     ModSecurity + CRS
            |
       rede frontend
            |
            v
       nginx:8080
            |
            v
       php-fpm:9000
```

Ao usar:

```text
compose.yml + compose.waf.yml
```

o `compose.waf.yml` remove a publicação direta do Nginx definida no Compose
base. O Nginx continua alcançável pelos serviços autorizados na rede Docker
`frontend`, mas não possui binding no host.

No laboratório, apenas o WAF é publicado:

```text
127.0.0.1:18080 -> waf:8080
```

A publicação definitiva em 80/443 será tratada junto da terminação TLS no WAF;
esta etapa prova primeiro a exclusividade do caminho HTTP sem misturar a
migração de certificados com a mudança de superfície.

## Privacidade dos audit logs

Baseline:

```text
MODSEC_AUDIT_ENGINE=RelevantOnly
MODSEC_AUDIT_LOG_FORMAT=JSON
MODSEC_AUDIT_LOG_PARTS=AFHZ
```

As partes `B` (request headers) e `C` (request body) permanecem omitidas. O WAF
continua inspecionando o tráfego para aplicar as regras; a restrição é sobre o
que persiste no audit log.

## Próximos passos

Depois da exclusividade de entrada:

1. terminação TLS no WAF e propagação segura do contexto HTTPS ao backend;
2. tuning de falsos positivos e limites;
3. integração dos eventos do WAF com o Wazuh;
4. checkpoint final do WAF.
