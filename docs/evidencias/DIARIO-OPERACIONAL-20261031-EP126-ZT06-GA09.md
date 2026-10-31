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

**Conclusao comprovada:** instalacao, autenticacao de controle, inicializacao e healthcheck do Connector institucional EP126. **NAO comprovado:** conectividade EP126->Wazuh/outros recursos, entrega de Resources ao cliente, autorizacao/negacao por grupos, MFA, isolamento entre zonas, ausencia de bypass, trafego exclusivo via EP126 e retestes dos PA-01..PA-07. Estado ZT-06 = implantacao operacional basica concluida; homologacao Zero Trust E2E pendente. Manter cartao e Grupo A abertos.

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


## Retificacao arquitetural — 31/10/2026, 19:27 BRT

A responsavel confirmou que a **arquitetura atual da Intranet possui Wazuh, nao Graylog**. Logo, o teste exploratorio ZT-07.1 de `127.0.0.1:9000` e `192.168.6.50:9000` (ambos `curl RC=7, HTTP=000`, sem listener TCP/9000 e sem container Graylog listado) investigou um servico que nao integra o desenho atual. O resultado NAO deve ser classificado como falha do Twingate nem do Wazuh. Nenhum Resource Graylog deve ser criado. Proximo gate ZT-07: identificar a exposicao efetiva dos componentes Wazuh na EP126 e selecionar somente uma interface de administracao legitimamente publicada para um Resource restrito a Operacao/SOC/Admin, mediante validacao de politica e MFA. Nao expor as portas de ingestao de agentes ou a API administrativa por padrao. Nenhuma alteracao de ambiente foi executada na coleta ZT-07.1.


## ZT-07.2 — Dashboard Wazuh acessivel em loopback e bridge (31/10/2026, 19:33 BRT)

A operadora executou `ZT-07.2` na EP126 às 19:33:21 BRT (apenas leitura). O contêiner `conectaeduca-wazuh-wazuh.dashboard-1` retornou `Running=true`, `Health=healthy`, `RestartCount=0`. Publicação Docker confirmada: `5601/tcp -> 127.0.0.1:443`. Network `conectaeduca-wazuh_wazuh-backend`; IP do contêiner no momento: `172.19.0.3`.

| Origem do teste | Destino HTTPS | Resposta | Limitação |
| --- | --- | --- | --- |
| EP126 (host) | `https://127.0.0.1:443/` | `HTTP 302`, `curl RC=0`, `remote_ip=127.0.0.1` | `-k` — TLS não validado; sem login funcional. |
| EP126 (host) | `https://172.19.0.3:5601/` | `HTTP 302`, `curl RC=0`, `remote_ip=172.19.0.3` | IP de contêiner dinâmico, TLS não validado, sem E2E Twingate. |

**Interpretação:** os dois caminhos locais no host EP126 responderam em HTTPS, mas não foram validados o alvo do redirecionamento 302, certificados, o transporte pelo Connector EP126 ou permissões Zero Trust. NÃO cadastrar automaticamente `127.0.0.1` como endereço de Resource no painel ou fixar `172.19.0.3` como endereço permanente. A implantação do Wazuh Dashboard mantém bind exclusivo de loopback.

**Diário local:** preparou-se o script incremental e idempotente `scripts/zt07/CE_ZT07_EP126_REGISTRAR_DIARIO_20261031.sh` para registrar ZT-07.1, identificação de containers Wazuh e ZT-07.2 com backup e SHA-256. **Ainda depende de execução explícita no terminal EP126**; não afirmar que esse adendo já foi escrito no `diario.md` local até receber o resultado.

**Próximo gate:** confirmar redirecionamento, endereçamento alcançável apenas pelo Connector institucional e política de acesso para Operação/SOC (MFA), depois testar acesso autorizado/negado sem alterar pfSense e sem expor as portas de ingestão, API ou Indexer. Cliente openSUSE Connector na mesma Remote Network continua sendo potencial rota alternativa.

## Custodia local confirmada — ZT-07 — 31/10/2026, 19:37 BRT

A responsavel executou na EP126 o script versionado `scripts/zt07/CE_ZT07_EP126_REGISTRAR_DIARIO_20261031.sh` (commit `8d707a33692b8753bce85e7278ea69481b617019`; blob Git `ce6bc357abcbc676cac17effe3ec2e8e00e56879`). Foram informados os resultados `INTEGRIDADE=OK`, `SINTAXE=OK`, `RESULTADO=DIARIO_LOCAL_ZT07_ATUALIZADO`, `REGISTRO_ZT07=CONFIRMADO` e `ALTERACAO_DOCKER_WAZUH_TWINGATE=NAO`.

- Diario local: `/home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP126/diario.md`.
- Backup: `/home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP126/diario.md.bak.ZT07-20261031T193733`.
- Hash SHA-256 anterior: `0114c8d9bb362f88497f53a71a8e93f76db34177e733df2493173c1bc4d85a27`.
- Hash SHA-256 posterior: `04b26843f9464f5aac5eb3f66e8e911896303095880476454bfcaf0b7beb881d`.
- Marcador documental: `CE-ZT07-EP126-WAZUH-20261031`.

**Interpretação:** adendo ZT-07.1/07.2 gravado na EP126, conforme saída apresentada pela operadora; backup e hash reportados. A homologação E2E do Resource Wazuh via Twingate permanece pendente.

## ZT-07.3 — Wazuh Dashboard HTTPS/TLS, 31/10/2026, 19:39 BRT

Coleta apenas de leitura apresentada pela responsável na EP126. `curl --insecure https://127.0.0.1:443/` retornou `HTTP 302 / RC=0`. Redirecionamento HTTP relativo: `/app/login` (sem query ou fragment e sem endereço absoluto). O certificado observado via OpenSSL apresentou `CN=wazuh.dashboard` e `SAN DNS:wazuh.dashboard`, emissor Wazuh (`OU=Wazuh, O=Wazuh, L=California`), validade UTC `2026-08-27 21:36:49` a `2036-08-24 21:36:49`. A tentativa de `curl` sem `-k` usando endereço `https://127.0.0.1/` falhou com `curl RC=60`, `TLS_VERIFY=20`, `HTTP=000` e `unable to get local issuer certificate`.

**Interpretação:** o Dashboard respondeu em HTTPS e redirecionou para o login, mas não houve comprovação de validação da cadeia TLS. O hostname `127.0.0.1` não consta do SAN exibido; isso poderá produzir erro de hostname após corrigir a confiança na CA. O resultado NÃO prova que a CA seja inválida, apenas que o cliente atual não conseguiu validá-la. Não instalar CA às cegas, não trocar certificado, não expor Dashboard nem cadastrar `127.0.0.1` como Resource sem projeto de endereçamento.

**Custódia:** script idempotente preparado no GitHub em `scripts/zt07/CE_ZT07_EP126_REGISTRAR_TLS_20261031.sh` (commit `91c5bdc96acd0647a09d6f26561d9d57ebc57a1f`), para adicionar este teste ao `diario.md` com backup e SHA-256. O diário local AINDA NÃO foi atualizado para o ZT-07.3 neste ponto; depende de execução pela responsável. A homologação Zero Trust E2E segue pendente.

**Próximo gate:** verificar resolução DNS do `wazuh.dashboard` a partir da EP126/Connector, origem confiável da CA e SNI/hostname correto, sem expor tokens ou material privado; depois desenhar Resource privado somente para administração/SOC com MFA.

## ZT-07.4 — DNS ausente e acesso temporario por nome (31/10/2026, ~19:43 BRT)

A responsavel concluiu a escrita incremental ZT-07.3 no diario local da EP126 por meio do script versionado em `91c5bdc`: `RESULTADO=DIARIO_LOCAL_ZT073_ATUALIZADO`, `MARCADOR=CE-ZT07-3-WAZUH-TLS-20261031`, `ALTERACAO_INFRAESTRUTURA=NAO`.

**Custodia local:** backup `/home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP126/diario.md.bak.ZT073-20261031T194257`; `SHA256_ANTES=04b26843f9464f5aac5eb3f66e8e911896303095880476454bfcaf0b7beb881d`; `SHA256_DEPOIS=11c42efd06af56a214cff5fce71418d34bea54764a2cf941e6ee85cb24236a1d`.

Na coleta ZT-07.4, `getent ahostsv4 wazuh.dashboard` retornou `RESOLUCAO_HOST=NAO_ENCONTRADA`. Em seguida, o comando de teste **temporario** `curl --resolve wazuh.dashboard:443:127.0.0.1 --insecure https://wazuh.dashboard/` retornou `HTTP=302`, `REMOTE_IP=127.0.0.1`, `CURL_RC=0`, com `TLS_VALIDADO=NAO`. Isto comprova resposta do Dashboard usando SNI/Host `wazuh.dashboard` quando o destino foi forçado artificialmente, mas **nao** cria DNS no host, nao valida cadeia TLS e nao demonstra Resource Twingate funcional.

**Estado correto:** DNS `wazuh.dashboard` nao configurado/nao resolvivel do host EP126 pela consulta efetuada. O Connector da EP126 esta em network_mode=host, mas ainda nao foi comprovado que seu resolvedor interno usa exatamente as mesmas fontes do host. O Connector do openSUSE na mesma Remote Network nao compartilha loopback/Docker da EP126; isso limita qualquer projeto com hostname resolvido em `127.0.0.1` a um Connector isolado/caminho especifico. Nao cadastrar esse Resource ate planejar rota e DNS estaveis. 

**Proximo gate:** confirmar sem expor segredos se existe CA Wazuh/volume montado e obter metadados do Docker Compose/aliases; desenhar topologia aprovada (DNS privado com destino realmente acessivel ao(s) Connector(s), grupo e politica MFA), retestar TLS corretamente, depois executar controle de acesso E2E. Sem mudancas de firewall, certificados ou redes nesta etapa.
