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
| FW-60 | pfSense | coletor/Wazuh | A DEFINIR | PENDENTE | observabilidade | receptor syslog ainda não está definido |

## Observações

- WAF -> Nginx (8080) e Nginx -> PHP-FPM (9000) ficam dentro da rede Docker da
  própria VM DMZ e **não atravessam o pfSense**.
- OpenBao está atualmente restrito ao host interno; não criar regra DMZ ->
  OpenBao sem requisito explícito.
- Twingate não pertence à implantação de terça-feira.
- A regra FW-60 permanece pendente até existir um receptor syslog definido na
  VM interna.
