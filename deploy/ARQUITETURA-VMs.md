# Arquitetura das VMs do ConectaEduca

## Decisão de capacidade

O ambiente utiliza três VMs principais:

| VM | RAM | Disco | Papel |
|---|---:|---:|---|
| pfSense | conforme laboratório | conforme laboratório | firewall/roteamento/segmentação |
| Ubuntu DMZ | 8 GiB | 180 GiB | aplicação e controles expostos |
| Ubuntu Interna | 16 GiB | 180 GiB | dados, SIEM, segredos, DLP e backup |

A VM interna recebe 16 GiB porque concentra os componentes de maior consumo e
maior persistência: MariaDB, Wazuh Manager/Indexer/Dashboard, OpenBao, Ferret e
o núcleo do Bacula.

## Posicionamento lógico

```text
Internet
   |
pfSense
   |
   +---------------- DMZ ----------------+
   | Ubuntu 8 GiB / 180 GiB             |
   | - ModSecurity/CRS                  |
   | - Nginx                            |
   | - PHP-FPM                          |
   | - componentes SMTP necessários     |
   | - Bacula File Daemon nativo        |
   +-------------------------------------+
                 |
                 | fluxos mínimos autorizados
                 |
   +-------------v------ REDE INTERNA ----------------+
   | Ubuntu 16 GiB / 180 GiB                         |
   | - MariaDB da aplicação                          |
   | - OpenBao                                       |
   | - Ferret Scan                                   |
   | - Wazuh Manager / Indexer / Dashboard           |
   | - Bacula Director                               |
   | - Bacula Storage Daemon                         |
   | - PostgreSQL dedicado ao Catalog do Bacula      |
   | - Bacula File Daemon nativo                     |
   +-------------------------------------------------+
```

O Kali permanece fora da operação normal e será usado somente no pentest final.

## Princípios

1. A DMZ não armazena o repositório principal de backups.
2. O backup não cria uma rede Docker plana entre DMZ e rede interna.
3. Agentes que precisam ler o filesystem do host são preferencialmente nativos.
4. Containers não recebem Docker socket.
5. Segredos não entram em Git, handoff ou relatórios de checkpoint.
6. Serviços administrativos permanecem privados; acesso remoto futuro será
   tratado pelo Twingate e pelas regras do pfSense.
7. O desenho local deve permanecer parametrizável para migração às VMs.

## Limitação conhecida do laboratório

O Bacula Storage Daemon ficará inicialmente na mesma VM interna de parte dos
dados protegidos. Isso protege contra deleção lógica, corrupção seletiva,
falha/recriação de containers e erros operacionais, mas **não protege contra
perda total da VM ou do disco virtual de 180 GiB**.

A arquitetura deve permitir, sem redesenho do catálogo ou dos clientes, mover
o Storage Daemon/volumes para armazenamento externo ou uma VM de backup em uma
evolução posterior.
