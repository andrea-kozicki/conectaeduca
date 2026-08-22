# Bacula — ConectaEduca

Implementação de backup e restore do ConectaEduca para o laboratório e para a implantação nas VMs Ubuntu.

A arquitetura foi definida antes da implementação para evitar backup indiscriminado de volumes Docker, segredos ou dados sem estratégia de consistência.

## Componentes

### VM interna

- Bacula Director em container;
- Bacula Storage Daemon em container;
- PostgreSQL dedicado ao Catalog em container;
- `bconsole` administrativo efêmero;
- Bacula File Daemon **nativo** no Ubuntu final.

### VM DMZ

- Bacula File Daemon **nativo** no Ubuntu final.

O File Daemon containerizado existente no laboratório é somente uma bancada de teste e **não entra no handoff final**.

## Estado atual

O núcleo Bacula está implementado e validado com:

- configuração runtime separada do Git;
- credenciais protegidas;
- TLS previsto no contrato dos File Daemons finais;
- FileSets por allowlist;
- exclusões explícitas para material sensível;
- teste de backup e restore;
- prova de consistência do MariaDB em staging sintético;
- integração com snapshot Raft do OpenBao;
- comparação SHA-256 de artefatos restaurados.

## OpenBao Raft

O OpenBao não é protegido por cópia bruta de volume.

A workload `bacula-snapshot` usa uma AppRole com privilégio mínimo para ler somente:

```text
sys/storage/raft/snapshot
```

O checkpoint final prova:

```text
snapshot Raft
    -> staging protegido
    -> backup Bacula
    -> remoção do original
    -> restore
    -> SHA-256 original == restaurado
```

Consulte:

- `../openbao/INTEGRACAO-BACULA-RAFT.md`
- `../../../scripts/evidencias/checkpoint_bacula_openbao_raft_final.sh`

## O que entra e o que não entra

A referência é `MATRIZ-BACKUP.md`.

Princípios principais:

- MariaDB: dump consistente;
- OpenBao: snapshot Raft;
- configuração específica: allowlist;
- Wazuh: regras/configuração customizada, não volume bruto do Indexer;
- Ferret: configuração/policies, não `inbox/` ou `reports/raw/`;
- `.env` real: não;
- Gmail App Password: não;
- root token OpenBao: nunca;
- unseal shares: nunca;
- Docker socket: nunca;
- imagens Docker: reconstruíveis/pull por digest.

## Documentos

Ordem sugerida de leitura:

1. `CAPACIDADE-180GB.md`
2. `MATRIZ-BACKUP.md`
3. `CONSISTENCIA.md`
4. `POLITICA-RPO-RTO-RETENCAO.md`
5. `ARQUITETURA-COMPONENTES.md`
6. `REDE-PFSENSE.md`
7. `IDENTIDADES-PRIVILEGIOS.md`
8. `CONTRATO-RESTORE.md`
9. `OBSERVABILIDADE-WAZUH.md`
10. `CONTRATO-CHECKPOINT.md`
11. `DECISOES-PRE-IMPLEMENTACAO.md`
12. `CONTRATO-FD-VM.md`

## Readiness dos File Daemons finais

Os templates e o instalador de FD nativo estão preparados:

```text
deploy/dmz/bacula-fd/bacula-fd.conf.example
deploy/interna/bacula/fd/bacula-fd.conf.example
deploy/interna/bacula/fd/director-clients-vm.conf.example
scripts/implantacao/preparar_bacula_fd_ubuntu.sh
```

A ativação final ocorre nas VMs, após materialização de credenciais e certificados reais.

## Limitação conhecida

No laboratório, o Storage Daemon e parte dos dados protegidos compartilham a VM interna. Isso protege contra falhas lógicas e operacionais, mas não contra perda física total dessa VM/disco.

A arquitetura permite mover o Storage para destino externo em evolução posterior.
