# PostgreSQL / Bacula — TLS, PgBouncer e hostssl

Data da validação: **08/09/2026**

Host: **EP126**

Estado: **VALIDADO**

## Objetivo

Eliminar tráfego PostgreSQL em claro entre containers sem depender do suporte
TLS nativo observado no Bacula 15.0.3 desta imagem.

A validação mostrou que a mesma `libpq.so.5` da imagem negocia TLS via
`psql`, inclusive `verify-full`, enquanto o backend PostgreSQL do Bacula
inicia a negociação SSL e encerra o handshake com EOF nos modos TLS nativos
testados. A mitigação adotada foi:

```text
Bacula Director
    |
    | Unix socket
    v
PgBouncer
    |
    | TLS verify-full
    v
PostgreSQL Catalog
```

O segmento Director → PgBouncer não usa a rede Docker. O segmento
PgBouncer → PostgreSQL exige TLS com validação de CA e identidade.

## Controles validados

- PostgreSQL com `ssl=on`;
- `VersionId=1026` preservado;
- Director funcional via `bconsole`;
- config do Director em volume somente leitura;
- runtime TLS do Director em volume somente leitura;
- Unix socket PgBouncer compartilhado com o Director;
- PgBouncer 1.24.1 com `server_tls_sslmode=verify-full`;
- backend PgBouncer → PostgreSQL comprovado sob TLS;
- regra ampla do `pg_hba.conf` promovida de `host` para `hostssl`;
- plaintext inter-container recusado;
- conexão direta `verify-full` positiva em **TLS 1.3**,
  cipher **TLS_AES_256_GCM_SHA384**;
- backend PgBouncer novo, criado após `hostssl`, comprovado sob TLS;
- Director e PgBouncer permaneceram operacionais após a promoção;
- arquivo baseline root-only do Bacula permaneceu byte-a-byte intacto.

## Evidência de integridade

- relatório bruto final SHA-256:
  `3e90f9669dc7e347c5f62b400997ac124b77024a98682a8eb52dcec09e772b06`
- pacote repo-ready SHA-256:
  `7ff9dde42aaeb6d3477844d7c194e8b45745cca91b6fd90cc04b7829d93ec903`
- Compose bridge SHA-256:
  `8a83f05325af1edfaf39dc27cdccabe81e345ebac7e5ea1486c0f4c37eaec888`
- config-hash do Director promovido:
  `a7a1c839e5e35c6794ddc639a0e0e8c977a15ac79acff38ae0cb90851ab918f3`
- baseline `bacula-dir.conf` preservado:
  `89dfa49d26e168eb3bd336e4440a4ac7e33219fde5cd1f7d45773f7868d9eea1`
- `pg_hba.conf` final:
  `9c0b6a824cd77a47696c3751a0e087ffa99b2e9a37e2c6f564773b3e19e80fc5`

Evidências diagnósticas anteriores, mantidas fora do Git:

- Stage 2 v6:
  `a0de203047303d006a437f48df73b17728d423c7c7e85c5b877750f60b0c4e2f`
- parser nativo Bacula v3:
  `9c4a6869ce7a342d62c38ea053bd867f4fab47c5291ff40a0bb808addeceffc1`
- diagnóstico libpq:
  `580424a49d3429d12da992c2f48d3a661182574c177cbebbf4df184698c60cb8`

## Risco residual

As regras locais de loopback PostgreSQL continuam permitindo conexão sem TLS.
Esse residual é deliberado e restrito ao próprio container/host lógico do
Catalog. O tráfego entre containers está sujeito a `hostssl`.

## Material sensível

Não são versionados: senhas, SCRAM verifier/`userlist.txt`, chaves privadas,
certificados runtime, `.env`, backups de `bacula-dir.conf`, backup do
`pg_hba.conf`, `bridge-state.env` ou relatório bruto.

O Git contém apenas configuração declarativa, documentação sanitizada e
hashes de integridade.
