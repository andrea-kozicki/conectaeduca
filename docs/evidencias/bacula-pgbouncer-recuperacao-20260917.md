# Recuperação do bridge Bacula/PgBouncer — EP126 — 17/09/2026

## Contexto

Durante a retomada do fluxo de migração do Bacula Storage para o diretório emulado da EP126, o gate funcional do Director falhou: o container aparecia como `healthy`, mas a porta TCP/9101 não estava em LISTEN e o `bconsole` recebia `Connection refused`.

A investigação isolou o problema no bridge PgBouncer usado pelo Bacula Director para acessar o Catalog PostgreSQL.

## Sintoma observado

O runtime do PgBouncer apresentava:

- container em restart loop;
- `pgbouncer.ini` com 0 bytes;
- `userlist.txt` preservado em `0600`, UID/GID `100:101`;
- CA do PostgreSQL preservada em `0644`, UID/GID `100:101`;
- volume de socket em `0770`, UID/GID `100:101`;
- Catalog PostgreSQL saudável.

Os logs do PgBouncer repetiam:

```text
ERROR load_init_file: main section missing from config file
FATAL cannot load config file
```

O Director, por consequência, não conseguia abrir o Catalog e encerrava sem disponibilizar TCP/9101.

A origem do truncamento do `pgbouncer.ini` para 0 bytes **não foi determinada** nesta investigação. O reparo foi orientado pelo estado observado e por uma fonte versionada conhecida, sem assumir causa não comprovada.

## Falha de observabilidade detectada

O incidente também expôs um problema de healthcheck: o container do Director podia aparecer como `healthy` mesmo sem o serviço estar funcional para o `bconsole`.

A partir deste incidente, a validação operacional do Director deve considerar como gate funcional:

```text
TCP/9101 em LISTEN
  +
bconsole conecta com sucesso
  +
status director responde
```

O estado Docker do container continua útil como sinal de infraestrutura, mas não deve ser usado sozinho como prova de disponibilidade do Bacula Director.

## Sequência de recuperação

As tentativas foram conduzidas de forma incremental, com rollback e sem alterar segredos.

### Repair v1

A primeira tentativa usou container auxiliar endurecido para materializar o arquivo. A operação falhou por ordem inadequada entre `chown` e `chmod` sob capabilities reduzidas.

O rollback dessa tentativa também falhou no mesmo ponto de permissão.

### Repair v2

A ordem foi corrigida para `chmod` antes de `chown`. O rollback passou a funcionar, mas a materialização ainda falhou dentro do helper Docker.

Nenhum segredo, Catalog ou Storage foi alterado.

### Repair v3

A estratégia foi alterada: a materialização passou a usar `sudo` pontual no host, diretamente no backing path do volume Docker identificado por `docker inspect`.

Foi adicionado um probe real antes do APPLY:

```text
sudo install
  -> stat/hash
  -> mv atômico
  -> stat/hash
  -> cleanup comprovado
```

Esse probe validou a mesma trilha de filesystem usada pelo reparo real.

O `pgbouncer.ini` foi materializado corretamente e o PgBouncer ficou `healthy`. Os logs mostraram:

- socket Unix em `/run/pgbouncer/.s.PGSQL.6432`;
- conexão do usuário `bacula_director` via Unix socket;
- conexão PgBouncer -> Catalog em `172.22.0.3:5432`;
- TLS 1.3 estabelecido no caminho PgBouncer -> PostgreSQL.

Apesar disso, a v3 produziu falso negativo porque exigia `test -S` do socket executado de dentro do Director. O próprio tráfego registrado provava que o Director estava usando o socket, portanto esse teste foi removido como gate.

O rollback da v3 funcionou e restaurou o arquivo anterior.

### Repair v4 — resultado final

A v4 separou os gates por responsabilidade:

- **PgBouncer:** container `healthy` + socket presente no próprio produtor;
- **Director:** TCP/9101 em LISTEN + `bconsole` funcional;
- **Catalog:** permanece `healthy`;
- **Storage:** permanece no named volume original;
- **Git:** worktree permanece limpa.

Resultado final:

```text
CONFIG_REPAIRED=1
PGBOUNCER_HEALTHY=1
PGBOUNCER_SOCKET_OK=1
DIRECTOR_FUNCTIONAL=1
BCONSOLE_OK=1
NO_JOBS_RUNNING=1
DIRECTOR_RESTART_USED=0
ROLLBACK_USED=0
ATOMIC_PATH_PROBE_OK=1
FINAL=PASS
```

O Director se recuperou sem restart direcionado.

## Cadeia funcional comprovada

```text
Bacula Director
    |
    | Unix socket :6432
    v
PgBouncer
    |
    | PostgreSQL + TLS 1.3
    v
Catalog PostgreSQL
```

A validação E2E do Director confirmou:

- TCP/9101 em LISTEN;
- `bconsole` conectado com sucesso;
- `status director` respondendo;
- `Jobs: run=0, running=0`;
- `No Jobs running.`.

## Proteção de segredos

Durante a recuperação:

- o conteúdo de `userlist.txt` não foi exibido;
- o SCRAM verifier não foi alterado;
- a CA do PostgreSQL não foi alterada;
- nenhum segredo foi versionado;
- nenhuma credencial foi adicionada à evidência;
- não houve `sudo -s` ou shell root persistente;
- privilégios administrativos foram usados apenas em comandos pontuais.

## Retomada do Storage emulado

Após a recuperação do PgBouncer, o `check` v5 do Storage emulado voltou a passar pelos gates funcionais.

Estado observado em 17/09/2026:

```text
READY_FOR_APPLY=1
ACTIVE_MOUNT=ORIGINAL_NAMED_VOLUME
FAIL=0
FINAL=WARN
```

O `WARN` é esperado e corresponde aos riscos já conhecidos:

1. o diretório emulado permanece no mesmo filesystem da raiz da EP126;
2. UID/GID `100:101` do container colidem semanticamente com identidades do host, mitigado por parents `root:root 0700`.

O named volume original, o target residual e o fingerprint registrado ficaram idênticos:

```text
files=2
bytes=23469
sha256-tree=d92f15ba004dbc00ea05db30dd57516c2c3822201fe20cbea2c406063a1958a6
```

O target residual de uma tentativa anterior foi reconhecido como idêntico à fonte atual e pode ser reutilizado pelo próximo APPLY, evitando recópia desnecessária.

## Limitação residual

O storage emulado em:

```text
/srv/conectaeduca-backup/bacula/volumes
```

permanece no mesmo domínio físico de falha da EP126. A validação demonstra isolamento lógico da área de storage e a mecânica de backup/restore, mas **não** demonstra resiliência contra perda física total da VM ou do disco virtual.

## Próximo gate

O próximo passo autorizado é o APPLY controlado do Storage emulado v5.

Depois da ativação do bind, o Bacula ainda deverá executar um novo ciclo completo:

```text
backup
  -> perda simulada da origem
  -> restore isolado
  -> SHA-256 restaurado == SHA-256 original
```

Somente esse teste fechará a validação funcional do novo destino emulado.
