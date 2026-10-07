# Fase 2 — Pentest Interno e Retestes

Esta branch concentra a documentação da segunda fase do ConectaEduca, dedicada ao pentest interno controlado, aos achados, às correções e aos retestes.

## Baseline

- Baseline de origem: `FREEZE-02`
- Commit de origem: `c37bdce07a9ae71ceb1a1e0c8e0e1e2b51e112ce`
- EP125: DMZ
- EP126: rede interna
- Identidade técnica principal: `teste`, sem sudo/wheel/docker
- Identidade funcional da aplicação: `teste@pucparana.com`
- Twingate: desligado nesta rodada, para preservar a comparação antes/depois

## Metodologia

O pentest interno passa a ser organizado segundo o **NIST SP 800-115**:

1. Planning — escopo, autorização, regras de engajamento, baseline e evidências;
2. Discovery — enumeração de hosts, portas, serviços, versões, configurações e superfícies;
3. Attack — validação controlada das vulnerabilidades potenciais identificadas;
4. Reporting — registro contínuo de evidências, achados, impacto, correções e retestes.

O **MITRE ATT&CK** permanece como referência para TTPs do adversário e o **STRIDE** como apoio para classificação das ameaças.

## Pontos do modelo do adversário

Os sete pontos não pertencem a uma única VM. Eles cobrem a arquitetura como um todo, com origem e alvo variando conforme o cenário.

| ID | Ponto | Escopo principal |
|---|---|---|
| PA-01 | Movimento lateral | EP125 → EP126 |
| PA-02 | Bypass WAF / acesso direto ao backend | EP125 |
| PA-03 | Escalação de privilégios host/container | EP125 e EP126 |
| PA-04 | Descoberta de segredos e credenciais | EP125 e EP126 |
| PA-05 | Abuso de credencial válida de baixo privilégio | principalmente EP126, além da aplicação na EP125 |
| PA-06 | Evasão de mecanismos de defesa | EP125 e EP126 |
| PA-07 | Acesso indevido, DLP, backup e exfiltração | principalmente EP126, com validações de egress/origem também a partir da EP125 quando aplicável |

## Estado atual

### PA-01 — Movimento lateral EP125 → EP126

**Planning:** concluído  
**Discovery:** em andamento  
**Attack:** não iniciado formalmente  
**Reporting:** em andamento

Resultados parciais:

- origem validada: `teste@ep125-pucpr`, sem grupos privilegiados;
- EP125: `192.168.6.34`;
- EP126: `192.168.6.50`;
- TCP/3306 (MariaDB): alcançável conforme política;
- TCP/9103 (Bacula Storage): alcançável conforme política;
- TCP/1514 (Wazuh): alcançável conforme política;
- demais superfícies administrativas testadas: filtradas/sem conexão;
- handshake sem autenticação identificou `12.3.2-MariaDB`;
- nenhum finding de vulnerabilidade confirmado até o momento.

A fase seguinte do PA-01 deve verificar se os fluxos legitimamente permitidos podem ser abusados além da finalidade prevista, sem ultrapassar as regras de engajamento.

## Regras de documentação

Cada execução deve registrar, quando aplicável:

- data/hora;
- origem e destino;
- identidade utilizada;
- comando ou ação;
- resultado esperado;
- resultado observado;
- evidência correlacionada no Wazuh/Suricata;
- arquivo de evidência;
- SHA-256;
- classificação como PASS, observação ou finding;
- correção e reteste, quando houver.
