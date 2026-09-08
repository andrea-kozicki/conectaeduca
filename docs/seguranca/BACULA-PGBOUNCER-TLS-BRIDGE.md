# Bacula / PostgreSQL — bridge TLS compensatório

## Motivo

Na build Bacula 15.0.3 instalada, a mesma `libpq.so.5` funciona com TLS
1.3 e `verify-full` via `psql`, mas `dbsslmode=require|verify-ca|verify-full`
no Bacula inicia o handshake SSL e encerra a conexão com EOF antes da
autenticação.

## Arquitetura validada

Bacula Director -> Unix socket -> PgBouncer -> TLS verify-full -> PostgreSQL

O trecho Director/PgBouncer não trafega pela rede Docker. O trecho de rede
PgBouncer/PostgreSQL valida a CA e a identidade do servidor.

## Stage 3

A regra ampla:

`host all all all scram-sha-256`

é promovida para:

`hostssl all all all scram-sha-256`

Assim, plaintext entre containers é recusado. Regras loopback locais
permanecem como residual explícito de administração local.

## Segredos

Nenhum verifier, senha, private key ou arquivo `.runtime` deve entrar no Git.
