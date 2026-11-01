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


## Custódia ZT-07.5 confirmada (31/10/2026, 19:51 BRT)

Resultado informado pela operadora: RESULTADO=DIARIO_LOCAL_ZT075_ATUALIZADO; marcador CE-ZT07-5-CONNECTOR-SEM-SHELL-20261031. Backup: diario.md.bak.ZT075-20261031T195124. SHA-256 antes: 44bde5d9c59b1930ac7b42ec345ab5c734a002f847f6f9292c56ddcce3882966. SHA-256 depois: a399abed5e4d9d429f5962d957d82e4e108ae7d6fbd4830b57dd9efd18bfa0fa. Nenhuma alteração de infraestrutura. Falha de docker exec por ausência de shell foi documentada como consulta DNS não executada, não como falha do Connector. Resource Wazuh ainda não criado; acesso por identidade e MFA não homologados.

## ZT-07.6 — Tentativa de isolamento executada na EP126 por engano

A operadora informou que executou por engano o script de isolamento do Connector pessoal do openSUSE na EP126, e a janela de terminal foi encerrada. O script de isolamento possuia validacao explicita de hostname e Docker host igual a `opensuse-andrea`, portanto deveria ter interrompido sua propria execucao antes de chamar `docker stop` na EP126. A causa do fechamento do terminal nao foi estabelecida.

Na reabertura da EP126, a operadora executou um diagnostico de recuperacao **somente de leitura** e informou: `hostname=ep126-pucpr-br`, `DockerHost=ep126-pucpr-br`, Connector `conectaeduca-twingate-connector` com `Running=true`, `Status=running`, `Health=healthy`, `RestartCount=0`, `RestartPolicy=unless-stopped`, `docker ps`: `Up 49 minutes (healthy)`. `ALTERACOES_REALIZADAS=NAO` no diagnostico. Nao houve necessidade de reiniciar ou restaurar o Connector institucional. **Sem indicios de parada do Connector na EP126**, na janela observada; este resultado nao audita outras sessoes externas.

**Status de ZT-07.6:** isolamento do Connector pessoal openSUSE NAO EXECUTADO neste passo, e nao comprovado. O plano de teste do Resource Wazuh permanece bloqueado ate conferir o acesso institucional alternativo e isolar de forma controlada o Connector pessoal no host correto. Nao modificar a EP126 para isolar o Connector pessoal.


## ZT-07.6 — Isolamento do Connector pessoal confirmado no openSUSE

Em 31/10/2026, a operadora confirmou que executou o isolamento no equipamento pessoal opensuse-andrea. Docker context default, Docker host opensuse-andrea, Compose project twingate e Compose service connector. A confirmacao ISOLAR-OPENSUSE foi fornecida antes da operacao.

Resultado final informado: Running=false e Status=exited para o contêiner pessoal conectaeduca-twingate-connector; retorno ZT076_ISOLAMENTO_CONCLUIDO=SIM. O aviso de deprecacao do argumento --time nao impediu a parada.

Este resultado comprova a parada do contêiner no openSUSE, mas o estado do Connector institucional no painel apos a parada ainda nao foi confirmado. Nao houve alteracao nos contêineres da EP126 nesta operacao. O acesso fim-a-fim Wazuh/Twingate, MFA e grupos ainda necessitam de testes.

O registro no diario.md LOCAL da EP126 relativo a ZT-07.6 ainda nao foi executado. Ultimo hash local confirmado para ZT-07.5: a399abed5e4d9d429f5962d957d82e4e108ae7d6fbd4830b57dd9efd18bfa0fa.

## ZT-07.6 — Confirmacao cruzada pelo painel e Docker na EP126

**Data:** 31/10/2026. Evidencia composta por captura de tela do painel Twingate e saida de terminal fornecidas pela responsavel, apos isolamento do Connector pessoal openSUSE.

- Twingate / Remote Network ConectaEduca - Rede Interna: Connector conectaeduca-interna-01 = Could not connect (indicador laranja, correspondente ao conteiner pessoal interrompido); Connector conectaeduca-interna-ep126 = Connected (indicador verde).
- Na EP126, docker inspect conectaeduca-twingate-connector mostrou Running=true; Health=healthy; RestartCount=0.
- A saida anterior no openSUSE confirmou Running=false e Status=exited no Connector pessoal. Houve apenas aviso de depreciacao da flag de parada; a operacao foi bem-sucedida.
- Conclusao estrita: isolamento do Connector pessoal e disponibilidade institucional confirmados neste instante. Ainda nao foi criado nem homologado um Resource Wazuh, e nao houve prova de acesso E2E, permissoes negativas ou MFA.

**Custodia do diario local:** preparou-se o script de registro versionado scripts/zt07/CE_ZT076_EP126_REGISTRAR_ISOLAMENTO_20261031.sh, commit d8f3b7f7c1376f4738ccd03cbedb9d62d7926b88. A execucao pela operadora na EP126 ainda esta pendente. Ultimo hash local confirmado: a399abed5e4d9d429f5962d957d82e4e108ae7d6fbd4830b57dd9efd18bfa0fa.

**Proximo gate:** definir Resource de teste Wazuh Dashboard, dominio/alias e certificado, limitar exclusivamente TCP/443, atribuir somente grupo de Operacao/SOC autorizado e politica MFA, realizar acessos positivos/negativos. Nao conceder Everyone nem publicar API do Wazuh, Manager ou Indexer.


## ZT-07.7 — verificacao visual das politicas MFA

As capturas da tela Twingate em 31/10/2026 mostram as politicas Resource Policy CE-SOC-MFA-1DIA e CE-INFRA-MFA-2HORAS, ambas com MFA required. A primeira mostra Authenticate every 1 day e a segunda Authenticate every 2 hours. Ambas mostram geoblocking not enabled, recurso nao disponivel no plano. A parte direita sobre Device Security esta cortada nas imagens, portanto nao comprova integralmente a configuracao de postura do dispositivo.

Decisao proposta para o Wazuh Dashboard: aproveitar CE-SOC-MFA-1DIA, associando acesso apenas ao grupo CE-SOC-OPERACAO. CE-PORTAL, Everyone e CE-INFRA-ADMIN nao sao autorizados nesta fase. O grupo e a politica precisam ser selecionados no formulario; nao ha evidencia de criacao final do Resource, de usuario de teste membro do grupo, de MFA completado ou de conectividade E2E.

O MFA exigido pela politica nao equivale a comprovacao de desafio MFA em acesso de cliente; a janela de autenticacao pode ser influenciada por sessoes validas. A CA TLS Wazuh permanece nao confiavel na coleta anterior, e o alias deve ser testado sem ignorar certificados como solucao definitiva.


## ZT-07.7 — Resource Wazuh criado (confirmacao da operadora)

A responsavel esclareceu que o Resource ConectaEduca — Wazuh Dashboard ja havia sido criado no Twingate. A captura apresentada era a tela de edicao (Update Resource), nao de criacao. A politica selecionada e CE-SOC-MFA-1DIA, que as capturas de Resource Policy mostram como MFA required e Authenticate every 1 day.

Parametros exibidos na captura: Remote Network ConectaEduca - Rede Interna, destino 127.0.0.1, alias wazuh.dashboard, TCP/443, UDP e ICMP bloqueados, Manual Access. O grupo efetivamente atribuido ainda requer verificacao na ficha de acesso; recomendacao aprovada para testes e CE-SOC-OPERACAO, sem Everyone.

Criacao do Resource: confirmada pela responsavel; testabilidade por Twingate Client, cumprimento efetivo do MFA, grupo de acesso, DNS/alias em cliente, cadeia TLS Wazuh e bloqueio de acesso nao autorizado seguem pendentes. Nenhuma mudanca adicional foi feita no painel por esta atualizacao documental. Diario local na EP126 ainda nao incorporou esta verificacao.


## ZT-07.8 — Client online, Wazuh não listado

Observação reportada pela operadora no openSUSE em 31/10/2026 após `twingate start`: status `online`; `twingate resources` lista somente `ConectaEducaAPP` endereço `192.168.6.34`, autenticação válida por aproximadamente 4 dias; `wazuh.dashboard` não resolvido por `getent ahostsv4`; interface `sdwan0` com `100.96.0.2/32`. O Client havia estado `not-running` antes da ativação; outra VPN ativa gerou aviso, mas o Client iniciou. O Connector Docker pessoal continua parado; o institucional EP126 estava Connected/healthy na verificação anterior.

**Diagnóstico restrito:** o Resource Wazuh criado não aparece na lista de Resources autorizados para a identidade atualmente ativa. Prioridade: conferir associação Resource→grupo `CE-SOC-OPERACAO`, membro do grupo e conta ativa do Client. Não classificar ausência do alias como defeito de DNS antes de resolver visibilidade/autorização; a documentação do Twingate recomenda verificar grupos primeiro. Não conceder Everyone, não alterar firewall/VM e não inserir credenciais no relatório. Depois conferir visibilidade, autenticação MFA e HTTPS/TLS por etapas.

Este adendo GitHub não alterou o diário local da EP126; sua próxima inclusão depende de evidência e SHA-256 novo.


## ZT-07.9 — Resource/grupo confirmados por capturas

Quatro capturas do Twingate Admin Console recebidas em 31/10/2026 confirmam: a lista Network > Resources mostra ConectaEducaAPP (Remote Network ConectaEduca - DMZ; 192.168.6.34) e ConectaEduca — Wazuh Dashboard (Remote Network ConectaEduca - Rede Interna; destino 127.0.0.1). O detalhe do Resource Wazuh confirma alias wazuh.dashboard, TCP [443] exclusivo, grupo de acesso CE-SOC-OPERACAO, política CE-SOC-MFA-1DIA, modo Manual Access; Everyone e os demais grupos não constam como autorizados. Sem Recent Activity registrado na captura.

Conclusão objetiva: NÃO falta associar o grupo CE-SOC-OPERACAO ao Resource; isso JÁ FOI CONFIRMADO. A lista do Client openSUSE continua mostrando somente ConectaEducaAPP. Próximo diagnóstico: validar se o usuário ativo no Client é membro de CE-SOC-OPERACAO, se a sessão foi atualizada e se o Resource está configurado como Standard/Browser Address em vez de Background Address. Somente depois examinar DNS/VPN e conectividade; nenhum teste HTTPS/Wazuh ocorreu até esse ponto.

As capturas não mostram membros do grupo nem a identidade ativa no Client; não atribuir a ausência a uma causa definitiva, não relaxar Everyone, não mudar política, não efetuar testes que contornem CA. A verificação não altera o diário local EP126.


## ZT-07.9 — causa de invisibilidade: grupo SOC sem membros

Captura da tela de grupo Team > CE-SOC-OPERACAO recebida em 31/10/2026 confirma explicitamente **0 users** e **No Users Added**. O painel mostra o Resource ConectaEduca — Wazuh Dashboard associado ao grupo com policy CE-SOC-MFA-1DIA. Portanto, a falta de associação **usuário→grupo** é a causa demonstrada para a ausência de autorização dessa conta, embora a visibilidade após inclusão ainda precise ser testada. Próxima ação orientada: adicionar apenas a identidade autorizada do Client ao grupo, preservando Never/Everyone sem acesso, revalidar `twingate resources`, alias, MFA e TLS.

Porta Wazuh: Resource usa 127.0.0.1 como endereço e Port Restrictions TCP/443; na EP126 houve publicação host 127.0.0.1:443 para contêiner porta 5601. Não incluir :5601 no Resource nem alterar portas; acesso pelo navegador após homologação seria https://wazuh.dashboard/ . Nao houve alteração automática no Twingate nem no diário local EP126.

## ZT-07.10/07.11 — Client com Resource e HTTPS timeout

### ZT-07.10 — Visibilidade e DNS confirmados (openSUSE, 31/10/2026)

Após a inclusão da identidade autorizada no grupo CE-SOC-OPERACAO, `twingate resources` no openSUSE listou `ConectaEducaAPP` (192.168.6.34, Auth expires in 4 days) e `ConectaEduca — Wazuh Dashboard` (127.0.0.1, alias wazuh.dashboard, AUTH STATUS sem texto exibido). `getent ahostsv4 wazuh.dashboard` devolveu 100.98.166.92 para STREAM, DGRAM e RAW: o Client publicou o Resource e seu endereco virtual. Isso nao comprova trafego TCP nem MFA completado.

### ZT-07.11 — Teste HTTPS falhou ANTES da resposta TLS

No mesmo openSUSE, Client `twingate status=online`. Teste `curl --noproxy '*' --silent --show-error --output /dev/null --connect-timeout 5 --max-time 20 --write-out 'HTTP=%{http_code} IP=%{remote_ip} TLS_VERIFY=%{ssl_verify_result}\\n' https://wazuh.dashboard/` retornou: `curl: (28) Connection timed out after 5001 milliseconds`, `HTTP=000 IP= TLS_VERIFY=0` e `CURL_EXIT_CODE=28`. Não houve resposta HTTP nem handshake TLS comprovado; **TLS_VERIFY=0 nesta circunstancia NAO e prova de confianca valida**. Nenhuma credencial enviada, nenhuma alteracao no host ou nas VMs.

Hipoteses abertas (nao provar causalidade sem teste): requisito de autenticacao on-demand/MFA do Resource (AUTH STATUS vazio), fluxo Client→Connector da Rede Interna, interacao entre duas VPNs no openSUSE, endereco de destino loopback 127.0.0.1 no contexto do Connector host-network e politica de acesso. O Dashboard havia respondido localmente no host EP126 com HTTP 302 em HTTPS 127.0.0.1:443, mas essa evidência anterior não comprova caminho remoto.

Proximo diagnostico read-only: (1) consultar estado/autenticacao do Resource Wazuh no Client e eventos do Admin Console (sem expor segredos); (2) testar conectividade TCP/TLS em passos separados e tempos controlados; (3) no EP126, validar o Docker Connector e acesso loopback, sem alteracao de firewall/Compose; (4) avaliar rota/vpn local e endereco de Resource antes de modificar destino. A cadeia TLS/CA Wazuh permanece pendente e so deve ser testada quando a conexao TCP funcionar.

Este registro é apenas no espelho GitHub da PR #214; o diario local EP126 ainda precisa receber essas evidências em sessao apropriada e gerar SHA-256 novo.


## ZT-07.11 — EP126 valida caminho local para Wazuh

Evidencia enviada pela operadora (31/10/2026): hostname `ep126-pucpr-br`; `docker inspect conectaeduca-twingate-connector --format` retornou `Running=true Health=healthy Network=host Restarts=0`. Teste local `curl --noproxy '*' --insecure` em `https://127.0.0.1:443/` retornou `HTTP=302 IP=127.0.0.1`. A resposta 302 demonstra que Wazuh Dashboard responde no host EP126, nao comprova confianca TLS porque o teste usou `--insecure`.

O teste remoto anterior via openSUSE permaneceu em `curl exit=28` (timeout de conexao em 5 segundos), `HTTP=000`, sem IP remoto nem handshake TLS; `TLS_VERIFY=0` nessa tentativa NAO deve ser tratado como TLS valido. O Client estava `online`, o Resource Wazuh aparecia no Client depois de incluir a conta no grupo `CE-SOC-OPERACAO` e o alias `wazuh.dashboard` resolveu para `100.98.166.92`.

Diagnostico: servico host local e estado do Connector confirmados, mas o fluxo real Client→Connector→127.0.0.1:443 continua INCONCLUSIVO. Proxima acao segura: consultar Recent Activity da tentativa, status de autorizacao/MFA do Resource e estado do Client; retestar apos reconexao controlada do Client somente se nao interferir com acesso institucional; sem mudar regras, destino nem reiniciar EP126. Para reconciliação de codigo das VMs, usar kit read-only da PR #215 em pacote isolado, sem pull, deploy ou merge.

Diario local EP126 nao alterado automaticamente por este adendo GitHub.


## ZT-07.12 — Resource sem eventos recentes no painel

Captura de 31/10/2026 do detalhe de Network > Resources > ConectaEduca — Wazuh Dashboard mostra explicitamente `No Recent Activity` na página do Resource. A configuração de acesso permanece CE-SOC-OPERACAO, política CE-SOC-MFA-1DIA, Remote Network ConectaEduca - Rede Interna, destino 127.0.0.1, alias wazuh.dashboard e TCP/443. A última tentativa openSUSE resultou em timeout curl 28 sem HTTP/TLS; o Connector institucional havia sido observado healthy/network=host/restarts=0 e o Wazuh na EP126 respondeu localmente HTTP 302. A ausência de eventos na interface é um indício de não entrega ao caminho de eventos, não comprovação conclusiva de causa. Próximo teste prioritário: inspecionar rotas para IP virtual 100.98.166.92 e VPNs ativas no Client openSUSE, sem mudar firewall, Recursos ou serviço; se necessário consultar logs sanitizados do Client/Connector e `Network > Overview` para Resource Activity. Nenhuma VM alterada por esta documentação.


## ZT-07.13 — autenticacao adicional pendente no Client

No openSUSE, a tentativa HTTPS ao Resource Wazuh retornou curl exit 28 (timeout 8 s, HTTP 000). O Client exibiu AUTH STATUS Pending, e o console de notificacoes relatou Additional authentication required para ConectaEduca — Wazuh Dashboard. A operadora tentou abrir wazuh.dashboard no Firefox, mas recebeu aviso de conexao expirada antes do login do Wazuh. Estado: MFA por Resource nao confirmado e HTTPS fim a fim nao demonstrado. Proximo gate: concluir a autenticacao pelo Twingate Client (notificacoes desktop), conferir que Pending desapareceu e so entao retestar HTTPS. O Connector institucional EP126 continua em ultimo estado conhecido healthy com acesso HTTP 302 local. Nenhuma alteracao de firewall, Resource ou VM foi realizada nesta etapa. A confianca TLS do Wazuh continua pendente.


## ZT-07.14 — Browser em loopback e autenticacao pendente

Em 31/10/2026 (BRT), nova captura do Firefox no openSUSE mostrou a barra de enderecos em `127.0.0.1` e mensagem de impossibilidade de conexao, com requisicao GET para o proprio loopback do cliente. Isso **nao comprova acesso remoto ao Wazuh nem equivale ao alias `wazuh.dashboard`**. O output simultaneo de `twingate resources` listou ConectaEducaAPP com autorizacao vigente e o Wazuh inicialmente sem texto em AUTH STATUS, passando a `Pending` numa consulta posterior. A etapa Resource MFA continua inconclusiva. A pendencia do `curl` anterior por timeout nao deve ser interpretada como validacao de TLS ou da rede.

Orientado utilizar exclusivamente `https://wazuh.dashboard/` para o teste de Resource, observar o notifier/desktop-auth sem publicar links OTP, e validar a transicao de `Pending` para uma sessao autenticada antes de inferir problema de Connector. Se a aba `127.0.0.1` tiver sido criada automaticamente no fluxo de autenticacao, investigar callback local do Client e seu listener como problema distinto; nao instalar proxy, mudar firewall ou trocar o IP no painel nesta etapa. Nenhuma VM foi alterada por este registro.


## ZT-07.15 — autenticação adicional do Wazuh concluída

Evidência fornecida pela operadora em openSUSE, após execução manual de `twingate auth 'ConectaEduca — Wazuh Dashboard'`: Client exibiu `Authentication successful`. Em nova consulta `twingate resources`, ConectaEduca — Wazuh Dashboard (destino 127.0.0.1, alias wazuh.dashboard) mostrou `Auth expires in 23 hours`, enquanto ConectaEducaAPP (192.168.6.34) apresentou `Auth expires in 4 days`. A autenticação adicional do Resource sob a política `CE-SOC-MFA-1DIA` foi concluída com sucesso e a sessão foi autorizada. A documentação não copia URI privada de autenticação, código MFA ou cookies.

Escopo comprovado: membership de identidade no grupo CE-SOC-OPERACAO, visibilidade de Resource, alias resolvido anteriormente e autorização por autenticação adicional. Ainda **não** comprovado: tráfego HTTPS fim a fim, confiabilidade da CA do Dashboard, login no Wazuh e teste negativo com identidade sem acesso. O último teste HTTPS ocorreu antes da autenticação e terminou em timeout RC 28; deve ser repetido sem `--insecure` agora que o Resource está autorizado.

Próximo gate: `curl` sem credenciais a `https://wazuh.dashboard/`, com `--noproxy '*'`, timeouts e retorno HTTP/TLS; diante de timeout persistente, revisar o caminho Client→Connector→loopback e a coexistência com VPN institucional, sem alterar acesso por grupo ou Connector operacional. Nenhuma alteração nas VMs foi realizada por este adendo; diário local EP126 ainda não atualizado.


## ZT-07.16 — MFA concluido e TLS emissor nao confiavel

O teste remoto no openSUSE, após `twingate auth` concluído com `Authentication successful`, confirmou sessão autorizada para o Resource Wazuh (`Auth expires in 23 hours`). Teste de `curl --noproxy '*'` sem `--insecure` em `https://wazuh.dashboard/` retornou `CURL_RC=60`, `HTTP=000`, `IP=100.98.166.92`, `TLS_VERIFY=20` e `unable to get local issuer certificate`. Interpretação: a conexão passou a alcançar a negociação TLS pelo Resource virtual do Twingate; o cliente rejeitou o certificado por cadeia emissora não confiável. HTTP e login no Dashboard ainda nao comprovados. O erro não e mais timeout neste teste.

Próximo passo: identificar somente a CA publica que assinou o certificado Wazuh na EP126 e conferir origem/fingerprint/SAN; transportar unicamente o certificado CA publico a uma área isolada no openSUSE para teste `curl --cacert` sem alterar trust store global. Nao copiar chaves, tokens ou arquivos .env; nao usar --insecure como aceite. Manter Twingate Resource 127.0.0.1 com TCP/443 e grupo SOC/MFA. Diário local EP126 ainda não atualizado automaticamente.


## ZT-07.17 — certificado Wazuh identificado; consolidado 31/10

A responsável apresentou saída do ZT-07.17 na EP126: certificado servido pelo Dashboard `CN=wazuh.dashboard`, `SAN=DNS:wazuh.dashboard`, issuer `OU=Wazuh,O=Wazuh,L=California`, notBefore `2026-08-27 21:36:49 GMT`, notAfter `2036-08-24 21:36:49 GMT`, fingerprint SHA-256 do servidor `DB:56:D8:D9:6C:08:90:E1:DB:72:27:46:06:F2:60:CD:F8:36:10:49:5E:BE:56:F5:14:CC:20:6B:1C:2D:BE:F0`. Montagem de CA pública localizada em `/opt/conectaeduca/deploy/interna/wazuh/.runtime/certs/root-ca.pem`, servida no contêiner em `/usr/share/wazuh-dashboard/certs/root-ca.pem`. Metadados da chave privada não são reproduzidos aqui.

Com o histórico anterior, o estado atual é: Connector saudável; Resource Wazuh criado; grupo SOC/MFA de 1 dia aplicado; `twingate auth` concluiu com sucesso e sessão autorizada; curl via Twingate evoluiu de timeout para RC=60 por emissor TLS não confiável. Prova HTTP/login remoto ainda pendente. Próximo gate: conferir fingerprint/assinatura da CA com `openssl verify -CAfile` no host EP126, então ensaiar `curl --cacert` no cliente sem alteração global da trust store.

Consolidação cronológica e critérios de aceite: [Consolidado EP126 ZT de 31/10](CONSOLIDADO-ZT-EP126-20261031-TESTES-E-PENDENCIAS.md). Critérios sugeridos: 4 gates para Wazuh (CA/TLS; navegador/login; testes positivo/negativo e telemetria; reconciliação/rollback/evidências) + até 2 frentes condicionais para proteção de demais interfaces e Pentest B. **Diário local da EP126 permanece sem esta atualização**; o último hash comprovado por execução foi ZT-07.6 (`248b7e2c8d983e19741b07e62e6cc89c57a3f387411e156eb6d9439558b90b37`).


## ZT-07.18 — certificados não legíveis no caminho host

Execução informada pela responsável na EP126: o pré-teste usando `[ -r "$CA" ] && [ -r "$CERT" ]` terminou com `CA_OU_CERTIFICADO_SEM_PERMISSAO_DE_LEITURA` e `ALTERACOES_REALIZADAS=NAO`. Isso não distingue qual arquivo falhou, nem comprova ausência do arquivo ou CA inválida: somente que a condição conjunta não foi satisfeita sob a conta ativa. Certificados mapeados em contêiner Wazuh: `/usr/share/wazuh-dashboard/certs/root-ca.pem` (CA pública) e `/usr/share/wazuh-dashboard/certs/wazuh.dashboard.pem` (certificado público de servidor). Próxima coleta proposta: copiar **somente** esses certificados públicos para diretório temporário privado no home via `docker cp`, desde que a conta já possua acesso autorizado ao Docker; usar `openssl verify -CAfile ... -verify_hostname wazuh.dashboard ...`, emitir fingerprints/sha256 e comparar certificado com live server. Não copiar chave privada, não modificar permissões dos mounts originais, não reiniciar serviços e não publicar conteúdo CA ainda. Diário local EP126 não alterado pelo adendo.


## ZT-07.18B — copia parcial dos certificados publicos

Diagnóstico enviado pela responsável na EP126: host `ep126-pucpr-br`; foi criado diretório temporário privado `/home/andrea.kiew/CE-ZT0718B.DxuqlyrH` (drwx------). `root-ca.pem` está presente, mas `wazuh.dashboard.pem` não está. Container `conectaeduca-wazuh-wazuh.dashboard-1` permanece `Up 12 hours (healthy)`. A interrupção ocorreu após a cópia da CA e antes da conclusão da cópia do certificado do servidor; a saída de erro original não está disponível, portanto sua causa não foi demonstrada. Nenhuma alteração no serviço foi relatada. Próximo teste somente leitura: aproveitar CA pública existente e capturar o certificado apresentado em `127.0.0.1:443` por `openssl s_client -servername wazuh.dashboard`, verificar fingerprint do certificado servido e executar `openssl verify -CAfile root-ca.pem -verify_hostname wazuh.dashboard`. Executar comandos em subprocesso Bash para não encerrar o shell interativo caso haja falha; não copiar chave privada ou alterar os mounts originais. Diário local EP126 ainda não atualizado com este registro.

## ZT-07.18C — validacao local da cadeia Wazuh concluida (PASS)

Saída fornecida pela responsável na EP126 (execução por `bash <<'BASH'`, subprocesso, sem encerramento do shell): `root-ca.pem` público em `~/CE-ZT0718B.DxuqlyrH/` inspecionado por OpenSSL: `subject=OU=Wazuh,O=Wazuh,L=California`; `issuer` idêntico; Basic Constraints crítico `CA:TRUE`; fingerprint SHA-256 da **CA** `EE:68:D3:51:A4:AE:B9:49:D3:34:68:82:D6:9B:33:89:75:15:18:4E:6B:C9:19:36:7F:22:21:70:BF:D9:EB:A5`. Certificado servidor público capturado via `openssl s_client -connect 127.0.0.1:443 -servername wazuh.dashboard` para `~/CE-ZT0718B.DxuqlyrH/wazuh-apresentado.pem`; fingerprint igual à coleta ZT-07.17: `FINGERPRINT_CORRESPONDE=SIM` (`DB:56:D8:D9:6C:08:90:E1:DB:72:27:46:06:F2:60:CD:F8:36:10:49:5E:BE:56:F5:14:CC:20:6B:1C:2D:BE:F0`).

`openssl verify -CAfile root-ca.pem -verify_hostname wazuh.dashboard wazuh-apresentado.pem` retornou `wazuh-apresentado.pem: OK`, `OPENSSL_VERIFY_RC=0`, `VALIDACAO_CA_LOCAL=PASS`. SHA-256 dos **arquivos** (diferente de fingerprint X.509): `root-ca.pem`: `68fa6e5bcdeaca4f4759932619887638594f26aff5b2269a7b833db49c498065`; `wazuh-apresentado.pem`: `29c6dc3b0a49a17f04dfafae034700d300cb9dfb12ba03083d4a05de8bc7117f`. Impressões digitais CA e servidor são objetos diferentes.

**Limites:** assinatura/nome do certificado efetivamente servido no loopback EP126 validados com CA pública. Isto ainda não comprova trust store no openSUSE, resposta HTTPS via Client Twingate, Firefox/login Wazuh nem acesso negado a identidade não autorizada. Nenhum serviço/certificado original foi alterado. Próximo gate: transferir somente CA pública por meio autorizado, comparar SHA-256 do arquivo no openSUSE e testar `curl --cacert <CA local> --noproxy '*' https://wazuh.dashboard/` sem `-k`, sem importar CA globalmente. Diário local da EP126 ainda não atualizado automaticamente.


## ZT-07.19 — SCP para CA publica impedido por timeout porta 22

Tentativa de transferência da CA pública do diretório privado na EP126 para openSUSE pelo comando `scp -o ConnectTimeout=8 andrea.kiew@192.168.6.50:/home/andrea.kiew/CE-ZT0718B.DxuqlyrH/root-ca.pem ...` falhou com `ssh: connect to host 192.168.6.50 port 22: Connection timed out` e `TRANSFERENCIA=FALHOU`; por isso o teste HTTPS `curl --cacert` **não foi executado**. Este resultado NÃO demonstra falha do Twingate: Resource Wazuh aprovado limita-se a TCP/443 no destino `127.0.0.1`, e SCP usa SSH/22 direto para o IP privado da EP126. Não alterar regras de firewall nem abrir portas para transportar CA. Plano alternativo: transporte manual da CA **pública** por texto Base64 através de terminal/clipboard já autorizado, seguido de checagem estrita de SHA-256 do arquivo (`68fa6e5bcdeaca4f4759932619887638594f26aff5b2269a7b833db49c498065`) ANTES de usar em `curl --cacert`; nunca copiar chave privada ou tokens. Diário local EP126 não atualizado por esta ação GitHub.
