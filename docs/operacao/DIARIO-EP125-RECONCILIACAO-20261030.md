# Diário operacional — EP125 — 30/10/2026 (BRT)

## Reconciliação Git controlada — concluída (código, sem deploy)

- VM: ep125-pucpr; usuário operacional: andrea.kiew; repositório: /opt/conectaeduca; branch: main.
- HEAD antes: `4bf7ac688b1ea738cd158f03a20b07732cdd90a3` (merge PR #202 PHP-FPM 8.5.12).
- Destino fixo da main remota: `b74ea581a0814d86a99b6b455d5569f12fa967e5`.
- Procedimento: precheck read-only, verificação de fast-forward, backup do overlay local, `git fetch` por SHA, `git merge --ff-only` e atualização da referência `origin/main`.
- Resultado: 27 commits aplicados por fast-forward, 10 arquivos versionados alterados (467 inserções, 16 exclusões); `HEAD...origin/main = 0 0`; árvore rastreada limpa.
- Único untracked preservado: `deploy/dmz/compose.audit-persistent.yml`; SHA-256 original e backup: `36469d6694b9eb2e802822946efd788ffb1e97c95170d0f2680731a98699998e`. Backup em `/home/andrea.kiew/ConectaEduca_Reconciliacao_EP125_20261030T164204/`.
- Overlay é o 10º arquivo Compose efetivo; montagem PHP de auditoria confirmada: `bind /var/log/conectaeduca/php-audit -> /var/www/conectaeduca/storage/logs`.
- PHP-FPM, WAF e Nginx: `healthy` após atualização Git. `StartedAt` UTC: PHP 19:06:58, WAF 19:06:56, Nginx 19:06:55 (16:06 BRT), `RestartCount=0` em todos. Causa do início recente não determinada; não atribuir ao script.
- Evidência local: `/home/andrea.kiew/ConectaEduca_Reconciliacao_EP125_20261030T164204/reconciliacao_git_20261030.txt`; `git-head-before.txt`; backup do overlay; resultados da validação pós-reconciliação apresentados pela operadora.
- **Limite do aceite:** reconciliação do Git na EP125 concluída. **Não houve deploy nem recriação de containers neste procedimento.** Não equivale a homologação operacional, testes de login/MFA/RBAC, WAF ou persistência após recriação. EP126 permanece sem reconciliação comprovada neste registro.
- Próximos gates: homologação operacional EP125, esclarecer reinício recente se necessário, reconciliação EP126, PRs draft e mudanças de runtime sob change control com rollback.


## Homologação operacional EP125 — Etapas 1 a 6 — 30/10/2026 (BRT)

**Fonte:** saídas de terminal da operadora e evidência TXT da Etapa 6; evidências completas permanecem na EP125, não anexadas ao GitHub. Registros automáticos no diário local confirmados nas Etapas 2–6; Etapa 1 foi incorporada ao diário local por atualização de arquivo.

| Etapa | Horário BRT | Evidência e resultado | Limite |
| --- | --- | --- | --- |
| 1 | 17:01 | PHP/WAF/Nginx running/healthy; HTTPS /, /login.php, /api/public_key.php e /assets/js/crypto-utils.js com HTTP 200 e TLS_VERIFY=0. | Sem autenticação ou prova de regra WAF. |
| 2 | 17:03 | HTTPS HTTP 200/TLS_VERIFY=0; bind PHP audit RW; audit.log presente, 28.360 bytes, modo 600. SHA256 evidência `c1985b4f228a8edf0b0f3d75baf0090426569e638697d469294c7a46df17ae83`. | Sem teste de persistência após recriação. |
| 3 | 17:07 | Somente WAF publica portas no host (192.168.6.34:80/443); Nginx/PHP sem portas publicadas. HTTPS HTTP/2 200, CSP/HSTS presentes. audit.log no contêiner 28.360 bytes, 0600, UID/GID 82; acesso pelo host inconclusivo. SHA256 `e520c8aa9afef90b461fff203e8d8902adffa6aaa463cc8988196368a32fb51d`. | Cabeçalhos X-Content-Type-Options e Referrer-Policy duplicados; regra WAF não comprovada. |
| 4 | 17:09 | Bind RW; host retorna Permission denied para stat; diretório no contêiner 0700, arquivo 0600, UID/GID 82. SHA256 `85b22fbee0a33afd5e11bc7a1670255100f4821a0c314ea5b18c09f049f0ef46`. | Restrição de acesso compatível com permissões; sem escrita ou recriação de contêiner. |
| 5 | 17:11 | WAF running/healthy, publica 80/443; / e /login.php HTTP 200, TLS_VERIFY=0. SHA256 `9f145aaeb0f4ce2ad67ac1fafecb90b233707cc6fbbdf5a9c964c5a17c865bb0`. | Sem evidência de bloqueio de regras WAF. |
| 6 | 17:11 | Login legítimo **bem-sucedido, conforme relato da operadora**; aplicação **solicitou MFA**, conforme relato. audit.log cresceu de 28.360 para 29.294 bytes (+934), resultado ARQUIVO_CRESCEU. Operadora confirmou DIARIO_ATUALIZADO=SIM. | Conteúdo do log não inspecionado: crescimento não atribuído conclusivamente ao login; solicitação de MFA não equivale à validação completa de MFA/segregação de papéis. |

**Caminhos de evidência na EP125:** `/home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP125/HOMOLOG/EP125_HOMOLOG_ETAPA{2,3,4,5,6}_20261030T*.txt`; diário local `/home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP125/diario.md`. A evidência da Etapa 6 foi compartilhada como `EP125_HOMOLOG_ETAPA6_20261030T171146.txt`; nela constam tamanho antes/depois e interpretação de escrita observada.

**Conclusão parcial:** disponibilidade e TLS das rotas testadas satisfatórios; exposição de portas consistente com ingress WAF; login positivo e apresentação de desafio MFA observados; escrita em audit.log observada. **Pendências:** completar MFA (conclusão e negação de bypass), RBAC por perfil, regra WAF em cenário benigno controlado, correlação do evento de auditoria, retenção/rotação, persistência pós-recriação sob change control, reconciliação EP126 e aceite Grupo A. Nenhum deploy/restart/alteração de firewall autorizado ou executado nestas homologações. Não fechar o P0 global.

### Adendo — MFA positivo confirmado por captura de tela (30/10/2026)

A operadora confirmou que, após login, digitou o código MFA correspondente à conta de teste e **acessou normalmente o dashboard**. Captura de tela compartilhada na conversa mostra área autenticada, dashboard, nome da conta de teste e perfil `usuario`. **Fluxo positivo login → desafio MFA → código válido → dashboard: aprovado por relato e captura de tela.** A captura não contém o código MFA nem prova por si só os controles negativos. Permanecem pendentes: rejeição de código inválido, impossibilidade de acesso antes do MFA, RBAC de candidato/empresa/admin e validação de sessão. A imagem permanece como evidência da conversa; não foi copiada ao repositório para evitar divulgar dados da conta de teste.


## Etapa 7 — Homologação funcional manual (30/10/2026, 17:32 BRT)

**Fonte:** `EP125_HOMOLOG_ETAPA7_20261030T173202.txt` enviado pela operadora. Host `ep125-pucpr`, modo `TESTE_FUNCIONAL_MANUAL`, sem credenciais, sem leitura de log e sem mudança de configuração.

| Controle | Resposta | Interpretação restrita |
| --- | --- | --- |
| LOGIN | S | Sucesso declarado pela operadora |
| MFA_SOLICITADO | S | Desafio apresentado |
| MFA_VALIDADO | S | Código legítimo validado; dashboard acessado conforme captura e relato anteriores |
| MFA_BLOQUEIO | S | Bloqueio declarado; falta verificação independente de bypass |
| RBAC_CANDIDATO | S | Fluxo básico declarado |
| RBAC_EMPRESA | S | Fluxo básico declarado |
| RBAC_ADMIN | S | Fluxo básico declarado |
| RBAC_NEGACAO | NA | **Não avaliado; não classificar como aprovado** |
| LOGOUT | S | Sucesso declarado |

**Limites:** o arquivo contém respostas manuais, não requisições/respostas HTTP, traces ou correlação de auditoria. Não inferir isolamento horizontal ou vertical a partir de navegação funcional.

### Roteiro reservado — pentest educacional de autorização (NÃO EXECUTADO)

**Pré-condições:** autorização e escopo definidos pelo professor; contas de teste próprias e dados sintéticos; autorização explícita para criar segunda conta candidato ou fixture; snapshots/backup e janela acordada; endpoints e identificadores reais documentados; sem alterar dados de terceiros. Manter taxa baixa, registrar horário, método, endpoint sem tokens e status HTTP, ID sintético, resultado esperado/obtido e hash de evidência.

- **PA-AUTHZ-HORIZONTAL (IDOR/BOLA):** com duas contas candidatas distintas A e B, criar recursos sintéticos separados. Autenticar A e tentar ler/editar somente o identificador do recurso sintético de B via fluxo autorizado. Esperado: 403 ou 404 e nenhuma leitura/alteração indevida. Se não houver segunda conta autorizada, marcar BLOQUEADO POR PRÉ-REQUISITO, não aprovado.
- **PA-AUTHZ-VERTICAL (BFLA/RBAC):** usar perfis candidato, empresa e administrador de teste. Mapear recursos e endpoints permitidos por papel. Para cada conta, tentar acessar uma rota/operação reservada a outro papel por navegação e requisição direta, sem ações destrutivas. Esperado: 403/404 ou redirecionamento controlado, sem execução de operação não autorizada. Não confundir ocultação de menu com autorização no servidor.
- **PA-MFA-NEGATIVO:** em conta própria, confirmar que sessão não autenticada completamente não alcança endpoint protegido; testar um único código inválido sob política de bloqueio, sem brute force. Esperado: recusa e ausência de sessão autenticada.
- **PA-SESSION:** confirmar que logout invalida sessão anterior e endpoints protegidos não aceitam reutilização de sessão encerrada; não registrar cookies/tokens nos artefatos.

**Situação:** roteiro preparado para execução posterior; nenhum desses testes de pentest foi executado nesta etapa. **Próxima homologação operacional:** Etapa 8, WAF com verificações benignas e autorizadas. Não fechar Grupo A/P0; EP126 ainda pendente.


## Homologação EP125 — Etapas 8–12 (30/10/2026, 17:48–17:53 BRT)

**Fonte:** evidências manuais enviadas pela operadora `EP125_HOMOLOG_ETAPA8_20261030T174842.txt`, `EP125_HOMOLOG_ETAPA9_20261030T174939.txt`, `EP125_HOMOLOG_ETAPA10_20261030T175041.txt`, `EP125_HOMOLOG_ETAPA11_20261030T175138.txt`, `EP125_HOMOLOG_ETAPA12_20261030T175300.txt`. Inspeções de leitura, sem reinícios ou alterações. Relatório local Daily 9 v19 consolidado, não anexado neste commit.

| Etapa | Evidência principal | Estado/limites |
| --- | --- | --- |
| 8 — WAF | Contêiner healthy; ModSecurity-nginx 1.0.4/libmodsecurity 3.0.16; **852 regras locais carregadas**; nginx -t OK; HTTPS 200, TLS_VERIFY=0 | **Estrutura OK**; bloqueio efetivo **não testado**; aviso ssl_stapling: issuer certificate not found |
| 9 — Auditoria | PHP/Nginx/WAF healthy; audit.log 34.128 bytes, modo 600; logs PHP em bind mount RW; mounts de segredos PHP RO | **Presença/metadata OK**; conteúdo/correlação de eventos não analisados; arquivo WAF não localizado nos caminhos amostrados |
| 10 — Retenção | bind `/var/log/conectaeduca/php-audit` → `/var/www/conectaeduca/storage/logs` RW; PHP docker log driver json-file, opções {}; WAF journald, tag conectaeduca-waf; SecAuditEngine RelevantOnly, LogType Serial, LogFormat JSON, StorageDir /var/log/modsecurity/audit/ | **Configuração identificada**; rotação e persistência após recriação **não comprovadas**; destino SecAuditLog foi mascarado pela coleta |
| 11 — TLS/headers | HTTPS 200, verificação curl 0, HTTP/2; CSP, HSTS, X-Content-Type-Options, Referrer-Policy, Permissions-Policy; certificado interno ConectaEduca Lab Root CA, CN conectaeduca.local, expira 13/10/2027 | **HTTPS funcional**; duplicados X-Content-Type-Options, Referrer-Policy e Permissions-Policy; X-Frame-Options SAMEORIGIN vs CSP frame-ancestors none; aviso ssl_stapling persiste. Script rotulou incorretamente versão HTTP como SSL_VERSION; negociação TLS 1.2/1.3 não provada individualmente |
| 12 — Hardening | PHP, Nginx, WAF running; usuários não-root (82,101,101); privileged=false; readonly rootfs=true; no-new-privileges=true; cap_drop ALL; CapEff=0; Seccomp=2 | **Controles verificados**; consulta de montagens de segredos falhou em todos os contêineres: template Docker não suporta hasPrefix. Repetir consulta sem função não suportada; não inferir ausência de segredos |

### Pendências priorizadas

1. Teste controlado, benigno e autorizado de **bloqueio real do WAF** e destino dos eventos ModSecurity.
2. Validar **rotação/retention** do audit.log PHP e do driver json-file; conferir daemon.json, logrotate, journal retention sem ler segredos ou recriar serviços.
3. Padronizar cabeçalhos duplicados e investigar se **OCSP Stapling** é aplicável ao certificado emitido pela CA interna; distinguir da futura cadeia pública ZeroSSL.
4. Repetir coleta de mounts de segredos com `docker inspect --format '{{range .Mounts}}{{println .Destination .Type .RW}}{{end}}'` e filtrar localmente, sem revelar conteúdo.
5. Correlacionar eventos de autenticação, autorização e auditoria sem dados sensíveis; comprovar persistência após recriação somente em janela aprovada.
6. Executar roteiro educacional de autorização horizontal/vertical e MFA negativo posteriormente, com duas contas sintéticas autorizadas e escopo formal.
7. EP126 indisponível em manutenção pelo suporte; não testar Wazuh/Bacula/Ferret nem declarar Grupo A/P0 concluído.

**Estado:** Etapas 8–12 concluídas como **diagnóstico**, não como homologação integral de todos os controles. Sem deploy, restart ou mudanças nas VMs pelo assistente.


## EP125 — Homologação Etapas 13 a 15B (30/10/2026)

- Etapa 13 (18:00): seis montagens de segredos em /run/secrets verificadas, quatro no PHP e duas no WAF, todas RW=false. Nginx sem montagens nesse diretório. Não houve leitura de segredos.
- Etapa 14 (18:01): WAF healthy; SecRuleEngine On, auditoria RelevantOnly em JSON, 852 regras carregadas. Sem montagens de logs em /var/log; aviso ssl_stapling continua. Bloqueio ainda não testado.
- Etapa 14B (18:02): SecAuditLog aponta para STDOUT; consulta direta ao journal inconclusiva.
- Etapa 14C (18:03): Docker journald; docker logs acessível com 83 linhas, das quais 41 com indicadores ModSecurity/transaction/messages e zero com expressão access denied. Journal do host inacessível ao usuário. Não interpretar linhas como ataques nem como transações distintas.
- Etapa 15 (18:03): sem parâmetros explícitos de retenção journald identificados; /var/log/journal e /run/log/journal presentes; consulta de ocupação inconclusiva; PHP usa json-file sem opções explícitas, WAF usa journald; logrotate instalado. Diretório de auditoria PHP não encontrado por acesso direto.
- Etapa 15B (18:05): docker inspect confirma bind mount RW do PHP com origem /var/log/conectaeduca/php-audit; teste direto no host retornou caminho inexistente ou inacessível e stat falhou. daemon.json ausente ou inacessível. Divergência permanece sem causa estabelecida.

**Conclusão:** montagens de segredos somente leitura comprovadas; auditoria WAF recuperável via docker logs; retenção, acesso ao diretório do host, bloqueio WAF, integração Wazuh e testes RBAC negativos ainda pendentes. Não houve alterações ou reinícios. EP126 sob manutenção; Grupo A/P0 não concluído.


## Etapa 15C e planejamento de validação WAF 16A/16B — 30/10/2026

**15C (18:09 BRT, leitura apenas):** Docker contexto default, daemon ep125-pucpr, root /var/lib/docker. Bind PHP RW de /var/log/conectaeduca/php-audit para /var/www/conectaeduca/storage/logs confirmado. Diretório pai /var/log/conectaeduca com modo 710, UID 0, GID 82. Usuária andrea.kiew não consegue stat da origem; no contêiner, diretório existe (82:82, 700) e audit.log existe (34.128 bytes, 600). Interpretação: restrição de acesso ao host é hipótese provável; não declarar inexistência/perda de logs. Sem chmod/chown, restart ou leitura de conteúdo.

**16A — seleção de regra (PLANEJADA, NÃO EXECUTADA):** inspecionar metadados de regras CRS, ações efetivas, SecRuleEngine, modo de anomalia, thresholds e exceções. Escolher regra/estímulo sintético não destrutivo e rota autorizada. Não assumir que uma única correspondência gera 403.

**16B — teste controlado (PLANEJADO, NÃO EXECUTADO):** obter autorização/janela, registrar baseline GET normal, enviar uma única requisição sintética aprovada, correlacionar status HTTP, ID de regra e auditoria via docker logs, sem preservar credenciais, cookies ou logs brutos. Critério: ação disruptiva + evidência correlacionada; caso contrário inconclusivo/falha. Interromper se degradação. Sem alteração de configuração prevista.

**Pendências:** retenção journald/json-file e rotação PHP, acesso privilegiado à origem bind, bloqueio WAF, TLS/OCSP/headers, Wazuh/EP126. P0/Grupo A permanece aberto. Relatório Daily 9 v21 gerado localmente; arquivo Word não publicado no GitHub.


## Homologação WAF — Etapas 16B, 16B.1, 16B.2 e 16C (30/10/2026)

- **16B, 18:29:48 BRT:** WAF healthy; baseline HTTPS falhou porque o script usou 127.0.0.1:443. Requisição sintética NÃO enviada; resultado interrompido, sem evidência de falha do WAF. Evidência `EP125_HOMOLOG_ETAPA16B_20261030T182948.txt`.
- **16B.1, 18:30:50 BRT:** Docker publica contêiner 8080/tcp em 192.168.6.34:80 e 8443/tcp em 192.168.6.34:443. Host escuta em 192.168.6.34:443; `conectaeduca.local` não resolvido localmente. Sem tráfego HTTP ou alterações. Evidência `EP125_HOMOLOG_ETAPA16B1_20261030T183050.txt`.
- **16B.2, 18:32:04 BRT:** usando `curl --resolve conectaeduca.local:443:192.168.6.34` com validação TLS, baseline HTTP **200** e requisição sintética textual de XSS HTTP **403**. `docker logs` acessível; 2 linhas com marcador `CEWAF16B2_20261030T183204_79631`. WAF healthy; sem mudança ou restart. Evidência `EP125_HOMOLOG_ETAPA16B2_20261030T183204.txt`.
- **16C, 18:33:11 BRT:** correlação read-only do mesmo marcador: 2 linhas, status **403**, mensagem ModSecurity presente e IDs **941100, 941110, 941160, 941320, 941390, 942131, 949110**. Intervenção explícita não extraída (`INTERVENCOES=NAO_IDENTIFICADAS`); nenhuma nova requisição. Evidência `EP125_HOMOLOG_ETAPA16C_20261030T183311.txt`.

**Conclusão restrita:** homologado comportamento observado de bloqueio HTTP 403 para a requisição sintética com correlação de regras OWASP CRS, incluindo 949110 (avaliação de anomalias). A ação disruptiva individual não foi identificada pelo parser; não extrapolar para cobertura universal de XSS/SQLi. **Próximo:** consolidar evidências e avaliar critérios pendentes da issue #201 (regressão autenticada, CSRF, rollback), sem alterações de runtime. Grupo A continua aberto.


## Complemento de rastreabilidade — Etapas 16A.2–16A.4 e Daily 9 v22 (30/10/2026)

- **16A.2:** duas coletas incompletas (18:24:06 e 18:24:30 BRT), sem inspeção interna; causa atribuída à ausência de `-i` no `docker exec` com heredoc. Evidências `EP125_HOMOLOG_ETAPA16A2_20261030T182406.txt` e `EP125_HOMOLOG_ETAPA16A2_20261030T182430.txt`.
- **16A.3 (18:25:24):** `docker exec -i` permitiu inspeção; CRS em `/opt/owasp-crs`, arquivos REQUEST-949 e RESPONSE-959 encontrados. Evidência `EP125_HOMOLOG_ETAPA16A3_20261030T182524.txt`.
- **16A.4 (18:26:25):** referências às ações `deny`/`block` e limiares de anomalia; valores efetivos/ação individual não inteiramente confirmados. Evidência `EP125_HOMOLOG_ETAPA16A4_20261030T182625.txt`.
- **Word:** Daily 9 v22 criada a partir da v21, preservando conteúdo anterior e adicionando adendo 16A.2–16C, matriz de resultados, limitações, referências e SHA-256 dos arquivos de evidência. Documento entregue na conversa, **não versionado no repositório**.
- **Gestão:** issue #201 segue aberta para regressão autenticada (CSRF e negação RBAC), demais superfícies e rollback; Grupo A/P0 permanece aberto. Sem mudanças de configuração, merge ou restart neste complemento.


## 30/10/2026 — EP125, homologação 17A–17B.2: retificação de falso zero e mapeamento RBAC/CSRF

**Fonte:** evidências locais recebidas da EP125; execução de scripts versionados em `scripts/homologacao/ep125/`. A EP125 permanece em `/opt/conectaeduca`, branch `main`, HEAD observado `b74ea58` (merge PR #212). O arquivo não rastreado `deploy/dmz/compose.audit-persistent.yml` foi preservado; atualização apenas por `git fetch` e extração `git show FETCH_HEAD:...` para `~/ConectaEduca_Fase2_Evidencias/EP125/scripts/`.

- **17A/17A.1:** zeros de CSRF/POST na busca original: **não conclusivos**; o método original de `grep` não retornava ocorrências mesmo com arquivos legíveis.
- **17B.0** (19:13:18 BRT, `EP125_HOMOLOG_ETAPA17B0_20261030T191318.txt`): WAF `running/healthy`, PHP UID/GID `82:82`, diretórios `public`/`src` presentes, oito termos de RBAC zerados pela busca original. Sem restart/configuração alterada.
- **17B.1** (19:14:31 BRT, `EP125_HOMOLOG_ETAPA17B1_20261030T191431.txt`): `grep` funcional; `public` 32 e `src` 88 arquivos PHP/JS. Método original: 0 para todos os termos. Método simplificado `find ... -exec grep -i -l -F`: `role=27`, `admin=20`, `candidato=1`, `empresa=30`, `csrf=33`, `POST=39`. **Falso zero identificado.**
- **17B.2** (19:16:28 BRT, `EP125_HOMOLOG_ETAPA17B2_20261030T191628.txt`): PHP `running/healthy` (UID/GID `82:82`). Indicadores por quantidade de arquivos (`public/src`): `csrf=4/29`; `csrf_token=1/3`; `hash_equals=0/1`; `session_start=0/1`; `role=2/25`; `permission=0/1`; `authorize=0/4`; `admin=1/19`; `empresa=4/26`; `candidato=0/1`; `REQUEST_METHOD=16/3`; `POST=17/22`; `403=0/1`; `forbidden=0/2`. Sem alterações da aplicação ou reinícios.

**Interpretação:** referências estáticas confirmadas, **sem comprovação funcional de CSRF ou RBAC negativo**. Não classificar o controle como ausente ou homologado com base na contagem. **Pendências:** identificar rotas e verificações efetivas; teste RBAC negativo autenticado por perfis existentes; validação CSRF controlada; regressão/rollback para aceite da issue #201. Manter #201 aberta.

**Gestão:** documento Daily 9 atualizado para v23 (adendo de 30/10, preservado conteúdo v22); scripts 17B.1/17B.2 e kit 16A.2–17B.0 publicados nesta branch; Trello P0 de reconciliação atualizado por comentário. Sem merge na `main` ou ações nas VMs por este registro.


## 30/10/2026 — Etapas 17B.3 e 18A–18F: matriz RBAC/CSRF, persistência de auditoria e falha Wazuh

**Fonte:** arquivos TXT de evidência executados na EP125 e compartilhados pela operadora. Sem intervenção em serviço, configuração ou volumes. A investigação Wazuh permanece inconclusiva quanto à causa raiz.

- **17B.3 (19:25 BRT):** matriz estática de rotas PHP da aplicação, 32 arquivos PHP/JS em public e 88 em src, referências a papéis e autorização presentes. Testes negativos autenticados RBAC/IDOR/BOLA e CSRF adiados por decisão explícita para o segundo pentest com Twingate; falta criar segunda conta sintética de empresa. Inspeção estática não equivale a comprovação funcional. Issue #201 continua aberta.
- **18A (19:28:38, EP125_HOMOLOG_ETAPA18A_20261030T192838.txt):** main HEAD b74ea58; overlay não rastreado `deploy/dmz/compose.audit-persistent.yml` preservado. PHP, WAF e Nginx healthy. PHP possui bind RW em `/var/www/conectaeduca/storage/logs`; `audit.log` existe, legível/gravável, 34.128 bytes. Bind sugere persistência, mas recriação/restore não foram testados. `wazuh-agent` em failed.
- **18B (19:29:40, EP125_HOMOLOG_ETAPA18B_20261030T192940.txt):** serviço wazuh-agent enabled, failed, Result=timeout, NRestarts=0; nenhum processo Wazuh identificado. Inspeção não privilegiada apontou diretórios inacessíveis, erroneamente interpretados inicialmente como ausentes.
- **18C (19:30:34, EP125_HOMOLOG_ETAPA18C_20261030T193034.txt):** pacote wazuh-agent 4.14.7-1 instalado e em hold; systemd usa `/var/ossec/bin/wazuh-control start` e TimeoutStartUSec=45s; execução encerrada com TERM após 45s. Ausência de acesso à árvore /var/ossec ainda não reconhecida nessa etapa.
- **18D (19:31:25, EP125_HOMOLOG_ETAPA18D_20261030T193125.txt):** `/var/ossec` modo 750, proprietário root:wazuh; `find` retornou Permission denied. `dpkg --verify` não privilegiado contém falsos indicadores de missing decorrentes de permissão; sem montagem separada de /var/ossec.
- **18E inicial (19:32:57):** `sudo -n` exigia autenticação e o bloco colado com `exit 2` encerrou a sessão de terminal. Erro no roteiro; sem alteração da VM. Após `sudo -v`, `sudo -n true` retornou OK. Orientação corrigida para execução em Bash isolado, evitando encerrar shell interativo.
- **18E corrigida (19:41:52, EP125_HOMOLOG_ETAPA18E_CORRIGIDA_20261030T194152.txt):** acesso sudo OK; `/var/ossec/bin`, `etc`, `logs`, `wazuh-control`, `wazuh-agentd`, `ossec.conf` EXISTEM. `dpkg --verify` privilegiado ainda aponta arquivos auxiliares ausentes em `/var/ossec/packages_files` e entradas init/systemd alternativas; relevância causal não comprovada. Journal confirma timeout às 15:57:43 BRT, não sua causa.
- **18F (19:42:56, EP125_HOMOLOG_ETAPA18F_20261030T194256.txt):** serviço failed, log interno `/var/ossec/logs/ossec.log` EXISTE; filtro de erros aplicado não retornou linhas; nenhum processo Wazuh localizado. Isso NÃO prova log vazio nem ausência de erro. Sem restart ou mudança de configuração.

**Decisão:** não reinstalar Wazuh nem elevar timeout sem diagnóstico/controle de mudanças. Abrir encaminhamento pontual ao suporte ou janela autorizada para examinar logs e corrigir a inicialização; confirmar coleta do audit.log na EP126 depois. Aceite da aplicação pode ser condicionado, mas observabilidade Wazuh e persistência pós-recriação NÃO homologadas. Overlay local não rastreado não deve ser apagado. Grupo A/P0 segue aberto. Testes ofensivos RBAC/CSRF/IDOR/BOLA adiados ao pentest 2; não declarar esses controles aprovados.


## 30/10/2026 — Twingate: configuração de recurso DMZ e evidências do painel (Daily 9 v26)

Capturas da operadora documentam duas Remote Networks (ConectaEduca - DMZ e Rede Interna), quatro conectores sem conexão funcional, três grupos manuais (CE-INFRA-ADMIN, CE-PORTAL, CE-SOC-OPERACAO) e Everyone. O conector `conectaeduca-dmz-01` aparece `Not yet connected`, vinculado à DMZ; painel oferece Docker, Linux e outros métodos, **sem instalação realizada**. O conector da rede interna anteriormente apresentou `Could not connect`; EP126 em manutenção.

O recurso `ConectaEducaAPP` foi criado na rede DMZ com endereço `192.168.6.34` e restrições **TCP 443, UDP Blocked, ICMP Block**. O painel informa Default Policy utilizada por ConectaEducaAPP. A tela de Manual Access mostra CE-PORTAL e o histórico de captura exibe a Default Policy sob esse grupo; recomenda-se confirmar persistência da associação após reabrir. Não conceder Everyone.

Políticas observadas: **Default Policy** reautenticação a cada 5 dias, **MFA not required**, Any Device, geoblocking indisponível; **CE-INFRA-MFA-2HORAS** reautenticação a cada 2 horas, MFA required, 0 recursos; **CE-SOC-MFA-1DIA** reautenticação diária, MFA required, 0 recursos. Não presumir dispositivo confiável ou geoblocking habilitado.

**Limites de evidência:** recurso e políticas configurados no painel não provam conectividade, bloqueio por identidade, proteção de exposição direta nem integração com pfSense. Aguardar resposta dos professores sobre portal público via WAF ou privado via Twingate. Não instalar conector, alterar NAT/firewall ou publicar serviços até validação de host, rotas, autorização e rollback. Daily 9 **v26** gerada localmente com dez novas capturas, preservando v25; arquivo Word não versionado no repositório.


## 30/10/2026 — Twingate EP125: PR #213, preflight e teste de acesso bridge → WAF

**PR de implementação (draft):** #213, branch `feat/twingate-dmz-connector-preflight-20261030`, contendo Compose isolado, modelo de env protegido, script `--preflight/--deploy` e README. Sem merge e sem deploy até esta evidência.

**Preflight EP125 — 21:03:05 BRT** (`CE_TWINGATE_DMZ_preflight_20261030T210305.txt`):
- Docker Compose v5.5.1; memória total 7,8 GiB, disponível 3,8 GiB; disco raiz 176 GiB, 137 GiB livres (19% usado).
- `conectaeduca-dmz-php-1`, `conectaeduca-dmz-waf-1` e `conectaeduca-dmz-nginx-1` **healthy**.
- WAF publica `192.168.6.34:443->8443/tcp` e `192.168.6.34:80->8080/tcp`.
- TCP/443 a partir do host: `TCP443_CONECTA=SIM`. Sem contêiner Twingate existente identificado; preflight somente leitura.

**Teste temporário Docker bridge → WAF — 21:04:08 BRT** (transcrição de terminal):
- Comando executado em Bash filho: `docker run --rm --network bridge --pull=missing --entrypoint curl curlimages/curl:8.11.1 --connect-timeout 5 --max-time 15 --silent --show-error --insecure --output /dev/null --write-out 'HTTP_STATUS=%{http_code}\\nREMOTE_IP=%{remote_ip}\\n' https://192.168.6.34/`.
- Imagem `curlimages/curl:8.11.1` baixada (digest observado `sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69`).
- Resultado: **HTTP_STATUS=200**, **REMOTE_IP=192.168.6.34**, **CODIGO_SAIDA=0**; contêiner temporário removido com `--rm`; aplicação não alterada.
- `--insecure` dispensou verificação TLS **apenas para o teste**, portanto não demonstra validade do certificado, identidade do servidor nem configuração TLS final.
- O teste confirma conectividade do contêiner na rede bridge até a entrada WAF/HTTPS da EP125; **não** comprova conector instalado, saída do conector à nuvem, política por identidade, nem bloqueio de acesso direto.

**Próximo controle de mudança:** conferir instruções e variáveis oficiais do conector no painel sem divulgar tokens, confirmar saída/DNS e preservar segredos apenas no `connector.env` local com permissão 600. Validar revisão do PR #213 antes de `--deploy`. Sem alterações na EP126.
