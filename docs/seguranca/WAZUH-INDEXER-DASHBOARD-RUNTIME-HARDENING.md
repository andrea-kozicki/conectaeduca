# Wazuh Indexer + Dashboard — hardening de runtime

O hardening deste lote está incorporado diretamente em `deploy/interna/wazuh/compose.host.yml`, que já faz parte do fluxo canônico de implantação do Wazuh. Assim, uma implantação nova ou uma recriação parcial que use `compose.yml` + `compose.host.yml` mantém os controles de runtime sem depender de um terceiro arquivo opcional.

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

`read_only: true` não faz parte deste lote. A investigação mostrou que Indexer e Dashboard materializam estado de runtime/keystore em caminhos do rootfs. Forçar rootfs somente leitura agora exigiria introduzir estado adicional de configuração, aumentando a complexidade operacional.

Limites de memória/CPU também não foram fixados neste lote. O uso real deve ser dimensionado por uma janela maior antes de escolher limites que possam induzir OOM ou throttling.

O `wazuh.manager` não é alterado por estes controles. Ele possui múltiplos daemons, identidades e necessidades de capabilities e será tratado em etapa separada.

## Implantação automatizada

`scripts/implantacao/validar_wazuh_operacional.sh` usa os arquivos `compose.yml` e `compose.host.yml`. Como os controles deste lote estão no `compose.host.yml`, o caminho automatizado preserva o hardening em novos deploys e em recriações de serviços.

## Uso manual a partir da raiz do repositório

As variáveis não secretas de binding devem estar definidas e os artefatos de `.runtime/` devem ter sido preparados antes da subida da stack.

```bash
docker compose \
  -p conectaeduca-wazuh \
  -f deploy/interna/wazuh/compose.yml \
  -f deploy/interna/wazuh/compose.host.yml \
  config

docker compose \
  -p conectaeduca-wazuh \
  -f deploy/interna/wazuh/compose.yml \
  -f deploy/interna/wazuh/compose.host.yml \
  up -d
```

Credenciais, certificados e `.runtime/` não pertencem a este artefato versionado.
