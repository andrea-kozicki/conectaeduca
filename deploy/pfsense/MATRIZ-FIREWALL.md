# Matriz de firewall — ConectaEduca

Esta é a matriz alvo inicial. IPs são preenchidos somente quando o laboratório
entregar o endereçamento.

| ID | Origem | Destino | Protocolo/porta | Ação | Fase | Justificativa |
|---|---|---|---|---|---|---|
| FW-01 | WAN | INTERNA | qualquer | BLOCK | inicial/permanente | serviços internos não são publicados |
| FW-02 | WAN | WAF na VM_DMZ | TCP 443 | PASS | após app saudável | entrada HTTPS da aplicação |
| FW-03 | WAN | WAF na VM_DMZ | TCP 80 | PASS opcional | após app saudável | somente redirect HTTP -> HTTPS |
| FW-10 | VM_DMZ / PHP | VM_INTERNA / MariaDB | TCP 3306 | PASS | aplicação | acesso ao banco |
| FW-11 | DMZ | INTERNA | restante | BLOCK | inicial | menor privilégio entre zonas |
| FW-20 | VM_INTERNA / Bacula Director | VM_DMZ / Bacula FD | TCP 9102 | PASS | quando Bacula entrar | controle do File Daemon |
| FW-21 | VM_DMZ / Bacula FD | VM_INTERNA / Bacula Storage | TCP 9103 | PASS | quando Bacula entrar | envio de dados de backup |
| FW-22 | WAN/DMZ | Bacula Director TCP 9101 | BLOCK | permanente | administração do Bacula não é pública |
| FW-30 | VM_DMZ / Wazuh Agent | VM_INTERNA / Wazuh Manager | TCP 1514 | PASS | quando Agent entrar | eventos do agente |
| FW-31 | VM_DMZ / Wazuh Agent | VM_INTERNA / Wazuh Manager | TCP 1515 | PASS temporário/necessário | enrollment | registro do agente |
| FW-40 | VM_DMZ / PHP | relay SMTP externo | TCP 587 | PASS condicional | SMTP real | envio autenticado STARTTLS |
| FW-50 | WAN | MariaDB/OpenBao/Wazuh/Bacula | qualquer | BLOCK | permanente | não expor serviços internos |
| FW-60 | pfSense | VM_INTERNA / Wazuh Manager | UDP `CONECTAEDUCA_WAZUH_SYSLOG_PORT` (padrão 5514) | PASS | observabilidade | transporte syslog correlacionado até o receiver host; decoder/alert/archive/indexação Wazuh ainda pendentes |

## Observações

- WAF -> Nginx (8080) e Nginx -> PHP-FPM (9000) ficam dentro da rede Docker da
  própria VM DMZ e **não atravessam o pfSense**.
- OpenBao está atualmente restrito ao host interno; não criar regra DMZ ->
  OpenBao sem requisito explícito.
- Twingate não pertence à implantação de terça-feira.
- A regra FW-60 teve o listener promovido e o transporte ponta a ponta até a
  VM interna/receiver validado inicialmente em 16/09/2026. Na execução observada,
  o caminho foi `192.168.6.49 -> 192.168.6.50:5514/UDP -> Wazuh Manager 514/UDP`,
  com origem restringida pelo `allowed-ips`.
- Em 17/09/2026, três probes sintéticos distintos originados na EP125 foram
  correlacionados aos datagramas de Remote Logging recebidos em
  `192.168.6.50:5514/UDP`: `MATCHED_PROBE_INDICES=[1,2,3]`, com três ocorrências
  de cada tupla e `FINAL=PASS`.
- Esse resultado fecha o gate de **transporte correlacionado até o receiver de
  host**, mas não substitui a prova da camada analítica interna do Wazuh. O
  estado restante é `WAZUH_DECODER_ALERT_ARCHIVE=PENDENTE` e
  `SIEM_E2E_COMPLETO=PENDENTE`.
- A evidência live está em
  `docs/evidencias/pfsense-wazuh-live-receiver-20260917.md`.
- Em novas topologias, os valores devem ser derivados de
  `CONECTAEDUCA_PFSENSE_IPV4`, `CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS` e
  `CONECTAEDUCA_WAZUH_SYSLOG_PORT`.
