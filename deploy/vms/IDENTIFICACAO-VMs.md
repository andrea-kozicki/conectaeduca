# Identificação padronizada das VMs — ConectaEduca

A identificação abaixo deve ser usada em console, terminal, documentação,
prints/evidências e arquivos de implantação.

| VM_ID | Hostname | Sistema | Papel | Classe planejada |
|---|---|---|---|---|
| `CE-PFSENSE` | `conectaeduca-pfsense` | pfSense | firewall, roteamento e segmentação | VM dedicada |
| `CE-UBUNTU-DMZ` | `conectaeduca-dmz` | Ubuntu | aplicação/WAF e serviços da DMZ | 8 GiB RAM / 180 GB |
| `CE-UBUNTU-INT` | `conectaeduca-interna` | Ubuntu | dados, SIEM, segredos, DLP e backup | 16 GiB RAM / 180 GB |

## Regra operacional

Antes de executar qualquer script, confirmar visualmente:

```text
VM_ID
hostname
papel
IP esperado
```

O `00-preflight-ubuntu.sh` imprime `VM_ID`, `VM_ROLE`,
`HOSTNAME_ESPERADO` e `HOSTNAME_ATUAL`.

No stage `base`, hostname divergente é apenas aviso porque a VM ainda pode estar
em preparação.

Nos stages `network` e `deploy`, hostname divergente reprova o checkpoint para
evitar implantação na máquina errada.

## Serviços por VM

### CE-PFSENSE

- pfSense;
- firewall;
- NAT/roteamento;
- segmentação WAN/DMZ/interna;
- sem containers da aplicação.

### CE-UBUNTU-DMZ

- ModSecurity + OWASP CRS;
- Nginx;
- PHP-FPM;
- integração SMTP quando habilitada;
- Bacula File Daemon nativo.

### CE-UBUNTU-INT

- MariaDB;
- Wazuh Manager / Indexer / Dashboard;
- OpenBao;
- Ferret Scan DLP;
- Bacula Director / Storage / Catalog;
- Bacula File Daemon nativo.

Twingate permanece fora da fase 1.

## Convenção de IP usada pelos scripts da fase 1

Para acompanhar a configuração operacional do laboratório, o cartão de
topologia usa três endereços explícitos:

```text
CONECTAEDUCA_PFSENSE_IPV4
CONECTAEDUCA_DMZ_IPV4
CONECTAEDUCA_INTERNA_IPV4
```

O objetivo do cartão é identificar a máquina e despachar o conjunto correto de
serviços. Ele não tenta inferir ou reconfigurar internamente o pfSense.
