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
- Mailpit e recursos de laboratório;
- volumes, staging e dados sintéticos;
- Wazuh `compose.lab.yml`;
- serviço, volumes e target Docker do Bacula File Daemon de laboratório;
- imagens temporárias de scanners;
- credenciais Twingate.

A documentação pode mencionar esses componentes para registrar sua exclusão; a validação de material de laboratório é aplicada aos artefatos operacionais.

## Handoff DMZ

Inclui a aplicação, Composer, build PHP/Nginx/WAF, overlays de Compose da VM DMZ e o template/instalador do Bacula File Daemon **nativo**.

`deploy/dmz/compose.database.yml` não entra porque o MariaDB pertence à rede interna.

## Handoff da rede interna

Inclui MariaDB, OpenBao, Ferret, Wazuh, Bacula, SQL e os scripts operacionais necessários.

Durante a geração:

- `deploy/interna/bacula/compose.vm.yml` é renomeado para `compose.yml` no pacote;
- `deploy/interna/bacula/compose.storage-emulado.yml` permanece no pacote como overlay canônico do Storage emulado;
- os comandos do handoff para o Bacula devem usar `-f compose.yml -f compose.storage-emulado.yml`, preservando `/srv/conectaeduca-backup/bacula/volumes -> /backup` por padrão;
- o path do bind pode ser sobrescrito por `CONECTAEDUCA_BACULA_STORAGE_PATH` quando houver destino apropriado;
- `deploy/interna/bacula/images/Dockerfile.vm` vira o `Dockerfile` do pacote;
- o Compose final não contém `filedaemon-lab` nem volumes sintéticos;
- o Dockerfile final contém somente os targets necessários ao Director/Storage;
- os File Daemons finais são instalados nativamente nas duas VMs Ubuntu;
- `preparar_bacula_catalog.fish` e sua dependência `materializar_bacula_catalog_secret.py` são copiados juntos.

O overlay versionado evita que um redeploy/handoff volte silenciosamente para o
named volume legado. O named volume existente pode permanecer preservado no host
como artefato de rollback, mas não é o destino ativo quando o overlay canônico é
aplicado.

## Wazuh e YARA

Manager, Indexer e Dashboard fazem parte do handoff interno. Enrollment do Agent, FIM, evento sintético e YARA permanecem reservados para demonstração em aula.

## Zero Trust

Twingate não é ativado no freeze. A ordem permanece:

1. implantar VMs;
2. configurar pfSense;
3. Pentest A sem Zero Trust;
4. ativar Twingate;
5. Pentest B.

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

Cada bundle inclui `SHA256SUMS` interno.
