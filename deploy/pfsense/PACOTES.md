# Pacotes na VM pfSense

## Princípio

O pfSense permanece dedicado a firewall, roteamento, NAT, segmentação e logs do próprio firewall. Pacotes adicionais entram por **subfase**, não na primeira subida.

## Subfase A — baseline de rede

**Nenhum pacote adicional.**

Primeiro provar:

1. interfaces e endereçamento;
2. rotas;
3. regras mínimas;
4. NAT necessário;
5. conectividade positiva prevista;
6. conectividade negativa/default deny.

A razão é operacional: adicionar IDS/IPS antes de estabilizar a rede amplia a quantidade de variáveis durante o diagnóstico.

## Subfase B — IDS após rede aprovada

Depois do baseline de rede, o único pacote adicional previsto no projeto é:

- **Suricata**, inicialmente em IDS/alert-only.

IPS/bloqueio só deve ser considerado depois de confirmar regras, alertas e ausência de falso positivo incompatível com o laboratório.

## Não instalar no pfSense

- Git;
- Docker;
- ModSecurity;
- Nginx/PHP;
- MariaDB;
- OpenBao;
- Wazuh Manager/Indexer/Dashboard;
- Ferret;
- Bacula core;
- Twingate;
- syslog-ng sem necessidade comprovada.

## Separação de responsabilidades

- pfSense: L3/L4, roteamento, filtragem e segmentação;
- ModSecurity/CRS: inspeção HTTP na DMZ;
- Wazuh: SIEM/endpoint;
- Suricata: IDS/IPS de rede quando habilitado;
- Twingate: Zero Trust posterior ao Pentest A.

Essa redação substitui a interpretação conflitante anterior entre "nenhum pacote na primeira subida" e "instalar Suricata": as duas decisões pertencem a momentos diferentes.
