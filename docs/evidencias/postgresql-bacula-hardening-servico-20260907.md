# PostgreSQL / Bacula Catalog — hardening de serviço

Data de consolidação: 07/09/2026.

## Escopo

Auditoria e hardening do PostgreSQL 17 usado como Catalog do Bacula na EP126 (`192.168.6.50/28`), com foco em autenticação, privilégio mínimo, exposição de rede, logging e reprodutibilidade em fresh volume.

Nenhuma senha, hash de autenticação, token, conteúdo de `env_file` ou chave privada foi versionado.

## Baseline auditado

Controles observados antes da mudança:

- PostgreSQL 17.11; Catalog `healthy`;
- `VersionId=1026`;
- porta 5432 sem publicação no host;
- rede Docker `internal=true`;
- `listen_addresses='*'` contido pela boundary Docker;
- `password_encryption=scram-sha-256`;
- regra geral de rede com SCRAM;
- role `bacula_director` com `LOGIN`, `NOSUPERUSER`, `NOCREATEDB`, `NOCREATEROLE`, `NOREPLICATION` e `NOBYPASSRLS`;
- sem memberships extras;
- `CONNECT` no banco e `USAGE` no schema `public`;
- sem `CREATE` para `bacula_director` e sem `CREATE` para `PUBLIC` no schema `public`;
- CRUD em 37 tabelas;
- `USAGE`, `SELECT` e `UPDATE` em 20 sequências;
- nenhuma função de aplicação `SECURITY DEFINER`;
- `log_statement=none`.

Achados do baseline: regras `trust` existiam somente em socket/loopback; `ssl=off`; `log_connections=off`; `log_disconnections=off`.

Relatório bruto local da auditoria v2: `PASS=39 WARN=3 FAIL=1`. O `FAIL` do helper correspondia às quatro regras `host trust` de loopback, não a exposição externa. SHA-256: `6d2c42cc5e348037f368e550c35c2a5ef984f8ba1625c6e2209141c3ef2634a1`.

## Hardening aplicado no runtime atual

Mudanças:

- todas as regras `trust` locais/loopback do `pg_hba.conf` foram convertidas para `scram-sha-256`;
- `log_connections=on`;
- `log_disconnections=on`;
- reload controlado sem restart.

Validação pós-mudança:

- `pg_hba` efetivo sem nenhuma regra `trust`;
- autenticação SCRAM com credencial administrativa funcional;
- TCP loopback sem password negado;
- socket local sem password negado;
- hash do `pg_hba.conf` alterado conforme esperado;
- Catalog permaneceu `healthy`;
- Bacula Director permaneceu `running`;
- gate final com `VersionId=1026` aprovado;
- rollback não foi necessário.

Relatório bruto local: `PASS=37 WARN=0 FAIL=0`, alteração aplicada=1, rollback=0. SHA-256: `d9e451b4a4b722e364be4f66a8181f381b7e1b89a1819499a449f17b60186156`.

## Reprodutibilidade em fresh volume

Foi executado teste isolado com container, volume e rede Docker descartáveis, sem alterar `conectaeduca-bacula-catalog` nem seus volumes.

Resultado:

- PostgreSQL 17.11 inicializado em volume vazio;
- `password_encryption=scram-sha-256`;
- `log_connections=on` e `log_disconnections=on` desde o fresh volume;
- `pg_hba` sem erros de parsing e sem regra `trust`;
- autenticação positiva com password aprovada;
- TCP loopback sem password negado;
- socket local sem password negado;
- 5432 não publicada no host;
- rede descartável `internal=true`;
- controles preservados após restart;
- `DECISION=REPRODUCIBLE_MECHANISM_VALIDATED`.

Relatório bruto local: `PASS=32 WARN=0 FAIL=0`. SHA-256: `f4db56b07b01550582d05131683239c9473442b73341b7370be63acc2b392e48`.

## Configuração versionada

O mecanismo reprodutível é composto por:

- `deploy/interna/bacula/postgresql/99-conectaeduca-hardening.sh`;
- `deploy/interna/bacula/compose.postgresql-hardening.yml`.

O overlay adiciona ao serviço `catalog` apenas o bind read-only do init script em `/docker-entrypoint-initdb.d/`. O script não contém segredos e só atua na inicialização de um `PGDATA` vazio.

## Estado e risco residual

Autenticação, privilégio mínimo, boundary de rede, logging e integridade do Catalog estão validados no runtime atual e possuem mecanismo de fresh-volume versionado.

O serviço permanece **PARCIAL** até a decisão/implantação de TLS no PostgreSQL. O baseline atual mantém `ssl=off`; a ativação de TLS exige mudança separada com material de certificado, validação do Bacula Director como cliente e rollback específico.
