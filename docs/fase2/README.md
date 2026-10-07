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

**Status: CONCLUÍDO / PASS**

- origem: `teste@ep125-pucpr` (`192.168.6.34`), sem grupos privilegiados;
- destino: EP126 (`192.168.6.50`);
- TCP/3306 MariaDB, TCP/9103 Bacula e TCP/1514 Wazuh permanecem acessíveis conforme a allowlist;
- demais superfícies administrativas testadas permanecem filtradas/sem conexão;
- MariaDB exige `require_secure_transport=ON` e não estabeleceu sessão útil no ensaio sem TLS;
- Bacula não expôs banner espontâneo nem identidade runtime/TLS à conta `teste`;
- Wazuh não expôs banner espontâneo nem `client.keys`/configuração à conta `teste`;
- nenhuma credencial reutilizável ou caminho de movimento lateral foi confirmado.

Observação separada: o ensaio MariaDB não teve alerta correspondente localizado em `wazuh-alerts-*`; como `wazuh-archives-*` está desabilitado, isso permanece classificado como limitação de cobertura/telemetria, não falha de detecção confirmada.

Evidências-chave:

- MariaDB 3159: `70cfe7867d4a27cdd55ab032be05120db25c50bf6bfacd3958a806d278d0b1c3`;
- Bacula runtime: `38b15c0edf642a3a3846b2cd6e1b09145df30b312452c1b55e2b28fde6bccfe3`;
- Wazuh 1514: `b9693fbdb23501c94cdca3c65d3fdfb04e22331305a577c3d7d25165eb756d1d`.

Documentação detalhada: [PA-01 — Movimento lateral](./PA-01-movimento-lateral.md).

## Próximos passos imediatos

1. Continuar PA-03 na EP125.
2. Aprofundar PA-04 com Discovery dedicada de segredos/credenciais.
3. Depois avançar para PA-02/PA-05 conforme a ordem operacional mais útil.

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


### Atualização PA-03 — sudo, SUID/SGID e capabilities na EP126

A triagem adicional confirmou:

- `sudo -n -l`: senha necessária; nenhum `NOPASSWD` confirmado;
- 17 binários SUID/SGID;
- nenhum SUID/SGID gravável por `teste`;
- nenhum diretório-pai desses binários gravável por `teste`;
- capabilities apenas `cap_net_raw=ep` em `ping` e `mtr-packet`;
- nenhuma capability de alto impacto ou arquivo com capability gravável;
- `UNPACKAGED_SUID_SGID=1` apenas para `/usr/bin/fusermount3`.

O resultado `MANUAL_REVIEW_REQUIRED` permanece uma triagem pendente, não finding. O próximo passo é verificar a associação de pacote e a integridade do `fusermount3`.

Evidência: SHA-256 `0fb64574f00e843c0f5b443f126d46440ff6a399f045c24f8448c8961608c0a2`.


### PA-03/EP126 — Discovery concluída

A triagem final do `fusermount3` confirmou que o único item anteriormente classificado como `UNPACKAGED` pertence ao pacote `fuse3`. A divergência ocorreu porque o sistema usa merged-/usr: `/bin` aponta para `/usr/bin`, enquanto o banco do pacote registra `/bin/fusermount3`.

Validações:

- ownership confirmado pelo `dpkg`;
- `dpkg -V fuse3` sem divergências;
- nenhuma primitive óbvia de escalação confirmada;
- nenhuma exploração executada.

Evidência: SHA-256 `7be13987d3b22412691063820dccbcf5fb1cefb5a6ebc65ac26474a2b408bdd8`.

**Resultado:** PA-03 na EP126 com Discovery concluída e classificação **PASS** para as superfícies avaliadas. O PA-03 global permanece aberto para repetir a metodologia na EP125.


### PA-01 — Bacula TCP/9103

O fluxo esperado EP125 -> EP126/Storage foi validado de forma passiva:

- `192.168.6.34:37300 -> 192.168.6.50:9103`: conexão estabelecida;
- nenhum payload enviado;
- nenhum dado espontâneo recebido em 2 segundos;
- nenhuma chave privada Bacula/TLS legível confirmada;
- quatro diretivas `Password` encontradas em arquivos legíveis foram classificadas, após revisão, como placeholders/templates de runtime e não como segredos literais.

Evidência: SHA-256 `3e76d0dff1fb414225c878446d4c7dad5f7aa99a23bd7900e71fce91842261d9`.

Próximo passo: validar metadados da configuração runtime real do File Daemon em `/opt/bacula/etc`.


### PA-01/Bacula 9103 — PASS

A verificação final da identidade runtime do File Daemon confirmou:

- `/opt/bacula/etc` protegido em `0750 bacula:bacula`;
- configuração efetiva e candidata inacessíveis a `teste`;
- árvore TLS não atravessável por `teste`;
- chave privada não legível;
- nenhum conteúdo ou segredo foi lido.

Evidência: SHA-256 `38b15c0edf642a3a3846b2cd6e1b09145df30b312452c1b55e2b28fde6bccfe3`.

**Resultado:** subteste Bacula TCP/9103 classificado como **PASS**, sem finding confirmado.

Próximo fluxo do PA-01: TCP/1514 Wazuh.


### PA-01/Wazuh 1514 — PASS

A validação final do fluxo Wazuh confirmou conexão TCP esperada em `1514`, sem payload e sem banner espontâneo. A identidade `teste` não possui leitura/escrita de `client.keys`, `ossec.conf` ou da árvore `/var/ossec/etc`.

Evidência: SHA-256 `b9693fbdb23501c94cdca3c65d3fdfb04e22331305a577c3d7d25165eb756d1d`.

**Resultado:** PASS, sem finding confirmado.

### Fechamento PA-01

MariaDB/3306, Bacula/9103 e Wazuh/1514 foram avaliados e nenhuma movimentação lateral foi confirmada. O PA-01 está **CONCLUÍDO / PASS**.
