# Evidencias Twingate — 31/10/2026 (BRT)

Status: EM INVESTIGACAO; sem homologacao Zero Trust E2E. Registro das saidas coletadas pela responsavel, sem mudancas adicionais nas VMs ou no pfSense.

## Cliente openSUSE
- RPM experimental de compatibilidade Twingate 2026.302.7126 instalado; override systemd para executar apenas /usr/bin/twingated.
- Setup na rede conectaeducalab, sem autostart, persistencia de login ou envio automatico de crash reports.
- Cliente online, daemon active, NRestarts=0, interface sdwan0 100.96.0.2/32.
- Painel confirma identidade no grupo CE-PORTAL e recurso ConectaEducaAPP (192.168.6.34 TCP/443, DMZ, Default Policy / Any Device).
- CLI retorna No resources currently available, inclusive apos disconnect/connect. Causa nao identificada.
- FortiClient ainda conectado; teste sem VPN institucional nao realizado.

## EP125 / conector
- Painel: conectaeduca-dmz-01 = Could not connect; segundo conector = Not yet connected. Uma tela anterior mostrou 1/2; conferir estado atual.
- Docker: conectaeduca-dmz-01 running/healthy, RestartCount=0; imagem twingate/connector:1.
- Logs de 12:17: repetidos erros libsdwan/pubnub-lib TLS/SSL I/O operation failed with error code 104, Transaction failed / Connection failed (~5 min). Nao e possivel atribuir a origem do reset.
- Host EP125: HTTPS IPv4 connect.twingate.com HTTP 200 com TLS valido; IPv6 sem rota default, teste curl -6 falhou. Nao comprova conectividade do proprio container.
- 12:21: rede conectaeduca-twingate-dmz_connector-egress; IP container 172.19.0.2, gateway 172.19.0.1; host rota IPv4 default via 192.168.6.33.
- 12:23: bridge, Internal=false, EnableIPv6=false, subnet 172.19.0.0/16, somente o conector associado, Docker 29.8.1, NetIO acumulado 29.9MB / 31.7MB, running/healthy. NetIO nao prova sessao ativa.

## Proximos gates
1. Diagnosticar DNS/TLS/egress no namespace de rede do container sem expor segredos.
2. Conferir painel e autenticacao do conector sem imprimir tokens.
3. Se necessario, suporte inspecionar pfSense/proxy e resets. Regras interfaces 33/49 foram desabilitadas para restaurar dominio/acesso EP126: revisar por change control, nao reativar em massa.
4. Somente com conector online e recurso entregue: testes positivos/negativos TCP 443 sem FortiClient, DNS/rotas, e bypass.
5. Nao declarar ZT ou sete PAs homologados sem E2E.

## Custodia local (nao anexada)
EP125: ConectaEduca_Fase2_Evidencias/EP125/TWINGATE_CONNECTOR_20261031T121721, TWINGATE_REDE_20261031T122118, TWINGATE_DOCKER_20261031T122329.
openSUSE: ~/CE_Twingate_Logs.
Nao publicar docker_logs_PRIVADO.txt, env, tokens ou links de autenticacao.

## Adendo de monitoramento — 31/10/2026, 13:09–13:19 BRT
- Janela UTC: 2026-10-31T16:09:16Z ate 2026-10-31T16:19:17Z; 21 amostras a cada ~30 s. Todas: Status=running, Health=healthy, Restarts=0.
- Falhas registradas em 16:11:16.281Z e 16:15:59.950Z, cada uma com duas linhas: `[libsdwan] [pubnub-lib] (16) TLS/SSL I/O operation failed with error code: 104` e `Transaction failed / Connection failed`. Intervalo ~283,67 s (4 min 43,67 s); recorrencia consistente com logs anteriores, sem causa-raiz demonstrada.
- Capturas do painel administrativo: conector conectaeduca-dmz-01 chegou a mostrar Connected, Controller Connected e Relay Connected; depois voltou a Could not connect. STUN Discovery Unavailable mesmo quando conectado. Duracao exata de cada estado nao medida.
- Conector→aplicacao: teste curl em namespace compartilhado do container para https://192.168.6.34 retornou HTTP=200, CONNECT=0.000282 s, TOTAL=0.030924 s, com -k (sem validar certificado).
- Conector→endpoint publico: curl do mesmo namespace para https://connect.twingate.com retornou HTTP=200 e TLS_VERIFY=0; nao valida todos os endpoints necessarios.
- Cliente openSUSE: unidade correta twingate.service foi iniciada sem habilitar autostart. Cliente online; em um momento ConectaEducaAPP visivel e rota 192.168.6.34 via sdwan0 src 100.96.0.2, mas curl HTTPS timeout 8 s. Em testes posteriores, cliente online com 'No resources currently available', rota via wlan0/192.168.18.1, curl timeout. Nao confundir esse ultimo timeout com falha do tunel, pois a rota nao era sdwan0.
- Painel de acesso: grupo CE-PORTAL contem a conta autorizada e o recurso ConectaEducaAPP (192.168.6.34, TCP 443, Default Policy, ConectaEduca - DMZ). Ausencia temporaria do recurso no cliente nao foi explicada.
- Tentativa nsenter para inspecionar conexoes: Permission denied em /proc/PID/ns/net; nenhuma alteracao de permissoes.
- Evidencia local EP125: /home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP125/TWINGATE_MONITOR_20261031T130916; arquivos estado_container.log, eventos_filtrados.log, logs_completos_PRIVADO.log e SHA256SUMS.txt. Hashes individuais nao foram transmitidos; nao publicar logs privados.
- Conclusao: disponibilidade E2E Zero Trust NAO homologada; healthcheck Docker nao comprova conectividade Controller/Relay. Proximo passo: diagnosticar estabilidade dos servicos de controle e sincronizacao de recurso no cliente; sem alterar pfSense, tokens ou container precipitadamente.
