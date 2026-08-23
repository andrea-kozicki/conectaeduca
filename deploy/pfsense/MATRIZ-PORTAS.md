# Matriz de portas — ConectaEduca

| Porta | Fluxo | Cruza pfSense? | Fase |
|---:|---|---|---|
| TCP 80 | WAN -> WAF DMZ, redirect para HTTPS | sim | opcional após app |
| TCP 443 | WAN -> WAF DMZ | sim | após app |
| TCP 8080 | WAF -> Nginx | não, Docker DMZ | interno |
| TCP 9000 | Nginx -> PHP-FPM | não, Docker DMZ | interno |
| TCP 3306 | PHP DMZ -> MariaDB interna | sim | aplicação |
| TCP 1514 | Wazuh Agent DMZ -> Manager interna | sim | quando Agent entrar |
| TCP 1515 | enrollment Agent -> Manager | sim | quando necessário |
| TCP 443 | acesso administrativo ao Wazuh Dashboard | somente rede administrativa/interna | posterior |
| TCP 9101 | Bacula Console/Director | não publicar em WAN/DMZ | Bacula |
| TCP 9102 | Director interna -> File Daemon DMZ | sim | Bacula |
| TCP 9103 | File Daemon DMZ -> Storage interna | sim | Bacula |
| TCP 587 | PHP DMZ -> relay SMTP externo | sim/outbound | se SMTP real |
| TCP 18200 host | OpenBao local -> container 8200 | não deve cruzar pfSense no baseline | interna |

## WAF

O ponto publicado da aplicação é o WAF/ModSecurity CRS. Nginx e PHP-FPM não
devem ser publicados diretamente na WAN.
