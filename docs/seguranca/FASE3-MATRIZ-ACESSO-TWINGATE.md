# Matriz de acesso — Fase 3 / Twingate (proposta, sem implantação)

**Regras gerais:** acesso por *recurso individual + grupo + MFA + porta mínima*, sem Resources do tipo CIDR amplo, sem `Everyone`, sem acesso direto a MariaDB/Catalog/OpenBao/Bacula por Twingate. Todas as portas não comprovadas ficam como `PENDENTE`. Papéis de usuário da aplicação **não** dão acesso à infraestrutura.

| ID | Endpoint | Porta | Público | TG-OPERACAO | TG-SEGURANCA | TG-ADMIN | TG-BACKUP | Sem grupo |
|---|---|---|---|---|---|---|---|---|
| WEB-PUBLIC | EP125 WAF `192.168.6.34` | TCP443 | **ALLOW**, com RBAC PHP | Público | Público | Público | Público | Público |
| WEB-ZT-TESTE (opcional) | EP125 WAF | TCP443 | público direto existe | DENY | DENY | **ALLOW via Client**, mas não isola /admin | DENY | DENY |
| ADMIN-PHP-PRIVADO* | Entrada distinta a projetar | TCP443 | **DENY** após implantação | DENY | DENY | **ALLOW + MFA** | DENY | DENY |
| MGMT-EP126-SSH | EP126 host | TCP22 | DENY | **ALLOW** se autorização/host ACL OK | condicionado | **ALLOW** | condicionado | DENY |
| MGMT-EP125-SSH | EP125 host | TCP22 | DENY | DENY | DENY | **ALLOW** se rota/firewall OK | DENY | DENY |
| SOC-WAZUH | Wazuh Dashboard privado | HTTPS/porta por confirmar | DENY | DENY | **ALLOW + MFA** | condicionado | DENY | DENY |
| BK-BACULARIS | Interface Bacularis privada | HTTPS/porta por confirmar | DENY | DENY | DENY | condicionado | **ALLOW + MFA** | DENY |
| OPENBAO | EP126 local | Nenhum Resource | DENY | DENY | DENY | DENY por padrão | DENY | DENY |
| APP-MARIADB | EP126 somente PHP | Nenhum Resource | DENY | DENY | DENY | DENY por padrão | DENY | DENY |
| BACULA-INTERNO | PgBouncer/Catalog/910x | Nenhum Resource | DENY | DENY | DENY | DENY por padrão | DENY | DENY |

`*` Não confundir `admin.conectaeduca.local` no **mesmo** IP:443 do WAF público com isolamento de rede. Até criar uma entrada privada distinta **e** negar `/admin` pela rota pública, a proteção permanece aplicativo/WAF/RBAC/MFA; no relatório, classificar isolamento de rede admin como **NÃO DEMONSTRADO**.

## Gate obrigatório de cada novo Resource

1. Confirmar serviço real (listener, endereço/bind, protocolo, TLS, firewall e autorização).
2. Confirmar que o Connector daquela Remote Network consegue alcançá-lo **sem permitir movimentação lateral indevida**.
3. Configurar porta TCP específica; verificar restrições no Admin Console (defaults amplos são inseguros).
4. Atribuir apenas os grupos desta matriz; MFA e device policy compatíveis.
5. Fazer **teste positivo**, **negativo por outra identidade**, **negativo sem Client**, **negativo a portas extras**.
6. Salvar evidências sanitizadas e hash; anotar limitações de caminho público/fallback.

## Papéis PHP e Groups Twingate não são sinônimos

`usuario`, `empresa` e `admin` descrevem autorização **dentro da aplicação**. O Twingate governa **a rede** e os Resources privados. Um operador do SOC pode não ter perfil `admin` PHP e um `admin` PHP não é automaticamente root da EP126.

## Bloqueadores vistos na EP126-F2-0014 (21/10/2026)

- **PASS:** Docker, Compose, baseline Compose, EP126 → EP125 TCP443.
- **GAP:** imagem fixada ainda não presente; Connector não existe, tenant/egress/grupos/Resources não validados.
- **WARN:** HTTPS sem confiança comprovada na CA; NTP=no.
- **Sem mudanças:** relatório de preflight e matriz de proposta, não prova de implantação.

**Prazo:** fechamento da implementação em 07/11, Pentest B de 08 a 14/11 e apresentação em 17/11.
