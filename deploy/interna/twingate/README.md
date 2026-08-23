# Twingate Connector — ConectaEduca

Imagem fixada:
`twingate/connector@sha256:833e7a968f1b3a5ad79b88b04f82aad1bfc8621f61b6b35f01be2411d35beba9`

Destino arquitetural: VM Ubuntu interna.

Controles:
- profile `twingate` (não sobe por padrão);
- `network_mode: host`;
- nenhuma porta publicada;
- nenhum volume;
- sem Docker socket;
- imagem executa como `nonroot`;
- `no-new-privileges`;
- tokens somente em `/dev/shm/conectaeduca-twingate.env` com modo 0600.

Fluxo:
1. `preparar_twingate_runtime.fish`
2. `ativar_twingate_connector.fish`
3. `checkpoint_twingate_operacional.sh`

Nenhum token deve ser versionado ou incluído em evidências.
