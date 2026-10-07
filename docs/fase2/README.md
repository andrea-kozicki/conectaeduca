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

> Observação: na retomada de 07/10/2026 a identidade `teste` não conseguiu obter o HEAD do repositório em `/opt/conectaeduca`. Por isso, aquele teste não comprovou divergência da baseline; apenas indicou que a baseline não era verificável por essa identidade.

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
**Discovery:** concluída para o vetor MariaDB  
**Attack:** iniciado  
**Reporting:** em andamento

Resultados confirmados até 07/10/2026:

- origem validada: `teste@ep125-pucpr`, sem grupos privilegiados;
- EP125: `192.168.6.34`;
- EP126: `192.168.6.50`;
- TCP/3306 (MariaDB): alcançável conforme política;
- TCP/9103 (Bacula Storage): alcançável conforme política;
- TCP/1514 (Wazuh): alcançável conforme política;
- demais superfícies administrativas testadas: filtradas/sem conexão;
- handshake sem autenticação identificou `12.3.2-MariaDB`;
- nenhuma senha reutilizável foi confirmada;
- primeiro ensaio de Attack sem TLS não estabeleceu sessão;
- o servidor retornou `MYSQL_ERROR_CODE=3159`, `SQLSTATE=08004` e a mensagem `Connections using insecure transport are prohibited while --require_secure_transport=ON.`;
- interpretação confirmada: `require_secure_transport=ON` bloqueia conexões MariaDB sem transporte seguro antes de uma autenticação útil;
- nenhum finding de vulnerabilidade confirmado até o momento.

Evidências recentes:

- triagem de material de senha: SHA-256 `8cd62b1d13434b37dc8e1f6a26924871849a71186a80e3ba632799c265882623`;
- primeiro ensaio MariaDB: SHA-256 `84ebe098c76c8bba51e62266d1d8802a105769d1226d51dc6308ccae42c7948c`;
- decodificação segura do erro 3159: SHA-256 `70cfe7867d4a27cdd55ab032be05120db25c50bf6bfacd3958a806d278d0b1c3`.

Correlação do último ensaio:

- UTC: `2026-10-07T20:36:51Z`;
- origem: `192.168.6.34:34896`;
- destino: `192.168.6.50:3306`.

Documentação detalhada: [PA-01 — Movimento lateral](./PA-01-movimento-lateral.md).

## Próximos passos imediatos

1. Correlacionar o ensaio de 07/10/2026 com Wazuh e/ou Suricata.
2. Confirmar se o evento é observável pelos controles de detecção.
3. Só então decidir se o próximo subteste MariaDB deve negociar TLS para testar a camada de autenticação.
4. Em seguida, avaliar os fluxos permitidos TCP/9103 e TCP/1514 de forma controlada.

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
