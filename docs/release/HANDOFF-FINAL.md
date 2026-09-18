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
- o path do bind pode ser sobrescrito por `CONECTAEDUCA_BACULA_STORAGE_PATH` ou por `--target` absoluto; após `apply` bem-sucedido o helper persiste o valor ativo em `.conectaeduca-storage-path.env` para os redeploys seguintes;
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

Para um destino customizado, use sempre um caminho absoluto, por exemplo:

```bash
python3 preparar_storage_emulado.py check --target /mnt/conectaeduca-backup/bacula/volumes
python3 preparar_storage_emulado.py apply --target /mnt/conectaeduca-backup/bacula/volumes
```

Valores relativos como `--target volumes` são rejeitados antes de qualquer `resolve()`, cópia ou alteração de runtime.

O helper atual é fail-closed. O `check` não altera o runtime e exige que o Director prove `No Jobs running`. Antes de qualquer parada de Director/Storage ou cópia, o preflight também mede os bytes efetivamente alocados da mídia legado e o espaço livre do filesystem que receberá o TARGET. Quando uma cópia é necessária, exige capacidade para a mídia alocada mais **2 GiB de reserva operacional**; falta de espaço bloqueia a promoção antes da janela de indisponibilidade.

O `apply` para Director e Storage, recalcula o fingerprint quiescente do named volume, prepara o destino do bind, copia com preservação de metadados, exige igualdade de fingerprint antes da troca, recria somente o Storage com o overlay e confirma o mount live. O named volume original **não é apagado**.

Ao preparar o path, o helper valida **toda a cadeia de ancestrais existentes** até `/`: cada componente precisa ser diretório real, `root`-owned, não ser symlink e não permitir escrita por group/other. Além disso, o parent final do TARGET precisa formar uma barreira `root:root 0700`; se ele não existir, o helper cria os parents ausentes em `0700`, e se já existir com modo mais permissivo o target é rejeitado em vez de alterar permissões preexistentes. Qualquer path que apareça entre o probe e o `mkdir` é tratado como race e falha fechado. Por isso targets rasos sob ancestrais traversáveis, como `/mnt/bacula`, não são aceitos; use um subdiretório dedicado como `/mnt/conectaeduca-backup/bacula/volumes`.

Os limites de operações potencialmente longas são configuráveis:

```bash
python3 preparar_storage_emulado.py check --fingerprint-timeout 1800
python3 preparar_storage_emulado.py apply --fingerprint-timeout 1800 --copy-timeout 3600
```

- `--fingerprint-timeout`: default 1800 s, faixa 300..21600 s;
- `--copy-timeout`: default 3600 s, faixa 600..43200 s.

Assim, mídia próxima ao budget documentado ou storage virtual mais lento não depende dos antigos limites fixos curtos, sem remover o comportamento fail-closed.

Se o destino já contiver dados divergentes, se não for possível provar ausência de jobs antes da janela de migração, se a capacidade for insuficiente, se a cópia divergir ou se o mount live não corresponder ao destino esperado, a promoção é interrompida. No `apply`, antes do gate final de `No Jobs running`, o helper executa `disable job all` via `bconsole`, bloqueando novos jobs agendados em runtime. Com o scheduler quiescente, repete o capacity gate sobre a mídia já estável, reconfirma `No Jobs running` e só então para Director/Storage. Se qualquer verificação pós-`disable job all` falhar antes do stop efetivo do Director, o helper restaura o scheduling por `reload`; se o Director tiver sido efetivamente parado apesar de erro no comando de stop, ele é iniciado novamente para reaplicar o estado persistente. Se essa quiescência não puder ser provada, o helper executa `reload` para restaurar o estado `Enabled` da configuração e aborta sem parar Storage. O restart posterior do Director reaplica o estado persistente dos Jobs. Após o restart final, o gate valida conectividade funcional via `bconsole` sem exigir novamente `No Jobs running`, porque um job agendado pode iniciar legitimamente nesse instante. Em qualquer falha que ainda exija rollback, o helper aplica a mesma barreira: `disable job all` + `No Jobs running` antes de parar o Director e recriar Storage no named volume legado. Se houver job ativo ou a quiescência for inconclusiva, o rollback de Storage é bloqueado fail-closed para não interromper mídia/catalog em uso. O target staged é preservado para diagnóstico, nunca sobrescrito silenciosamente.

Cada execução grava relatório `.txt` e sidecar `.sha256` em `/var/tmp/conectaeduca-evidencias` por padrão. O diretório pode ser alterado por `CONECTAEDUCA_EVIDENCE_DIR`. O destino do bind usa `${CONECTAEDUCA_BACULA_STORAGE_PATH:-/srv/conectaeduca-backup/bacula/volumes}`.

Após um `apply` bem-sucedido, o helper cria `deploy/interna/bacula/.conectaeduca-storage-path.env` no source tree, ou o arquivo equivalente no diretório Bacula do handoff. O arquivo contém somente `CONECTAEDUCA_BACULA_STORAGE_PATH='<target>'`, com target restrito ao subconjunto literal aceito pelo Compose. Ele é criado apenas depois de Storage e Director terem sido validados.

O estado persistido também participa do rollback, mas é reconciliado com o **mount live realmente ativo** após uma falha. O helper faz snapshot do `.conectaeduca-storage-path.env` antes do APPLY; se `/backup` tiver sido realmente revertido ao named volume legado, restaura exatamente o conteúdo anterior ou remove o arquivo criado durante a tentativa. Se o rollback de Storage for bloqueado/abortado e `/backup` continuar no novo bind, o helper preserva/materializa o TARGET ativo no env-file. Se não for possível provar nem o volume legado nem o bind esperado, o env-file não é alterado e a reconciliação falha fechado. Assim um redeploy posterior não desvia silenciosamente `/backup` do estado que permaneceu ativo.

Em um runtime no qual `/backup` já seja o bind esperado, o helper funciona de forma idempotente, mas só aprova o runtime se o mount live for `Type=bind`, tiver `Source` igual ao target, `Destination=/backup` e `RW=true`. Um `apply` idempotente também materializa/revalida `.conectaeduca-storage-path.env` antes de futuros redeploys.

### Composição canônica do Bacula no handoff

O Bacula da EP126 **não** é suportado apenas com `compose.yml` e o overlay de
Storage emulado. Após o gate acima, o handoff deve preservar a mesma ordem de overlays validada no
runtime, adicionando o Storage emulado por último. Todo redeploy posterior deve reutilizar o target persistido pelo helper:

```bash
test -r .conectaeduca-storage-path.env

docker compose \
  --env-file .conectaeduca-storage-path.env \
  -f compose.yml \
  -f compose.postgresql-hardening.yml \
  -f compose.director-hardening.yml \
  -f compose.storage-hardening.yml \
  -f compose.director-pgbouncer.yml \
  -f compose.storage-emulado.yml \
  config -q

docker compose \
  --env-file .conectaeduca-storage-path.env \
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
destino `/backup` pelo bind gravado em `.conectaeduca-storage-path.env`.

O overlay versionado evita que um redeploy/handoff volte silenciosamente para o
named volume legado. O helper versionado evita o problema inverso: ativar o bind
antes de migrar e verificar as mídias existentes. O arquivo de target persistente evita que um `--target` customizado seja perdido em um Compose posterior. O named volume legado deve permanecer preservado como artefato de rollback, mas deixa de ser o destino ativo após a promoção validada.

O Storage emulado é uma decisão de laboratório e **não** constitui disaster recovery. O helper pode registrar `PHYSICAL_ISOLATION=0` quando o destino permanecer no mesmo filesystem da VM; essa condição é um risco residual explícito e não invalida a prova funcional de backup/restore.

## Wazuh e YARA

Manager, Indexer e Dashboard fazem parte do handoff interno. Enrollment do Agent, FIM, evento sintético e YARA permanecem reservados para demonstração em aula.

### Suricata EVE → Wazuh: overflow do decoder JSON

Em 18/09/2026 foi isolada e corrigida uma causa operacional de perda/ruído no pipeline do Wazuh. O `wazuh-analysisd` produzia bursts fixos de `Too many fields for JSON decoder.` a cada aproximadamente 8 s. A investigação eliminou Ferret DLP e OpenBao audit como causas: os JSONs amostrados tinham, respectivamente, no máximo 19 e 8 campos, e não reproduziram o erro em `wazuh-logtest`.

A causa foi o `event_type=stats` do EVE do Suricata na EP125. A amostra continha registros com 508 campos, acima de `analysisd.decoder_order_size=256`, em cadência mediana de ~8,0007 s, coincidente com os bursts do Manager. A correção desabilitou **somente** o item `stats` dentro de `eve-log.types` no `suricata.yaml`; estatísticas globais/`stats.log` permaneceram habilitadas. O candidato foi aprovado por `suricata -T`, o serviço reiniciou `active` e não houve rollback.

A validação posterior na EP126 observou 32 s de Manager sem nenhuma ocorrência de `Too many fields for JSON decoder`, sem outras linhas `ERROR`, com taxa de erro de 0,0000/s. Estado operacional:

- `WAZUH_JSON_DECODER_FLOOD=RESOLVIDO`;
- `ROOT_CAUSE=SURICATA_EVE_EVENT_TYPE_STATS`;
- `EVE_STATS_DISABLED=1`;
- `GLOBAL_SURICATA_STATS_DISABLED=0`;
- `WAZUH_JSON_OVERFLOW_RESOLVED=1`.

Esse fechamento remove o principal bloqueio técnico para retomar a correlação analítica pfSense → Wazuh → Indexer. A correlação E2E do pfSense continua pendente até prova específica de persistência/consulta no Indexer.

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
