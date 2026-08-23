# pfSense — ConectaEduca / Fase 1

Este bloco prepara a implantação do pfSense **antes dos containers**.

## Arquitetura

```text
Rede externa / laboratório
          |
         WAN
      +--------+
      |pfSense |
      +---+----+
          |
     +----+----------------+
     |                     |
    DMZ                 INTERNA
     |                     |
Ubuntu DMZ            Ubuntu Interna
8 GiB / 180 GiB       16 GiB / 180 GiB
```

A VM pfSense permanece dedicada a firewall, roteamento e segmentação.

## O que os scripts fazem

Todos os scripts são **somente leitura**.

- `00-preflight-pfsense.sh`: inventaria host, interfaces, rotas, PF, DNS, memória e disco.
- `10-checkpoint-interfaces.sh`: valida as três interfaces e os IPs esperados.
- `20-checkpoint-firewall.sh`: coleta regras PF/NAT compiladas para revisão.
- `90-coletar-evidencias.sh`: reúne relatórios em `.tar.gz` sem incluir `config.xml`.

Eles NÃO:

- editam `/conf/config.xml`;
- criam regras;
- alteram NAT;
- habilitam SSH;
- instalam pacotes;
- manipulam credenciais;
- configuram automaticamente interfaces.

## Ordem de terça-feira

1. Confirmar no hypervisor as três NICs e respectivos MACs.
2. Console do pfSense: atribuir WAN, DMZ e INTERNA.
3. Console: configurar IPs/gateway entregues pelo laboratório.
4. Rodar `00-preflight-pfsense.sh`.
5. Preencher `/tmp/conectaeduca-pfsense.env`.
6. Rodar `10-checkpoint-interfaces.sh`.
7. WebGUI: aliases, firewall, NAT e administração conforme os checklists.
8. Rodar `20-checkpoint-firewall.sh`.
9. Testar segmentação a partir das duas VMs.
10. Exportar backup do pfSense pela GUI.
11. Rodar `90-coletar-evidencias.sh`.

## ModSecurity

O ModSecurity/OWASP CRS **não é instalado no pfSense**.

Ele permanece na VM Ubuntu DMZ no container WAF, à frente do Nginx e do
PHP-FPM:

```text
WAN -> pfSense -> WAF/ModSecurity CRS -> Nginx -> PHP-FPM
```

O pfSense filtra e roteia. O ModSecurity inspeciona HTTP/HTTPS em camada de
aplicação.
