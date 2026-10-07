# PA-01 — Movimento lateral EP125 → EP126

## Objetivo

Avaliar se uma posição inicial de baixo privilégio na EP125 (DMZ) pode ser convertida em acesso indevido a serviços ou ativos internos da EP126, preservando as regras de engajamento do laboratório e sem uso de elevação de privilégio.

## Contexto de execução

- Data principal desta etapa: 07/10/2026
- Origem: `teste@ep125-pucpr`
- UID/GID: `uid=1001(teste) gid=1001(teste)`
- Grupos: `teste users`
- EP125: `192.168.6.34/28`
- EP126: `192.168.6.50`
- Sem sudo, wheel ou docker
- Sem instalação de pacotes
- Sem brute force
- Sem exibição de valores secretos
- NIST SP 800-115: Planning concluído; Discovery concluída para o vetor MariaDB; Attack iniciado; Reporting contínuo

## 1. Retomada e integridade das evidências

A retomada identificou três diretórios anteriores do PA-01 e validou os arquivos `.sha256` existentes. As evidências de contexto, Nmap, fingerprint de serviços, handshake MariaDB, busca de material de banco e clientes alternativos foram encontradas e tiveram integridade confirmada.

A checagem do Git feita como `teste` retornou `HEAD=UNKNOWN` e `branch=UNKNOWN`. Isso **não deve ser classificado como drift da baseline**. A identidade não conseguiu verificar o HEAD do repositório; portanto, o resultado é "baseline não verificável por esta identidade".

## 2. Discovery — segmentação EP125 → EP126

A revalidação por TCP Connect confirmou:

| Porta | Estado | Interpretação |
|---|---|---|
| 1514/tcp | open | fluxo permitido para Wazuh |
| 3306/tcp | open | fluxo permitido para MariaDB |
| 9103/tcp | open | fluxo permitido para Bacula Storage |
| 22/tcp | filtered | superfície administrativa bloqueada |
| 80/tcp | filtered | bloqueada |
| 443/tcp | filtered | bloqueada |
| 1515/tcp | filtered | bloqueada |
| 5432/tcp | filtered | bloqueada |
| 6432/tcp | filtered | bloqueada |
| 8200/tcp | filtered | bloqueada |
| 9097/tcp | filtered | bloqueada |
| 9101/tcp | filtered | bloqueada |
| 9102/tcp | filtered | bloqueada |
| 9200/tcp | filtered | bloqueada |
| 9443/tcp | filtered | bloqueada |
| 55000/tcp | filtered | bloqueada |

Resultado parcial: a segmentação observada continua aderente ao desenho de allowlist previsto para o caminho EP125 → EP126.

## 3. Discovery — identificação do MariaDB

O handshake sem autenticação retornou:

- protocolo: `10`;
- versão anunciada: `12.3.2-MariaDB`;
- autenticação tentada: não, durante o teste de banner/handshake.

A exposição da versão é tratada como informação de serviço, não como vulnerabilidade confirmada.

## 4. Discovery — triagem de material de autenticação

Foi executada uma triagem sem exibir valores secretos.

Achados:

- duas referências a arquivos de segredo no `deploy/interna/mariadb/compose.yml`:
  - `/run/secrets/conectaeduca_db_password`
  - `/run/secrets/mariadb_root_password`
- ambos os caminhos não existem no host EP125 para a identidade `teste`;
- `/run/secrets`: ausente no host;
- `/dev/shm`: presente, sem arquivos regulares legíveis;
- `/etc/conectaeduca`: existe, porém não é enumerável por `teste`;
- nenhum literal de senha reutilizável foi confirmado;
- um `db_password` encontrado em script foi classificado como expressão de código, não como senha hardcoded.

Conclusão desta etapa:

> A Discovery não demonstrou material de autenticação MariaDB reutilizável pela identidade de baixo privilégio da EP125.

Evidência:

`SHA-256 8cd62b1d13434b37dc8e1f6a26924871849a71186a80e3ba632799c265882623`

## 5. Attack — ensaio de conexão MariaDB sem TLS

Foi realizada uma única tentativa controlada de estabelecimento de sessão no MariaDB com identidade de teste inexistente e valor descartável, sem brute force.

Parâmetros de segurança:

- número de tentativas: 1;
- brute force: não;
- segredo real utilizado: não;
- modificação de banco: não;
- consulta SQL: não.

A primeira evidência registrou:

- `PROTOCOL_VERSION=10`;
- `SERVER_VERSION=12.3.2-MariaDB`;
- `MYSQL_ERROR_CODE=3159`;
- nenhuma sessão autenticada estabelecida.

Evidência:

`SHA-256 84ebe098c76c8bba51e62266d1d8802a105769d1226d51dc6308ccae42c7948c`

### 5.1 Decodificação do retorno 3159

Uma segunda execução, também limitada a uma tentativa e sem uso de segredo real, capturou de forma controlada a mensagem textual do erro.

Correlação:

- UTC: `2026-10-07T20:36:51Z`;
- origem: `192.168.6.34:34896`;
- destino: `192.168.6.50:3306`.

Resposta:

- `MYSQL_ERROR_CODE=3159`;
- `SQLSTATE=08004`;
- `SERVER_ERROR_MESSAGE=Connections using insecure transport are prohibited while --require_secure_transport=ON.`;
- `INTERPRETATION=SECURE_TRANSPORT_REQUIRED`;
- `RESULT=SESSION_NOT_ESTABLISHED`.

Interpretação técnica: o serviço MariaDB está configurado com `require_secure_transport=ON` e recusou o fluxo sem TLS antes que a credencial de teste pudesse ser avaliada de maneira útil. O resultado é, portanto, evidência positiva de um controle adicional de proteção em profundidade; não é finding de vulnerabilidade.

Evidência:

`SHA-256 70cfe7867d4a27cdd55ab032be05120db25c50bf6bfacd3958a806d278d0b1c3`

## 6. Correlação local - tentativa 1

Após a confirmação do bloqueio por `require_secure_transport=ON`, foi iniciada a correlação local do evento ofensivo usando os seguintes identificadores:

- UTC: `2026-10-07T20:36:51Z`;
- origem: `192.168.6.34:34896`;
- destino: `192.168.6.50:3306`.

A primeira versão do script tentou inspecionar fontes locais como `/var/ossec/logs/ossec.log`, `/var/log/suricata/eve.json` e o journal. Entretanto, a execução foi interrompida logo na primeira fonte porque a identidade `teste` não possui permissão de acesso e `Path.exists()` propagou `PermissionError`.

Resultado correto desta execução:

- classificação: **TEST_ERROR / inconclusivo**;
- não houve conclusão sobre existência ou ausência de detecção;
- o erro está no tratamento de permissão do script de correlação, não no controle de segurança avaliado;
- nenhuma elevação de privilégio foi tentada.

Evidência:

`SHA-256 291bc56da54e3e2b41521a4ae045b92e421b01c9298f4a8d8b3a82c50d34b0b8`

A correlação local deve ser repetida com tratamento individual de fontes não acessíveis. Se nenhuma fonte útil puder ser lida por `teste`, o evento será pesquisado na telemetria central do Wazuh/Suricata.

### 6.1 Correlação local - tentativa 2

A versão corrigida do script continuou mesmo diante de fontes inacessíveis.

Resultados observados:

- 0 fontes de arquivo úteis legíveis pela identidade `teste`;
- 5 fontes com `ACCESS_DENIED`, incluindo logs do Wazuh e do Suricata;
- `/var/log/syslog` e `/var/log/auth.log` não legíveis;
- `/var/log/messages` ausente;
- `journalctl` executado com sucesso técnico (`RC=0`), mas com aviso explícito de que `teste` não vê mensagens de outros usuários e do sistema;
- 0 correspondências do evento na visão parcial do journal.

O campo automático `NO_LOCAL_CORRELATION_FOUND` do script deve ser interpretado com cautela: como não havia telemetria de sistema plenamente visível, o resultado metodologicamente correto é **correlação local inconclusiva por visibilidade insuficiente**.

Isso não demonstra falha de detecção. Também fornece uma observação positiva de mínimo privilégio: o usuário ofensivo de baixo privilégio não possui leitura dos principais logs defensivos.

Evidência:

`SHA-256 bcb9334710fae27a0d243cd78855319a76da59139e059de55348fdfb8efc25f0`

O evento deverá agora ser pesquisado na telemetria central do Wazuh/Suricata usando a janela e o 5-tuple registrados anteriormente.

### 6.2 Wazuh Dashboard - superfície de acesso

Na EP126, ainda sob identidade host `teste`, foi feita a descoberta do endpoint do Wazuh Dashboard sem alterar configuração.

Resultados:

- `https://127.0.0.1/`: HTTP 302;
- `https://localhost/`: HTTP 302;
- `https://192.168.6.50/`: conexão recusada/indisponível;
- `ss -ltn` mostrou listener `127.0.0.1:443`;
- nenhuma publicação em `192.168.6.50:443` foi observada.

Interpretação: a superfície administrativa do Wazuh Dashboard permanece restrita a loopback na EP126, reduzindo exposição de rede. O resultado é consistente com o hardening documentado do projeto.

Evidência:

`SHA-256 a2b1834df1b4593b319a1185dd249ed3d150c9f8eada8fedcd330affc9297cca`

A próxima etapa de correlação deve usar a interface local do Dashboard e a identidade de aplicação `teste`, read-only, pesquisando o evento MariaDB na janela temporal registrada.

### 6.4 Estrutura real dos eventos Suricata no Wazuh

Foi expandido um alerta Suricata já indexado no Wazuh Threat Hunting para confirmar a estrutura dos campos antes da busca do evento MariaDB.

Documento de referência:

- índice: `wazuh-alerts-4.x-2026.10.07`;
- agente: `ep125-pucpr`;
- origem do log: `/var/log/suricata/eve.json`;
- decoder: `json`;
- regra Wazuh: `86601`;
- grupos: `ids`, `suricata`.

Campos confirmados:

- `data.src_ip`;
- `data.src_port`;
- `data.dest_ip`;
- `data.dest_port`;
- `data.proto`;
- `data.event_type`;
- `data.alert.signature`;
- `data.alert.action`.

O exemplo inspecionado representava tráfego TCP `192.168.6.34:42410 -> 10.96.210.127:3268`, com `data.event_type=alert` e ação `allowed`.

Também foi confirmada a dupla representação temporal:

- `data.timestamp`: horário local com offset `-0300`;
- `timestamp`: horário UTC usado pelo índice Wazuh.

Interpretação metodológica: o Threat Hunting consultado está sobre o índice `wazuh-alerts-*`. Portanto, a ausência do 5-tuple do MariaDB nesse índice demonstrará ausência de **alerta indexado no Wazuh**, e não necessariamente ausência de observação do tráfego bruto pelo Suricata.

A próxima consulta deve usar os campos estruturados reais e a janela local `17:35:30-17:38:30`.

## 7. Estado do PA-01

| Fase NIST SP 800-115 | Estado |
|---|---|
| Planning | concluído |
| Discovery | concluída para o vetor MariaDB |
| Attack | iniciado |
| Reporting | em andamento |

Até este ponto:

- não foi comprovado movimento lateral;
- não foi obtida credencial reutilizável;
- não foi estabelecida sessão MariaDB;
- não foi confirmada vulnerabilidade;
- a segmentação continua funcionando conforme esperado;
- o MariaDB aplica transporte seguro obrigatório às conexões testadas.

## 8. Próximos passos

1. Correlacionar o evento `192.168.6.34:34896 → 192.168.6.50:3306`, às `2026-10-07T20:36:51Z`, com Wazuh e/ou Suricata.
2. Registrar se houve visibilidade/detecção e qual fonte produziu o evento.
3. Só depois decidir se um novo subteste MariaDB deve negociar TLS para atingir a camada de autenticação.
4. Avaliar de forma controlada os fluxos permitidos TCP/9103 e TCP/1514.
5. Consolidar PASS, observações e eventuais findings com evidência e SHA-256.

## 9. Regra de interpretação

Porta aberta, banner ou metadado de serviço não constituem finding por si sós. Um finding só deve ser registrado quando houver evidência reproduzível de que um controle pode ser contornado, uma credencial/segredo pode ser indevidamente usado, ou um impacto não autorizado pode ser alcançado dentro do escopo do teste.
