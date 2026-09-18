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

Inclui MariaDB, OpenBao, Ferret, Wazuh, Bacula, Twingate declarativo, SQL e os scripts operacionais necessários. O bundle continua com Twingate **inativo**; entram apenas os artefatos necessários para a ativação posterior ao Pentest A.

Durante a geração:

- os reconciliadores versionados da PKI da API Wazuh, da identidade técnica
  `teste`, da ACL mínima do Dashboard e o validador operacional são copiados
  para `scripts/implantacao/`; o verificador do bundle exige esses quatro
  artefatos e valida sua sintaxe;
- `deploy/interna/bacula/compose.vm.yml` é renomeado para `compose.yml` no pacote; os comandos do handoff usam esse nome final;
- `deploy/interna/bacula/images/Dockerfile.vm` vira o `Dockerfile` do pacote;
- o Compose final não contém `filedaemon-lab` nem volumes sintéticos;
- o Dockerfile final contém somente os targets necessários ao Director/Storage;
- os File Daemons finais são instalados nativamente nas duas VMs Ubuntu;
- `preparar_bacula_catalog.fish` e sua dependência `materializar_bacula_catalog_secret.py` são copiados juntos;
- o pipeline Ferret/DLP, o healthcheck, o instalador operacional e o bridge OpenBao→Wazuh entram com suas dependências;
- o preparador de runtime Wazuh para VM entra junto com sua biblioteca comum;
- `deploy/interna/twingate`, o materializador efêmero, o ativador e os checkpoints Twingate entram no pacote sem credenciais;
- scripts finais resolvem a raiz pelo próprio pacote ou por `PROJECT_ROOT`; o bundle não exige `.git` nem um caminho institucional específico.

## Fontes de verdade do runtime final

O handoff distingue explicitamente configuração versionada, baseline de rollback
e estado live. Esses papéis **não são intercambiáveis**:

| Componente | Fonte de verdade no runtime final | Papel de outros artefatos |
|---|---|---|
| Bacula Director — configuração live | volume externo `conectaeduca-bacula-director-config` | `.runtime/config/bacula-dir.conf` no host é baseline de rollback, não segunda fonte live |
| Bacula Director — acesso ao Catalog | socket Unix `/run/pgbouncer`, porta `6432` | acesso direto `catalog:5432` pertence ao modelo antigo/laboratório |
| PgBouncer | volumes externos de config/socket declarados nos overlays | material sensível continua fora do Git |
| Bacula renderer sintético | **não faz parte do handoff final** | `materializar_bacula_core.py` e `preparar_bacula_core.fish` permanecem apenas no repositório de laboratório |
| OpenBao → SMTP cross-VM | **não habilitado** | runbook, policy e scripts SMTP permanecem fora do handoff operacional |

`RELEASE-METADATA.txt` registra esse contrato de forma verificável:

- `bacula_director_config_source=external_volume_director_config`;
- `bacula_director_db_transport=pgbouncer_unix_socket_6432`;
- `bacula_host_baseline_role=rollback_only`;
- `bacula_final_runtime_materialization=host_gate`;
- `openbao_smtp_cross_vm_status=not_enabled`.

O último item Bacula é deliberado: o repositório transporta o contrato correto,
mas a promoção/reconciliação completa do volume live continua dependente do gate
de host da EP126 e não é declarada como reproduzida apenas pelo bundle.

## Wazuh e YARA

Manager, Indexer e Dashboard fazem parte do handoff interno. Além dos arquivos
de `deploy/interna/wazuh`, o bundle interno inclui:

- `scripts/implantacao/reconciliar_wazuh_api_pki.py`;
- `scripts/implantacao/reconciliar_wazuh_teste_readonly.py`;
- `scripts/implantacao/reconciliar_wazuh_dashboard_acl.sh`;
- `scripts/implantacao/validar_wazuh_operacional.sh`.

A presença desses arquivos no bundle fecha o **transporte dos artefatos
reproduzíveis**, não substitui a validação live. O reconciliador de ACL do
Dashboard, em particular, permanece classificado como preparado no Git até ser
exercitado na EP126 e ter a evidência anexada.

Enrollment do Agent, FIM, evento sintético e YARA permanecem reservados para
demonstração em aula.

## Zero Trust

Os **artefatos** Twingate fazem parte do handoff interno para tornar reproduzível a etapa pós-Pentest A. Tokens continuam fora do pacote e `twingate_active=no` permanece registrado em `RELEASE-METADATA.txt`.

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

## Rotas deliberadamente excluídas

O handoff final não transporta atalhos de laboratório ou integrações ainda não
habilitadas, mesmo quando esses arquivos continuam úteis no repositório de
desenvolvimento:

- `scripts/bootstrap/materializar_bacula_core.py` e
  `preparar_bacula_core.fish`: geram o modelo Bacula sintético antigo,
  incluindo `filedaemon-lab`; não representam o runtime atual com PgBouncer;
- scripts OpenBao/SMTP cross-VM: a integração EP126 → DMZ não é uma capacidade
  final habilitada e o bundle interno não contém `deploy/dmz`;
- checkpoints de release que exigem simultaneamente DMZ + Interna, `.git` ou
  volumes sintéticos permanecem no repositório/CI e não são ferramentas de VM.

O runtime Bacula atual usa
`Director → /run/pgbouncer:6432 → TLS verify-full → PostgreSQL`. O bundle
preserva Compose, overlays, templates e o bootstrap da identidade
`bacula_director`, mas **a materialização completa do volume
`conectaeduca-bacula-director-config` continua sendo gate de host**. Isso é
registrado como `bacula_final_runtime_materialization=host_gate` e não é
mascarado por um renderer de laboratório.

## Smoke test offline do bundle

Cada handoff contém `scripts/release/smoke_handoff.sh`. O smoke é projetado
para rodar **depois da extração do tarball**, sem checkout Git e sem dependências
de host que poderiam gerar falso positivo operacional.

Exemplo:

```bash
tar -xzf conectaeduca-handoff-dmz-<sha>.tar.gz
env -u PROJECT_ROOT \
  bash conectaeduca-dmz/scripts/release/smoke_handoff.sh dmz

tar -xzf conectaeduca-handoff-interna-<sha>.tar.gz
env -u PROJECT_ROOT \
  bash conectaeduca-interna/scripts/release/smoke_handoff.sh interna
```

O smoke é deliberadamente read-only e não exige Docker, rede, systemd, sudo ou
segredos. Ele comprova:

- execução fora de `.git`;
- metadata do freeze;
- presença/ausência nominal de artefatos;
- sintaxe Shell e compilação Python dos scripts transportados;
- placeholders de segredo preservados onde esperado;
- fonte de verdade Bacula/PgBouncer;
- exclusão de material de laboratório e SMTP cross-VM;
- superfície declarativa Twingate;
- self-test do reconciliador de ACL do Dashboard Wazuh.

`HANDOFF_SMOKE=PASS` significa **portabilidade estrutural/reprodutibilidade do
bundle**, não validação live da VM.
