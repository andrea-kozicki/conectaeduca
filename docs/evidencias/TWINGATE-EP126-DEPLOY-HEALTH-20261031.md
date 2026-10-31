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
