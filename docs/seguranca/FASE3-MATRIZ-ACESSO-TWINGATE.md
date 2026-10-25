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


## Atualização de baseline — 25/10/2026, 11:06 BRT (Grupo A)

**Evidência executada nas VMs, sem alterações operacionais:**
- EP125: HTTPS `https://192.168.6.34/login.php` validado em leitura local com TLS e HTTP 200; endpoint de chave pública envelope v2 e JavaScript de criptografia disponíveis (preflight PR #205).
- EP125: Docker/Wazuh Agent/Bacula FD ativos, PHP-FPM/WAF/Nginx `running/healthy`, WAF publicado somente em 80/443 de `192.168.6.34`, Nginx e PHP sem host port bindings; porta 8088 não escuta. Isso **não comprova** bloqueio do upstream via bridge Docker.
- EP126: Docker/Wazuh Agent/Bacula FD ativos, NTP sincronizado (assim como EP125); Manager/Dashboard/Indexer Wazuh, Director/PgBouncer/Catalog/Storage Bacula e MariaDB/OpenBao saudáveis nos respectivos healthchecks. Bacularis WebAPI executando sem healthcheck.
- EP126 → EP125 TCP443 `ALCANCAVEL`; **TLS não validado**. Diagnóstico OpenSSL/Python com verificação obrigatória: `VERIFY_CODE=20`, `VERIFY_MESSAGE=unable to get local issuer certificate`. **Não afirmar nome/SAN inválidos:** a cadeia não foi verificada; confirmar CA emissora/intermediária de EP125 e trust store de EP126, instalar CA institucional por procedimento aprovado e retestar cadeia + nome IP (sem `-k`/`verify=False`).
- Auditoria PHP → Wazuh: marcador sintético EP126-F2-0062 correlacionado à regra 110250, agente 001; rotação/retenção/privacidade ainda pendentes.
- Bacula: Bacularis com conta `teste` **deliberadamente de privilégio mínimo** mostra histórico de Jobs (05–06/10) sem erro do Director; lista de definições Jobs vazia para esse usuário **não demonstra** inexistência de agendamentos ou falha de autorização. Validar schedules/backup recente/restore com operador autorizado, sem elevar privilégios de `teste`.

**Gates ainda abertos para 28/10 (horário 15h solicitado, não presumir autorização/confirmacão do suporte):**
1. Autorização institucional explícita e operador responsável pelas alterações na EP126/pfSense/ACLs; escopo de egress Twingate e rollback;
2. Cadeia TLS confiável em EP126 e dispositivo Client aprovado, incluindo SAN para destino usado;
3. Decisão sobre rota HTTPS direta: se permanecer disponível, demonstrar somente **acesso controlado via Twingate**, não isolamento exclusivo; a mesma porta 443 não segrega rotas `/admin`;
4. ACL da bridge Docker/WAF e políticas de firewall pfSense aprovadas/revisadas, sem assumir que Twingate isola contêineres;
5. Recursos estritos por endereço/porta e grupos mínimos; impedir publicação de DB/OpenBao/Bacula diretamente;
6. Plano de operação e revogação de tokens do Connector sem registrar segredos em evidências.

**Status:** inventários e diagnósticos autônomos concluídos; implementação Zero Trust ainda **NÃO COMPROVADA**; Pentest B e testes BOLA/IDOR permanecem posteriores à implantação autorizada.
