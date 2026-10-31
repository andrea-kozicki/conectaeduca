# Diario operacional complementar — EP126 — 31/10/2026 (BRT)

## Evidencias observadas na sessao
- Acesso atual via Guacamole a EP126 confirmado pela responsavel.
- EP126 hostname ep126-pucpr-br, IP 192.168.6.50; xrdp active/running em TCP 3390.
- Conexao RDP estabelecida: 10.96.43.36:45130 -> 192.168.6.50:3390. Estado no pfSense associado a LAN49, ESTABLISHED:ESTABLISHED.
- EP125 recebe RDP do mesmo IP institucional 10.96.43.36 na porta 3389.
- Nao foi identificada a regra que impediu acesso historico. Suporte acionado para avaliar restauracao segura da segmentacao LAN33/LAN49; nenhuma alteracao de firewall autorizada neste registro.
- Bacula EP126: bacularis-webapi, bacula-director, bacula-storage, bacula-pgbouncer e bacula-catalog Up 9 hours no momento da coleta; quatro ultimos healthy.
- Estado de Schedule/execucao automatica NAO comprovado por esse comando.
- BAC-05: decisao historica de backup manual por falta de janela operacional; mudanca exige aprovacao.
- Twingate EP126: pendente definicao de Connector/Remote Network/Resources e preflight; nao implantado nem homologado nesta sessao.
- EP125 Connector Twingate: instabilidade anterior permanece em investigacao; nao usar como evidencia de E2E funcional.

## Scripts preparados no GitHub (nao executados nesta etapa)
- scripts/zt06/CE_ZT06_EP126_PREFLIGHT.sh: preflight read-only de rede/containers/egress, sem segredos.
- scripts/ga09/CE_GA09_EP126_SCHEDULE_READONLY.sh: contagem de agendamentos no arquivo runtime Bacula, sem mostrar conteudo sensivel e sem executar Jobs.

## Proximos gates
1. Rodar scripts na EP126 e preservar os relatórios e SHA256 locais.
2. Decidir topologia de Connector Twingate e autorizacao de mudanca; nao copiar tokens em chat, logs, GitHub ou Trello.
3. Obter parecer do suporte sobre regra efetiva de Guacamole e restauracao de segmentacao.
4. Confirmar politica BAC-05 antes de qualquer Schedule, backup ou restore.
5. Reconciliar codigo/VM somente apos diff, backup e rollback revisados.

**Nota de custodia:** este documento e um espelho no GitHub das evidencias informadas pela responsavel. O diario local em /home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP126/diario.md NAO foi alterado remotamente.

## Adendo GA-ZT / ZT-06 — Implantacao do Connector institucional EP126 (31/10/2026, 18:45–19:11 BRT)

**Natureza da evidencia:** execucao operacional relatada pela responsavel, sustentada por saidas de terminal e capturas do painel Twingate nesta sessao; nao e verificacao independente por acesso remoto. Este adendo ATUALIZA a anotacao historica anterior que indicava Twingate EP126 ainda pendente. A anotacao anterior permanece para rastreabilidade cronologica.

- 18:45 BRT — preflight em `ep126-pucpr-br`, usuario `andrea.kiew`: Docker Engine 29.9.2, Docker Compose v5.6.1, `/opt/conectaeduca/deploy/interna/twingate/compose.yml` existente, SHA256 `ab78d9fcbea955f2141116daab3fea74b6ae2762aba4833aabc23e1f9d1edd29`. Nenhum container Twingate listado na EP126; verificacao HTTPS externa retornou HTTP 200, sem comprovar todos os endpoints exigidos.
- Compose original: servico `connector`, profile `twingate`, `network_mode: host`, `restart: unless-stopped` e tres variaveis interpoladas `TWINGATE_NETWORK`, `TWINGATE_ACCESS_TOKEN` e `TWINGATE_REFRESH_TOKEN`. Nao havia `env_file`, `secrets` ou `volumes` declarados. A imagem fixa do repositorio e `twingate/connector@sha256:833e7a968f1b3a5ad79b88b04f82aad1bfc8621f61b6b35f01be2411d35beba9`.
- Painel Twingate: Connector previamente inativo foi renomeado `conectaeduca-interna-ep126` na Remote Network `ConectaEduca - Rede Interna` (tenant `conectaeducalab`). Connector pessoal `conectaeduca-interna-01` no openSUSE permaneceu conectado. Cada instância possui seu proprio par de tokens; nenhum token foi incluido neste registro.
- Credenciais do novo Connector provisionadas pela operadora em `~/.config/conectaeduca/twingate-ep126.env` com permissao `0600`, fora do Git; `docker compose ... config --quiet` retornou `COMPOSE_VALIDADO=SIM`. Nenhum valor de credencial foi transcrito.
- 19:07 BRT — deploy real na EP126 usando projeto Compose `conectaeduca-zt-ep126`, servico `connector`, perfil `twingate` e override LOCAL externo ao repositorio `~/.config/conectaeduca/twingate-ep126.override.yml`, com imagem `twingate/connector:1`. Imagem baixada e `conectaeduca-twingate-connector` iniciado; Compose original preservado. Esta divergencia entre a imagem fixada no Git e o runtime deve ser reconciliada em change control antes de tratar o manifesto da main como equivalente a producao.
- Versao efetiva: Connector `1.95.0`; ImageID/digest `sha256:0ef390ef3e526ba7cfb1c6504b794518226188c005087c95205fa9a5b769372a`.
- 19:11:39 BRT — leitura posterior: `Running=true`, `Health=healthy`, `RestartCount=0`, `NetworkMode=host`, `RestartPolicy=unless-stopped`, `Up 4 minutes (healthy)`. Captura do painel: `conectaeduca-interna-ep126 = Connected` e `conectaeduca-interna-01 = Connected`.

**Conclusao comprovada:** instalacao, autenticacao de controle, inicializacao e healthcheck do Connector institucional EP126. **NAO comprovado:** conectividade EP126->Graylog/Wazuh/outros recursos, entrega de Resources ao cliente, autorizacao/negacao por grupos, MFA, isolamento entre zonas, ausencia de bypass, trafego exclusivo via EP126 e retestes dos PA-01..PA-07. Estado ZT-06 = implantacao operacional basica concluida; homologacao Zero Trust E2E pendente. Manter cartao e Grupo A abertos.

**Proximos gates (sem alteracao automatica):** (1) validar alcance de recursos a partir da EP126, (2) conferir Resources/grupos/politicas; (3) garantir acesso institucional alternativo e, em janela autorizada, isolar Connector openSUSE para E2E exclusivo EP126; (4) testes positivos/negativos com usuarios e portas; (5) reconciliar manifestos, digest, rollback e CI; (6) preservar evidencias sanitizadas e revisar aprovacao institucional/pfSense. Nenhum bloqueio de firewall foi alterado neste registro.

**Custodia:** documento GitHub e espelho da evidencia informada; o arquivo local `/home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP126/diario.md` nao foi modificado por esta atualizacao remota.

## Custodia local confirmada — 31/10/2026, 19:23 BRT

A responsavel executou na EP126 o script versionado `scripts/zt06/CE_EP126_ATUALIZAR_DIARIO_20261031.sh` (commit `dea0e0ed69a2831128246405a0ef1904982d47af`, blob Git `805391bab3311e297c789c1150b695b42cd212e5`). Saida de execucao recebida: `RESULTADO=DIARIO_LOCAL_ATUALIZADO`; `REGISTRO_ZT06=CONFIRMADO`; Docker `Running=true Health=healthy Reinicios=0 Rede=host RestartPolicy=unless-stopped Versao=1.95.0`.

- Arquivo local atualizado: `/home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP126/diario.md`.
- Backup anterior: `/home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP126/diario.md.bak.ZT06-20261031T192359`.
- SHA-256 antes: `e531bf05db18886fdbcbdcad487ea49c2e1813782aa5778edefab1dd45e58da9`.
- SHA-256 depois: `0114c8d9bb362f88497f53a71a8e93f76db34177e733df2493173c1bc4d85a27`.
- Marcador no diario: `CE-ZT06-EP126-DEPLOY-20261031`.

Esta confirmacao substitui as notas historicas anteriores que diziam que o diario local nao tinha sido alterado. O resultado e sustentado pela saida copiada da VM, sem acesso remoto independente nesta atualizacao. Homologacao Zero Trust E2E continua PENDENTE.
