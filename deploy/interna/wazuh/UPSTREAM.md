# Origem da configuração Wazuh

Esta pasta foi preparada a partir da implantação `single-node` oficial do Wazuh Docker.

- Wazuh: 4.14.7
- Repositório upstream: `wazuh/wazuh-docker`
- Tag validada na Fase 4G-B: `v4.14.7`
- Commit observado na validação: `adcc5b57d2f7edfcbe6c399272dc76fbdf12b623`
- Licença do upstream: GPLv2

Arquivos de configuração estáticos preservam a estrutura do upstream. Credenciais,
hashes e certificados são gerados localmente em `.runtime/`, que é ignorado pelo Git.
