# Logging pfSense -> Wazuh

## Estado desta fase

A arquitetura do receptor remoto está definida no repositório, mas a promoção
na VM interna e o teste ponta a ponta ainda devem ser executados antes de
declarar a integração operacional.

Fluxo versionado para a VM interna:

```text
pfSense
  -> UDP/${CONECTAEDUCA_WAZUH_SYSLOG_PORT} na VM_INTERNA
     (5514 por padrão)
  -> publicação Docker
  -> UDP/514 no Wazuh Manager
```

No perfil de VM:

- TCP 1514 permanece reservado aos Wazuh Agents;
- `CONECTAEDUCA_WAZUH_SYSLOG_PORT` define a porta UDP no host, com 5514
  como padrão;
- o Wazuh Manager recebe o tráfego em UDP 514;
- `allowed-ips` é renderizado com `CONECTAEDUCA_PFSENSE_IPV4` da topologia;
- TCP 1515 continua sendo superfície temporária de enrollment, não parte do
  fluxo de syslog.

Estado declarativo:

`WAZUH_SYSLOG_RECEIVER=DEFINIDO_NO_REPOSITORIO`

`PROMOCAO_RUNTIME=PENDENTE`

`PFSENSE_REMOTE_SYSLOG=PENDENTE_DE_VALIDACAO_E2E`

## Procedimento de integração

1. promover o overlay de VM e a configuração renderizada do Manager;
2. confirmar o Manager saudável e a publicação UDP na porta configurada por
   `CONECTAEDUCA_WAZUH_SYSLOG_PORT` (5514 por padrão) no IP da VM interna;
3. confirmar TCP/1514 inalterada para os Agents;
4. configurar o Remote Logging do pfSense para o IP da VM interna e para a
   mesma `CONECTAEDUCA_WAZUH_SYSLOG_PORT` usada pelo Wazuh (5514 por padrão);
5. usar como origem o endereço do pfSense definido na mesma topologia;
6. confirmar chegada dos datagramas ao host;
7. confirmar ingestão pelo Wazuh e a correlação esperada;
8. registrar a evidência e somente então declarar o fluxo ponta a ponta
   operacional.

## Segurança e limites

- não instalar Wazuh Manager no pfSense;
- não instalar Wazuh Agent improvisado no firewall para substituir syslog;
- não abrir UDP/514 diretamente no host: a superfície publicada é a porta
  `CONECTAEDUCA_WAZUH_SYSLOG_PORT` (5514 por padrão);
- manter a origem restrita ao IP do pfSense da topologia;
- não enviar logs para a Internet;
- syslog UDP neste laboratório não fornece confidencialidade nem autenticação
  criptográfica; se transporte cifrado for requisito, tratá-lo em mudança
  específica posterior.

O receptor definido no repositório não equivale, por si só, a evidência de
ingestão ponta a ponta. Essa evidência deve ser produzida após a promoção.
