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
