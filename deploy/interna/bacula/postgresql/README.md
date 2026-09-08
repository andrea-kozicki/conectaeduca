# PostgreSQL / Bacula Catalog — hardening reprodutível

Este diretório contém o mecanismo de hardening aplicado **somente na criação de um `PGDATA` vazio** do PostgreSQL usado como Catalog do Bacula.

## Controles

O arquivo `99-conectaeduca-hardening.sh`:

- substitui regras `trust` geradas pelo `initdb` por `scram-sha-256`;
- habilita `log_connections=on`;
- habilita `log_disconnections=on`;
- não contém senha, hash, token ou chave.

O mecanismo foi validado em container/volume descartáveis com PostgreSQL 17.11, rede Docker `internal=true`, 5432 sem publicação no host, autenticação positiva com password, testes negativos sem password e revalidação após restart.

## Uso obrigatório do overlay

Na VM interna:

```bash
docker compose \
  -f compose.vm.yml \
  -f compose.postgresql-hardening.yml \
  config

docker compose \
  -f compose.vm.yml \
  -f compose.postgresql-hardening.yml \
  up -d
```

No laboratório local:

```bash
docker compose \
  -f compose.yml \
  -f compose.postgresql-hardening.yml \
  config
```

O overlay adiciona somente o bind read-only do init script ao serviço `catalog`.

## TLS do Catalog e bridge Bacula/PgBouncer

O TLS permanece separado do hardening de criação do `PGDATA`, mas agora possui
mecanismo próprio versionado e validado.

Arquitetura validada:

`Bacula Director -> Unix socket -> PgBouncer -> TLS verify-full -> PostgreSQL`

Arquivos relacionados:

- `../compose.director-pgbouncer.yml`
- `../pgbouncer/Dockerfile`
- `../pgbouncer/pgbouncer.ini.template`
- `99z-conectaeduca-hostssl.sh`
- `../../../../docs/seguranca/BACULA-PGBOUNCER-TLS-BRIDGE.md`

No PostgreSQL, a regra ampla de rede é promovida para `hostssl`, enquanto
regras loopback permanecem como residual explícito de administração local.
Plaintext inter-container e `verify-full` foram testados funcionalmente.

## Importante

- Em volume já existente, `/docker-entrypoint-initdb.d` não é reaplicado. O runtime atual foi endurecido separadamente e permanece persistente no volume existente.
- **Não apague `catalog-data` apenas para reaplicar este hardening.** A exclusão do volume destruiria o Catalog.
- TLS do PostgreSQL não faz parte deste mecanismo de criação do `PGDATA`; a mudança própria foi implementada e validada via bridge Bacula/PgBouncer + `hostssl`, com material runtime fora do Git.
- Evidências brutas ficam fora do Git quando houver risco de material sensível; no repositório entra apenas síntese sanitizada e SHA-256.
