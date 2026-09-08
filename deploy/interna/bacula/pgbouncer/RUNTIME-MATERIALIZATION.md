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

Nunca versionar o `userlist.txt`, verifier, senha ou cópias runtime.
