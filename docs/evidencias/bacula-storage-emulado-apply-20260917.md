# Bacula Storage emulado — APPLY v5 — EP126 — 17/09/2026

## Objetivo

Ativar o Storage Daemon do Bacula usando um diretório dedicado na EP126:

```text
/srv/conectaeduca-backup/bacula/volumes
```

O objetivo é demonstrar a mecânica de storage dedicado em laboratório sem afirmar
isolamento físico inexistente. O destino permanece no mesmo filesystem da VM.

## Pré-condições

Antes do APPLY:

- Git em `main` e worktree limpa;
- Director e Storage operacionais;
- `bconsole` funcional;
- `No Jobs running.`;
- Storage usando o named volume original;
- `Archive Device = /backup`;
- `bacula-sd -t` aprovado;
- fingerprint da fonte obtido sem expor payload;
- target residual reconhecido como idêntico à fonte;
- overlay Compose validado.

Fingerprint observado:

```text
files=2
bytes=23469
digest=d92f15ba004dbc00ea05db30dd57516c2c3822201fe20cbea2c406063a1958a6
```

## Riscos residuais conhecidos

O APPLY manteve dois WARNs esperados:

1. `/srv` e `/` pertencem ao mesmo filesystem, portanto não existe isolamento físico;
2. UID/GID `100:101` do Bacula no container colidem semanticamente com identidades do host.

A mitigação adotada para o bind mount usa diretórios pais `root:root 0700` e
target com ownership do Bacula no container.

## Execução

O Director e o Storage foram quiescidos de forma controlada após confirmação de
ausência de jobs.

Com a fonte quiescente, o fingerprint foi recalculado e permaneceu idêntico ao
target residual. Por isso a cópia anterior foi reutilizada:

```text
STAGED_TARGET_REUSED=1
COPY_COMPLETED=0
COPY_VERIFIED=1
```

O overlay runtime foi escrito em:

```text
/etc/conectaeduca/bacula/compose.storage-emulado.yml
```

O Compose efetivo preservou os mounts de configuração/TLS e substituiu somente
`/backup` por:

```text
/srv/conectaeduca-backup/bacula/volumes -> /backup
```

Somente o container do Storage foi recriado.

## Hardening preservado

Após o recreate, o Storage permaneceu com:

- imagem `conectaeduca/bacula-storage:15.0.3`;
- `cap_drop: ALL`;
- capabilities adicionais limitadas a CHOWN/FOWNER/SETGID/SETUID;
- `no-new-privileges:true`;
- root filesystem read-only;
- `PidsLimit=256`;
- redes Bacula backend/uplink;
- publicação `192.168.6.50:9103`;
- restart policy `unless-stopped`.

O `bacula-sd -t` pós-recreate foi aprovado.

## Integridade do target

Após o startup do novo Storage, o target manteve o fingerprint:

```text
files=2
bytes=23469
digest=d92f15ba004dbc00ea05db30dd57516c2c3822201fe20cbea2c406063a1958a6
```

O named volume original não foi removido.

## Readiness do Director

O Director foi iniciado novamente e validado funcionalmente por:

- TCP/9101 em LISTEN;
- `bconsole` conectado;
- `status director` respondendo;
- `No Jobs running.`.

O state root-only foi atualizado para `status=active` somente após esse readiness
funcional.

## Resultado

```text
APPLY_RESULT=STORAGE_EMULADO_ATIVO
SOURCE_NAMED_VOLUME_PRESERVED=1
COPY_VERIFIED=1
STAGED_TARGET_REUSED=1
OVERLAY_WRITTEN=1
STORAGE_RECREATED=1
ROLLBACK_USED=0
PHYSICAL_ISOLATION=0
FAIL=0
FINAL=WARN
```

O `WARN` é esperado e corresponde exclusivamente aos riscos residuais de
laboratório já documentados.

## Observação sobre ACTIVE_MOUNT

O resumo do script ainda registrou:

```text
ACTIVE_MOUNT=ORIGINAL_NAMED_VOLUME
```

Esse campo foi calculado no preflight e não foi atualizado após o recreate. Ele
não deve ser usado como evidência pós-APPLY.

A execução demonstrou que o Compose efetivo substituiu `/backup` pelo bind e
recriou o Storage com o overlay, mas um gate pós-APPLY específico deve confirmar
via `docker inspect` o mount live final antes do teste destrutivo de
backup/restore.

## Próximo gate

Antes do teste final de backup/restore:

1. confirmar via `docker inspect` que `/backup` está efetivamente em bind para
   `/srv/conectaeduca-backup/bacula/volumes`;
2. confirmar named volume original ainda preservado;
3. confirmar Director/Storage funcionais e zero jobs;
4. executar novo backup;
5. simular perda da origem;
6. executar restore isolado;
7. comparar SHA-256.

Somente esse ciclo fecha a validação funcional do storage emulado.
