# Pente fino — Fase 3: supply chain e builds — 18/09/2026

## Objetivo

Auditar a cadeia de fornecimento do ConectaEduca sem acesso às EP125/EP126,
separando referência de imagem, receita de build, dependências obtidas durante
o build e ferramentas de CI.

Esta fase é **repo-only**. Pinagem no Git não substitui reconstrução e validação
live das imagens finais.

## Mini-fases

- **3A — inventário e classificação de proveniência**;
- **3B — builds reproduzíveis e dependências de sistema**;
- **3C — gate automático de supply chain no CI**;
- **3D — consolidação e fechamento**.

## 3A — inventário e classificação — CONCLUÍDA NO REPO

### Imagens externas usadas como base de Dockerfile

| Receita | Referência | Estado |
|---|---|---|
| DMZ Nginx | `nginx:stable-alpine@sha256:...` | digest pinado |
| Composer stage | `composer:2@sha256:...` | digest pinado |
| PHP-FPM | `php:8.5.9-fpm-alpine3.24@sha256:...` | digest pinado |
| WAF | `owasp/modsecurity-crs:4.25.1-nginx-lts@sha256:...` | digest pinado |
| Bacula base | `debian:trixie-slim@sha256:...` | digest pinado |

### Imagens externas de runtime em Compose

Foram encontradas referências externas pinadas por digest para:

- PostgreSQL 17 / Bacula Catalog;
- Ferret Scan 2.4.3;
- MariaDB 12.3.2;
- OpenBao 2.6.1;
- Twingate Connector;
- Wazuh Manager 4.14.7;
- Wazuh Indexer 4.14.7;
- Wazuh Dashboard 4.14.7;
- Mailpit de laboratório.

Nenhuma referência externa de runtime observada no baseline final depende
somente de uma tag flutuante.

### Imagens locais do projeto

As seguintes referências são deliberadamente locais e, portanto, não podem ser
avaliadas apenas pelo texto do Compose:

- `conectaeduca/php-fpm:dmz`;
- `conectaeduca/nginx:dmz`;
- `conectaeduca/waf:dmz`;
- `conectaeduca/bacula-director:15.0.3`;
- `conectaeduca/bacula-storage:15.0.3`;
- `conectaeduca/bacula-filedaemon:15.0.3` — laboratório;
- `conectaeduca/pgbouncer:1.24.1-tls-bridge`.

Para essas imagens, a fonte de proveniência é a **receita de build + entradas do
build + dependências instaladas**, e não a tag local.

### CI e dependências PHP

O baseline observado possui:

- `actions/checkout` fixado por SHA;
- `shivammathur/setup-php` fixado por SHA;
- Gitleaks 8.30.1 com SHA-256 do asset verificado antes da extração;
- Semgrep 1.173.0 instalado por versão exata;
- Composer 2.10.2 no workflow PHPUnit;
- `composer.lock` versionado;
- `composer install` baseado no lock;
- `composer audit --locked` no CI.

O `composer.json` usa constraints semânticas para manutenção normal, enquanto
o lock registra as versões/revisões efetivamente instaladas.

## Gaps encontrados para a 3B

### 1. Bridge PgBouncer: tag promete versão que o build não fixa

`deploy/interna/bacula/pgbouncer/Dockerfile` usa:

```text
ARG BACULA_BASE_IMAGE=conectaeduca/bacula-director:15.0.3
apt-get install ... pgbouncer
```

A imagem final é referenciada como
`conectaeduca/pgbouncer:1.24.1-tls-bridge`, mas a receita não fixa nem comprova
a versão do pacote PgBouncer. Uma reconstrução posterior pode produzir conteúdo
diferente sob a mesma tag local.

### 2. APT upgrade mutável

Os Dockerfiles WAF e Bacula executam `apt-get upgrade`. Mesmo com a imagem base
fixada por digest, o conteúdo obtido dos repositórios Debian/Ubuntu em uma data
futura pode mudar.

No Bacula, os pacotes principais são fixados por
`BACULA_VERSION=15.0.3-3`, mas `dma` e `ca-certificates` continuam sem versão
explícita.

### 3. APK mutável no PHP

O Dockerfile PHP fixa a imagem base por digest, porém usa:

- `apk add` sem versões explícitas para bibliotecas;
- `apk upgrade` de OpenSSL/cURL sem versões fixas.

Isso é útil para incorporar correções de segurança, mas não é uma reconstrução
bit-a-bit determinística. O projeto precisa declarar qual objetivo prevalece:
**rebuild determinístico** ou **rebuild atualizado com verificação posterior**.

### 4. Imagem local como base de outra imagem local

O PgBouncer deriva de
`conectaeduca/bacula-director:15.0.3` apenas por tag. Como a imagem é local, a
3B deve definir uma forma de vincular o bridge ao conteúdo efetivamente
construído do Director, ou ao menos registrar/verificar o image ID/digest local
esperado no processo de build.

## Decisão de escopo da 3A

A 3A **não altera versões de pacotes nem Dockerfiles**. Ela fecha apenas o
inventário e a classificação de proveniência para que a 3B não faça pinagem
arbitrária ou cosmética.

Nenhum gap acima é declarado resolvido nesta mini-fase.
