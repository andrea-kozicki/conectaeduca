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
