# Bacula — ConectaEduca

Implementação de backup e restore do ConectaEduca para o laboratório e para a implantação nas VMs Ubuntu.

A arquitetura foi definida antes da implementação para evitar backup indiscriminado de volumes Docker, segredos ou dados sem estratégia de consistência.

## Componentes

### VM interna

- Bacula Director em container;
- Bacula Storage Daemon em container;
- PostgreSQL dedicado ao Catalog em container;
- `bconsole` administrativo efêmero;
- Bacula File Daemon **nativo** no Ubuntu final.

### VM DMZ

- Bacula File Daemon **nativo** no Ubuntu final.

O File Daemon containerizado existente no laboratório é somente uma bancada de teste e **não entra no handoff final**.

## Estado atual

O núcleo Bacula está implementado e validado com:

- configuração runtime separada do Git;
- credenciais protegidas;
- FileSets por allowlist;
- exclusões explícitas para material sensível;
- Director, Storage, Catalog e PgBouncer em runtime endurecido;
- conectividade cross-zone mínima entre Interna e DMZ;
- TLS comprovado no fluxo Director -> File Daemon DMZ;
- backup sintético cross-zone concluído;
- perda simulada da origem;
- restore isolado na DMZ concluído;
- comparação SHA-256 pós-restore idêntica ao artefato original;
- prova de consistência do MariaDB em staging sintético;
- integração com snapshot Raft do OpenBao.

A evidência operacional fresh de 14/09/2026 está documentada em:

```text
docs/evidencias/bacula-crosszone-dmz-20260914.md
```

## Validação cross-zone nas VMs acadêmicas atuais

Fluxo efetivamente comprovado:

```text
EP126 / Bacula Director
    |
    | TCP 9102 + TLS
    v
EP125 / Bacula File Daemon
    |
    | TCP 9103
    v
EP126 / Bacula Storage Daemon
```

A prova fresh executada em 14/09/2026 concluiu:

- `DmzSmokeBackup`: JobId 6, status `T`, 2 arquivos, 8233 bytes, 0 erros;
- remoção controlada da origem após o backup;
- `DmzSmokeRestore`: JobId 7, status `T`, 2 arquivos, 8233 bytes, 0 erros;
- origem ainda ausente antes da validação;
- SHA-256 restaurado idêntico ao original;
- tamanho restaurado idêntico ao original;
- limpeza final dos artefatos sintéticos.

O backup não é considerado válido apenas porque o Job terminou: o critério de
aceite inclui **restore real após perda simulada e igualdade SHA-256**.

## OpenBao Raft

O OpenBao não é protegido por cópia bruta de volume.

A workload `bacula-snapshot` usa uma AppRole com privilégio mínimo para ler somente:

```text
sys/storage/raft/snapshot
```

O checkpoint final prova:

```text
snapshot Raft
    -> staging protegido
    -> backup Bacula
    -> remoção do original
    -> restore
    -> SHA-256 original == restaurado
```

Consulte:

- `../openbao/INTEGRACAO-BACULA-RAFT.md`
- `../../../scripts/evidencias/checkpoint_bacula_openbao_raft_final.sh`

## O que entra e o que não entra

A referência é `MATRIZ-BACKUP.md`.

Princípios principais:

- MariaDB: dump consistente;
- OpenBao: snapshot Raft;
- configuração específica: allowlist;
- Wazuh: regras/configuração customizada, não volume bruto do Indexer;
- Ferret: configuração/policies, não `inbox/` ou `reports/raw/`;
- `.env` real: não;
- Gmail App Password: não;
- root token OpenBao: nunca;
- unseal shares: nunca;
- Docker socket: nunca;
- imagens Docker: reconstruíveis/pull por digest.

## Documentos

Ordem sugerida de leitura:

1. `CAPACIDADE-180GB.md`
2. `MATRIZ-BACKUP.md`
3. `CONSISTENCIA.md`
4. `POLITICA-RPO-RTO-RETENCAO.md`
5. `ARQUITETURA-COMPONENTES.md`
6. `REDE-PFSENSE.md`
7. `IDENTIDADES-PRIVILEGIOS.md`
8. `CONTRATO-RESTORE.md`
9. `OBSERVABILIDADE-WAZUH.md`
10. `CONTRATO-CHECKPOINT.md`
11. `DECISOES-PRE-IMPLEMENTACAO.md`
12. `CONTRATO-FD-VM.md`
13. `../../../docs/evidencias/bacula-crosszone-dmz-20260914.md`
14. `../../../docs/evidencias/bacula-pgbouncer-recuperacao-20260917.md`

## File Daemon: runtime acadêmico x handoff reproduzível

Os templates e o instalador de FD nativo do handoff estão preparados:

```text
deploy/dmz/bacula-fd/bacula-fd.conf.example
deploy/interna/bacula/fd/bacula-fd.conf.example
deploy/interna/bacula/fd/director-clients-vm.conf.example
scripts/implantacao/preparar_bacula_fd_ubuntu.sh
```

O contrato versionado do handoff instala o pacote `bacula-fd` da distribuição
e materializa a configuração em
`/etc/bacula/bacula-fd.conf.conectaeduca`.

Na validação cross-zone de 14/09/2026, porém, a EP125 já possuía um runtime
institucional diferente:

```text
/opt/bacula/bin/bacula-fd
/opt/bacula/etc/bacula-fd.conf
```

Esse runtime foi validado funcionalmente pelo mesmo binário efetivamente executado
pelo systemd, mas **não é reproduzido pelo instalador atual do repositório**.

Consequentemente, há dois estados distintos:

- **funcionalidade cross-zone nas VMs acadêmicas atuais:** validada;
- **reprodutibilidade do FD a partir do handoff Git:** pendente de reconciliação.

O segundo gate só deve ser fechado após testar o instalador package-based em VM
limpa, ou após versionar o procedimento `/opt/bacula` caso essa instalação seja
formalmente definida como baseline institucional.


## Incidente PgBouncer e gate funcional do Director

Em 17/09/2026, durante a retomada da migração do Storage, foi detectado um estado
em que o container do Director aparecia como `healthy`, mas TCP/9101 não estava
em LISTEN e o `bconsole` recebia `Connection refused`.

A investigação encontrou o `pgbouncer.ini` runtime com 0 bytes, enquanto
`userlist.txt`, CA, Catalog e Storage permaneciam íntegros. O bridge foi reparado
a partir do template versionado sem expor ou alterar o SCRAM verifier.

O gate operacional passou a separar:

```text
PgBouncer:
  container healthy + socket local produzido

Director:
  TCP/9101 LISTEN + bconsole funcional
```

A recuperação final comprovou o caminho:

```text
Director
  -> Unix socket PgBouncer :6432
  -> PostgreSQL Catalog com TLS 1.3
```

O Director se recuperou sem restart direcionado, o `bconsole` informou
`No Jobs running.`, e Git, Catalog e Storage permaneceram sem regressão.

A causa do truncamento do `pgbouncer.ini` para 0 bytes não foi determinada e
não deve ser inferida. A investigação e os gates adotados estão registrados em:

```text
docs/evidencias/bacula-pgbouncer-recuperacao-20260917.md
```

## Limitação conhecida e storage emulado

No laboratório, o Storage Daemon e parte dos dados protegidos compartilham a VM
interna e o mesmo disco virtual.

A prova de 14/09/2026 demonstra proteção funcional contra os cenários lógicos e
operacionais cobertos pelo fluxo de backup/restore, mas **não protege contra perda
física total da VM/disco interno**.

Em 16/09/2026 ficou definido que não haverá segundo disco/storage externo no
ambiente acadêmico. Para fins de demonstração, será usado um diretório dedicado
na EP126 como **storage emulado**, com proposta inicial:

```text
/srv/conectaeduca-backup/bacula/volumes
```

Esse diretório deve ser tratado explicitamente como o mesmo domínio de falha da
VM. O objetivo é demonstrar a mecânica de:

```text
backup
  -> perda lógica simulada
  -> restore isolado
  -> SHA-256 restaurado == SHA-256 original
```

O storage emulado **não deve ser apresentado como proteção contra falha física**.
Essa limitação permanece registrada como risco residual.

A arquitetura continua preparada para mover o Storage para destino externo em
evolução posterior.
