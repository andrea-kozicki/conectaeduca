# Sprint 2 — Matriz executiva do pentest interno e apresentação (14/10/2026)

**Status:** preliminar. **Origem:** síntese documental do relatório académico integrado v26.9 (56 páginas) e dos registros PA-01–PA-07, não substitui logs nem hashes das evidências primárias. **Entrega prevista:** 19/10/2026.

## Escopo e limites

- Ambientes avaliados: EP125/DMZ, EP126/rede interna (identidade Linux `teste`, UID1001) e papéis fictícios da aplicação (usuario, empresa, admin).
- Baseline de referência FREEZE-02 `main@c37bdce07a9ae71ceb1a1e0c8e0e1e2b51e112ce`; **não alterar** imagens/configuração das VMs e **não confundir** a branch documental com runtime.
- Enunciado da Sprint 2 originalmente exige >=3 posições de ameaça, com ao menos uma externa; orientação posterior do professor é pentest interno. Foram exercitadas 3 posições internas/lógicas, mas nenhuma varredura externa Kali/WAN dessa Fase 2 foi demonstrada. **Solicitar conciliação docente**, sem inventar execução.
- Quatro objetivos obrigatórios: movimento lateral, escalação de privilégios, evasão de defesa e vazamento de dados.

## Rastreabilidade S01–S13

| ID | Cenário | Evidência vinculada | Estado defendível |
|---|---|---|---|
| S01 | Perímetro/exposição | PT-EXT planejado, PT-01 interno | Reenquadrado; externo não executado |
| S02 | WAF/payloads | PA-02.I.1 HTTP 403 publicado / 200 Nginx; I.2 Wazuh 110300 | Parcial, sem exploit/impacto |
| S03 | Segmentação/lateral | PA-01, PA-02.J-G4 pfSense BLOCK 8080/8088 | Concluído no recorte |
| S04 | Login/MFA/rate limit | PA-05.E.1/E.2 GET com sessão 200, anônimo 401 | Parcial; rate limit/MFA atual não cobertos integralmente |
| S05 | RBAC/ownership | PA-05.A/B/C/D/E, POST negativos, auth 200/401 | Parcial; horizontal sem fixtures |
| S06 | MariaDB/grants | PA-01 e PA-05.D.5 erro SELECT #1142 para tabela base | Concluído no recorte |
| S07 | Segredos | PA-04, Gitleaks | Concluído no recorte |
| S08 | Containers/host | PA-03, LOGIN-02 | Concluído no recorte |
| S09 | SIEM | Wazuh 110300 temporalmente correlacionado ao PA-02.I | Cobertura forte, sem request-ID 1:1 |
| S10 | FIM/YARA | PA-06.G1-G3, agente 001 e FIM atual, YARA histórico | Canário atual bloqueado por fixture |
| S11 | DLP/egress | PA-07; Ferret POST /scan 403, egress privado não ensaiado | Parcial / scan inconclusivo |
| S12 | Backup/restore | BAC-04 histórico; Bacula atual inacessível para restore | Histórico + bloqueio atual |
| S13 | Privacidade/LGPD | Evento histórico minimizado, Ferret Scan não concluído | Parcial / atual inconclusivo |

## Achados e ressalvas

- **OBS-01 WAF/backend:** marcador inerte obtém 403 via HTTPS publicado versus 200 por Nginx interno na EP125; alerta Wazuh `110300` na mesma janela, sem ID transacional que prove atribuição unívoca. Sem execução XSS/SQLi demonstrada, nem alcance externo do Nginx por origem não autorizada.
- **OBS-02 pfSense:** regra residual LAN49 PASS→Any com outros bloqueios específicos; states privados observados não provam tráfego ilegítimo ou exfiltração.
- **OBS-03 Ferret Web UI:** POST `http://127.0.0.1:18082/scan` foi rejeitado 403, corpo `cross-origin request rejected`; Origin e Host observados são coerentes; a GUI também exibiu `No sensitive data found` após falha. Não declarar varredura negativa. Investigar comportamento do scanner sem contornar proteção de origem.
- **OBS-04 Wazuh SCA:** regra de checagem de socket com resultado N/A, não vulnerabilidade confirmada.
- **OBS-05 Inscricoes:** ausência de gate explícito `status=publicada` em função de serviço do código; sem fixture de oportunidade não publicada e sem prova dinâmica.

## Testes educacionais ainda NÃO executados (planejamento)

- **S02-XSS.R1:** GET com marcador HTML inerte em `/oportunidades.php?busca=`; inspeção do atributo/DOM e status. Código revisto usa `OutputEncoder::attr` / `htmlspecialchars(ENT_QUOTES|ENT_SUBSTITUTE, UTF-8)`.
- **S02-SQLI.R1:** GET com aspas simples codificadas no mesmo filtro, comparando status com consulta de controle. Código revisto usa PDO `prepare` + `bindValue`.
- **S02-CMDI.R0:** inspeção de caminhos até sinks de shell; não executar injeção dinâmica sem sink, fixture descartável e autorização.
- Sem `UNION`, time-based, dumping, payloads destrutivos, dados reais, sessão privilegiada adicional ou alteração de WAF/TLS.

## Revisões realizadas fora das VMs (14/10)

- Apresentação acadêmica **v26.10** gerada em PowerPoint editável e PDF, **20 slides**, organizada conforme a Sprint 2 e com S01–S13 em 2 slides de matriz.
- QA visual de todos os slides efetuado; nenhum dado de sessão/cookie incluído.
- GitHub PR [#189](https://github.com/andrea-kozicki/conectaeduca/pull/189) continua **draft**, sem merge e sem alterações em `main`. A rodada recente do branch documental no GitHub Actions apresentou **Semgrep, Gitleaks, PHPUnit Security Tests e Repository Static Integrity: success**; não confundir CI com avaliação dinâmica.
- Os arquivos binários PPTX/PDF do trabalho acadêmico são entregues via conversa, **não versionados no Git**.

## Pontos a resolver até 19/10

1. Confirmar com o professor a equivalência da orientação posterior **pentest interno** em relação à obrigação original de ponto externo.
2. Executar uma sonda por vez de XSS/SQLi com evidência HTTP/DOM e hash; sem marcar como PASS até analisar o resultado.
3. Priorizar lacunas com acesso legítimo: S04/MFA-rate limit, S05/BOLA, S10/FIM/YARA, S11/S13 DLP e S12 backup, rotulando como **bloqueado** quando faltarem fixtures/operador.
4. Sincronizar versões finais relatório/apresentação e cadeia de custódia; sem produzir uma severidade explorada a partir de hipóteses.


---

## Atualização datada — 15/10/2026 (não retroativa)

Este registro preserva o snapshot de 14/10 acima. Consultar o **[adendo integrado de 15/10](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md)** e os detalhes de [Wazuh 80710](PENTEST-PA06-S09G9-WAZUH-80710-20261015.md) e [Ferret DLP](PENTEST-PA07-S11S13-G5-FERRET-ERRO-SCAN-20261015.md).

| Cenário | Resultado adicional | Impacto / limite |
|---|---|---|
| **S05** | S05-DYN14: papel `usuario`, rota legítima 200 e quatro rotas privilegiadas 403. | RBAC vertical funcionando no recorte; BOLA horizontal/objeto não publicado dependem de fixtures. |
| **S09** | PA-06/S09.G9: 9.348 eventos 80710 nível 10 em ~20h, 3 amostras `dockerd/veth`; desativação também marcada como ativação. | **PA-06-OBS-02**: ruído e semântica imprecisa podem reduzir visibilidade; sem evasão/alerta perdido provado. Coleta do audit.log da aplicação segue não demonstrada. |
| **S11** | PA-07-DLP-01: fluxo `app.js` confirma que falha de `/scan` pode terminar com alerta verde sem achados; G4 já registrara 403 e UI verde. | **Falha da interface DLP comprovada**, risco de decisão de liberação sobre arquivo não varrido; nenhuma exfiltração nem falha do scanner backend confirmadas. |
| **S11/S03** | PA-07-EG-01: pfSense LAN49, bloqueios para DMZ e saída não privada e exceções 80/443/9102 acima de `Default allow LAN to any`. | **Risco residual condicionado** a Floating/aliases/estados: possíveis demais destinos privados por regra genérica; configuração não prova conexão indevida. |
| **S13** | Ferret G10–G13/B: submissão/persistência íntegra de fixture sintética e configuração JSONL `dlp.jsonl` demonstradas. | Sem prova contemporânea de execução do scanner ou correlação DLP→Wazuh da fixture. |

PA-01/03/04 concluídos **no recorte testado**; PA-02/05/06/07 parciais; S10 canário atual e S12 restore atual bloqueados sem permissões/operador; ponto externo Kali/WAN não executado. **Prazo acadêmico de referência: 19/10/2026.** Nenhum merge ou alteração do FREEZE-02 é autorizado por este adendo.

**PA-07.EG-01.G (15/10, alias pfSense):** confirmou-se por GUI o alias CE_RFC1918 com `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`. Portanto `!CE_RFC1918` nas regras LAN49 abrange destinos **não privados** IPv4; regras específicas PASS 80/443 e BLOCK restante não provam Internet irrestrita. O `Default allow LAN to any` mantém **risco residual condicionado** de acesso a outras redes privadas não cobertas por bloqueios anteriores. Sem conectividade indevida, exfiltração ou bypass comprovados. Ver [adendo integrado, §4.2](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md). IPv6 fora do recorte.


**PA-02/EP125 rota Docker verificada (15/10, fechamento no recorte):** `hostname=ep125-pucpr`; `ip -4 route get 172.18.0.2` indicou `dev br-202618f3ee42 src 172.18.0.1 uid 1001`, e `ip -4 -br addr show dev br-202618f3ee42` indicou interface `UP 172.18.0.1/16`. Junto às evidências HTTP existentes (WAF 403 versus Nginx local 200 e autenticação 401 sem sessão nas rotas protegidas), comprova superfície HTTP direta **interna à DMZ** que não atravessa o WAF, **sem demonstrar exposição WAN nem exploração bem-sucedida**. **PA-02 concluído no recorte**, **S02 permanece parcial** por ausência de cobertura DAST original completa. A fotografia anterior de 3 PAs concluídos é histórica; **após PA-02: 4/7 PA concluídos no recorte (01,02,03,04), 3/7 parciais (05,06,07).** Detalhes no [adendo integrado](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).


**PA-07/S11–S13.G14 (15/10 — retorno do suporte):** script Ferret foi executado sob operador autorizado após inserção temporária da flag de deploy \`runtime_secrets_included=no\`; artefato \`file_id=ebb49a7dd666c98b...\` (SHA-256 sintético G10) foi processado com \`summary=1 findings=1\` (1 resumo + 1 evento finding). Suporte informou persistência em \`dlp.jsonl\`. **PENDENTE** encontrar *alerta contemporâneo* correlato no Wazuh (agent 002, hash e regra 110100–110113); evento de setembro de 2026 não substitui correlação de outubro. Também pendente comprovar exclusão efetiva de segredos e reversão da flag temporária. PA-07 continua **parcial**, sem exfiltração ou bloqueio automático comprovados. A falha PA-07-DLP-01 na UI permanece válida.


**Atualização 15/10/2026 - PA-07.G15 E2E FERRET→WAZUH COMPROVADO:** agente `002`, `scan_id=78672418-0760-47b6-ab28-7735a51bef6f`, fixture sintética `file_id=ebb49a7dd666c98bbb683882b5e4050302fa360bbf5654e824cf99f3b701a5a2`; dois eventos na ingestão atual: `dlp_scan_summary` regra 110102 nível 3 e `dlp_finding` regra 110110 nível 6, ambos 15/10/2026 às ~17h48 BRT. **E2E detecção/telemetria PASS no recorte S11/S13**; não equivale a bloqueio de exfiltração e PA-07 geral permanece parcial. OBS-PA07-02: `confidence_level=MEDIUM` versus regex `^medium$` da regra 110112 gera fallback 110110; estatísticas 3 finding totais vs 1 emitido (suprimidos 0), interpretação pendente. A flag temporária de release requer comprovação/reversão. Ver [adendo integrado, §10](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).


**PA-06 FIM EP125 15/10 — eventos históricos observados:** consulta FIM Events da EP125 (agent 001) via Dashboard, 7 dias, 247 eventos do CSV: **222 modificações 550/n7, 14 criações 554/n5, 11 exclusões 553/n7**, 143 caminhos, incluindo `/usr/sbin/sshd`, arquivos PAM e /boot. Criações kernel 6.8.0-146/147 e remoções 6.8.0-138/146 em eventos agrupados sugerem manutenção legítima, não comprovada. **Observabilidade FIM PASS no recorte histórico**; sem canário de laboratório, YARA nem prova de ator malicioso, PA-06 geral **PARCIAL**. Screenshot e CSV SHA256 preservados no [adendo §11](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).


**PA-06/S10.FIM-03 — conteúdo sshd detectado (15/10):** `ep125-pucpr`, regra 550 nível 7, `/usr/sbin/sshd`, modo scheduled, `size 921416→925512`, inode e MD5/SHA1/SHA256 modificados, `mtime_after=08/10/2026` (timestamp armazenado). Alerta `15/10/2026 11:45:26.785Z` **não é prova de alteração neste instante**. Controle FIM opera sobre conteúdo; **sem atribuição maliciosa e sem canário**. [Adendo §12](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md). PA-06 global parcial por YARA e auditoria PHP.


**PA-06 FIM-04 — correlação dpkg (15/10):** consulta em EP125 constatou upgrade `openssh-server` de `1:9.6p1-3ubuntu13.19` para `.20` em 15/10/2026 06:56:59, dia do alerta FIM de `/usr/sbin/sshd`. **Hipótese forte de alteração legítima de pacote; sem prova de causalidade por hash ou timezone, não declarar ataque nem inocuidade absoluta.** Controle FIM PASS no recorte, PA-06 geral PARCIAL até YARA e audit PHP. Captura SHA-256 no [adendo §13](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).


**PA-06.YARA-02 — três alertas históricos recuperados em 15/10:** `rule.id=110211`, `agent.id=001`, **Last 90 days** apresentou **3 eventos em 02/09/2026**: 19:40:52, 19:59:18, 20:35:28 BRT; `ConectaEduca_Benign_Demo`, regras `conectaeduca,yara`, nível 12, decoder específico, `active-responses.log`. **PASS histórico da integração YARA→Wazuh**, com amostras benignas; não demonstra malware real ou acionamento em outubro. **S10 = FIM PASS observacional outubro + YARA PASS histórico setembro, canário contemporâneo bloqueado**. PA-06 permanece PARCIAL por auditoria PHP→SIEM e limites da validação atual. [Adendo §15](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).


**PA-06.AUD-01 — busca PHP no Wazuh (15/10):** agente EP125 `001`, pesquisa textual `forbidden_access_attempt`, **Last 90 days**, zero alertas correspondentes. `src/Security/AuditLogger.php` gera JSONL em `storage/logs/audit.log` na raiz de execução da aplicação, não necessariamente exposta ao agente do host. **Ingestão PHP→SIEM NÃO DEMONSTRADA**, sem atribuir falha confirmada. Priorizar busca por origem `location:*audit.log*` sem filtro do agente; depois confirmar caminho no contêiner e config `localfile` com suporte. Captura SHA256 no [adendo §16](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).


**PA-06.AUD-02 — CSV Auditd não equivale à auditoria PHP (15/10):** filtro genérico `location:*audit.log*` gerou CSV com **10.000 eventos da EP125**, **todos** do caminho `/var/log/audit/audit.log` (Auditd do host), incluindo regras `80730=6778`, `110506=3089`, `110502=50`, `80710=42`, `110504=26`, `110501=15`. Não é prova de auditoria PHP, que escreve em `storage/logs/audit.log`. Exportação pode ter limite de 10k; não concluir zero PHP no universo indexado. **PA-06 AUD pendente** até busca restrita `location:*storage/logs/audit.log*`/análise de mounts e Wazuh `localfile`. [Adendo §17](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).


**PA-06.AUD-03 — EP125 e EP126 sem alerta indexado de audit PHP (15/10):** filtro `location:*storage/logs/audit.log*` retornou zero na GUI para os agentes 001 e 002. Na captura EP126 a janela de tempo não está visível; não alegar prova absoluta de ausência nos últimos 90 dias. Auditd Linux presente/alertando ≠ PHP `AuditLogger.php` integrado. **Resultado: não demonstrado/inconclusivo, possível lacuna de visibilidade; encaminhar à verificação read-only do suporte sobre o contêiner PHP, bind mounts, Wazuh `localfile`, decoder e `archives`.** Sem configurar/alterar VMs. [Adendo §18](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).


**PA-06.AUD-04 — inspeção de metadados host/Docker EP125 (15/10):** relatório TXT com SHA-256/sidecar conferidos `19829bc14ea785c28209d697da33cf6b66382916b3026c0cace97147b43b27c4`. `/opt/conectaeduca` visível, `storage/logs/audit.log` não encontrado OU inacessível nos caminhos do host; Wazuh config local não encontrada/acessível; Docker PHP `conectaeduca-dmz-php-1` running, `/var/www/conectaeduca` / `www-data`, **sem mount relevante de app/storage identificado pela consulta**. Possível auditoria restrita ao contêiner; ingestão PHP→SIEM permanece não demonstrada. A conta de laboratório possui `docker` (root-equivalent), exigir autorização antes de `docker exec`. Sem sudo, sem leitura de conteúdo e sem alterações. [Adendo §19](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).


**PA-06.AUD-05 — readonly root e tmpfs planejado (15/10):** diagnóstico `CE-PA06-AUD05-20261015T224823Z-LwV8FL.txt` com SHA-256 sidecar conferido `050f1cca1bd76288b934f033a95c112db040a70a5b6b73f8b3e866d59570227b`: PHP container running/usuario www-data, raiz readonly, sem volume/bind para storage detectado. **Não concluir escrita impossível**: `deploy/dmz/compose.vm.yml` declara tmpfs gravável de `storage/logs`; consulta de `Mounts` não determinou `HostConfig.Tmpfs`. Conclusão: pipeline de centralização PHP→SIEM permanece não demonstrado; próxima observação segura AUD-06 limita-se aos metadados de tmpfs, sem entrar no container. [Adendo §20](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).


**PA-06.AUD-06 — tmpfs de auditoria confirmado (15/10):** EP125, consulta sem sudo/exec/logs, relatório `CE-PA06-AUD06-20261015T225409Z-L2oAD2.txt`, SHA-256 sidecar validado `a96b4097af1e15e321081723d65948ad00e579a12f810a5e0227b8f4d233b16c`. PHP running, www-data, RootFS readonly, driver json-file e **`Tmpfs_audit_dir_configurado=SIM`**. Confirma configuração runtime do tmpfs previsto no overlay VM, portanto **não há evidência de impossibilidade de escrita por readonly**. Não prova existência/volume de `audit.log`, retenção persistente nem ingestão PHP no Wazuh. Tmpfs volátil exige coletor/forwarder/persistência externa se retenção for requisito. AUD-06 encerrado; **S09/PA-06 auditoria PHP→SIEM permanece não demonstrada**, com próximo gate condicionado à aprovação para consulta interna de metadados ou execução pelo suporte. [Adendo §21](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).


**PA-07.BAC-01 — inventário EP126 (15/10/2026):** conta Linux `teste`; `bacula-fd.service` active/running; `bconsole` instalado (não executado); escutas 9102 e 9103 presentes; consulta Docker indisponível para conta; sem Jobs/catálogo/restore contemporâneos. TXT `CE-PA07-BAC01-20261015T232136Z-Bp4ohJ.txt` SHA256 confirmado `05501112dbf48200d646ce158b6acdfb78fa71616de78ce36b52e47d582ab8b0`. Documentação `deploy/interna/bacula/README.md` atribui Director/Storage/Catalog a containers, FD nativo ao host; remete a backup/restore sintético **histórico setembro** com SHA iguais (JobId6/7), não teste de outubro. PA07.BAC01 PASS de inventário; S12 restore atual bloqueado. Próximo `BAC02`: identificação não invasiva de escutas e metadados de configurações, sem `bconsole`. [Adendo §22](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).


**PA-07.BAC-02 — escutas EP126 e duas provas históricas Bacula (15/10):** FD nativo `active/running`, TCP9101 loopback, TCP9102 todas interfaces, TCP9103 endereço específico/não classificado, processos não visíveis para `teste`, config Bacula não identificada/acessível. `CE-PA07-BAC02-20261015T232757Z-uD25id.txt` SHA256 sidecar conferido `df008c8e06804c5a7ba4ab7cc55c21e7f598bce2d7abba4deebe53d34f997148`. **Não declarar portas expostas a WAN**, jobs concluídos ou restore corrente. Duas campanhas históricas no Git `docs/evidencias/`: 14/09 backup6+restore7 e 17/09 backup8+restore9, perda simulada e SHA256 original=restaurado. S12 **histórico de recuperação PASS nos recortes sintéticos de setembro**, contemporâneo outubro não comprovado. Próximo passo suporte/GUI autorizada para sumarizar catálogo e, se houver autorização, restore supervisionado; `bconsole` não executado. [Adendo §23](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).


**PA-07.RULE-01 — revisão case-sensitive das regras Ferret (15/10):** código `main` `sanitizar_ferret.py` copia `confidence_level` como recebido, mas `conectaeduca_dlp_rules.xml` usa regex `^low$` / `^medium$` / `^high$` (PCRE2 sem flag de ignorar caixa). Evento observado `MEDIUM`→genérica `110110` nível6, ao invés de específica `110112` nível8; descompasso estático confirmado, correspondência com XML efetivamente carregado não verificada. Simulação de regex Python com entradas sintéticas demonstrou que proposta `(?i)` evita divergência e preserva fallback; **não é teste Wazuh runtime**. Patch offline em cópia XML passou `git apply` e parse XML, mas **nenhuma regra instalada alterada**. Recomendar homologação `wazuh-logtest` + change control. [Adendo §24](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md). PA07 segue parcial.


## Registro posterior — PA-05 encerrado, PA-06.AUD-07 confirmado por suporte (15/10/2026)

> **Prevalece sobre a classificação PRELIMINAR de 14/10 e anteriores.** Não atribuir observações novas à execução de cenários que não ocorreram.

| Eixo/cenário | Situação vigente | Motivo e fonte |
|---|---|---|
| PA-05 / S05 | **Eixo encerrado administrativamente; S05 parcial** | RBAC vertical GET legítimo 200, quatro GET 403; ownership estático favorável. BOLA horizontal **não executado** por falta de duas contas do mesmo papel com recursos privados. Oportunidade não publicada **não testada** sem objeto/fixture. |
| PA-06 / S09 | **Eixo parcial; lacuna de auditoria PHP confirmada pelo suporte** | `audit.log` dentro do contêiner PHP ~25,8KB **gravando**; **não coletado pelo Wazuh**, sem persistência por bind/volume, com `tmpfs rw` runtime confirmado em AUD06. A ausência de coleta foi **relatada pelo suporte**, não inferida apenas de zero hits na busca. |
| PA-06 / S10 | **Parcial; canário atual não executado** | FIM em outubro e YARA histórico setembro; falta fixture autorizada para canário contemporâneo. |
| PA-07 / S11,S12,S13 | **Parcial, sem mudança** | DLP detect-only E2E atual, restores Bacula apenas históricos; egress sintético e restore atual não executados. |
| S01 PT-EXT | **Pendente de orientação docente** | Kali com rede distinta não foi utilizada como origem externa na campanha. |

**Achado `PA-06-AUD-07`**: retenção volátil dos eventos de auditoria PHP e falta de centralização no Wazuh. `tmpfs` é mecanismo de montagem temporária distinto de `bind/volume`: a indicação do suporte sobre mounts não contradiz AUD06. Perda de logs **não foi provocada nem observada diretamente**, e a escrita está **confirmada pelo suporte**, não pela leitura do pentester. Correção diferida [issue #195](https://github.com/andrea-kozicki/conectaeduca/issues/195). [Adendo §§25–26](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).

**Contagem atual:** `PA01..04` quatro concluídos nos recortes; `PA05` um administrativamente encerrado com cobertura parcial; `PA06..07` dois parciais. Não declarar `5/7 PASS`. Não modificar as VMs nem a baseline FREEZE-02.


**PA-07.BAC-03 — retorno do suporte e situação S12 (15/10):** EP126 `bacula-fd` ativo desde 06/10, segundo suporte; Jobs e FileSets geridos no Director central; não foram fornecidos Jobs/datas/status/erros atuais nem cobertura efetiva MariaDB/OpenBao. Não há registros **locais** adicionais de restore além de setembro, o que não exclui registros no Director. Contraste com documentação versionada que prevê Director/Storage/Catalog containerizados na EP126: **localização/runtime atual a confirmar; não declarar ausência de serviços**. **S12: histórico sintético setembro verificado, FD atual ativo, Jobs/restauração outubro NÃO DEMONSTRADOS**. PA-07 permanece PARCIAL; nenhuma operação administrativa na VM. [Adendo §27](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).


**Nota metodológica — identidade de teste versus observação institucional (15/10):** resultados de `teste` nas EP125/EP126 qualificam **a posição adversária de baixo privilégio**, enquanto inspeções por conta institucional da operadora e relatos do suporte são **evidências operacionais complementares**, jamais privilégios do atacante simulado. Negação observada de acesso pode ser evidência favorável de menor privilégio **nos objetos e ações avaliados** e também limitar a avaliação de serviços administrativos, sem provar que tais serviços estejam ausentes. `PA-05` sem duas contas do mesmo papel é **falta de fixture**, não controle efetivamente exercitado. `PA-06` canário sem diretório gravável e `PA-07` Jobs Bacula/Director sem acesso operacional seguem delimitados. Retirar `sudo` não elimina acessos equivalentes por Docker/socket e não substitui autorização. Detalhes: [matriz de identidades e limites de cobertura](PENTEST-MATRIZ-IDENTIDADES-LIMITES-COBERTURA-20261015.md). Nenhuma VM, config ou FREEZE-02 modificada.


**PA-07.BAC-04 — Bacularis Web Jobs, conta teste (captura 16/10):** login no painel EP126 Bacularis `http://127.0.0.1:9097/web/` com conta de aplicativo `teste`; ao abrir Jobs, erro `4`/`[CF0019]` `Connection refused` no destino `director:9101`. Screenshot `imagem(20261016-004419).png` SHA-256 `2e9c5cd1a336776a87abfe5112cd544a9c608d79553e531371dde13504bc3e99` guardado fora do Git. **Sem clique em Executar job e sem modificar o ambiente.** UI permitiu acesso à seção Jobs, mas **não consultou o Director**; ausência de linhas **não demonstra inexistência de Jobs**. Não atribuir a RBAC nem concluir que o Director global está inativo. Encaminhar para o operador confirmar `director:9101` e exportar metadados de Jobs/FileSets/status. PA-07/S12 segue PARCIAL. [Adendo §28](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).


**PA-07.BAC-05 — Director reiniciando: análise parcial do suporte (15/10/2026):** após BAC-04 (Bacularis `teste` erro `CF0019/Connection refused` ao consultar Jobs), suporte informou `director:9101` **correto**, mas **container Bacula Director em falha/reinício repetido**, erro `Unable to connect to PostgreSQL server` na conexão ao **Catalog PostgreSQL**. Origem do erro DB ainda **não apurada**; não declarar DB definitivamente down, credencial errada, catalog corrompido ou perda de Jobs/backups. Assim, BAC-04 tem agora explicação operacional **atribuída ao suporte**. `S12/PA-07` **PARCIAL**, restauração atual e Jobs recentes **não demonstrados**. Avaliação de impacto depende de quanto tempo o Director ficou indisponível e dos Jobs reais; histórico de setembro continua válido no seu período. Backlog [issue #196](https://github.com/andrea-kozicki/conectaeduca/issues/196), [adendo §29](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md). Não alterar VM.


**PA-07.BAC-06 — proposta de bypass PgBouncer (15/10):** suporte sugeriu conexão direta `/run/pgbouncer:6432`→`conectaeduca-bacula-catalog:5432`. Inspeção Git `pgbouncer.ini.template` prova projeto intencional de **socket Unix** + SCRAM/pooling + **TLS verify-full** PgBouncer→Catalog; Compose usa serviço `catalog` em backend internal. Incidente documentado 17/09 recuperou PgBouncer inoperante (ini 0 bytes) preservando proxy, sem reiniciar diretamente Director; NÃO afirmar mesma causa em outubro. Alteração direta tecnicamente plausível como exceção, mas **não validada e pode suprimir controles**, exige confirmação DNS, SSL/TLS, credenciais, rede, rollback e autorização formal. Primeiro gate é diagnosticar PgBouncer e socket com suporte. **Nenhuma mudança runtime recomendada durante FREEZE-02; PA07/S12 PARCIAL.** [Adendo §30](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).


**GATE DE CORREÇÃO PÓS-PRIMEIRO PENTEST — PA-07/S12 (decisão da responsável):** ocorrência Bacularis `CF0019`, Director reiniciando/erro Catalog informado pelo suporte e proposta de desvio do PgBouncer **registrados, mas não corrigidos**. Durante FREEZE-02: nenhuma alteração em VMs. **Não abrir agora PR corretivo:** eventual PR novo e separado do PR documental #189 **somente após** (i) encerramento formal do primeiro pentest, (ii) autorização expressa da equipe do laboratório para mudanças de configuração e (iii) diagnóstico suficiente, usando [issue #196](https://github.com/andrea-kozicki/conectaeduca/issues/196) como backlog. Priorização técnica: restaurar o socket PgBouncer original e os controles de TLS/SCRAM; bypass direto excepcional requer change control, validação equivalente e rollback. Mesmo com correção futura, S12 desta campanha segue **PARCIAL**, pois não houve restauro atual comprovado. [Adendo §31](PENTEST-FASE2-ADENDO-INTEGRADO-20261015.md).
