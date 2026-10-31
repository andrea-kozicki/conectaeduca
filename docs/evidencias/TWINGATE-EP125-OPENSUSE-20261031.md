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
