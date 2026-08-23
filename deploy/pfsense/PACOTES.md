# Pacotes na VM pfSense

## Fase 1 — obrigatório

Nenhum pacote adicional.

A VM pfSense deve permanecer dedicada a:

- firewall;
- roteamento;
- NAT;
- segmentação;
- DNS/NTP conforme a topologia;
- logs do próprio firewall.

## NÃO instalar no pfSense

- Docker;
- ModSecurity;
- Nginx/PHP da aplicação;
- MariaDB;
- OpenBao;
- Wazuh Manager/Indexer/Dashboard;
- Ferret;
- Bacula core;
- Twingate nesta fase.

## ModSecurity

ModSecurity + OWASP CRS pertence à **VM DMZ**, dentro do container WAF.

## Avaliar somente depois da rede base

Pacotes como IDS/IPS, bloqueio adicional ou transporte de logs podem ser
avaliados mais adiante se fizerem parte da rubrica/escopo.

Não adicionar Suricata, Snort, pfBlockerNG ou syslog-ng na primeira subida
apenas porque estão disponíveis: cada pacote aumenta superfície, consumo e
complexidade de diagnóstico.
