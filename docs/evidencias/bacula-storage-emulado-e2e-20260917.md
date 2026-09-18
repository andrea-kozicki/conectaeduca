# Evidência operacional — Bacula storage emulado E2E

Data da validação: **17/09/2026**.

Esta evidência registra o fechamento funcional do Bacula após a migração do Storage
Daemon para o bind emulado na EP126:

```text
/srv/conectaeduca-backup/bacula/volumes -> /backup
```

O objetivo foi provar que o novo destino permanece funcional em um ciclo completo
de **backup -> perda simulada da origem -> restore isolado -> SHA-256 idêntico -> cleanup**.

Nenhum dado real do usuário ou segredo foi usado no teste.

## 1. Gate pós-APPLY

Antes do teste destrutivo, o gate read-only confirmou:

- Storage `running/healthy`;
- `/backup` montado como `Type=bind`, `RW=true`;
- source live `/srv/conectaeduca-backup/bacula/volumes`;
- `bacula-sd -t` aprovado;
- named volume `conectaeduca-bacula_storage-data` ainda preservado;
- fingerprint live do target idêntico ao fingerprint registrado no state ativo;
- overlay runtime existente e não vazio;
- PgBouncer `healthy`;
- Director em TCP/9101 LISTEN;
- `bconsole` funcional;
- `No Jobs running.`;
- worktree Git limpa;
- `READY_FOR_DESTRUCTIVE_BACKUP_RESTORE_TEST=1`;
- `FINAL=PASS`.

Fingerprint observado:

```text
files=2
bytes=23469
digest=d92f15ba004dbc00ea05db30dd57516c2c3822201fe20cbea2c406063a1958a6
```

## 2. Preparação na EP125

Foi criado um artefato sintético exclusivo para a execução:

```text
/var/lib/conectaeduca/bacula-smoke-dmz/input/prova-storage-emulado-20260917T021104Z.bin
```

Resultado:

- Bacula FD ativo;
- TCP/9102 em LISTEN;
- tamanho: **8233 bytes**;
- SHA-256 original:

```text
3613c747b065df074f7b7b30e7c25da130d2787ca4fd42dc8ba03df869c0097a
```

Gate: `PASS=6 WARN=0 FAIL=0 FINAL=PASS`.

## 3. Backup no storage emulado

Na EP126, o gate revalidou o runtime antes do Job:

- Storage, Director e PgBouncer healthy;
- bind live correto em `/backup`;
- `bacula-sd -t` aprovado;
- named volume original preservado;
- Director em TCP/9101;
- `bconsole` funcional;
- nenhum Job concorrente.

O Job de backup foi então executado:

```text
JobId=8
Name=DmzSmokeBackup
Type=B
JobStatus=T
JobFiles=2
JobBytes=8233
JobErrors=0
Pool=DmzSmokePool
WriteStorage=ConectaEducaStorage
WriteDevice=FileStorage
```

Gate: `PASS=11 WARN=0 FAIL=0 FINAL=PASS`.

## 4. Perda simulada da origem

Antes da remoção, a EP125 recalculou o hash e o tamanho da origem e exigiu
igualdade com o state preparado:

```text
PREDELETE_SHA256=3613c747b065df074f7b7b30e7c25da130d2787ca4fd42dc8ba03df869c0097a
PREDELETE_SIZE=8233
```

Somente após essa revalidação o artefato foi removido. Um `stat` posterior retornou
falha, comprovando que a origem estava realmente ausente.

Gate: `PASS=2 WARN=0 FAIL=0 FINAL=PASS`.

## 5. Correção fail-closed do helper de restore

A primeira versão do helper de restore usou `job=DmzSmokeRestore` no comando
`restore`. O `bconsole` rejeitou essa keyword. Um parser genérico capturou o
`jobid=8` ecoado no comando e o confundiu com um novo Restore JobId.

Esse resultado **não foi aceito como restore**. A origem permaneceu ausente e o
backup JobId 8 permaneceu intacto.

A versão 2 do helper foi corrigida para:

- usar `restorejob=DmzSmokeRestore`;
- usar seleção não interativa `all done yes`;
- aceitar JobId somente quando o Director imprime `Job queued. JobId=N`;
- exigir Restore JobId diferente do Backup JobId;
- consultar o Catalog e exigir `Name=DmzSmokeRestore` e `Type=R`;
- só então aceitar `JobStatus=T`, arquivos restaurados e zero erros.

## 6. Restore real

O restore v2 selecionou explicitamente o backup JobId 8 e gerou um novo Job:

```text
JobId=9
Name=DmzSmokeRestore
Type=R
JobStatus=T
JobFiles=2
JobBytes=8233
JobErrors=0
LastReadStorage=ConectaEducaStorage
LastReadDevice=FileStorage
```

O Director confirmou:

```text
Job queued. JobId=9
```

Gate: `PASS=9 WARN=0 FAIL=0 FINAL=PASS`.

## 7. Verificação criptográfica na EP125

Antes da validação, a origem continuava ausente.

Caminho isolado restaurado:

```text
/var/lib/conectaeduca/bacula-smoke-dmz/restore/var/lib/conectaeduca/bacula-smoke-dmz/input/prova-storage-emulado-20260917T021104Z.bin
```

Comparação:

```text
ORIGINAL_SHA256=3613c747b065df074f7b7b30e7c25da130d2787ca4fd42dc8ba03df869c0097a
RESTORED_SHA256=3613c747b065df074f7b7b30e7c25da130d2787ca4fd42dc8ba03df869c0097a
ORIGINAL_SIZE=8233
RESTORED_SIZE=8233
E2E_RESULT=BACKUP_LOSS_RESTORE_SHA256_PASS
```

Gate: `PASS=3 WARN=0 FAIL=0 FINAL=PASS`.

## 8. Cleanup

Após o state estar marcado como `verified`, o helper removeu somente os artefatos
sintéticos conhecidos e recriou o diretório dedicado de restore vazio com owner
`bacula:bacula` e modo `0750`.

Resultado:

```text
FINAL_WORKFLOW_STATE=CLEANED
PASS=1
WARN=0
FAIL=0
FINAL=PASS
```

## Conclusão

O Bacula foi comprovado no storage emulado ativo na sequência:

```text
artefato sintético EP125
        |
        v
backup JobId 8
        |
        v
Storage EP126 em bind dedicado
        |
        v
origem removida
        |
        v
restore JobId 9 para diretório isolado
        |
        v
SHA-256 restaurado == SHA-256 original
        |
        v
cleanup controlado
```

Portanto, o fluxo funcional de backup e recuperação está **fechado para o runtime
acadêmico observado** com o destino emulado.

### Risco residual

O bind dedicado continua no mesmo disco virtual/VM da EP126. Logo:

```text
PHYSICAL_ISOLATION=0
```

A prova valida a mecânica de backup, perda lógica, recuperação e integridade,
mas **não demonstra proteção contra perda física total da VM ou do disco interno**.
Esse risco permanece explicitamente aceito no laboratório, já que um segundo
disco/storage externo não será utilizado nesta implantação acadêmica.

## Cadeia de evidências locais

| Evidência | SHA-256 |
|---|---|
| gate pós-APPLY v2 | `6364f7638e902c53fa728dc942bfc30b64fc175ca9d96c5923189ff1103beb2c` |
| prepare EP125 | `7b54a9caf86f3e42b096119d6f9772aa4d3ceb5dd990ac7dc2c2c009f97daa6b` |
| backup EP126 | `304e8d066525d2dfaf21574dc8052ba6cbc7727d5d2c489b1a583f5d2c323508` |
| perda simulada EP125 | `9d595b8dd0136d2abbf40992c06d51c293d409e7bad6bf7854fa5c9ef17c1b4e` |
| restore real EP126 | `bd20f4fa5c2321a0dd7ab6faf56ce02b459a2c4f8a8f432eac466426b6fe9078` |
| verificação SHA-256 EP125 | `290ab864815b7c7ae2f4085b1a00aaa4ec8b983134e9b49a2e1ae4a00778fcec` |
| cleanup EP125 | `9df680be4568edc4e1fef1f17f6144ccde9d4a51dfb9421bbc7fea0ecc29b71d` |

Os relatórios brutos permanecem fora do Git; os hashes acima permitem correlacionar
a documentação versionada com a cadeia local de evidência da execução.
