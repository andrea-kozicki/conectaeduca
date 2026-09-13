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
| Wazuh Dashboard | ✅ VALIDADO no runtime | usuário dedicado; config/certs RO; interface somente `127.0.0.1:443`; ACL mínima do `wazuh.yml`; `cap_drop=ALL`; NNP; PIDs 128; healthcheck HTTPS local | rootfs permanece gravável por compatibilidade; limites de CPU/RAM não fixados |
| Wazuh Indexer | ✅ VALIDADO no runtime | usuário dedicado; sem porta publicada; dados em volume; `internal_users.yml`, TLS e `opensearch.yml` RO; `cap_drop=ALL`; NNP; PIDs 256; healthcheck local | rootfs permanece gravável por compatibilidade; limites de CPU/RAM não fixados |
| Wazuh Manager | ✅ VALIDADO no runtime (baixo risco) | NNP; PIDs 1024; healthcheck para nove daemons, Filebeat e API local; somente `1514` publicado em `192.168.6.50`; `55000` não publicado | rootfs gravável e capabilities da imagem mantidas por decisão explícita; redução adicional exige fase própria |
| Bacula Catalog/PostgreSQL | 🟡 PARCIAL | não privilegiado; NNP; sem porta publicada; healthcheck healthy; dados em volume | processo inicial/default do container e hardening de rootfs/capabilities continuam separados da validação do serviço |
| Bacula Director | ✅ VALIDADO no runtime | rootfs RO; PID 1 efetivo como `bacula` UID 100/GID 101; bootstrap restrito a CHOWN/SETUID/SETGID; `cap_drop=ALL`; capabilities finais zeradas; NNP; PIDs 256; healthcheck; 9101 não publicado | dimensionamento CPU/RAM pode ser refinado sem bloquear baseline |
| Bacula Storage | ✅ VALIDADO no runtime | rootfs RO; PID 1 efetivo como `bacula` UID 100/GID 101; bootstrap restrito a CHOWN/SETUID/SETGID; `cap_drop=ALL`; capabilities finais zeradas; NNP; PIDs 256; healthcheck; 9103 somente em `192.168.6.50`; `/backup` 100:101:0750 | dimensionamento CPU/RAM pode ser refinado sem bloquear baseline |

Auditoria-base do runtime EP126 em 07/09/2026: **9 containers, PASS=95 WARN=44 FAIL=0**. Os valores observados são a referência; alguns rótulos do helper original foram posteriormente interpretados com mais rigor, por exemplo `0:0` = root e `PidsLimit=<nil>` = ausência de limite. As linhas acima já incorporam as promoções validadas nas PRs #43, #44 e #45.

## EP126 — hardening dos serviços

| Serviço | Estado | Controles já comprovados | Próximo passo |
|---|---|---|---|
| MariaDB 12.3.2 | ✅ VALIDADO | TLS obrigatório; TLS 1.2/1.3; sem root remoto, usuário anônimo ou DB `test`; app somente CRUD no schema; sem privilégios globais, `FILE` ou `GRANT OPTION`; `local_infile=OFF`; `skip_name_resolve=ON`; `general_log=OFF`; secrets externos de 64 caracteres; origem da conta restrita à EP125 `192.168.6.34`; aplicação validada com HTTP 200 após novas conexões; teste local negativo aprovado | manter baseline; revalidar Host se IP/topologia da EP125 mudar; `secure_file_priv=<NULL>` permanece como risco residual compensado |
| PostgreSQL / Bacula Catalog | ✅ VALIDADO | SCRAM; role `bacula_director` sem privilégios administrativos; 5432 sem publicação no host; `ssl=on`; bridge Director→Unix socket→PgBouncer→TLS `verify-full`→PostgreSQL; regra ampla `hostssl`; plaintext inter-container bloqueado; TLS 1.3 validado; baseline e rollback preservados | residual explícito de plaintext apenas no loopback local; revalidar certificados antes da expiração e após mudança de topologia |
| Bacula Director | 🟡 PARCIAL | runtime endurecido; Director→Storage com TLS obrigatório validado; console administrativo local protegido; bconsole e acesso ao Catalog via PgBouncer funcionais após promoção | revisar sistematicamente Jobs, FileSets, RunScripts e eventual segregação de Console/RBAC se o ambiente deixar de ser mono-operador |
| Bacula Storage | 🟡 PARCIAL | runtime endurecido; Director autorizado e canal TLS funcional; `/backup` persistente restrito; 9103 limitado ao IP interno | revisar política de retenção/mídia e Directors autorizados após mudanças de topologia |
| Wazuh Manager | ✅ VALIDADO | runtime e auditoria de serviço concluídos; API/RBAC, enrollment, Active Response, módulos necessários e exposição mínima revisados; Manager invariável na promoção final | sem pendência crítica pré-freeze; rootfs/capabilities permanecem decisão de compatibilidade documentada |
| Wazuh Indexer | ✅ VALIDADO | `cap_drop=ALL`, NNP, PIDs 256, healthcheck, 9200 privada; security plugin/usuários/TLS/anônimo revisados; `allow_default_init_securityindex=false` promovido live | sem pendência crítica pré-freeze; hostname verification do transport single-node permanece risco residual aceito |
| Wazuh Dashboard | ✅ VALIDADO | `cap_drop=ALL`, NNP, PIDs 128, loopback e ACL mínima do `wazuh.yml`; sessão/cookies/TLS revisados; `verificationMode=full` e `cookie.secure=true` promovidos live | sem pendência crítica pré-freeze; `session.keepalive=true` com TTL 15 min permanece risco residual aceito |
| OpenBao | ✅ VALIDADO | Raft, Shamir 2/3, políticas dedicadas, AppRole SMTP/Bacula, runtime forte e integração OpenBao → Wazuh validados | listener HTTP permanece restrito ao loopback; qualquer consumo entre VMs exigirá TLS e workload identity |
| Ferret | ✅ VALIDADO | runtime forte; DLP → Wazuh E2E; limites de recursos, monitor de health, retenção e logrotate validados; gate final `PASS=59 WARN=2 FAIL=0` | quarentena permanece evolução futura; modo atual continua detect-only |

## EP125 — serviços e componentes de DMZ

| Componente | Estado | Evolução já registrada | Próxima auditoria |
|---|---|---|---|
| Suricata | ✅ VALIDADO | instalação 8.0.6; ET Open; `eve.json`; integração Wazuh; `HOME_NET` restringido para `192.168.6.32/28` | manter baseline e revalidar após mudanças de rede; reconciliar coleta local ao migrar o agente 001 para `conectaeduca-dmz` |
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
| 08/09/2026 | PostgreSQL/Bacula TLS | bridge Unix socket PgBouncer → PostgreSQL com `verify-full`; HBA amplo `host` → `hostssl`; plaintext inter-container bloqueado; novo backend pós-`hostssl` validado | `docs/evidencias/postgresql-bacula-tls-20260908.md` |
| 08/09/2026 | Bacula Director + Storage runtime | rootfs RO; PID-less; UID/GID final 100:101; capabilities finais zeradas; NNP; PIDs 256; healthchecks e TLS funcional | `docs/seguranca/BACULA-DIRECTOR-STORAGE-HARDENING.md` / PR #43 |
| 08/09/2026 | Wazuh Indexer + Dashboard runtime | `cap_drop=ALL`, NNP, PIDs limits e healthchecks incorporados ao `compose.host.yml` | `docs/seguranca/WAZUH-INDEXER-DASHBOARD-RUNTIME-HARDENING.md` / PR #44 |
| 08/09/2026 | Wazuh Manager runtime | NNP, PIDs 1024 e healthcheck para daemons/Filebeat/API; capabilities e rootfs mantidos por decisão explícita | `docs/seguranca/WAZUH-MANAGER-RUNTIME-HARDENING.md` / PR #45 |
| 08/09/2026 | Wazuh EP126 + Ferret DLP E2E | agente `002` centralizado em `conectaeduca-interna`; 7 colisões podadas; configtests OK; finding sintético `high` gerou alerta 110113 level 12; `E2E_PROVEN=1` | `docs/evidencias/wazuh-ep126-dlp-e2e-20260908.md` / PR #46 |
| 12/09/2026 | OpenBao operação | Shamir 2/3, AppRole e integração sanitizada com Wazuh concluídos | PR #59 / Trello #41 |
| 12/09/2026 | Ferret operação | health, limites, retenção/logrotate e pipeline sintético pós-merge concluídos | PR #61 / Trello #42 |
| 12/09/2026 | Wazuh service-layer | auditoria final + hardening Indexer/Dashboard promovido live; `PASS=145 WARN=0 FAIL=0 GAP=0` | PRs #62–#64 / `docs/evidencias/wazuh-servico-final-20260912.md` |

## Referências Git recentes

- PR #43 — `hardening: versiona runtime PID-less do Bacula`;
- PR #44 — `hardening: adiciona controles de runtime ao Wazuh`;
- PR #45 — `hardening: incorpora controles low-risk do Wazuh Manager`;
- PR #46 — `docs: registra estado validado do Wazuh EP126 e DLP E2E`.

## Fontes declarativas relevantes

- MariaDB: `deploy/interna/mariadb/`
- OpenBao: `deploy/interna/openbao/`
- Ferret: `deploy/interna/ferret/`
- Wazuh: `deploy/interna/wazuh/`
- Bacula: `deploy/interna/bacula/`
- DMZ Nginx/PHP/WAF: `deploy/dmz/`
- Evidências sanitizadas: `docs/evidencias/`
- Estado validado Wazuh EP126: `deploy/interna/wazuh/ESTADO-VALIDADO-EP126.md`

## Pendências transversais relevantes

- a política central `conectaeduca-interna` está aplicada e possui SHA-256 conhecido, mas o `agent.conf` efetivo ainda não foi canonicalizado no Git; antes de versioná-lo, recuperar o arquivo ativo no Manager e confirmar byte a byte o SHA `41f69c91175616230592ecad696a08f1b7f8241f6a8eab242f3d84e532a3971b`;
- a policy `conectaeduca-dmz` só deve ser canonicalizada após a auditoria/poda da EP125, evitando duplicar Suricata, FIM de demonstração ou interferir no Active Response/YARA;
- a porta TCP/1515 é superfície temporária de enrollment e deve permanecer fechada no estado operacional normal; o validador deve tratá-la como exceção explícita, não como requisito permanente.

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
