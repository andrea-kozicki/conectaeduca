# Wazuh Indexer + Dashboard — hardening de runtime

Este overlay endurece somente `wazuh.indexer` e `wazuh.dashboard`.

## Controles aplicados

### Indexer
- `cap_drop: ALL`
- `no-new-privileges:true`
- `pids_limit: 256`
- healthcheck local em `/_plugins/_security/health`

### Dashboard
- `cap_drop: ALL`
- `no-new-privileges:true`
- `pids_limit: 128`
- healthcheck HTTPS local em `/login`

## Decisões deliberadas

`read_only: true` não faz parte deste lote. A investigação mostrou que
Indexer e Dashboard materializam estado de runtime/keystore em caminhos
do rootfs. Forçar rootfs somente leitura agora exigiria introduzir estado
adicional de configuração, aumentando a complexidade operacional.

Limites de memória/CPU também não foram fixados neste lote. O uso real deve
ser dimensionado por uma janela maior antes de escolher limites que possam
induzir OOM ou throttling.

O `wazuh.manager` não é alterado por este overlay. Ele possui múltiplos
daemons, identidades e necessidades de capabilities e será tratado em etapa
separada.

## Uso

Aplicar junto com os arquivos base e host:

```bash
docker compose \
  -f compose.yml \
  -f compose.host.yml \
  -f compose.runtime-hardening.yml \
  up -d
```

Credenciais, certificados e `.runtime/` não pertencem a este artefato.
