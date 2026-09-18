# Logging pfSense -> Wazuh

## Estado operacional

A integração de Remote Logging do pfSense com o Wazuh teve o **transporte até o
receiver de host** promovido em 16/09/2026 e correlacionado por probes sintéticos
em 17/09/2026.

Fluxo operacional observado nesta execução:

```text
pfSense 192.168.6.49
  -> UDP/5514 na VM interna 192.168.6.50
  -> publicação Docker
  -> UDP/514 no Wazuh Manager
```

Controles confirmados:

- TCP/1514 permanece reservado aos Wazuh Agents;
- a superfície host do syslog é 192.168.6.50:5514/UDP nesta topologia;
- o Wazuh Manager possui receiver em UDP/514;
- `allowed-ips` restringe a origem ao pfSense derivado da topologia;
- o pfSense usa a interface/origem correspondente ao endereço da topologia;
- foram habilitados System Events, Firewall Events, DNS Events,
  General Authentication Events e Gateway Monitor Events;
- logging local do pfSense permanece habilitado;
- a regra de bloqueio DMZ -> rede interna gera log;
- três probes identificáveis da EP125 foram encontrados dentro dos datagramas
  de Remote Logging recebidos em 192.168.6.50:5514/UDP.

Estado declarativo:

`WAZUH_SYSLOG_RECEIVER=OPERACIONAL`

`PROMOCAO_RUNTIME=CONCLUIDA`

`PFSENSE_REMOTE_SYSLOG=TRANSPORTE_CORRELACIONADO_CONFIRMADO`

`CORRELACAO_RECEIVER_HOST=CONFIRMADA`

`WAZUH_DECODER_ALERT_ARCHIVE=PENDENTE`

`SIEM_E2E_COMPLETO=PENDENTE`

## Evidência de transporte

O teste inicial de 16/09/2026 confirmou, para a topologia então ativa:

- binding host: `192.168.6.50:5514/udp -> 514/udp`;
- receiver Wazuh: `connection=syslog`, `protocol=udp`, `allowed-ips=192.168.6.49`;
- 10 datagramas observados de `192.168.6.49:514` para
  `192.168.6.50:5514`;
- `BINDING_OK=1`;
- `RECEIVER_CONFIG_OK=1`;
- `PACKETS_SEEN=1`;
- `TRANSPORTE_PFSENSE_WAZUH=CONFIRMADO`;
- `FINAL=PASS` para o gate de transporte.

Naquela execução também houve 4 correspondências em `alerts.json`, mas elas não
foram tratadas como prova de ingestão porque não estavam correlacionadas por
timestamp/counter a um evento sintético específico.

Em 17/09/2026 foi executado um teste live adicional. A EP125 gerou três tuplas
TCP identificáveis sem payload:

```text
192.168.6.34:47101 -> 192.168.6.50:62101
192.168.6.34:47102 -> 192.168.6.50:62102
192.168.6.34:47103 -> 192.168.6.50:62103
```

Durante a mesma janela, a EP126 capturou exclusivamente Remote Logging com o
filtro BPF:

```text
src host 192.168.6.49 and dst host 192.168.6.50 and udp dst port 5514
```

Resultado:

```text
SYSLOG_UDP_DATAGRAM_BLOCKS=15
MATCHED_PROBE_INDICES=[1, 2, 3]
PROBE_1_MATCHES=3
PROBE_2_MATCHES=3
PROBE_3_MATCHES=3
PFSENSE_REMOTE_SYSLOG_LIVE=CONFIRMADO
CORRELACAO_INGESTAO_RECEIVER=CONFIRMADA
PASS=5
WARN=0
FAIL=0
FINAL=PASS
```

Nenhum payload bruto de syslog foi persistido; a evidência conserva apenas
metadados, contagens e hashes dos blocos correlacionados. Evidência consolidada:
`docs/evidencias/pfsense-wazuh-live-receiver-20260917.md`.

Essa prova fecha o caminho **pfSense -> receiver de host UDP/5514** com correlação
do estímulo sintético. Ela não é promovida automaticamente a E2E completo do
SIEM: ainda falta demonstrar, para esses mesmos eventos, a etapa de
**decoder/regra/archive/alert/indexação** dentro do Wazuh. Na validação atual,
`logall=no` e `logall_json=no`, portanto um syslog recebido que não produza alerta
pode não aparecer em `archives.json`/Threat Hunting.

## Procedimento de integração

O checkpoint `40-checkpoint-logging.sh` valida mais do que a presença do destino `@host:porta`. Para BSD `syslogd`, ele exige que o forwarding cubra System Events, Firewall Events, DNS Events, General Authentication Events e Gateway Monitor Events, ou uma regra global equivalente (`Everything`). Uma diretiva irrelevante como `mail.* @host:porta` não aprova o gate. O parser continua fail-closed para `syslog-ng`, cuja gramática é diferente. Para `General Authentication`, os seletores `auth.*;authpriv.*` só contam quando estão sob contexto irrestrito `!*`; um bloco limitado como `!sshd` não prova cobertura geral de autenticação. Além disso, a cobertura exige explicitamente prioridade completa (`auth.*` e `authpriv.*`); seletores restritos como `auth.emerg;authpriv.emerg` não aprovam o gate. Para `System Events`, o gate exige o conjunto canônico observado na configuração do pfSense: `*.notice`, `kern.debug`, `security.*` e `daemon.notice`; combinações excessivamente restritivas como `kern.emerg;security.emerg;daemon.emerg` não contam como cobertura suficiente.

O procedimento de reprodução deve usar os valores derivados da topologia, e não
copiar os literais observados nas execuções de 16–17/09/2026.

Variáveis canônicas:

```text
CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS
CONECTAEDUCA_WAZUH_SYSLOG_PORT
CONECTAEDUCA_PFSENSE_IPV4
```

`CONECTAEDUCA_WAZUH_SYSLOG_PORT` usa `5514` como padrão quando não sobrescrita.
O overlay `compose.vm-pfsense-syslog.yml` e o preparador
`12-preparar-wazuh-runtime-vm.sh` derivam o listener e `allowed-ips` desses
valores.

Para reproduzir em novo runtime:

1. materializar/carregar a topologia e promover o overlay de VM e a configuração renderizada do Manager;
2. confirmar o Manager saudável e a publicação `${CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS}:${CONECTAEDUCA_WAZUH_SYSLOG_PORT}/udp` no host da VM interna;
3. confirmar TCP/1514 inalterada para os Agents;
4. configurar o Remote Logging do pfSense para `${CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS}:${CONECTAEDUCA_WAZUH_SYSLOG_PORT}`;
5. usar como origem a interface/endereço correspondente a `${CONECTAEDUCA_PFSENSE_IPV4}`;
6. confirmar que o receiver renderizado restringe `allowed-ips` a `${CONECTAEDUCA_PFSENSE_IPV4}`;
7. restringir o conteúdo remoto às categorias necessárias;
8. gerar um evento de teste identificável e correlacioná-lo aos datagramas recebidos no listener de host;
9. separadamente, provar decoder/regra/archive/alert/indexação do mesmo evento dentro do Wazuh antes de declarar SIEM E2E completo;
10. registrar a evidência com os valores efetivos renderizados.

## Segurança e limites

- não instalar Wazuh Manager no pfSense;
- não instalar Wazuh Agent improvisado no firewall para substituir syslog;
- não abrir UDP/514 diretamente no host;
- manter a origem restrita ao IP do pfSense da topologia;
- não enviar logs para a Internet;
- syslog UDP neste laboratório não fornece confidencialidade nem autenticação
  criptográfica; transporte cifrado exigiria mudança específica posterior.
