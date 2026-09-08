# Evolução de hardening — containers e serviços

Este diretório registra a evolução do hardening do ConectaEduca em camadas. O objetivo é separar claramente **hardening do runtime/container**, **hardening do serviço**, **identidade/segredos**, **rede** e **validação funcional**, evitando tratar “estar em Docker” como sinônimo de serviço seguro.

## Como rastrear

Cada evolução deve deixar quatro vínculos:

1. **configuração versionada** — Compose, Dockerfile ou arquivo do serviço;
2. **evidência operacional** — checkpoint/relatório sanitizado em `docs/evidencias/`;
3. **integridade** — SHA-256 do relatório operacional quando aplicável;
4. **histórico Git** — commit/PR que documenta ou altera o controle.

O estado usado nesta matriz é:

- ✅ **VALIDADO** — controle observado e funcionalmente validado;
- 🟡 **PARCIAL** — existem controles comprovados, mas a camada ainda tem itens em revisão;
- ⏳ **A AUDITAR** — componente implantado, porém a auditoria aprofundada desta camada ainda não foi concluída;
- 🚧 **BLOQUEADO** — validação depende de boundary ou privilégio institucional.

> **Regra de evidência:** segredos, hashes de autenticação, tokens e chaves privadas não devem ser versionados. Relatórios brutos que contenham material sensível devem ser resumidos/sanitizados antes de entrar no Git.

## EP126 — runtime/container

| Componente | Estado | Controles comprovados | Pontos ainda em revisão |
|---|---|---|---|
| MariaDB | 🟡 PARCIAL | usuário `mysql`; `privileged=false`; sem host network/PID namespace/Docker socket RW; healthcheck healthy; configs, TLS e secrets montados RO; dados em volume; `3306` somente em `192.168.6.50` | rootfs gravável; NNP/cap_drop/limites ainda não consolidados |
| OpenBao | ✅ VALIDADO no runtime | usuário `openbao`; rootfs RO; `cap_drop=ALL`; NNP; PIDs 256; memória 1 GiB; tmpfs com `nosuid,nodev,noexec`; config RO; API só em loopback; healthcheck healthy | limite de CPU pode ser avaliado sem urgência |
| Ferret | ✅ VALIDADO no runtime | usuário `ferret`; rootfs RO; `cap_drop=ALL`; NNP; PIDs 128; tmpfs restritivo; config/inbox RO; API só em loopback | CPU/memória e healthcheck ainda podem ser avaliados |
| Wazuh Dashboard | 🟡 PARCIAL | usuário dedicado; não privilegiado; config/certs RO; interface somente `127.0.0.1:443`; ACL mínima do `wazuh.yml` tornou-se reprodutível | rootfs, NNP, capabilities e limites ainda precisam análise de compatibilidade |
| Wazuh Indexer | 🟡 PARCIAL | usuário dedicado; não privilegiado; sem porta publicada; dados em volume; `internal_users.yml`, TLS e `opensearch.yml` RO | rootfs, NNP, capabilities, limites e healthcheck |
| Wazuh Manager | 🟡 PARCIAL | não privilegiado; regras/decoders/ossec.conf/TLS RO; dados em volumes; somente `1514` publicado em `192.168.6.50` | processo inicia com default/root; NNP, capabilities, limites e healthcheck |
| Bacula Catalog/PostgreSQL | 🟡 PARCIAL | não privilegiado; NNP; sem porta publicada; healthcheck healthy; dados em volume | processo inicial default/root; rootfs/capabilities/limites |
| Bacula Director | 🟡 PARCIAL | não privilegiado; NNP; config e TLS RO; sem porta publicada | roda como `0:0`; rootfs, capabilities, limites e healthcheck |
| Bacula Storage | 🟡 PARCIAL | não privilegiado; NNP; config/TLS RO; storage em volume; `9103` somente em `192.168.6.50` | roda como `0:0`; rootfs, capabilities, limites e healthcheck |

Auditoria-base do runtime EP126 em 07/09/2026: **9 containers, PASS=95 WARN=44 FAIL=0**. Os valores observados são a referência; alguns rótulos do helper original foram posteriormente interpretados com mais rigor, por exemplo `0:0` = root e `PidsLimit=<nil>` = ausência de limite.

## EP126 — hardening dos serviços

| Serviço | Estado | Controles já comprovados | Próximo passo |
|---|---|---|---|
| MariaDB 12.3.2 | ✅ VALIDADO | TLS obrigatório; TLS 1.2/1.3; sem root remoto, usuário anônimo ou DB `test`; app somente CRUD no schema; sem privilégios globais, `FILE` ou `GRANT OPTION`; `local_infile=OFF`; `skip_name_resolve=ON`; `general_log=OFF`; secrets externos de 64 caracteres; origem da conta restrita à EP125 `192.168.6.34`; aplicação validada com HTTP 200 após novas conexões; teste local negativo aprovado | manter baseline; revalidar Host se IP/topologia da EP125 mudar; `secure_file_priv=<NULL>` permanece como risco residual compensado |
| PostgreSQL / Bacula Catalog | ⏳ A AUDITAR | runtime parcialmente endurecido e healthcheck saudável | revisar `pg_hba.conf`, autenticação, listen, roles, privilégios e TLS |
| Bacula Director | ⏳ A AUDITAR | configuração/TLS externalizados em mounts RO | revisar consoles/clients autorizados, TLS, ACLs, Jobs/FileSets/RunScripts e credenciais |
| Bacula Storage | ⏳ A AUDITAR | config/TLS RO e exposição 9103 restrita ao IP interno | revisar Directors autorizados, TLS, paths e permissões do storage |
| Wazuh Manager | ⏳ A AUDITAR | integração Suricata E2E e regras/decoders próprios já validados | revisar API/RBAC, enrollment, Active Response, integrações e serviços não usados |
| Wazuh Indexer | ⏳ A AUDITAR | TLS/config internalizados em arquivos RO; sem porta publicada | revisar security plugin, TLS HTTP/transport, usuários internos e acesso anônimo |
| Wazuh Dashboard | 🟡 PARCIAL | interface em loopback; acesso ao `wazuh.yml` por ACL mínima reprodutível; API Manager acessível e 401 sem autenticação conforme esperado | revisar sessão/cookies/TLS/RBAC e opções do OpenSearch Dashboards |
| OpenBao | 🟡 PARCIAL | Raft, políticas dedicadas, AppRole SMTP/Bacula e runtime forte já implementados | auditoria sistemática de listener, auth methods, TTLs, tokens, audit device e policies |
| Ferret | 🟡 PARCIAL | configuração própria, sanitização do pipeline e runtime forte | revisar escopo, retenção, acessos ao inbox/reports e concluir E2E com Wazuh quando boundary institucional permitir |

## EP125 — serviços e componentes de DMZ

| Componente | Estado | Evolução já registrada | Próxima auditoria |
|---|---|---|---|
| Suricata | ✅ VALIDADO | instalação 8.0.6; ET Open; `eve.json`; integração Wazuh; `HOME_NET` restringido para `192.168.6.32/28` | manter baseline e revalidar após mudanças de rede |
| Nginx | 🟡 PARCIAL | hardening pós-VM com non-root/read-only/capabilities/PIDs/tmpfs registrado no projeto | auditoria aprofundada de TLS, headers, métodos, timeouts, disclosure e proxy/FastCGI |
| PHP-FPM | 🟡 PARCIAL | runtime minimal/read-only/non-root/capabilities/PIDs/tmpfs já registrado | auditar `php.ini`, FPM pool, funções perigosas, upload/session/error disclosure e limites |
| ModSecurity + OWASP CRS | 🟡 PARCIAL | WAF, TLS, tuning e testes de probes já existem | consolidar política, paranoia level, exclusions e logging sem dados sensíveis |
| Aplicação ConectaEduca | 🟡 PARCIAL | RBAC, MFA, CSRF, rate limiting, criptografia híbrida e auditoria já possuem testes | DAST/pentest e regressões após hardening de infraestrutura |

## Linha do tempo de hardening

| Data | Componente/camada | Evolução | Evidência |
|---|---|---|---|
| 03–04/09/2026 | PHP-FPM/Nginx runtime | read-only, non-root, capabilities removidas, limites de PIDs e tmpfs controlados | histórico/configs em `deploy/dmz/` e checkpoints existentes |
| 07/09/2026 | Suricata serviço | `HOME_NET` RFC1918 amplo → DMZ real `192.168.6.32/28` | `docs/evidencias/suricata-homenet-ep125-20260907.md` |
| 07/09/2026 | Suricata → Wazuh | pipeline E2E `eve.json` → Agent → Manager/Indexer → Threat Hunting validado | `docs/evidencias/suricata-wazuh-e2e-20260907.md` |
| 07/09/2026 | Wazuh Dashboard runtime | ACL de leitura do `wazuh.yml` tornou-se reprodutível via watcher systemd | `docs/evidencias/wazuh-dashboard-acl-reprodutivel-20260907.md` |
| 07/09/2026 | EP126 runtime | auditoria transversal dos 9 containers | relatório local com PASS/WARN/FAIL; síntese nesta matriz |
| 07/09/2026 | MariaDB serviço | auditoria interna de TLS, contas, grants e parâmetros de risco | `docs/evidencias/mariadb-hardening-servico-20260907.md` |
| 07/09/2026 | MariaDB identidade/segredos | confirmado: app sem privilégios administrativos, secrets externos fortes e controle compensatório para `secure_file_priv` | `docs/evidencias/mariadb-hardening-servico-20260907.md` |
| 07/09/2026 | MariaDB origem da aplicação | origem real `192.168.6.34` observada no `PROCESSLIST`; conta alterada de `Host='%'` para `Host='192.168.6.34'`; cinco HTTP 200 e teste negativo local após mudança | `docs/evidencias/mariadb-hardening-servico-20260907.md` |

## Fontes declarativas relevantes

- MariaDB: `deploy/interna/mariadb/`
- OpenBao: `deploy/interna/openbao/`
- Ferret: `deploy/interna/ferret/`
- Wazuh: `deploy/interna/wazuh/`
- Bacula: `deploy/interna/bacula/`
- DMZ Nginx/PHP/WAF: `deploy/dmz/`
- Evidências sanitizadas: `docs/evidencias/`

## Critério para fechar um componente

Um componente só deve migrar para ✅ **VALIDADO** quando houver, quando aplicável:

- baseline anterior conhecido;
- mudança/configuração versionada;
- backup/rollback definido para mudanças de risco;
- teste sintático/configtest;
- restart/recreate controlado;
- teste funcional pós-mudança;
- evidência sanitizada;
- SHA-256 do relatório operacional;
- risco residual explicitado.

Esta página é um **índice vivo**: cada nova auditoria ou hardening deve acrescentar uma entrada na linha do tempo e atualizar apenas o componente afetado.