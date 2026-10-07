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


### Correlação local - tentativa 1

Foi tentada a correlação local do evento MariaDB a partir da EP125 usando a identidade `teste`. A execução encerrou prematuramente ao consultar `/var/ossec/logs/ossec.log`, pois `Path.exists()` gerou `PermissionError` diante de um caminho não acessível.

Classificação do resultado:

- **TEST_ERROR / inconclusivo**;
- não indica falha de Wazuh, Suricata ou do mecanismo de detecção;
- confirma apenas que a primeira versão do script não tratava corretamente fontes sem permissão;
- SHA-256 da evidência da tentativa: `291bc56da54e3e2b41521a4ae045b92e421b01c9298f4a8d8b3a82c50d34b0b8`.

O próximo passo é repetir a correlação local com tratamento individual de `PermissionError`. Caso nenhuma fonte local seja legível pela identidade `teste`, a correlação será feita pela telemetria central do Wazuh/Suricata.


### Correlação local - tentativa 2

A versão corrigida do script de correlação local tratou individualmente fontes sem permissão.

Resultados:

- `/var/ossec/logs/ossec.log`: ACCESS_DENIED;
- `/var/ossec/logs/alerts/alerts.log`: ACCESS_DENIED;
- `/var/ossec/logs/alerts/alerts.json`: ACCESS_DENIED;
- `/var/log/suricata/eve.json`: ACCESS_DENIED;
- `/var/log/suricata/fast.log`: ACCESS_DENIED;
- `/var/log/syslog`: não legível;
- `/var/log/messages`: ausente;
- `/var/log/auth.log`: não legível;
- `journalctl` retornou RC 0, porém informou que a identidade `teste` não enxerga mensagens de outros usuários e do sistema;
- nenhum match do evento foi encontrado na visão limitada do journal.

Interpretação: a correlação local permanece **inconclusiva por visibilidade insuficiente**. O resultado não deve ser registrado como falha de detecção. A identidade de baixo privilégio não possui acesso às principais fontes de telemetria, o que é coerente com mínimo privilégio.

Evidência: SHA-256 `bcb9334710fae27a0d243cd78855319a76da59139e059de55348fdfb8efc25f0`.

Próximo passo: realizar correlação central no Wazuh/Suricata usando `2026-10-07T20:36:51Z`, origem `192.168.6.34:34896` e destino `192.168.6.50:3306`.


### Wazuh Dashboard - endpoint local na EP126

Foi validado, a partir da EP126 com a identidade host `teste`, o endpoint publicado do Wazuh Dashboard.

Resultados:

- `https://127.0.0.1/` -> HTTP 302;
- `https://localhost/` -> HTTP 302;
- `https://192.168.6.50/` -> sem conexão;
- listener visível: `127.0.0.1:443`.

Interpretação: o Dashboard está disponível apenas em loopback e não está publicado diretamente no endereço da EP126. Esse comportamento é coerente com o desenho de menor exposição da superfície administrativa.

Evidência: SHA-256 `a2b1834df1b4593b319a1185dd249ed3d150c9f8eada8fedcd330affc9297cca`.

Próximo passo: abrir o Dashboard localmente na EP126, autenticar com a identidade de aplicação `teste` em perfil read-only e correlacionar o evento MariaDB de `2026-10-07T20:36:51Z`, origem `192.168.6.34:34896`, destino `192.168.6.50:3306`.


### PA-03 — Escalação de privilégios

**Estado:** Em Teste — NIST Discovery na EP126.

Resultados atuais:

- identidade `teste` fora de `sudo/wheel/docker`;
- nenhum diretório do `PATH` gravável;
- Docker socket não legível/não gravável;
- três candidatos root-owned writable confirmados como symlinks para `/dev/null`, portanto **NOT FINDING**;
- cinco serviços ConectaEduca inspecionados sem unidade, `ExecStart` ou diretório-pai gravável por `teste`;
- `ROOT_SERVICE_WRITE_CANDIDATES=0`;
- `RESULT=NO_ROOT_SERVICE_WRITE_PATH_CONFIRMED`.

Evidência da triagem: SHA-256 `7324c77f4d7dc72c641916ddea67940ff3c236b27276b22978e4ceb8856356ce`.

Documentação: [PA-03 — Escalação de privilégios](./PA-03-escalacao-privilegios.md).

### PA-04 — Descoberta de segredos e credenciais

**Estado:** Em Teste — NIST Discovery na EP126.

Até o momento, nenhuma variável de ambiente sensível nem arquivo doméstico comum de credenciais foi confirmado para a identidade `teste`. A triagem dedicada continuará após o fechamento da Discovery do PA-03/EP126.

Documentação: [PA-04 — Segredos e credenciais](./PA-04-segredos-credenciais.md).
