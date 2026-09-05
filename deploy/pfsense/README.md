# pfSense — ConectaEduca

## Papel arquitetural

O pfSense é a fronteira entre rede externa, DMZ e rede interna. Ele permanece dedicado a:

- roteamento;
- filtragem;
- NAT quando necessário;
- segmentação;
- logging do firewall;
- Suricata como incremento posterior ao baseline de rede.

O WAF continua na VM DMZ. Wazuh, OpenBao, MariaDB, Ferret e Bacula core continuam na VM interna.

## Evolução do trabalho

### 1. Planejamento

Foram versionados:

- checklists de console/WebGUI;
- matriz de firewall;
- matriz de portas;
- scripts de checkpoint somente leitura;
- runbook;
- preparação de Suricata.

### 2. Implantação

As VMs operacionais usadas no laboratório são:

- EP125 / DMZ: `192.168.6.34/28`;
- EP126 / interna: `192.168.6.50/28`.

O acesso administrativo ao pfSense é limitado pela infraestrutura institucional. O projeto não tenta contornar essa limitação e não depende de SSH no firewall.

### 3. Validação por comportamento

Foram executados testes TCP nos dois sentidos.

Resultado resumido:

```text
EP126 -> EP125
  PASS: 80, 443, 9102
  BLOCK: 22, 3389, 3306, 5432, 8200, 9101, 9103, 1514, 1515, 55000

EP125 -> EP126
  PASS: 3306, 9103, 1514
  BLOCK: 22, 80, 443, 3389, 5432, 8200, 9101, 1515, 55000
```

ICMP entre as VMs permaneceu bloqueado; os gateways continuaram alcançáveis.

Isso comprova o **efeito de segmentação observado**: portas funcionais selecionadas atravessam, enquanto superfícies administrativas não atravessam no teste.

O resultado não deve ser apresentado como auditoria integral das regras internas do pfSense, porque a conta disponível não possui privilégio administrativo completo.

## Suricata — sem contradição de fases

O projeto usa duas subfases:

1. **rede base:** nenhum pacote adicional; provar roteamento/firewall primeiro;
2. **IDS:** instalar Suricata depois do baseline aprovado, inicialmente em alert-only.

Portanto, "não instalar Suricata na primeira subida" e "Suricata é o pacote adicional previsto" são decisões compatíveis quando associadas às subfases corretas.

## Administração institucional

Não alterar ou endurecer às cegas serviços usados pela infraestrutura da PUC.

Em particular:

- não habilitar SSH no pfSense para contornar limitação de GUI;
- não editar `/conf/config.xml` manualmente;
- não tentar elevar privilégios da conta fornecida;
- não modificar XRDP/SSSD/cloud-init das VMs sem necessidade e autorização.

## Evidências

A evidência de rede deve preferir:

- resultados de conectividade positiva/negativa;
- screenshots permitidos da WebGUI;
- relatórios dos checkpoints;
- matriz de portas atualizada.

Quando a interface administrativa não permite inspecionar toda a regra, registrar a limitação em vez de inferir detalhes não comprovados.

## NTP

Os diagnósticos das duas VMs registraram serviço NTP ativo, mas relógio ainda não sincronizado.

Essa dependência está sendo tratada com o suporte institucional porque afeta correlação temporal de:

- Wazuh;
- pfSense;
- Bacula;
- evidências de pentest.

O projeto não deve substituir a configuração institucional por conta própria apenas para eliminar o warning.
