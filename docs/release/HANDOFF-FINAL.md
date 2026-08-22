# Freeze e handoff final — ConectaEduca

Este diretório documenta o corte entre a construção/containerização local e a implantação nas VMs Ubuntu da disciplina Experiência Criativa 8.

## Princípios

Os handoffs são produzidos exclusivamente a partir de um commit Git. Arquivos locais não rastreados não são usados como fonte.

Não entram nos pacotes:

- `.runtime/`;
- `.env` real;
- RoleID/SecretID de AppRole;
- root token ou shares de unseal do OpenBao;
- senhas e chaves privadas;
- Mailpit e outros recursos de laboratório;
- volumes, staging e dados sintéticos;
- Wazuh `compose.lab.yml`;
- Bacula File Daemon containerizado de laboratório;
- imagens temporárias de scanners;
- credenciais Twingate.

## Handoff DMZ

Inclui a aplicação, Composer, build PHP/Nginx/WAF, overlays de Compose para a VM DMZ e o template/instalador do Bacula File Daemon nativo.

`deploy/dmz/compose.database.yml` fica de fora porque o MariaDB pertence à rede interna na arquitetura final.

## Handoff da rede interna

Inclui MariaDB, OpenBao, Ferret, Wazuh, Bacula, SQL e os scripts operacionais necessários.

O arquivo `deploy/interna/bacula/compose.vm.yml` é a variante de implantação sem o File Daemon containerizado usado nos testes de backup/restore. Durante a geração do handoff ele é entregue como `deploy/interna/bacula/compose.yml`.

Os File Daemons finais são instalados nativamente nas duas VMs Ubuntu.

## Wazuh e YARA

Manager, Indexer e Dashboard fazem parte do handoff interno.

O enrollment do Agent, FIM, evento sintético e integração YARA permanecem reservados para a demonstração em aula.

## Zero Trust

Twingate não é ativado no freeze. A ordem permanece:

1. implantar VMs;
2. configurar pfSense;
3. executar Pentest A sem Zero Trust;
4. ativar Twingate;
5. executar Pentest B.

## Geração

```bash
scripts/release/gerar_handoff.sh dmz ~/Downloads HEAD
scripts/release/gerar_handoff.sh interna ~/Downloads HEAD
```

## Verificação

```bash
scripts/release/verificar_handoff.sh \
  ~/Downloads/conectaeduca-handoff-dmz-<sha>.tar.gz dmz

scripts/release/verificar_handoff.sh \
  ~/Downloads/conectaeduca-handoff-interna-<sha>.tar.gz interna
```

Os arquivos `SHA256SUMS` internos verificam todos os arquivos do pacote. O diretório de freeze também recebe checksums dos próprios bundles.
