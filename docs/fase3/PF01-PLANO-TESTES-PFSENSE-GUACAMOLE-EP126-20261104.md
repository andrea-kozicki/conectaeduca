# PF-01 — Plano de testes pfSense, Guacamole e EP126

**ConectaEduca / Experiência Criativa 8 — 04/11/2026 — responsável técnica: Andréa Kozicki.**

**Natureza:** documento de planejamento. Nenhuma alteração de regras, VM, XRDP, Twingate ou serviço foi executada nesta elaboração. Plano para execução futura com suporte institucional, dentro do PA-01 e dos testes de regressão da Fase 3.


## 0. Limites de acesso e divisão executável de responsabilidades

**Correção da responsável (04/11): Andréa tem acesso operacional somente às VMs EP125 e EP126. Não possui acesso administrativo ao servidor Guacamole/guacd.** O uso do portal Guacamole como **cliente** para entrar na EP126 não concede acesso às configurações administrativas do servidor Guacamole, ao serviço guacd, aos logs do guacd ou à origem da conexão no lado institucional. O plano **não deve solicitar a ela** abertura de configuração, edição de conexões ou logs do servidor Guacamole.

| Parte | Responsável executante | Acesso necessário | Entrega sem credenciais |
| --- | --- | --- | --- |
| Diagnóstico da EP126 | Andréa na EP126 | Terminal da VM, permissões já existentes | Estado de xrdp/xrdp-sesman, listeners 3389/3350 e falha local Xvnc se observável |
| Diagnóstico da EP125 | Andréa na EP125 | Terminal da VM, permissões já existentes | Conexão dirigida EP125→EP126:3389 para avaliar **somente esta origem** (não equivale a teste do guacd) |
| Smoke de Guacamole | Andréa como usuária final | Portal normalmente oferecido à turma | Login e desktop visíveis PASS/FAIL, hora aproximada e erro na interface, sem credenciais |
| Origem de guacd e configuração da conexão | **Suporte/admin do Guacamole** | Administração institucional de Guacamole/guacd | Origem IP/interface, destino EP126, porta/protocolo e momento do erro, sem senha |
| Rastreamento de pacotes/rules, backup e reversão do pfSense | **Suporte institucional ou operador expressamente habilitado** | Firewall, Config History, logs/tracker e console fora de banda | Identificador da regra, interface ingressante, decisão e diff sanitizado |

**Sem acesso ao servidor Guacamole, nenhum teste executado da EP125 pode provar que o tráfego real de guacd tenha vindo da EP125.** Da mesma forma, uma sessão XRDP autenticada seguida de falha Xvnc no loopback da EP126 não prova bloqueio pfSense. Se suporte não puder fornecer a origem/protocolo do guacd e o backup/console, a fase de reativação fica **BLOQUEADA**, mas os testes passivos nas duas VMs continuam possíveis.

### Comandos exclusivamente de leitura que Andréa pode usar depois nas VMs

**EP126 — listeners e serviços**, sem sudo, sem reinício e sem ler logs sensíveis:

~~~bash
echo '=== PF01 VM EP126 — XRDP/Xvnc somente leitura ==='
for svc in xrdp xrdp-sesman; do
  printf 'SERVICO=%s ESTADO=' "$svc"
  systemctl is-active "$svc" 2>/dev/null || true
done
ss -lnt | awk 'NR == 1 || /:3389[[:space:]]|:3350[[:space:]]|:5910[[:space:]]/'
echo 'CONFIGURACAO_ALTERADA=NAO'
~~~

**EP125 — teste de transporte para EP126**, sem precisar de GUI ou acesso administrativo Guacamole, limitado ao RDP TCP/3389; **esta é somente a origem EP125, não a origem real de guacd**:

~~~bash
python3 - <<'PY'
import socket
host, port = '192.168.6.50', 3389
try:
    with socket.create_connection((host, port), timeout=3):
        print('PF01_EP125_EP126_3389=TCP_CONECTOU')
except (OSError, TimeoutError):
    print('PF01_EP125_EP126_3389=TCP_NAO_CONECTOU')
print('ORIGEM_GUACD_DEMONSTRADA=NAO')
print('SERVICOS_MODIFICADOS=NAO')
PY
~~~

A conectividade positiva desse segundo teste demonstra somente alcançabilidade de 3389 entre as VMs naquele momento; não prova sucesso de Guacamole, autenticação ou segmentação para terceiros. Uma negativa não identifica qual firewall/host/rede bloqueou.

## 1. Questão a investigar e histórico confiável

O acesso ao desktop da EP126 (192.168.6.50, LAN49) pelo Guacamole foi restabelecido após o suporte desativar as regras específicas do ConectaEduca nas interfaces LAN33/LAN49. A correlação temporal **não identifica qual regra causou falha, nem prova que a falha histórica do Xvnc foi de rede**.

A captura histórica do XRDP mostrava sesman em 127.0.0.1:3350, login reportado como bem-sucedido e erro da conexão local ao Xvnc 127.0.0.1:5910. Esse trecho é loopback da EP126 e **não cruza pfSense**. Uma possível falha de Guacamole→XRDP e outra de XRDP→Xvnc são diagnósticos distintos.

Nas capturas de 03/11, a responsável havia criado regras específicas LAN33 (9 desativadas) e LAN49 (8 desativadas), incluindo bloqueios interzona. As permissões gerais Pass any-any remanescentes não foram criadas pela responsável. As regras Floating institucionais preexistentes, inclusive as com tracker 1753729384 (LAN33→10.96.41.0/24) e 1753729514 (LAN49→10.96.41.0/24), foram registradas como habilitadas com Quick e logging desativado. **Não atribuir essas Floating à responsável nem modificá-las**. Falta de log não prova ausência de bloqueio.

## 2. Fluxos que precisam ter origem real confirmada

| Fluxo | Origem | Destino | Porta/observação | Classificação |
| --- | --- | --- | --- | --- |
| Navegador → Portal Guacamole | Usuário institucional autorizado | Portal Guacamole | HTTPS conforme implantação | Legitimo |
| Serviço guacd → XRDP | **IP/interface do guacd desconhecidos** | EP126 192.168.6.50 | RDP TCP 3389, se porta padrão; verificar conexão | Legitimo crítico |
| XRDP → sesman → Xvnc | EP126 loopback | 127.0.0.1 | 3350 / 5910 na captura antiga | Interno; não depende do pfSense |
| EP125 PHP → MariaDB EP126 | 192.168.6.34 (LAN33) | 192.168.6.50 (LAN49) | TCP 3306 se runtime atual | Legitimo |
| EP125 agente → Wazuh EP126 | EP125 | EP126 | 1514/1515 conforme agente/protocolo efetivo | Legitimo |
| EP126 → serviços Bacula/DMZ | EP126 | EP125 | 9102/9103 condicionais aos papéis FD/SD | Legitimo condicional |
| EP126 → DNS institucional | EP126 | 10.96.210.37 / 10.96.210.127 | DNS 53 TCP/UDP | Validar necessidade |
| EP126 → DC / NTP / SSSD | EP126 | IPs DC/NTP a confirmar | Portas AD só se serviço comprovado | Condicional, não causa presumida |
| Cliente não autorizado → EP126 | Origem de teste aprovada | EP126 | RDP/SSH ou outros serviços do PA-01 | NEGAR |
| Usuário Twingate sem privilégio → Wazuh EP126 | Identidade final | Resource administrativo privado | Conforme Resource/MFA | NEGAR |

Não assumir que o guacd está no EP125 ou em LAN33. O IP do cliente que abre o navegador também não é a origem necessária do fluxo guacd→XRDP.

## 3. Matriz PF-01 de execução por fases

| ID | Fase | Teste controlado | PASS/critério de aborto |
| --- | --- | --- | --- |
| PF01-00 | Backup e gestão | Suporte guarda backup atual do pfSense, registra Config History/diff, console independente, operador e procedimento de rollback | Sem canal de recuperação ou backup validado: BLOQUEAR todas as alterações |
| PF01-01 | Baseline positivo | Sessão Guacamole→EP126 com conta de teste, conexão autorizada, acesso gráfico e estabilidade. Registrar horário e mensagem de erro exata, se houver | Login e desktop PASS; caso falhe, investigar antes de reativar regras |
| PF01-02 | Trajeto RDP — SUPORTE | **Suporte/admin do Guacamole** informa protocolo, origem do guacd, destino e porta real; suporte de rede informa interface ingressante pfSense e rota. Andréa apenas informa o resultado de acesso como usuária e o horário | 5-tuple e interface conhecidos; não pedir acesso administrativo Guacamole à responsável |
| PF01-03 | Regras/logs/states | Revisar rules LAN33/LAN49, Floating Quick, aliases, ordem e trackers; correlacionar Firewall Logs, States e horários de conexão | Mapear regra acionada. Sem log não prova passagem |
| PF01-04 | Captura dirigida | Se ambíguo, suporte captura apenas metadados SYN/SYN-ACK na interface de entrada/saída, com filtro para guacd→EP126 porta RDP | Determinar se há encaminhamento L3/L4; pcap bruto sob custódia |
| PF01-05 | Separar XRDP/Xvnc — EP126 | Andréa verifica serviços/listeners no terminal da EP126; logs sanitizados apenas se sua permissão atual permitir. Suporte aprofunda se necessário | Falha 127.0.0.1 local NÃO deve ser atribuída ao pfSense |
| PF01-06 | Revisar política proposta | Criar diff de regra estrita para guacd exato→EP126 RDP, caso fluxo exista; rever allow de serviços necessários antes de deny interzona; considerar Quick e Pass any-any | Sem any-any novo, sem RPC aberto por atacado, sem regra institucional alterada |
| PF01-07 | Mudança unitária | Em janela, suporte reabilita/aplica **uma regra específica por ciclo**, registra tracker/horário/config diff | Repetir Guacamole positivo e segregação negativa após cada mudança; em regressão REVERTER última regra |
| PF01-08 | Negações | Origem de teste sem direito tenta acessar somente destino/porta em escopo; testar usuário final sem Resource administrativo Twingate | Sem acesso indevido; se conexão passa, não declarar segmentação PASS |
| PF01-09 | Regressão | Aplicação HTTPS via WAF, EP125→SQL EP126, Wazuh, Guacamole, Twingate autorizado e negado | TODOS os fluxos legítimos PASS e indevidos DENY na mesma revisão de firewall |
| PF01-10 | Aceite | Registrar estados antes/depois, Config History, Tracker IDs, horário, capturas minimizadas e hash privado da evidência | Aceitar mudança ou restaurar baseline; PA-01 não fecha apenas com login |

## 4. Árvore de decisão para diagnóstico

- **Não há SYN do guacd chegando ao ingresso pfSense:** checar host real, porta, DNS e roteamento, sem acusar regras LAN.
- **SYN chega ao ingresso, mas não aparece na interface de saída, com tracker Block correspondente:** forte evidência de bloqueio do pfSense; conferir Floating Quick, interface de entrada, aliases e NAT.
- **SYN sai do firewall, mas RDP não completa:** investigar firewall da EP126, listener XRDP, retorno, estados e rotas.
- **RDP completou e sesman confirmou login, mas Xvnc falhou em loopback:** investigação de sessão Xvnc local. Não é falha interzona por si.
- **Tudo legítimo funciona e uma tentativa negativa também funciona:** política insuficiente; verificar Pass any-any já existente, Floating Quick, estados e ordem.

O pfSense processa Floating antes de grupos e interfaces, e suas regras de interface são avaliadas no ingresso. A state table pode manter conexões anteriores: repetir **novas** tentativas controladas, sem limpar globalmente estados fora da janela do suporte.

## 5. Gates de segurança e rollback

1. **Antes de alterações**: suporte disponibiliza canal de acesso independente (console/hypervisor), backup sob custódia, revisão do Config History e aprovação da janela. Backup da VM EP126 **não substitui** backup do pfSense.
2. **Ciclo unitário**: ativar uma regra, aplicar, registrar tracker e horário, testar positivo Guacamole/serviços e negativo segmentação, decidir MANTER ou REVERTER antes da próxima.
3. **Falha/aborto**: não avançar. Suporte desfaz a última regra aplicada e valida baseline; se perder GUI, suporte recupera pelo console/histórico. Não habilitar todas as 17 regras de uma vez.
4. **Não modificar** Floating institucionais ou permissões genéricas remotamente sem controle próprio do suporte. Não abrir LAN33↔LAN49 irrestrito e não liberar portas dinâmicas AD/RPC sem tráfego comprovado.
5. **Privacidade**: manter config.xml, PCAP, logs brutos, IPs institucionais e credenciais em custódia privada; GitHub e Trello recebem somente tracker, horário, resultado sanitizado e hash das evidências.

### Registro mínimo de cada ensaio

| Campo | Exemplo de valor esperado |
| --- | --- |
| Identificador | PF01-07 |
| Data/hora BRT, operador suporte | Preencher |
| Revisão/Tracker ID da regra | Preencher |
| Origem/destino/protocolo/porta | Sanitizados, mas rastreáveis na custódia |
| Guacamole→EP126 | PASS / FAIL / INCONCLUSIVO |
| XRDP/Xvnc local | PASS / FAIL / NÃO APLICÁVEL |
| Serviços EP125→EP126 | PASS / FAIL / INCONCLUSIVO |
| Tentativa negativa sem permissão | DENY / ALLOW INDEVIDO / INCONCLUSIVO |
| Última regra revertida | SIM / NÃO |
| Decisão e hash da evidência privada | MANTER / REVERTER / BLOQUEADO |

## 6. Pedido objetivo ao suporte

**Sem reabrir inventários já realizados e sem pedir administração do Guacamole à responsável:** informar (1) IP/interface de origem real do guacd e configuração de destino/porta da conexão EP126; (2) se no episódio de falha houve timeout até XRDP ou login XRDP sucedido seguido de erro Xvnc, e quais tracker IDs foram efetivamente desativados; (3) quem executará backup, uma regra por janela e rollback pelo console se houver perda de acesso. A tabela AD só deve entrar na análise se for demonstrado uso real por SSSD/PAM.

## Referências

- [Netgate — Rule Methodology](https://docs.netgate.com/pfsense/en/latest/firewall/rule-methodology.html)
- [Netgate — Floating Rules](https://docs.netgate.com/pfsense/en/latest/firewall/floating-rules.html)
- [Netgate — Firewall Logs / Tracker ID](https://docs.netgate.com/pfsense/en/latest/monitoring/logs/firewall.html)
- [Netgate — States](https://docs.netgate.com/pfsense/en/latest/monitoring/status/firewall-states.html)
- [Netgate — Packet Capture GUI](https://docs.netgate.com/pfsense/en/latest/diagnostics/packetcapture/webgui.html)
- [Netgate — Backup/Restore](https://docs.netgate.com/pfsense/en/latest/backup/restore.html)
- [Apache Guacamole — RDP connection settings](https://guacamole.apache.org/doc/gug/configuring-guacamole.html)
- [Microsoft — service port requirements](https://learn.microsoft.com/en-US/troubleshoot/windows-server/networking/service-overview-and-network-port-requirements)

**Status em 04/11:** plano preparado no GitHub; **nenhum teste operacional PF-01 executado**. PA-01 pendente, causalidade da falha antiga inconclusiva.
