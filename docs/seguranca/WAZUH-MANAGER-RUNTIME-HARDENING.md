# Wazuh Manager — hardening de runtime de baixo risco

## Escopo

Esta etapa incorpora ao `compose.host.yml` os controles de runtime que foram
validados no Wazuh Manager 4.14.7 da EP126:

- `no-new-privileges:true`;
- `pids_limit: 1024`;
- healthcheck local para os nove daemons essenciais, Filebeat e API HTTPS
  em `localhost:55000`.

O Manager continua com rootfs gravável e com o conjunto de capabilities da
imagem/runtime inalterado. Essa decisão é deliberada.

## Evidência de validação

Promoção live validada em 2026-09-08:

- `PASS=83`;
- `WARN=0`;
- `FAIL=0`;
- `ROLLBACK_USED=0`;
- `SUCCESS_FINAL=1`;
- 3 agentes Active recuperados após a recriação;
- 6/6 amostras de estabilidade com `running`, `healthy`, `RestartCount=0`,
  Filebeat ativo, nove daemons essenciais ativos e API respondendo;
- Indexer e Dashboard não foram recriados.

SHA-256 do relatório final:

```text
1dde642d02c4e728f4de08173116e58e89616dbd2b533084eb9b1cb6935bc665
```

SHA-256 do overlay runtime validado:

```text
d30fe5341865641784f0d0e0af535fb89ad5b0ceb78365ac4adb512c9ee48fd5
```

## Decisão sobre capabilities

Os microprobes anteriores mostraram que a redução agressiva de capabilities
não deve ser incorporada nesta etapa. Um conjunto reduzido sem `SYS_CHROOT`
impediu o `wazuh-analysisd` de iniciar. Um conjunto ampliado conseguiu iniciar
o core, mas isso não cobre todo o ciclo de vida do Manager, Active Response e
tarefas futuras.

Por isso, esta etapa mantém:

```text
CAPABILITIES_CHANGED=0
ROOTFS_READONLY_PROMOTED=0
```

Uma eventual redução de capabilities deve ser tratada em uma fase separada,
com validação funcional específica.

## Healthcheck

O healthcheck exige simultaneamente:

1. os nove daemons essenciais do Manager em estado `running`;
2. processo Filebeat presente;
3. resposta HTTPS da API local na porta 55000 com código esperado
   (`200`, `301`, `302`, `401` ou `403`).

O código `401` é saudável nesse teste sem autenticação: comprova que a API
está disponível e exigindo credenciais.

## Uso

A configuração é canônica no arquivo:

```text
deploy/interna/wazuh/compose.host.yml
```

O fluxo normal continua usando:

```bash
cd deploy/interna/wazuh

docker compose \
  --env-file .runtime/stack.env \
  -f compose.yml \
  -f compose.host.yml \
  up -d
```

`.runtime/`, senhas, certificados privados e demais segredos não devem ser
versionados.
