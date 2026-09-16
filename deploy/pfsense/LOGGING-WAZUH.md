# Logging pfSense -> Wazuh

## Estado operacional

A integração de Remote Logging do pfSense com o Wazuh foi promovida e validada
ponta a ponta em 16/09/2026.

Fluxo operacional:

```text
pfSense 192.168.6.49
  -> UDP/5514 na VM interna 192.168.6.50
  -> publicação Docker
  -> UDP/514 no Wazuh Manager
```

Controles confirmados:

- TCP/1514 permanece reservado aos Wazuh Agents;
- a superfície host do syslog é 192.168.6.50:5514/UDP;
- o Wazuh Manager recebe o tráfego em UDP/514;
- `allowed-ips` restringe a origem a 192.168.6.49;
- o pfSense usa a interface/origem LAN49;
- foram habilitados System Events, Firewall Events, DNS Events,
  General Authentication Events e Gateway Monitor Events;
- logging local do pfSense permanece habilitado.

Estado declarativo:

`WAZUH_SYSLOG_RECEIVER=OPERACIONAL`

`PROMOCAO_RUNTIME=CONCLUIDA`

`PFSENSE_REMOTE_SYSLOG=E2E_APROVADO`

## Evidência E2E

O teste de 16/09/2026 confirmou:

- binding host: `192.168.6.50:5514/udp -> 514/udp`;
- receiver Wazuh: `connection=syslog`, `protocol=udp`, `allowed-ips=192.168.6.49`;
- 10 datagramas observados de `192.168.6.49:514` para
  `192.168.6.50:5514`;
- indício de ingestão no Wazuh: 4 correspondências em `alerts.json`;
- `BINDING_OK=1`;
- `RECEIVER_CONFIG_OK=1`;
- `PACKETS_SEEN=1`;
- `TRANSPORTE_PFSENSE_WAZUH=CONFIRMADO`;
- `FINAL=PASS`.

A captura de transporte foi feita apenas sobre cabeçalhos de rede; nenhum payload
de syslog foi persistido na evidência.

## Procedimento de integração

Para reproduzir em novo runtime:

1. promover o overlay de VM e a configuração renderizada do Manager;
2. confirmar o Manager saudável e a publicação UDP/5514 no IP da VM interna;
3. confirmar TCP/1514 inalterada para os Agents;
4. configurar o Remote Logging do pfSense para `192.168.6.50:5514`;
5. usar como origem o endereço/interface correspondente a `192.168.6.49`;
6. restringir o conteúdo remoto às categorias necessárias;
7. confirmar chegada dos datagramas ao host;
8. confirmar ingestão/correlação no Wazuh;
9. registrar a evidência.

## Segurança e limites

- não instalar Wazuh Manager no pfSense;
- não instalar Wazuh Agent improvisado no firewall para substituir syslog;
- não abrir UDP/514 diretamente no host;
- manter a origem restrita ao IP do pfSense da topologia;
- não enviar logs para a Internet;
- syslog UDP neste laboratório não fornece confidencialidade nem autenticação
  criptográfica; transporte cifrado exigiria mudança específica posterior.
