# Runtime do bridge Bacula/PgBouncer

Volumes externos esperados:

- `conectaeduca-bacula-director-config`
- `conectaeduca-bacula-director-tls`
- `conectaeduca-bacula-pgbouncer-config`
- `conectaeduca-bacula-pgbouncer-socket`

## Director

O `bacula-dir.conf` promovido fica no volume `director-config`, com
`root:root 0600`. O volume é montado em `/etc/bacula-runtime` (diretório),
e o Director lê `/etc/bacula-runtime/bacula-dir.conf`. O Catalog deve usar:

- `DB Address = "/run/pgbouncer"`
- `DB Port = 6432`
- nenhuma diretiva `dbssl*`

O volume `director-config` deve conter previamente o diretório vazio
`tls/` (`root:root 0755`). Isso é necessário porque o volume inteiro é montado
somente leitura em `/etc/bacula-runtime`; o runtime OCI precisa encontrar o
mountpoint `/etc/bacula-runtime/tls` já existente para encaixar o segundo
volume somente leitura.

O runtime TLS usado pelos recursos File/Storage do Director é copiado para o
volume externo `conectaeduca-bacula-director-tls` e montado somente leitura
em `/etc/bacula-runtime/tls`.

O arquivo baseline root-only do host e o diretório TLS root-only não precisam
ter suas permissões afrouxadas e permanecem como fontes seguras de rollback.

## PgBouncer

O volume `pgbouncer-config` contém runtime não versionável:

- `userlist.txt` com SCRAM verifier: `bacula:bacula 0600`
- CA pública do PostgreSQL: `0644`
- `pgbouncer.ini`: `0644`

O volume `pgbouncer-socket` deve ter owner/grupo `bacula` e modo `0770`.

O baseline mantém `listen_addr =` vazio: PgBouncer **não** deve abrir listener
TCP apenas para CRED-01. Consumidores autorizados usam o named volume
`conectaeduca-bacula-pgbouncer-socket` e o socket
`/run/pgbouncer/.s.PGSQL.6432`. A rede `bacula-backend` permanece necessária
para a conexão de saída PgBouncer -> Catalog PostgreSQL, não como superfície de
entrada do cliente CRED-01.

Nunca versionar o `userlist.txt`, verifier, senha ou cópias runtime.


## Gates operacionais após incidente de 17/09/2026

O estado Docker de um container não é suficiente, isoladamente, para provar a
disponibilidade funcional do bridge.

Após o incidente em que o Director aparecia como `healthy` sem disponibilizar
TCP/9101, os gates ficam definidos assim:

### PgBouncer

O PgBouncer é considerado funcional quando:

- o container está `running` e `healthy`;
- o socket `/run/pgbouncer/.s.PGSQL.6432` existe no próprio container produtor;
- os logs não indicam falha fatal de carregamento de configuração.

A existência do socket não deve ser usada isoladamente como prova end-to-end do
consumidor.

### Director

O Director é considerado funcional quando:

- TCP/9101 está efetivamente em estado LISTEN;
- o `bconsole` conecta;
- `status director` responde.

Quando necessário para operações de manutenção, `No Jobs running.` deve ser
comprovado pelo `bconsole` antes de quiesce/recreate.

### Catalog

O Catalog deve permanecer `healthy`. No caminho atual, o Director acessa o
Catalog pelo socket Unix do PgBouncer, e o PgBouncer estabelece a conexão com o
PostgreSQL usando TLS.

A evidência do incidente e da recuperação está em:

```text
docs/evidencias/bacula-pgbouncer-recuperacao-20260917.md
```
