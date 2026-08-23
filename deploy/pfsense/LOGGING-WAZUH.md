# Logging pfSense -> Wazuh

## Estado desta fase

O pfSense deve gerar logs localmente desde a primeira implantação, mas a regra
de envio remoto para o Wazuh **não deve ser criada às cegas**.

O Compose atual do Wazuh publica para a VM:

- TCP 1514: Agent;
- TCP 1515: enrollment;
- Dashboard conforme binding administrativo.

Ele não define nesta fase um listener syslog UDP/TCP 514 dedicado.

Portanto:

`PFSENSE_REMOTE_SYSLOG_PARA_WAZUH=PENDENTE`

## Quando integrar

1. definir receptor syslog na VM interna;
2. definir protocolo e porta;
3. restringir origem ao IP do pfSense;
4. configurar Remote Logging no pfSense;
5. confirmar recepção no SIEM;
6. registrar regra na matriz de firewall;
7. testar perda/recuperação do receptor.

## O que não fazer

- não instalar Wazuh Manager no pfSense;
- não instalar um Wazuh Agent improvisado no firewall apenas para contornar a
  ausência do receptor;
- não abrir porta 514 na VM interna sem serviço realmente ouvindo;
- não enviar logs para a Internet.

Se posteriormente for exigido transporte syslog cifrado, avaliar mecanismo
específico nessa fase, sem alterar a implantação base do firewall.
