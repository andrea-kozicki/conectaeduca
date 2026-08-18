# Wazuh — ConectaEduca

Configuração versionável da stack Wazuh single-node usada no laboratório do ConectaEduca.

## Segurança adotada

- imagens fixadas em `4.14.7`;
- nenhuma senha padrão do Wazuh no Compose versionado;
- certificados e chaves privadas fora do Git em `.runtime/`;
- hashes de usuários do Indexer gerados localmente;
- credenciais do Manager/Dashboard em arquivos locais `0600`;
- no laboratório, somente o Dashboard é publicado em `127.0.0.1:8443`;
- Indexer `9200` e API `55000` não são publicados no host;
- a implantação definitiva nas VMs será criada em fase posterior, após pfSense e endereçamento real.

## Preparação

Execute a partir da raiz do repositório, exclusivamente na branch `feature/auth-local`:

```bash
bash scripts/evidencias/preparar_wazuh_fase4g_c.sh
```

Depois:

```bash
bash scripts/evidencias/testar_wazuh_fase4g_c.sh
```

Não envie, não versione e não compartilhe o diretório
`deploy/interna/wazuh/.runtime/`.
