# Inventário de componentes do handoff

Este documento define a chamada nominal dos componentes que devem existir no handoff final do ConectaEduca para a EC8.

## DMZ — containers de runtime

| Papel | Origem |
|---|---|
| PHP-FPM | imagem própria `conectaeduca/php-fpm:dmz` |
| Nginx | imagem própria `conectaeduca/nginx:dmz` |
| WAF ModSecurity/OWASP CRS | imagem própria `conectaeduca/waf:dmz` |

O MariaDB não pertence à DMZ final.

## Rede interna — containers de runtime

| Papel | Origem |
|---|---|
| MariaDB | imagem oficial pinada |
| OpenBao | imagem oficial pinada |
| Ferret Scan | imagem oficial pinada |
| Wazuh Manager | imagem oficial pinada |
| Wazuh Indexer | imagem oficial pinada |
| Wazuh Dashboard | imagem oficial pinada |
| PostgreSQL / Bacula Catalog | imagem oficial pinada |
| Bacula Storage | imagem própria |
| Bacula Director | imagem própria |
| Twingate Connector | imagem oficial pinada; artefato presente, ativação pós-Pentest A |

## Proveniência de imagens

A supply chain diferencia duas classes:

- **imagens externas**: devem ser referenciadas por digest `sha256` no baseline;
- **imagens locais `conectaeduca/*`**: a proveniência depende da receita de build,
  das bases externas pinadas e das dependências instaladas durante o build.

Tag local não é tratada como prova criptográfica de conteúdo. O inventário
detalhado e os gaps de reconstrução estão registrados em
`docs/seguranca/PENTE-FINO-FASE3-SUPPLY-CHAIN-20260918.md`.

## Bootstrap

O `wazuh/wazuh-certs-generator` é imagem de preparação de certificados. Não é workload persistente.

## Componentes nativos

O Bacula File Daemon final é instalado nativamente nas duas VMs Ubuntu:

- DMZ;
- rede interna.

O container `filedaemon-lab` permanece apenas como artefato histórico/de laboratório e não entra no handoff operacional.

## Fora do handoff final

- Mailpit;
- Bacula File Daemon containerizado de laboratório;
- Trivy e outros scanners temporários;
- credenciais e runtime efêmero do Twingate; os artefatos declarativos entram, mas o Connector permanece inativo até o pós-Pentest A;
- `.runtime`, `.env` real, credenciais, chaves privadas e material Shamir.

## Fonte de verdade operacional

| Item | Estado no handoff |
|---|---|
| Config live do Bacula Director | volume externo `director-config` |
| Baseline host `.runtime/config/bacula-dir.conf` | rollback-only; não entra no bundle |
| Transporte Director → Catalog | PgBouncer por `/run/pgbouncer:6432` |
| Renderer Bacula sintético/`filedaemon-lab` | excluído do handoff |
| OpenBao/SMTP cross-VM | não habilitado; policy/runbook/scripts excluídos |
| Materialização final do volume Bacula | gate de host; não declarada como concluída pelo Git |

Esses papéis são conferidos por `RELEASE-METADATA.txt` e
`scripts/release/verificar_handoff.sh`.

## Critério de aprovação

O freeze não é aprovado apenas pela ausência de componentes proibidos. Ele também exige a presença nominal de todos os componentes esperados nas respectivas VMs.

## Reprodutibilidade do bundle

Os bundles finais não são checkouts Git. Scripts operacionais incluídos devem
resolver a raiz pelo próprio arquivo ou por `PROJECT_ROOT`, e
`RELEASE-METADATA.txt` registra o commit de origem e as exclusões de runtime.

Checkpoints que validam o **repositório de origem** continuam no CI e não são
confundidos com ferramentas operacionais da VM.