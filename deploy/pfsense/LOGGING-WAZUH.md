# Logging pfSense -> Wazuh

## Estado operacional

A integração de Remote Logging do pfSense com o Wazuh foi promovida e validada
ponta a ponta em 16/09/2026.

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
- o Wazuh Manager recebe o tráfego em UDP/514;
- `allowed-ips` restringe a origem ao pfSense derivado da topologia;
- o pfSense usa a interface/origem correspondente ao endereço da topologia;
- foram habilitados System Events, Firewall Events, DNS Events,
  General Authentication Events e Gateway Monitor Events;
- logging local do pfSense permanece habilitado.

Estado declarativo:

`WAZUH_SYSLOG_RECEIVER=OPERACIONAL`

`PROMOCAO_RUNTIME=CONCLUIDA`

`PFSENSE_REMOTE_SYSLOG=E2E_APROVADO`

## Evidência E2E

O teste de 16/09/2026 confirmou, para a topologia então ativa:

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

O procedimento de reprodução deve usar os valores derivados da topologia, e não
copiar os literais observados na execução de 16/09/2026.

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
8. confirmar chegada dos datagramas ao host;
9. confirmar ingestão/correlação no Wazuh;
10. registrar a evidência com os valores efetivos renderizados.

## Segurança e limites

- não instalar Wazuh Manager no pfSense;
- não instalar Wazuh Agent improvisado no firewall para substituir syslog;
- não abrir UDP/514 diretamente no host;
- manter a origem restrita ao IP do pfSense da topologia;
- não enviar logs para a Internet;
- syslog UDP neste laboratório não fornece confidencialidade nem autenticação
  criptográfica; transporte cifrado exigiria mudança específica posterior.
