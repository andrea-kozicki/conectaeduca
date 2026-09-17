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
- `deploy/interna/bacula/compose.storage-emulado.yml` permanece no pacote como último overlay canônico do Storage emulado;
- `deploy/interna/bacula/preparar_storage_emulado.py` permanece no pacote como gate obrigatório de migração/ativação do bind;
- o path do bind pode ser sobrescrito por `CONECTAEDUCA_BACULA_STORAGE_PATH` quando houver destino apropriado;
- `deploy/interna/bacula/images/Dockerfile.vm` vira o `Dockerfile` do pacote;
- o Compose final não contém `filedaemon-lab` nem volumes sintéticos;
- o Dockerfile final contém somente os targets necessários ao Director/Storage;
- os File Daemons finais são instalados nativamente nas duas VMs Ubuntu;
- `preparar_bacula_catalog.fish` e sua dependência `materializar_bacula_catalog_secret.py` são copiados juntos.

### Gate obrigatório do Storage emulado

**Não aplique `compose.storage-emulado.yml` diretamente sobre uma instalação que ainda use mídia apenas no named volume legado.** Antes do primeiro `up -d` com o bind, execute o helper versionado a partir de `deploy/interna/bacula`:

```bash
python3 preparar_storage_emulado.py check
python3 preparar_storage_emulado.py apply
```

O `check` é somente leitura para o runtime e exige que o Director prove `No Jobs running`. O `apply` é fail-closed e executa a janela controlada: para Director e Storage, recalcula o fingerprint quiescente do named volume, prepara o destino do bind, copia com preservação de metadados, exige igualdade de fingerprint antes da troca, recria somente o Storage com o overlay e confirma o mount live. O named volume original **não é apagado**.

Se o destino já contiver dados divergentes, se não for possível provar ausência de jobs, se a cópia divergir ou se o mount live não corresponder ao destino esperado, a promoção é interrompida. Quando uma falha ocorre durante o `apply`, o helper tenta restaurar o Storage sobre o named volume legado e voltar o Director ao estado funcional; o target staged é preservado para diagnóstico, nunca sobrescrito silenciosamente.

Cada execução grava relatório `.txt` e sidecar `.sha256` em `/var/tmp/conectaeduca-evidencias` por padrão. O diretório pode ser alterado por `CONECTAEDUCA_EVIDENCE_DIR`. O destino do bind usa `${CONECTAEDUCA_BACULA_STORAGE_PATH:-/srv/conectaeduca-backup/bacula/volumes}`.

Em um runtime no qual `/backup` já seja o bind esperado, o helper funciona de forma idempotente e apenas valida o mount/fingerprint e o gate de ausência de jobs.

### Composição canônica do Bacula no handoff

O Bacula da EP126 **não** é suportado apenas com `compose.yml` e o overlay de
Storage emulado. Após o gate acima, o handoff deve preservar a mesma ordem de overlays validada no
runtime, adicionando o Storage emulado por último:

```bash
docker compose \
  -f compose.yml \
  -f compose.postgresql-hardening.yml \
  -f compose.director-hardening.yml \
  -f compose.storage-hardening.yml \
  -f compose.director-pgbouncer.yml \
  -f compose.storage-emulado.yml \
  config -q

docker compose \
  -f compose.yml \
  -f compose.postgresql-hardening.yml \
  -f compose.director-hardening.yml \
  -f compose.storage-hardening.yml \
  -f compose.director-pgbouncer.yml \
  -f compose.storage-emulado.yml \
  up -d
```

A ordem é deliberada: a base fornece os recursos comuns; os overlays de
PostgreSQL, hardening e PgBouncer materializam o runtime funcional validado; o
overlay `compose.storage-emulado.yml` vem por último para substituir somente o
destino `/backup` pelo bind `${CONECTAEDUCA_BACULA_STORAGE_PATH:-/srv/conectaeduca-backup/bacula/volumes}`.

O overlay versionado evita que um redeploy/handoff volte silenciosamente para o
named volume legado. O helper versionado evita o problema inverso: ativar o bind
antes de migrar e verificar as mídias existentes. O named volume legado deve
permanecer preservado como artefato de rollback, mas deixa de ser o destino ativo
após a promoção validada.

O Storage emulado é uma decisão de laboratório e **não** constitui disaster recovery. O helper pode registrar `PHYSICAL_ISOLATION=0` quando o destino permanecer no mesmo filesystem da VM; essa condição é um risco residual explícito e não invalida a prova funcional de backup/restore.

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
