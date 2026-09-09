# Segurança — documentação e evolução

Esta área reúne documentação de segurança operacional e rastreabilidade do hardening do ConectaEduca.

## Evolução de hardening

➡️ [`hardening/README.md`](hardening/README.md) — painel vivo por container e serviço, com estado, controles comprovados, pendências, linha do tempo e vínculo com evidências.

O painel separa as camadas de:

- runtime/container;
- serviço;
- identidade e segredos;
- rede/exposição;
- validação funcional.

## Hardening validado recentemente

- [`BACULA-DIRECTOR-STORAGE-HARDENING.md`](BACULA-DIRECTOR-STORAGE-HARDENING.md) — hardening de runtime do Bacula Director e Storage na EP126;
- [`BACULA-PGBOUNCER-TLS-BRIDGE.md`](BACULA-PGBOUNCER-TLS-BRIDGE.md) — bridge compensatória Director → Unix socket → PgBouncer → PostgreSQL com TLS `verify-full`;
- [`WAZUH-INDEXER-DASHBOARD-RUNTIME-HARDENING.md`](WAZUH-INDEXER-DASHBOARD-RUNTIME-HARDENING.md) — controles de runtime do Indexer e Dashboard;
- [`WAZUH-MANAGER-RUNTIME-HARDENING.md`](WAZUH-MANAGER-RUNTIME-HARDENING.md) — hardening de baixo risco do `wazuh.manager`;
- [`../../deploy/interna/wazuh/ESTADO-VALIDADO-EP126.md`](../../deploy/interna/wazuh/ESTADO-VALIDADO-EP126.md) — estado operacional validado da centralização do agente 002 e prova DLP ponta a ponta.

## Evidências operacionais sanitizadas

Evidências sanitizadas ficam em [`../evidencias/`](../evidencias/).

Para o fechamento recente do Wazuh na EP126, consulte também:

- [`../evidencias/wazuh-ep126-dlp-e2e-20260908.md`](../evidencias/wazuh-ep126-dlp-e2e-20260908.md).

## Outros documentos

- [`custodia-shamir-openbao.md`](custodia-shamir-openbao.md) — custódia Shamir do OpenBao;
- [`semgrep-excecoes.md`](semgrep-excecoes.md) — exceções e decisões relacionadas ao Semgrep.

## Referências Git recentes

- PR #43 — hardening de runtime Bacula Director + Storage;
- PR #44 — hardening de runtime Wazuh Indexer + Dashboard;
- PR #45 — hardening de runtime Wazuh Manager;
- PR #46 — estado validado da EP126 e DLP E2E.

## Regra de rastreabilidade

Mudanças relevantes de hardening devem ser associadas a configuração versionada, evidência sanitizada, SHA-256 do relatório operacional quando aplicável e commit/PR correspondente. Segredos, tokens, chaves privadas e hashes de autenticação não devem ser incluídos no Git.
