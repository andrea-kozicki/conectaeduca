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

## 3B — builds/dependências — CONCLUÍDA NO REPO

A mini-fase não tentou converter builds com APT/APK em reprodutibilidade
bit-a-bit por meio de versões inventadas. O contrato adotado diferencia
**determinismo da base** de **rastreabilidade do refresh de segurança**.

### Alterações implementadas

- Nginx local:
  - base externa continua pinada por digest;
  - label OCI de commit obrigatório;
  - política `base-digest`;
  - `build-provenance.txt`.

- PHP-FPM local:
  - label OCI de commit obrigatório;
  - política `security-refresh-traceable`;
  - manifesto completo de pacotes Alpine após o refresh;
  - proveniência embutida na imagem.

- WAF local:
  - label OCI de commit obrigatório;
  - política `security-refresh-traceable`;
  - manifesto completo de pacotes Debian após `apt upgrade`;
  - contexto de build normalizado para a raiz do repositório.

- Bacula Director/Storage:
  - pacotes Bacula principais continuam fixados em `15.0.3-3`;
  - label OCI de versão/commit;
  - manifesto dos pacotes efetivamente instalados;
  - política `security-refresh-traceable`.

- PgBouncer:
  - `PGBOUNCER_UPSTREAM_VERSION=1.24.1`;
  - build falha se o binário instalado não reportar `1.24.1`;
  - versão Debian efetiva do pacote é gravada separadamente;
  - manifesto completo de pacotes;
  - parent image ref no Dockerfile e parent image ID no build oficial.

- Contexto Docker:
  - `.dockerignore` agora exclui qualquer `.runtime`, secrets, credentials,
    material criptográfico e artefatos efêmeros.

- Build oficial:
  - novo `scripts/build/construir_imagens_locais.sh`;
  - exige Git limpo;
  - injeta o SHA do commit;
  - constrói DMZ/Bacula em ordem explícita;
  - gera aliases `-git-<sha12>`;
  - gera relatório e TSV com SHA-256;
  - `--plan` não toca no Docker.

### Limite explícito

PHP, WAF e a base Bacula ainda consultam repositórios APK/APT durante o build.
Logo, o projeto **não afirma rebuild bit-a-bit idêntico** para essas imagens.
A 3B transforma essa mutabilidade em estado observável e rastreável, sem
mascará-la sob tags locais estáveis.

A decisão futura entre snapshots de repositório e refresh contínuo de segurança
fica separada de ajustes cosméticos de pinagem.

## 3C — gate automático de supply chain — CONCLUÍDA NO REPO

Workflow versionado:

` .github/workflows/supply-chain-build.yml `

Validação funcional no commit `189975315c2d89c104109eb6b6b3e3fbbd6ad40c`:

- Repository Static Integrity #67: **PASS**;
- Supply Chain Build Gate #2 / run `35368769143`: **PASS**.

### Camada 1 — policy estática

O job `Supply chain policy` valida automaticamente:

- `scripts/build/construir_imagens_locais.sh --alvo all --plan`;
- bases externas de Dockerfile pinadas por digest;
- aliases multi-stage tratados como stages internos, não imagens externas;
- imagens externas dos Compose pinadas por digest;
- marcadores obrigatórios de provenance nos Dockerfiles locais;
- padrões obrigatórios de exclusão no `.dockerignore`;
- presença dos controles do orquestrador oficial;
- PgBouncer prometendo e verificando `1.24.1`.

Resultado: **PASS**.

### Camada 2 — build real do Nginx DMZ

O runner construiu `conectaeduca/nginx:supply-chain-ci` com o commit da
execução injetado no build.

O gate comprovou:

- `org.opencontainers.image.revision` igual ao commit construído;
- `io.conectaeduca.build-policy=base-digest`;
- `build-provenance.txt` presente;
- `source_commit` coerente;
- `package_policy=base-image-only`.

Resultado emitido:

`NGINX_SUPPLY_CHAIN_BUILD=PASS`

Image ID observado nessa execução:

`sha256:6e3a52fb20318798de897cbe7bca52e01b4c68080868ef4ae337ab163b2da51c`

Esse image ID é evidência da execução de CI, não referência estável a ser
copiada para o Git.

### Camada 3 — build real Bacula Director → PgBouncer

O runner construiu primeiro
`conectaeduca/bacula-director:15.0.3` a partir de
`Dockerfile.vm --target director`.

Em seguida construiu
`conectaeduca/pgbouncer:1.24.1-tls-bridge` sobre o Director recém-gerado.

O build do bridge comprovou:

- pacote Bacula principal `15.0.3-3`;
- `pgbouncer --version` retornando `PgBouncer 1.24.1`;
- commit-fonte coerente no provenance;
- `pgbouncer_upstream_version=1.24.1`;
- parent image ID gravado no bridge;
- parent image ID idêntico ao image ID do Director recém-construído.

Resultado emitido:

`BACULA_PGBOUNCER_SUPPLY_CHAIN_BUILD=PASS`

Na execução de prova:

- Director image ID:
  `sha256:76ac80a1cee13e74181d8ef9e9bc79ed7e5aa47f410b7efc34f727893871df20`;
- PgBouncer parent image ID:
  `sha256:76ac80a1cee13e74181d8ef9e9bc79ed7e5aa47f410b7efc34f727893871df20`.

### Escopo deliberado dos builds de CI

A 3C **não executa build completo de PHP e WAF em todo PR**. Essas receitas
permanecem cobertas pelo gate estático de digest/proveniência, enquanto os
builds reais são concentrados em:

1. Nginx, como prova leve do mecanismo de provenance;
2. Bacula → PgBouncer, como cadeia local crítica com vínculo pai/filho e versão
   funcional assertada.

Essa escolha reduz custo/tempo de runner sem chamar uma verificação estática de
"build validado".

O scan de vulnerabilidades das imagens efetivamente promovidas continua sendo
um checkpoint separado.
