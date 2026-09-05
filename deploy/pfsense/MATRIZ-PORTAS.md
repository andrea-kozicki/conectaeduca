# Matriz de portas — ConectaEduca

A tabela distingue **fluxo arquitetural** de **resultado observado**. O teste de conectividade prova o comportamento visto pelas VMs; ele não substitui export administrativo das regras do pfSense.

| Porta | Fluxo arquitetural | Cruza pfSense? | Estado/resultado |
|---:|---|---|---|
| TCP 80 | cliente/WAN -> WAF DMZ; EP126 -> WAF para teste | sim | WAF previsto; EP126→EP125 alcançável no teste |
| TCP 443 | cliente/WAN -> WAF DMZ; EP126 -> WAF para teste | sim | EP126→EP125 alcançável no teste |
| TCP 8080 | WAF -> Nginx | não | privado na rede Docker DMZ |
| TCP 9000 | Nginx -> PHP-FPM | não | privado na rede Docker DMZ |
| TCP 3306 | PHP/DMZ -> MariaDB interna | sim | EP125→EP126 alcançável; EP126→EP125 não |
| TCP 1514 | Wazuh Agent DMZ -> Manager interna | sim | EP125→EP126 alcançável; agentes operacionais |
| TCP 1515 | enrollment Agent -> Manager | sim somente durante bootstrap | fechado/não alcançável após enrollment |
| TCP 443 admin | Dashboard Wazuh | não deve ser exposto à DMZ | acesso entre zonas bloqueado no teste |
| TCP 55000 | API Wazuh Manager | não deve ser exposta à DMZ | bloqueada no teste |
| TCP 9200 | Indexer API | não deve ser exposta | não publicada no host |
| TCP 9101 | Bacula Director/console | não publicar em WAN/DMZ | bloqueada entre zonas no teste |
| TCP 9102 | Director interna -> File Daemon DMZ | sim | EP126→EP125 alcançável |
| TCP 9103 | File Daemon DMZ -> Storage interna | sim | EP125→EP126 alcançável |
| TCP 8200 | OpenBao container API | não cruza pfSense no baseline | DMZ→interna bloqueado; host interno usa binding local |
| TCP 587 | PHP DMZ -> relay SMTP externo | outbound | somente se SMTP real estiver habilitado |
| TCP 22 | administração SSH | não é fluxo funcional entre zonas | bloqueado entre EP125/EP126 no teste |
| TCP 3389 | XRDP institucional | não é fluxo da aplicação | bloqueado entre EP125/EP126 no teste |
| TCP 5432 | PostgreSQL Bacula Catalog | interno ao núcleo Bacula | bloqueado entre zonas no teste |

## Resultado do teste de segmentação entre VMs

### EP126 → EP125

Alcançáveis:

- 80;
- 443;
- 9102.

Não alcançáveis no teste:

- 22;
- 3389;
- 3306;
- 5432;
- 8200;
- 9101;
- 9103;
- 1514;
- 1515;
- 55000.

### EP125 → EP126

Alcançáveis:

- 3306;
- 9103;
- 1514.

Não alcançáveis no teste:

- 22;
- 80;
- 443;
- 3389;
- 5432;
- 8200;
- 9101;
- 1515;
- 55000.

ICMP entre as duas VMs permaneceu bloqueado, embora cada VM alcançasse seu gateway.

## Interpretação

O resultado observado é coerente com uma política de allowlist entre zonas: fluxos funcionais atravessam e superfícies administrativas permanecem indisponíveis.

Como a conta de administração do laboratório no pfSense é limitada, a documentação deve distinguir:

- **comportamento comprovado pela rede**;
- **regra exata/configuração interna do pfSense**, que só pode ser afirmada quando houver evidência administrativa correspondente.
