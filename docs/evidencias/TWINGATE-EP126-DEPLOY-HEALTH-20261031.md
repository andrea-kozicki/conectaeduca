# Twingate — EP126 — deployment e health (31/10/2026)

> Atualizacao factual complementar ao Daily 9 v28, a PR #214 e ao card Trello ZT-06. Nao constitui homologacao Zero Trust fim a fim.

## Identidade e escopo
- Host: `ep126-pucpr-br` (Intranet da PUCPR), operador `andrea.kiew`.
- Tenant Twingate: `conectaeducalab`; Remote Network: `ConectaEduca - Rede Interna`.
- Connector institucional: `conectaeduca-interna-ep126` (Connected no painel apos deploy).
- Connector historico pessoal: `conectaeduca-interna-01` (Connected no openSUSE, nao homologado institucionalmente).

## Evidencia de terminal
- 31/10 18:45 BRT — Docker Engine 29.9.2; Docker Compose v5.6.1; Compose institucional localizado em `deploy/interna/twingate/compose.yml` (EP126: `/opt/conectaeduca/deploy/interna/twingate/compose.yml`). SHA256 local: `ab78d9fcbea955f2141116daab3fea74b6ae2762aba4833aabc23e1f9d1edd29`; sem container Twingate local antes do deploy; HTTPS externo HTTP 200.
- Estrutura: service `connector`; profile `twingate`; `network_mode: host`; `restart: unless-stopped`; variaveis `TWINGATE_NETWORK`, `TWINGATE_ACCESS_TOKEN`, `TWINGATE_REFRESH_TOKEN` interpoladas.
- Tokens criados para o Connector institucional, em arquivo local de modo 0600, fora do Git; `COMPOSE_VALIDADO=SIM`. Nenhum valor de token consta neste artefato.
- 31/10 19:07 BRT — `docker compose -p conectaeduca-zt-ep126 --profile twingate -f <compose-institucional> -f <override-local> up -d --no-deps --pull always connector`; download `twingate/connector:1` e criacao/inicializacao `conectaeduca-twingate-connector` bem-sucedidos.
- 31/10 19:11:39 BRT — `Running=true`, `Health=healthy`, `Reinicios=0`, `Rede=host`, `RestartPolicy=unless-stopped`; versao `1.95.0`; `Up 4 minutes (healthy)`; painel = Connected.
- ImageID/digest efetivo: `sha256:0ef390ef3e526ba7cfb1c6504b794518226188c005087c95205fa9a5b769372a`.

## Divergencia Git x runtime
A imagem **fixada no Compose versionado** permanece `twingate/connector@sha256:833e7a968f1b3a5ad79b88b04f82aad1bfc8621f61b6b35f01be2411d35beba9`. A implantacao efetiva foi feita com override **local** `~/.config/conectaeduca/twingate-ep126.override.yml` usando `twingate/connector:1`, sem atualizar o Compose da main. Proxima reconciliacao deve propor pinagem do digest validado, revisar CI e rollback em PR proprio. Nao declarar que a main descreve exatamente o runtime.

## Classificacao
**OBSERVADO (dados fornecidos pela operadora):** versao, health, ImageID, inicializacao, painel Connected, Compose valido, ausência de reinicios durante a janela.

**PENDENTE:** alcance de resources da Intranet, identidade/grupos/MFA, autorizacao positiva e negativa, E2E cliente->Connector EP126->Resource, testes com Connector openSUSE temporariamente isolado, acesso sem FortiClient, validacao de certificados e comparacao PA-01..PA-07. Um Connector `healthy`/Connected nao comprova mitigacao nem isolamento.

## Risco e gates
- Dois Connectors da mesma Remote Network estao Connected; enquanto ambos participarem, nao se pode atribuir um teste somente a EP126. Nao parar openSUSE sem acesso alternativo e janela segura.
- Manter PR #214 como draft, sem merge automatico; nao fechar ZT-06 ou Grupo A somente pelo healthcheck.
- Nao publicar tokens, env, logs brutos ou dumps de configuracao expandida. Nao alterar pfSense sem aprovacao.

## Proveniencia
Transcricao sintetica das saidas e capturas de painel informadas pela operadora em 31/10/2026. Arquivos de prova bruta e hash dos prints nao foram depositados neste documento. Diario local da EP126 nao editado por esta acao GitHub.


## Retificacao arquitetural — 31/10/2026, 19:27 BRT

A responsavel confirmou que a **arquitetura atual da Intranet possui Wazuh, nao Graylog**. Logo, o teste exploratorio ZT-07.1 de `127.0.0.1:9000` e `192.168.6.50:9000` (ambos `curl RC=7, HTTP=000`, sem listener TCP/9000 e sem container Graylog listado) investigou um servico que nao integra o desenho atual. O resultado NAO deve ser classificado como falha do Twingate nem do Wazuh. Nenhum Resource Graylog deve ser criado. Proximo gate ZT-07: identificar a exposicao efetiva dos componentes Wazuh na EP126 e selecionar somente uma interface de administracao legitimamente publicada para um Resource restrito a Operacao/SOC/Admin, mediante validacao de politica e MFA. Nao expor as portas de ingestao de agentes ou a API administrativa por padrao. Nenhuma alteracao de ambiente foi executada na coleta ZT-07.1.


## ZT-07.2 — Identificacao da implantacao Wazuh na EP126 (31/10/2026, 19:30 BRT)

A coleta nao destrutiva realizada pela responsavel identifica os servicos centrais do Wazuh em contêineres Docker e o agente do host em systemd. `systemctl is-active` retornou `inactive` para wazuh-manager/dashboard/indexer, mas isso **NAO** caracteriza indisponibilidade: os tres contêineres estavam `Up 10 hours (healthy)`; `wazuh-agent` do host estava `active`.

| Componente / contêiner | Evidencia de publicacao | Interpretacao |
| --- | --- | --- |
| `conectaeduca-wazuh-wazuh.manager-1` | `192.168.6.50:1514->1514/tcp`; `192.168.6.50:5514->514/udp`; `55000/tcp` interno; `1515-1516/tcp` internos | Recepcao de eventos e API interna; nao publicar no Twingate para usuarios finais. |
| `conectaeduca-wazuh-wazuh.dashboard-1` | `127.0.0.1:443->5601/tcp`, mais `443/tcp` exposta pelo contêiner | Painel restrito a loopback do HOST; ainda nao comprova HTTPS funcional nem endereco correto para Resource remoto. |
| `conectaeduca-wazuh-wazuh.indexer-1` | `9200/tcp` apenas interno | API do indexador nao publicada no host. |
| `wazuh-agent` host | `active` | Servico independente dos contêineres centrais. |

`ss -lnt` identificou apenas `192.168.6.50:1514` e `127.0.0.1:443` entre portas pesquisadas. O teste Graylog/9000 anterior foi retificado: o Graylog nao pertence a arquitetura atual.

**Proximo gate ZT-07:** validar resposta HTTPS no loopback e identificar, por `docker inspect` sem segredos, as redes e enderecos internos atuais do contêiner Dashboard; depois avaliar Resource privado enderecavel a partir do Connector, com politica restrita a Operacao/SOC e MFA. Nao criar Resource no endereco `127.0.0.1` sem verificar comportamento do cliente e roteamento; nao alterar bind de 443, pfSense ou Docker. A constatacao de `healthy` nao substitui teste E2E.


## ZT-07.2 — Dashboard Wazuh acessivel em loopback e bridge (31/10/2026, 19:33 BRT)

A operadora executou `ZT-07.2` na EP126 às 19:33:21 BRT (apenas leitura). O contêiner `conectaeduca-wazuh-wazuh.dashboard-1` retornou `Running=true`, `Health=healthy`, `RestartCount=0`. Publicação Docker confirmada: `5601/tcp -> 127.0.0.1:443`. Network `conectaeduca-wazuh_wazuh-backend`; IP do contêiner no momento: `172.19.0.3`.

| Origem do teste | Destino HTTPS | Resposta | Limitação |
| --- | --- | --- | --- |
| EP126 (host) | `https://127.0.0.1:443/` | `HTTP 302`, `curl RC=0`, `remote_ip=127.0.0.1` | `-k` — TLS não validado; sem login funcional. |
| EP126 (host) | `https://172.19.0.3:5601/` | `HTTP 302`, `curl RC=0`, `remote_ip=172.19.0.3` | IP de contêiner dinâmico, TLS não validado, sem E2E Twingate. |

**Interpretação:** os dois caminhos locais no host EP126 responderam em HTTPS, mas não foram validados o alvo do redirecionamento 302, certificados, o transporte pelo Connector EP126 ou permissões Zero Trust. NÃO cadastrar automaticamente `127.0.0.1` como endereço de Resource no painel ou fixar `172.19.0.3` como endereço permanente. A implantação do Wazuh Dashboard mantém bind exclusivo de loopback.

**Diário local:** preparou-se o script incremental e idempotente `scripts/zt07/CE_ZT07_EP126_REGISTRAR_DIARIO_20261031.sh` para registrar ZT-07.1, identificação de containers Wazuh e ZT-07.2 com backup e SHA-256. **Ainda depende de execução explícita no terminal EP126**; não afirmar que esse adendo já foi escrito no `diario.md` local até receber o resultado.

**Próximo gate:** confirmar redirecionamento, endereçamento alcançável apenas pelo Connector institucional e política de acesso para Operação/SOC (MFA), depois testar acesso autorizado/negado sem alterar pfSense e sem expor as portas de ingestão, API ou Indexer. Cliente openSUSE Connector na mesma Remote Network continua sendo potencial rota alternativa.

## ZT-07.3 — Wazuh Dashboard HTTPS/TLS, 31/10/2026, 19:39 BRT

Coleta apenas de leitura apresentada pela responsável na EP126. `curl --insecure https://127.0.0.1:443/` retornou `HTTP 302 / RC=0`. Redirecionamento HTTP relativo: `/app/login` (sem query ou fragment e sem endereço absoluto). O certificado observado via OpenSSL apresentou `CN=wazuh.dashboard` e `SAN DNS:wazuh.dashboard`, emissor Wazuh (`OU=Wazuh, O=Wazuh, L=California`), validade UTC `2026-08-27 21:36:49` a `2036-08-24 21:36:49`. A tentativa de `curl` sem `-k` usando endereço `https://127.0.0.1/` falhou com `curl RC=60`, `TLS_VERIFY=20`, `HTTP=000` e `unable to get local issuer certificate`.

**Interpretação:** o Dashboard respondeu em HTTPS e redirecionou para o login, mas não houve comprovação de validação da cadeia TLS. O hostname `127.0.0.1` não consta do SAN exibido; isso poderá produzir erro de hostname após corrigir a confiança na CA. O resultado NÃO prova que a CA seja inválida, apenas que o cliente atual não conseguiu validá-la. Não instalar CA às cegas, não trocar certificado, não expor Dashboard nem cadastrar `127.0.0.1` como Resource sem projeto de endereçamento.

**Custódia:** script idempotente preparado no GitHub em `scripts/zt07/CE_ZT07_EP126_REGISTRAR_TLS_20261031.sh` (commit `91c5bdc96acd0647a09d6f26561d9d57ebc57a1f`), para adicionar este teste ao `diario.md` com backup e SHA-256. O diário local AINDA NÃO foi atualizado para o ZT-07.3 neste ponto; depende de execução pela responsável. A homologação Zero Trust E2E segue pendente.

**Próximo gate:** verificar resolução DNS do `wazuh.dashboard` a partir da EP126/Connector, origem confiável da CA e SNI/hostname correto, sem expor tokens ou material privado; depois desenhar Resource privado somente para administração/SOC com MFA.
