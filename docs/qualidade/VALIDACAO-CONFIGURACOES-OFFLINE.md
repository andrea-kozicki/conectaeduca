# Validação offline de configurações — ConectaEduca

Este controle funciona **sem EP125, EP126, acesso à VPN ou Docker ativo**. Ele
analisa somente arquivos versionados no Git; não executa comandos nas VMs,
não inicializa contêineres e não altera arquivos de produção.

## O que a validação cobre

- Sintaxe e chaves duplicadas dos arquivos YAML em `deploy/` e dos workflows
  em `.github/workflows/`.
- Tags declarativas `!override` e `!reset` do Docker Compose. Outras tags
  customizadas são recusadas.
- XML versionado do Wazuh, incluindo arquivos com múltiplos elementos de topo
  (`<group>` e `<decoder>`), válidos como fragmentos de configuração do Wazuh.
- IDs de regras e nomes de decoders duplicados entre os arquivos Wazuh do
  repositório, além de XML do PHPUnit e da fonte PA-06 V6.
- Testes de regressão com entradas válidas e inválidas para comprovar que
  os verificadores rejeitam erros deliberados.

## Como executar em outro computador

```bash
python3 -m venv .venv-ce-offline
.venv-ce-offline/bin/python -m pip install 'PyYAML==6.0.3'
.venv-ce-offline/bin/python -m unittest discover -s tests/python \
  -p 'test_validar_configuracoes_offline.py' -v
.venv-ce-offline/bin/python scripts/evidencias/validar_configuracoes_offline.py
```

Execute na raiz de um clone do repositório. Use um ambiente virtual fora do
controle de versão; não inclua resultados locais ou credenciais no commit.

## O que **não** foi homologado

Um resultado `CONFIG_OFFLINE=PASS` comprova apenas consistência **estática do
código-fonte**. Ele não atesta que os arquivos sejam aceitos por `docker compose
config`, que os serviços iniciem, que certificados ou volumes existam, nem que
o Wazuh carregue as regras. O comportamento de pfSense, Zero Trust, Ferret,
OpenBao e dos demais serviços exige testes de integração em um ambiente
disponível. A implementação deste gate não altera os resultados já registrados
dos testes realizados em novembro de 2026.
